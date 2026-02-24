/**
 * Shift Automation Scheduler
 *
 * Автоматизация жизненного цикла отчётов пересменки:
 * - Автоматическое создание pending отчётов при начале временного окна
 * - Переход pending → failed по истечении дедлайна
 * - Переход review → rejected по истечении adminReviewTimeout
 * - Начисление штрафов за пропуск
 * - Push-уведомления
 * - Очистка failed отчётов в 23:59
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 * REFACTORED: Migrated to BaseReportScheduler (2026-02-17)
 * REFACTORED: Added PostgreSQL support (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('../utils/async_fs');
const { fileExists, loadJsonFile } = require('../utils/file_helpers');
const { getMoscowTime, getMoscowDateString, MOSCOW_OFFSET_HOURS } = require('../utils/moscow_time');
const BaseReportScheduler = require('../utils/base_report_scheduler');
const db = require('../utils/db');

const USE_DB = process.env.USE_DB_SHIFTS === 'true';
const DATA_DIR = process.env.DATA_DIR || '/var/www';

class ShiftScheduler extends BaseReportScheduler {
  constructor() {
    super({
      name: 'Shift',
      stateDir: `${DATA_DIR}/shift-automation-state`,
      penaltyCategory: 'shift_missed_penalty',
      penaltyCategoryName: 'Пропущенная пересменка',
      penaltyPrefix: 'penalty_shift_',
      sourceType: 'shift_report',
      notificationTitle: 'Пересменки не пройдены',
      notificationBodyFn: (count, shiftLabel) => `${count} магазинов не прошли ${shiftLabel === 'утренний' ? 'утреннюю' : 'вечернюю'} пересменку`,
      notificationType: 'shift_failed',
      startupDelayMs: 2000,
    });

    this.SHIFT_REPORTS_DIR = `${this.DATA_DIR}/shift-reports`;
    this.SHOP_MANAGERS_FILE = `${this.DATA_DIR}/shop-managers.json`;
    this.POINTS_SETTINGS_DIR = `${this.DATA_DIR}/points-settings`;
  }

  // ==================== SETTINGS ====================

  async getSettings() {
    const settingsFile = path.join(this.POINTS_SETTINGS_DIR, 'shift_points_settings.json');
    return await loadJsonFile(settingsFile, {
      morningStartTime: '07:00',
      morningEndTime: '13:00',
      eveningStartTime: '14:00',
      eveningEndTime: '23:00',
      missedPenalty: -3,
      adminReviewTimeout: 2
    });
  }

  // ==================== SINGLE-FILE STORAGE ====================

  getTodayReportsFile() {
    const today = getMoscowDateString();
    return path.join(this.SHIFT_REPORTS_DIR, `${today}.json`);
  }

  async loadTodayReports() {
    return await loadJsonFile(this.getTodayReportsFile(), []);
  }

  async saveTodayReports(reports) {
    try {
      await writeJsonFile(this.getTodayReportsFile(), reports);
      return true;
    } catch (e) {
      console.error(`${this.tag} Error saving reports:`, e.message);
      return false;
    }
  }

  // ==================== GENERATE PENDING ====================

  async generatePendingReports(shiftType, targetDate = null) {
    const settings = await this.getSettings();
    const shops = await this.getAllShops();
    // targetDate used for midnight-crossing windows (pre-midnight generates for tomorrow)
    const today = targetDate || getMoscowDateString();

    if (shops.length === 0) {
      console.log(`${this.tag} No shops found, skipping ${shiftType} report generation`);
      return 0;
    }

    // Use target date for reports file (may be tomorrow's file)
    const reportsFile = path.join(this.SHIFT_REPORTS_DIR, `${today}.json`);
    let reports = await loadJsonFile(reportsFile, []);
    let created = 0;

    // DB: проверяем уже СДАННЫЕ отчёты (review/confirmed) — не блокируем на failed
    let dbSubmittedSet = new Set();
    if (USE_DB) {
      try {
        const result = await db.query(
          `SELECT shop_address, shift_type FROM shift_reports
           WHERE (date = $1 OR (created_at AT TIME ZONE 'Europe/Moscow')::date = $1::date)
           AND status IN ('review', 'confirmed')`,
          [today]
        );
        for (const row of result.rows) {
          dbSubmittedSet.add(`${row.shop_address}|${row.shift_type}`);
        }
        console.log(`${this.tag} DB: ${dbSubmittedSet.size} submitted reports for ${today}`);
      } catch (dbErr) {
        console.error(`${this.tag} DB check error:`, dbErr.message);
      }
    }

    const deadlineTime = shiftType === 'morning' ? settings.morningEndTime : settings.eveningEndTime;
    const { hours, minutes } = this.parseTime(deadlineTime);
    const deadlineMoscow = new Date(`${today}T${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:00`);
    const deadlineUtc = new Date(deadlineMoscow.getTime() - MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);

    for (const shop of shops) {
      const exists = reports.some(r =>
        r.shopAddress === shop.address &&
        r.shiftType === shiftType &&
        r.status === 'pending'
      );
      if (exists) continue;

      // DB: пропускаем если отчёт уже СДАН (review/confirmed)
      if (dbSubmittedSet.has(`${shop.address}|${shiftType}`)) continue;

      const report = {
        id: `pending_${shiftType}_${shop.address}_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
        shopAddress: shop.address,
        shopName: shop.name,
        shiftType,
        status: 'pending',
        createdAt: new Date().toISOString(),
        deadline: deadlineUtc.toISOString(),
        employeeName: null,
        employeeId: null,
        answers: [],
        submittedAt: null,
        reviewDeadline: null,
        confirmedAt: null,
        rating: null,
        confirmedByAdmin: null,
        failedAt: null,
        rejectedAt: null
      };

      reports.push(report);
      created++;

      // DB dual-write: сохраняем pending в PostgreSQL
      if (USE_DB) {
        try {
          await db.upsert('shift_reports', {
            id: report.id,
            employee_name: '',
            employee_id: null,
            employee_phone: null,
            shop_address: report.shopAddress,
            shop_name: report.shopName,
            shift_type: report.shiftType,
            status: 'pending',
            answers: '[]',
            date: today,
            created_at: report.createdAt,
            deadline: report.deadline,
            updated_at: report.createdAt
          });
        } catch (dbErr) {
          console.error(`${this.tag} DB upsert pending error:`, dbErr.message);
        }
      }

      console.log(`${this.tag} Created pending ${shiftType} report for ${shop.name} (${shop.address}) [date=${today}]`);
    }

    if (created > 0) {
      await writeJsonFile(reportsFile, reports);
    }

    console.log(`${this.tag} Generated ${created} pending ${shiftType} reports for ${today}`);
    return created;
  }

  // ==================== CHECK DEADLINES ====================

  async checkPendingDeadlines() {
    const now = new Date();
    let reports = await this.loadTodayReports();
    const settings = await this.getSettings();
    let failedCount = 0;
    const failedShops = [];

    for (let i = 0; i < reports.length; i++) {
      const report = reports[i];
      if (report.status !== 'pending') continue;

      const deadline = new Date(report.deadline);

      if (now > deadline) {
        reports[i].status = 'failed';
        reports[i].failedAt = now.toISOString();
        failedCount++;

        failedShops.push({
          shopAddress: report.shopAddress,
          shopName: report.shopName,
          shiftType: report.shiftType,
          deadline: report.deadline
        });

        console.log(`${this.tag} Report FAILED: ${report.shopName} (${report.shiftType}), deadline was ${report.deadline}`);

        await this.assignPenaltyFromSchedule(
          report,
          settings.missedPenalty,
          (r) => `Не пройдена ${r.shiftType === 'morning' ? 'утренняя' : 'вечерняя'} пересменка`
        );
      }
    }

    if (failedCount > 0) {
      await this.saveTodayReports(reports);

      // DB dual-write: обновляем pending → failed
      if (USE_DB) {
        for (const report of reports) {
          if (report.status === 'failed' && report.failedAt) {
            try {
              await db.updateById('shift_reports', report.id, {
                status: 'failed',
                failed_at: report.failedAt,
                updated_at: new Date().toISOString()
              });
            } catch (dbErr) {
              console.error(`${this.tag} DB update failed error:`, dbErr.message);
            }
          }
        }
      }

      await this.sendAdminFailedNotification(failedCount, failedShops);
    }

    return failedCount;
  }

  // ==================== CHECK REVIEW TIMEOUTS (override) ====================

  async checkReviewTimeouts() {
    const now = new Date();
    let reports = await this.loadTodayReports();
    let rejectedCount = 0;

    for (let i = 0; i < reports.length; i++) {
      const report = reports[i];
      if (report.status !== 'review') continue;
      if (!report.reviewDeadline) continue;

      const reviewDeadline = new Date(report.reviewDeadline);

      if (now > reviewDeadline) {
        reports[i].status = 'rejected';
        reports[i].rejectedAt = now.toISOString();
        rejectedCount++;

        console.log(`${this.tag} Report REJECTED (admin timeout): ${report.shopName} (${report.shiftType}), employee: ${report.employeeName}`);

        await this.assignPenaltyDirect(report);
      }
    }

    if (rejectedCount > 0) {
      await this.saveTodayReports(reports);

      // DB dual-write: обновляем rejected статусы
      if (USE_DB) {
        for (const report of reports) {
          if (report.status === 'rejected' && report.id) {
            try {
              await db.updateById('shift_reports', report.id, {
                status: 'rejected',
                rejected_at: report.rejectedAt,
                updated_at: new Date().toISOString()
              });
              console.log(`${this.tag} DB updated: ${report.id} → rejected`);
            } catch (dbErr) {
              console.error(`${this.tag} DB update error:`, dbErr.message);
            }
          }
        }
      }
    }

    // DB: проверяем старые застрявшие отчёты (не из сегодняшнего файла)
    if (USE_DB) {
      try {
        const stuckRows = await db.query(
          `SELECT id, shop_address, shift_type, employee_name, date
           FROM shift_reports
           WHERE status = 'review'
             AND review_deadline IS NOT NULL
             AND review_deadline < $1`,
          [now.toISOString()]
        );

        // Группируем по дате для batch-обновления JSON-файлов
        const byDate = {};
        for (const row of (stuckRows.rows || stuckRows)) {
          try {
            await db.updateById('shift_reports', row.id, {
              status: 'rejected',
              rejected_at: now.toISOString(),
              updated_at: now.toISOString()
            });
            rejectedCount++;
            console.log(`${this.tag} DB stale REJECTED: ${row.shop_address} (${row.shift_type}), employee: ${row.employee_name}`);

            // Запоминаем для обновления JSON
            if (row.date) {
              const dateStr = typeof row.date === 'string' ? row.date.split('T')[0] : row.date.toISOString().split('T')[0];
              if (!byDate[dateStr]) byDate[dateStr] = [];
              byDate[dateStr].push(row.id);
            }
          } catch (dbErr) {
            console.error(`${this.tag} DB stale reject error:`, dbErr.message);
          }
        }

        // Обновляем JSON-файлы за соответствующие даты (синхронизация с БД)
        for (const [dateStr, ids] of Object.entries(byDate)) {
          try {
            const jsonFile = path.join(this.SHIFT_REPORTS_DIR, `${dateStr}.json`);
            if (await fileExists(jsonFile)) {
              const fileReports = await loadJsonFile(jsonFile, []);
              let changed = false;
              for (const r of fileReports) {
                if (ids.includes(r.id) && r.status === 'review') {
                  r.status = 'rejected';
                  r.rejectedAt = now.toISOString();
                  changed = true;
                }
              }
              if (changed) {
                await writeJsonFile(jsonFile, fileReports);
                console.log(`${this.tag} JSON synced: ${dateStr}.json — ${ids.length} report(s) → rejected`);
              }
            }
          } catch (jsonErr) {
            console.error(`${this.tag} JSON sync error for ${dateStr}:`, jsonErr.message);
          }
        }
      } catch (err) {
        console.error(`${this.tag} DB stale review check error:`, err.message);
      }
    }

    return rejectedCount;
  }

  // ==================== FIND ADMIN FOR SHOP ====================

  async findAdminForShop(shopAddress) {
    try {
      const shops = await this.getAllShops();
      const shop = shops.find(s => s.address === shopAddress);
      if (!shop) {
        console.log(`${this.tag} Shop not found by address: ${shopAddress}`);
        return null;
      }

      const managersData = await loadJsonFile(this.SHOP_MANAGERS_FILE, { developers: [], managers: [], storeManagers: [] });
      const manager = (managersData.managers || []).find(m =>
        (m.managedShops || []).includes(shop.id)
      );

      if (!manager) {
        console.log(`${this.tag} No manager found for shop ${shop.id} (${shopAddress})`);
        return null;
      }

      return {
        phone: manager.phone,
        name: manager.name || 'Управляющий',
        employeeId: `admin_${manager.phone}`
      };
    } catch (e) {
      console.error(`${this.tag} Error finding admin for shop:`, e.message);
      return null;
    }
  }

  // ==================== ASSIGN PENALTY TO ADMIN (for rejected reports) ====================

  async assignPenaltyDirect(report) {
    const settings = await this.getSettings();
    const admin = await this.findAdminForShop(report.shopAddress);

    if (admin) {
      await this.createPenalty({
        employeeId: admin.employeeId,
        employeeName: admin.name,
        shopAddress: report.shopAddress,
        points: settings.missedPenalty,
        reason: `Пересменка отклонена (не проверена вовремя). Сотрудник: ${report.employeeName || 'неизвестен'}`,
        sourceId: `${report.id}_admin_penalty`
      });
      console.log(`${this.tag} Admin penalty assigned to ${admin.name} for shop ${report.shopAddress}`);
    } else {
      console.log(`${this.tag} Cannot assign admin penalty - no manager found for shop ${report.shopAddress} (report ${report.id})`);
    }
  }

  // ==================== CLEANUP ====================

  async cleanupFailedReports() {
    let reports = await this.loadTodayReports();
    const initialCount = reports.length;

    reports = reports.filter(r => r.status !== 'failed');

    const removedCount = initialCount - reports.length;

    if (removedCount > 0) {
      await this.saveTodayReports(reports);
      console.log(`${this.tag} Cleanup: removed ${removedCount} failed reports`);
    }

    return removedCount;
  }

  // ==================== OVERRIDE: USE isTimeReached for time windows ====================

  /**
   * Проверяет, находимся ли мы в интервале [start, end) с поддержкой перехода через полночь.
   * Например: start=23:01, end=13:00 → true в 00:30, 01:00, 12:59; false в 13:00, 22:00
   */
  isInTimeWindow(startTime, endTime) {
    const moscow = getMoscowTime();
    const moscowMinutes = moscow.getUTCHours() * 60 + moscow.getUTCMinutes();

    const startParts = this.parseTime(startTime);
    const endParts = this.parseTime(endTime);
    const startMinutes = startParts.hours * 60 + startParts.minutes;
    const endMinutes = endParts.hours * 60 + endParts.minutes;

    if (startMinutes <= endMinutes) {
      // Обычный интервал (14:00 - 23:00)
      return moscowMinutes >= startMinutes && moscowMinutes < endMinutes;
    } else {
      // Интервал через полночь (23:01 - 13:00)
      return moscowMinutes >= startMinutes || moscowMinutes < endMinutes;
    }
  }

  async runScheduledChecks() {
    const now = new Date();
    const moscow = getMoscowTime();
    const settings = await this.getSettings();
    const state = await this.loadState();

    console.log(`\n[${now.toISOString()}] ${this.tag} Running checks... (Moscow time: ${moscow.toISOString()})`);

    // Morning window (supports midnight crossover, e.g. 23:01 - 13:00)
    if (this.isInTimeWindow(settings.morningStartTime, settings.morningEndTime)) {
      const lastGen = state.lastMorningGeneration;

      // FIX: For midnight-crossing windows (e.g. 23:01-13:00), when we're in the
      // pre-midnight part (23:01-23:59), pending reports are for TOMORROW's morning.
      // Compare lastGen against tomorrow so we don't skip generation.
      let compareDate = now;
      let targetDate = null;
      const mStart = this.parseTime(settings.morningStartTime);
      const mEnd = this.parseTime(settings.morningEndTime);
      const startMin = mStart.hours * 60 + mStart.minutes;
      const endMin = mEnd.hours * 60 + mEnd.minutes;
      if (startMin > endMin) {
        // Midnight-crossing window
        const moscowNow = moscow.getUTCHours() * 60 + moscow.getUTCMinutes();
        if (moscowNow >= startMin) {
          // Pre-midnight part: reports are for tomorrow's morning
          compareDate = new Date(now.getTime() + 24 * 60 * 60 * 1000);
          const tomorrowMoscow = new Date(moscow.getTime() + 24 * 60 * 60 * 1000);
          targetDate = tomorrowMoscow.toISOString().split('T')[0];
          console.log(`${this.tag} Pre-midnight morning window detected, generating for ${targetDate}`);
        }
      }

      if (!lastGen || !this.isSameDay(new Date(lastGen), compareDate)) {
        const created = await this.generatePendingReports('morning', targetDate);
        if (created > 0) {
          state.lastMorningGeneration = compareDate.toISOString();
        }
      }
    }

    // Evening window
    if (this.isInTimeWindow(settings.eveningStartTime, settings.eveningEndTime)) {
      const lastGen = state.lastEveningGeneration;
      if (!lastGen || !this.isSameDay(new Date(lastGen), now)) {
        const created = await this.generatePendingReports('evening');
        if (created > 0) {
          state.lastEveningGeneration = now.toISOString();
        }
      }
    }

    // Check pending deadlines
    const failed = await this.checkPendingDeadlines();
    if (failed > 0) {
      console.log(`${this.tag} ${failed} reports marked as failed`);
    }

    // Check review timeouts
    const rejected = await this.checkReviewTimeouts();
    if (rejected > 0) {
      console.log(`${this.tag} ${rejected} reports auto-rejected (admin timeout)`);
    }

    // Cleanup at 23:59 Moscow time
    const moscowHours = moscow.getUTCHours();
    const moscowMinutes = moscow.getUTCMinutes();
    if (moscowHours === 23 && moscowMinutes >= 59) {
      const lastCleanup = state.lastCleanup;
      if (!lastCleanup || !this.isSameDay(new Date(lastCleanup), now)) {
        await this.cleanupFailedReports();
        state.lastCleanup = now.toISOString();
      }
    }

    await this.saveState(state);
    console.log(`${this.tag} Checks completed\n`);
  }

  // ==================== API: SET REVIEW STATUS ====================

  async setReportToReview(reportId, employeeId, employeeName) {
    const settings = await this.getSettings();
    const now = new Date();
    let reports = await this.loadTodayReports();

    const index = reports.findIndex(r => r.id === reportId);
    if (index === -1) {
      console.log(`${this.tag} Report ${reportId} not found`);
      return null;
    }

    const reviewDeadline = new Date(now.getTime() + settings.adminReviewTimeout * 60 * 60 * 1000);

    reports[index].status = 'review';
    reports[index].employeeId = employeeId;
    reports[index].employeeName = employeeName;
    reports[index].submittedAt = now.toISOString();
    reports[index].reviewDeadline = reviewDeadline.toISOString();

    await this.saveTodayReports(reports);

    // DB dual-write: upsert при переходе pending → review
    if (USE_DB) {
      try {
        await db.upsert('shift_reports', {
          id: reports[index].id,
          employee_name: employeeName,
          employee_id: employeeId,
          employee_phone: employeeId,
          shop_address: reports[index].shopAddress,
          shop_name: reports[index].shopName,
          shift_type: reports[index].shiftType,
          status: 'review',
          answers: JSON.stringify(reports[index].answers || []),
          date: getMoscowDateString(),
          created_at: reports[index].createdAt || now.toISOString(),
          submitted_at: now.toISOString(),
          deadline: reports[index].deadline,
          review_deadline: reviewDeadline.toISOString(),
          updated_at: now.toISOString()
        });
        console.log(`${this.tag} DB upsert: ${reportId} → review`);
      } catch (dbErr) {
        console.error(`${this.tag} DB upsert error:`, dbErr.message);
      }
    }

    console.log(`${this.tag} Report ${reportId} set to review, deadline: ${reviewDeadline.toISOString()}`);
    return reports[index];
  }

  // ==================== API: CONFIRM REPORT ====================

  async confirmReport(reportId, rating, adminName) {
    const now = new Date();
    let reports = await this.loadTodayReports();

    const index = reports.findIndex(r => r.id === reportId);
    if (index === -1) {
      console.log(`${this.tag} Report ${reportId} not found`);
      return null;
    }

    reports[index].status = 'confirmed';
    reports[index].rating = rating;
    reports[index].confirmedByAdmin = adminName;
    reports[index].confirmedAt = now.toISOString();

    await this.saveTodayReports(reports);

    // DB dual-write: обновляем статус при confirm
    if (USE_DB && reports[index].id && !reports[index].id.startsWith('pending_')) {
      try {
        await db.updateById('shift_reports', reports[index].id, {
          status: 'confirmed',
          rating: rating,
          confirmed_by_admin: adminName,
          confirmed_at: now.toISOString(),
          updated_at: now.toISOString()
        });
        console.log(`${this.tag} DB updated: ${reportId} → confirmed`);
      } catch (dbErr) {
        console.error(`${this.tag} DB update error:`, dbErr.message);
      }
    }

    // Send notification to employee
    if (reports[index].employeeId) {
      await this.sendPushToEmployee(
        reports[index].employeeId,
        'Пересменка оценена',
        `Ваш отчёт оценён на ${rating} баллов`,
        { type: 'shift_confirmed', rating: String(rating) }
      );
    }

    console.log(`${this.tag} Report ${reportId} confirmed with rating ${rating}`);
    return reports[index];
  }
}

// Singleton
const scheduler = new ShiftScheduler();

// Ensure directories
(async () => {
  for (const dir of [scheduler.SHIFT_REPORTS_DIR, scheduler.stateDir]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

module.exports = {
  startShiftAutomationScheduler: () => scheduler.start(),
  generatePendingReports: (shiftType) => scheduler.generatePendingReports(shiftType),
  checkPendingDeadlines: () => scheduler.checkPendingDeadlines(),
  checkReviewTimeouts: () => scheduler.checkReviewTimeouts(),
  cleanupFailedReports: () => scheduler.cleanupFailedReports(),
  setReportToReview: (id, empId, empName) => scheduler.setReportToReview(id, empId, empName),
  confirmReport: (id, rating, admin) => scheduler.confirmReport(id, rating, admin),
  loadTodayReports: () => scheduler.loadTodayReports(),
  saveTodayReports: (reports) => scheduler.saveTodayReports(reports),
  getShiftSettings: () => scheduler.getSettings(),
  getMoscowTime,
  getMoscowDateString
};
