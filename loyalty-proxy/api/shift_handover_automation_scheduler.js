/**
 * Shift Handover Automation Scheduler
 *
 * Автоматизация жизненного цикла отчётов "Сдача смены":
 * - Автоматическое создание pending отчётов при начале временного окна
 * - Переход pending → failed по истечении дедлайна
 * - Переход awaiting_review → rejected по таймауту adminReviewTimeout
 * - Push-уведомления админу
 * - Очистка failed отчётов в 23:59
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 * REFACTORED: Migrated to BaseReportScheduler (2026-02-17)
 * REFACTORED: Added PostgreSQL support for checkIfShiftHandoverSubmitted/checkReviewTimeouts (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('../utils/async_fs');
const { fileExists, loadJsonFile } = require('../utils/file_helpers');
const { getMoscowTime, getMoscowDateString, MOSCOW_OFFSET_HOURS } = require('../utils/moscow_time');
const BaseReportScheduler = require('../utils/base_report_scheduler');
const db = require('../utils/db');
const { loadShopManagers } = require('./shop_managers_api');
const { generateId } = require('../utils/id_generator');

const USE_DB = process.env.USE_DB_SHIFT_HANDOVER === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';

class ShiftHandoverScheduler extends BaseReportScheduler {
  constructor() {
    super({
      name: 'ShiftHandover',
      stateDir: `${DATA_DIR}/shift-handover-automation-state`,
      defaultState: {
        lastMorningGeneration: null,
        lastEveningGeneration: null,
        lastAdminTimeoutCheck: null,
        lastCleanup: null,
        lastCheck: null
      },
      penaltyCategory: 'shift_handover_missed_penalty',
      penaltyCategoryName: 'Сдача смены - пропуск',
      penaltyPrefix: 'penalty_sh_',
      sourceType: 'shift_handover',
      notificationTitle: 'Смены не сданы',
      notificationBodyFn: (count, shiftLabel) => `${count} магазинов не сдали ${shiftLabel === 'утренний' ? 'утреннюю' : 'вечернюю'} смену`,
      notificationType: 'shift_handover_failed',
      startupDelayMs: 6000,
    });

    this.SHIFT_HANDOVER_REPORTS_DIR = `${this.DATA_DIR}/shift-handover-reports`;
    this.SHIFT_HANDOVER_PENDING_DIR = `${this.DATA_DIR}/shift-handover-pending`;
    this.POINTS_SETTINGS_DIR = `${this.DATA_DIR}/points-settings`;
  }

  // ==================== SETTINGS ====================

  async getSettings() {
    const defaults = {
      minPoints: -3,
      zeroThreshold: 7,
      maxPoints: 1,
      morningStartTime: '07:00',
      morningEndTime: '14:00',
      eveningStartTime: '14:00',
      eveningEndTime: '23:00',
      missedPenalty: -3,
      adminReviewTimeout: 4
    };

    const settingsFile = path.join(this.POINTS_SETTINGS_DIR, 'shift_handover_points_settings.json');
    const loaded = await loadJsonFile(settingsFile, {});

    return {
      ...defaults,
      ...loaded,
      morningStartTime: loaded.morningStartTime || defaults.morningStartTime,
      morningEndTime: loaded.morningEndTime || defaults.morningEndTime,
      eveningStartTime: loaded.eveningStartTime || defaults.eveningStartTime,
      eveningEndTime: loaded.eveningEndTime || defaults.eveningEndTime,
      missedPenalty: loaded.missedPenalty !== undefined ? loaded.missedPenalty : defaults.missedPenalty,
      adminReviewTimeout: loaded.adminReviewTimeout !== undefined ? loaded.adminReviewTimeout : defaults.adminReviewTimeout
    };
  }

  // ==================== PENDING REPORTS ====================

  async ensureDir(dir) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }

  async loadTodayPendingReports() {
    await this.ensureDir(this.SHIFT_HANDOVER_PENDING_DIR);
    const reports = [];
    const today = getMoscowDateString();

    try {
      const files = (await fsp.readdir(this.SHIFT_HANDOVER_PENDING_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const filePath = path.join(this.SHIFT_HANDOVER_PENDING_DIR, file);
          const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
          const reportDate = report.date || (report.createdAt ? report.createdAt.split('T')[0] : null);
          if (reportDate === today) {
            reports.push({ ...report, _filePath: filePath });
          }
        } catch (e) {
          console.error(`${this.tag} Error reading file ${file}:`, e.message);
        }
      }
    } catch (e) {
      console.error(`${this.tag} Error reading pending directory:`, e.message);
    }

    return reports;
  }

  async savePendingReport(report) {
    const filePath = report._filePath;
    if (!filePath) {
      console.error(`${this.tag} No _filePath in report`);
      return false;
    }
    const dataToSave = { ...report };
    delete dataToSave._filePath;
    try {
      await writeJsonFile(filePath, dataToSave);
      return true;
    } catch (e) {
      console.error(`${this.tag} Error saving report:`, e.message);
      return false;
    }
  }

  async createPendingReport(shop, shiftType, deadline) {
    await this.ensureDir(this.SHIFT_HANDOVER_PENDING_DIR);

    const now = new Date();
    const today = getMoscowDateString();
    const reportId = generateId(`pending_sh_${shiftType}_${shop.address.replace(/[^a-zA-Z0-9а-яА-ЯёЁ]/g, '_')}`);
    const filePath = path.join(this.SHIFT_HANDOVER_PENDING_DIR, `${reportId}.json`);

    const report = {
      id: reportId,
      shopAddress: shop.address,
      shopName: shop.name,
      shiftType,
      shiftLabel: shiftType === 'morning' ? 'Утро' : 'Вечер',
      status: 'pending',
      date: today,
      deadline,
      createdAt: now.toISOString(),
      completedBy: null,
      completedAt: null,
      failedAt: null
    };

    await writeJsonFile(filePath, report);

    // DB dual-write: save pending to PostgreSQL (same as shift scheduler)
    if (USE_DB) {
      try {
        const deadlineTs = this.getDeadlineTime(deadline);
        await db.upsert('shift_handover_reports', {
          id: report.id,
          employee_name: '',
          employee_phone: null,
          shop_address: report.shopAddress,
          shop_name: report.shopName,
          shift_type: report.shiftType,
          status: 'pending',
          answers: '[]',
          date: report.date,
          created_at: report.createdAt,
          deadline: deadlineTs.toISOString(),
          updated_at: report.createdAt
        });
        console.log(`${this.tag} DB: pending created ${report.id}`);
      } catch (dbErr) {
        console.error(`${this.tag} DB upsert pending error:`, dbErr.message);
      }
    }

    console.log(`${this.tag} Created pending ${shiftType} shift handover for ${shop.name}, deadline: ${deadline}`);
    return report;
  }

  // ==================== CHECK IF SUBMITTED ====================

  async checkIfShiftHandoverSubmitted(shopAddress, shiftType, today) {
    // DB path: один SQL-запрос вместо readdir + readFile для каждого файла
    if (USE_DB) {
      try {
        // Only look for actually submitted reports (not pending/failed placeholders)
        const result = await db.query(
          `SELECT id FROM shift_handover_reports
           WHERE shop_address = $1 AND date = $2 AND shift_type = $3
           AND status NOT IN ('pending', 'failed')
           LIMIT 1`,
          [shopAddress, today, shiftType]
        );
        if (result.rows.length > 0) return true;

        // Fallback: shift_type может быть null в старых данных, проверяем по времени
        const result2 = await db.query(
          `SELECT id, created_at FROM shift_handover_reports
           WHERE shop_address = $1 AND date = $2 AND shift_type IS NULL
           AND status NOT IN ('pending', 'failed')
           LIMIT 10`,
          [shopAddress, today]
        );
        for (const row of result2.rows) {
          if (row.created_at) {
            const createdHour = (new Date(row.created_at).getUTCHours() + 3) % 24;
            const reportShiftType = createdHour >= 14 ? 'evening' : 'morning';
            if (reportShiftType === shiftType) return true;
          }
        }
        return false;
      } catch (err) {
        console.error(`${this.tag} DB error in checkIfShiftHandoverSubmitted:`, err.message);
        // Fallback to files
      }
    }

    await this.ensureDir(this.SHIFT_HANDOVER_REPORTS_DIR);

    try {
      const files = (await fsp.readdir(this.SHIFT_HANDOVER_REPORTS_DIR)).filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const filePath = path.join(this.SHIFT_HANDOVER_REPORTS_DIR, file);
          const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
          const reportDate = report.createdAt ? report.createdAt.split('T')[0] : null;

          let reportShiftType = 'morning';
          if (report.createdAt) {
            const createdHour = (new Date(report.createdAt).getUTCHours() + 3) % 24;
            reportShiftType = createdHour >= 14 ? 'evening' : 'morning';
          }

          if (reportDate === today &&
              report.shopAddress === shopAddress &&
              reportShiftType === shiftType) {
            return true;
          }
        } catch (e) {
          // Пропускаем некорректные файлы
        }
      }
    } catch (e) {
      console.error(`${this.tag} Error checking submitted reports:`, e.message);
    }

    return false;
  }

  // ==================== GENERATE PENDING ====================

  async generatePendingReports(shiftType) {
    const settings = await this.getSettings();
    const shops = await this.getAllShops();
    const today = getMoscowDateString();

    if (shops.length === 0) {
      console.log(`${this.tag} No shops found, skipping ${shiftType} report generation`);
      return 0;
    }

    const pendingReports = await this.loadTodayPendingReports();
    let created = 0;

    const deadlineTime = shiftType === 'morning' ? settings.morningEndTime : settings.eveningEndTime;

    console.log(`${this.tag} Generating ${shiftType} reports, deadline: ${deadlineTime}`);

    for (const shop of shops) {
      const existsPending = pendingReports.some(r =>
        r.shopAddress === shop.address &&
        r.shiftType === shiftType &&
        r.status === 'pending'
      );
      if (existsPending) continue;

      const alreadySubmitted = await this.checkIfShiftHandoverSubmitted(shop.address, shiftType, today);
      if (alreadySubmitted) {
        console.log(`${this.tag} Shift handover already submitted for ${shop.name} (${shiftType}), skipping`);
        continue;
      }

      await this.createPendingReport(shop, shiftType, deadlineTime);
      created++;
    }

    console.log(`${this.tag} Generated ${created} pending ${shiftType} shift handovers`);
    return created;
  }

  // ==================== CHECK DEADLINES ====================

  async checkPendingDeadlines() {
    const moscow = getMoscowTime();
    const today = getMoscowDateString();
    const reports = await this.loadTodayPendingReports();
    const settings = await this.getSettings();
    let failedCount = 0;
    const failedShops = [];

    const moscowHours = moscow.getUTCHours();
    const moscowMinutes = moscow.getUTCMinutes();
    const currentMinutes = moscowHours * 60 + moscowMinutes;

    for (const report of reports) {
      if (report.status !== 'pending') continue;

      const submitted = await this.checkIfShiftHandoverSubmitted(report.shopAddress, report.shiftType, today);
      if (submitted) {
        console.log(`${this.tag} Shift handover submitted for ${report.shopName}, removing pending`);
        if (report._filePath && (await fileExists(report._filePath))) {
          await fsp.unlink(report._filePath);
        }
        continue;
      }

      const deadline = this.parseTime(report.deadline);
      const deadlineMinutes = deadline.hours * 60 + deadline.minutes;

      if (currentMinutes >= deadlineMinutes) {
        report.status = 'failed';
        report.failedAt = new Date().toISOString();
        await this.savePendingReport(report);

        // DB dual-write: update failed status in PostgreSQL
        if (USE_DB) {
          try {
            await db.updateById('shift_handover_reports', report.id, {
              status: 'failed',
              failed_at: report.failedAt,
              updated_at: new Date().toISOString()
            });
          } catch (dbErr) {
            console.error(`${this.tag} DB update failed error:`, dbErr.message);
          }
        }

        failedCount++;

        failedShops.push({
          shopAddress: report.shopAddress,
          shopName: report.shopName,
          shiftType: report.shiftType,
          deadline: report.deadline
        });

        console.log(`${this.tag} FAILED: ${report.shopName} (${report.shiftType}), deadline was ${report.deadline}`);

        // Assign penalty + send push to employee
        const penalty = await this.assignPenaltyFromSchedule(
          report,
          settings.missedPenalty,
          (r) => `Не сдана ${r.shiftType === 'morning' ? 'утренняя' : 'вечерняя'} смена`
        );

        if (penalty && penalty.employeePhone) {
          const shiftLabel = report.shiftType === 'morning' ? 'утреннюю' : 'вечернюю';
          await this.sendPushToEmployee(
            penalty.employeePhone,
            'Штраф за пропуск сдачи смены',
            `Вам начислен штраф ${penalty.points} баллов за пропуск ${shiftLabel} сдачи смены`,
            { type: 'shift_handover_penalty', points: String(penalty.points), shiftType: report.shiftType }
          );
        }
      }
    }

    if (failedCount > 0) {
      await this.sendAdminFailedNotification(failedCount, failedShops);
    }

    return failedCount;
  }

  // ==================== FIND MANAGER FOR SHOP ====================

  async findManagerForShop(shopAddress) {
    try {
      // 1. Найти shop_id по адресу
      let shopId = null;

      if (USE_DB) {
        try {
          const result = await db.query(
            'SELECT id FROM shops WHERE address = $1 LIMIT 1',
            [shopAddress]
          );
          if (result.rows && result.rows.length > 0) {
            shopId = result.rows[0].id;
          }
        } catch (e) {
          console.error(`${this.tag} DB error finding shop by address:`, e.message);
        }
      }

      // File fallback
      if (!shopId) {
        const shops = await this.getAllShops();
        const shop = shops.find(s => s.address === shopAddress);
        if (shop) shopId = shop.id;
      }

      if (!shopId) {
        console.log(`${this.tag} Shop not found for address: ${shopAddress}`);
        return null;
      }

      // 2. Найти управляющую
      const managersData = await loadShopManagers();
      const manager = (managersData.managers || []).find(m =>
        m.managedShops && m.managedShops.includes(shopId)
      );

      if (!manager) {
        console.log(`${this.tag} No manager found for shop ${shopId} (${shopAddress})`);
        return null;
      }

      return { name: manager.name, phone: manager.phone };
    } catch (e) {
      console.error(`${this.tag} Error finding manager for shop:`, e.message);
      return null;
    }
  }

  // ==================== CHECK ADMIN REVIEW TIMEOUT (override checkReviewTimeouts) ====================

  async checkReviewTimeouts() {
    const settings = await this.getSettings();
    const timeoutHours = settings.adminReviewTimeout;
    const maxRating = settings.maxRating || 10;
    const now = new Date();
    let rejectedCount = 0;
    const rejectedReports = [];

    if (USE_DB) {
      try {
        const cutoff = new Date(now.getTime() - timeoutHours * 60 * 60 * 1000).toISOString();
        const result = await db.query(
          `SELECT * FROM shift_handover_reports
           WHERE status = 'pending' AND employee_name != '' AND created_at < $1`,
          [cutoff]
        );

        for (const row of result.rows) {
          // Обновляем в БД с авто-оценкой
          await db.updateById('shift_handover_reports', row.id, {
            status: 'rejected',
            expired_at: now.toISOString(),
            rating: maxRating,
            auto_rated: true,
            updated_at: now.toISOString()
          });

          // Dual-write: обновляем файл если есть
          const filePath = path.join(this.SHIFT_HANDOVER_REPORTS_DIR, `${row.id}.json`);
          if (await fileExists(filePath)) {
            try {
              const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
              report.status = 'rejected';
              report.expiredAt = now.toISOString();
              report.rejectionReason = `Таймаут проверки (${timeoutHours} ч)`;
              report.rating = maxRating;
              report.autoRated = true;
              await writeJsonFile(filePath, report);
            } catch (e) {
              // Файл мог не существовать — ок
            }
          }

          rejectedCount++;
          rejectedReports.push({
            id: row.id,
            shopAddress: row.shop_address,
            employeeName: row.employee_name,
            createdAt: row.created_at
          });

          console.log(`${this.tag} REJECTED + AUTO-RATED (${maxRating}/10): ${row.shop_address} by ${row.employee_name}`);

          // Штраф управляющей
          const manager = await this.findManagerForShop(row.shop_address);
          if (manager) {
            await this.createPenalty({
              employeeId: manager.phone,
              employeeName: manager.name,
              employeePhone: manager.phone,
              shopAddress: row.shop_address,
              points: settings.missedPenalty,
              reason: `Сдача смены не проверена вовремя. Сотрудник: ${row.employee_name || 'неизвестен'}`,
              sourceId: `${row.id}_admin_penalty`
            });
            console.log(`${this.tag} Admin penalty assigned to manager ${manager.name} for ${row.shop_address}`);
          }
        }

        if (rejectedCount > 0) {
          await this.sendAdminRejectedNotification(rejectedCount, rejectedReports);
        }
        return rejectedCount;
      } catch (err) {
        console.error(`${this.tag} DB error in checkReviewTimeouts:`, err.message);
        // Fallback to files
      }
    }

    await this.ensureDir(this.SHIFT_HANDOVER_REPORTS_DIR);

    try {
      const files = (await fsp.readdir(this.SHIFT_HANDOVER_REPORTS_DIR)).filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const filePath = path.join(this.SHIFT_HANDOVER_REPORTS_DIR, file);
          const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));

          if (report.status !== 'pending') continue;
          // Skip scheduler-created records (no employee submitted) — let checkPendingDeadlines mark them failed
          if (!report.employeeName) continue;

          const createdAt = new Date(report.createdAt);
          const hoursPassed = (now - createdAt) / (1000 * 60 * 60);

          if (hoursPassed >= timeoutHours) {
            report.status = 'rejected';
            report.expiredAt = now.toISOString();
            report.rejectionReason = `Таймаут проверки (${timeoutHours} ч)`;
            report.rating = maxRating;
            report.autoRated = true;

            await writeJsonFile(filePath, report);

            // DB dual-write
            if (USE_DB && report.id) {
              try {
                await db.updateById('shift_handover_reports', report.id, {
                  status: 'rejected',
                  expired_at: now.toISOString(),
                  rating: maxRating,
                  auto_rated: true,
                  updated_at: now.toISOString()
                });
              } catch (dbErr) {
                console.error(`${this.tag} DB update error:`, dbErr.message);
              }
            }

            rejectedCount++;

            rejectedReports.push({
              id: report.id,
              shopAddress: report.shopAddress,
              employeeName: report.employeeName,
              createdAt: report.createdAt
            });

            console.log(`${this.tag} REJECTED + AUTO-RATED (${maxRating}/10): ${report.shopAddress} by ${report.employeeName}`);

            // Штраф управляющей
            const manager = await this.findManagerForShop(report.shopAddress);
            if (manager) {
              await this.createPenalty({
                employeeId: manager.phone,
                employeeName: manager.name,
                employeePhone: manager.phone,
                shopAddress: report.shopAddress,
                points: settings.missedPenalty,
                reason: `Сдача смены не проверена вовремя. Сотрудник: ${report.employeeName || 'неизвестен'}`,
                sourceId: `${report.id}_admin_penalty`
              });
              console.log(`${this.tag} Admin penalty assigned to manager ${manager.name} for ${report.shopAddress}`);
            }
          }
        } catch (e) {
          // Пропускаем некорректные файлы
        }
      }
    } catch (e) {
      console.error(`${this.tag} Error checking admin timeout:`, e.message);
    }

    if (rejectedCount > 0) {
      await this.sendAdminRejectedNotification(rejectedCount, rejectedReports);
    }

    return rejectedCount;
  }

  // ==================== CLEANUP ====================

  async cleanupFailedReports() {
    let removedCount = 0;

    try {
      if (await fileExists(this.SHIFT_HANDOVER_PENDING_DIR)) {
        const files = await fsp.readdir(this.SHIFT_HANDOVER_PENDING_DIR);
        for (const file of files) {
          if (file.endsWith('.json')) {
            try {
              await fsp.unlink(path.join(this.SHIFT_HANDOVER_PENDING_DIR, file));
              removedCount++;
            } catch (e) {
              console.error(`${this.tag} Error removing file ${file}:`, e.message);
            }
          }
        }
      }
    } catch (e) {
      console.error(`${this.tag} Error reading pending directory:`, e.message);
    }

    if (removedCount > 0) {
      console.log(`${this.tag} Cleanup: removed ${removedCount} pending/failed files`);
    }

    const emptyState = {
      lastMorningGeneration: null,
      lastEveningGeneration: null,
      lastAdminTimeoutCheck: null,
      lastCleanup: new Date().toISOString(),
      lastCheck: new Date().toISOString()
    };
    await this.saveState(emptyState);
    console.log(`${this.tag} State reset for new day`);

    return removedCount;
  }

  // ==================== UNIQUE NOTIFICATIONS ====================

  async sendAdminRejectedNotification(count, rejectedReports) {
    this._initPush();

    const title = 'Отчёты отклонены';
    const body = `${count} отчётов о сдаче смены отклонены по таймауту`;

    console.log(`${this.tag} PUSH to Admin: ${body}`);

    if (this._pushNotification) {
      try {
        await this._pushNotification(title, body, {
          type: 'shift_handover_rejected',
          count: String(count),
        });
        console.log(`${this.tag} Push notification sent successfully`);
      } catch (e) {
        console.error(`${this.tag} Error sending push notification:`, e.message);
      }
    }
  }

  async sendAdminNewReportNotification(report) {
    this._initPush();

    const title = 'Новая сдача смены';
    const body = `${report.employeeName} сдал смену (${report.shopAddress})`;

    console.log(`${this.tag} PUSH to Admin: ${body}`);

    if (this._pushNotification) {
      try {
        await this._pushNotification(title, body, {
          type: 'shift_handover_submitted',
          reportId: report.id,
          shopAddress: report.shopAddress,
          employeeName: report.employeeName,
        });
      } catch (e) {
        console.error(`${this.tag} Error sending push notification:`, e.message);
      }
    }
  }

  // ==================== API: MARK PENDING AS COMPLETED ====================

  async markPendingAsCompleted(shopAddress, shiftType, employeeName) {
    const reports = await this.loadTodayPendingReports();

    for (const report of reports) {
      if (report.shopAddress === shopAddress &&
          report.shiftType === shiftType &&
          report.status === 'pending') {
        if (report._filePath && (await fileExists(report._filePath))) {
          await fsp.unlink(report._filePath);
          console.log(`${this.tag} Marked pending as completed: ${shopAddress} (${shiftType}) by ${employeeName}`);
          return true;
        }
      }
    }

    return false;
  }
}

// Singleton
const scheduler = new ShiftHandoverScheduler();

// Ensure directories
(async () => {
  for (const dir of [scheduler.SHIFT_HANDOVER_PENDING_DIR, scheduler.SHIFT_HANDOVER_REPORTS_DIR, scheduler.stateDir]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

// API exports
async function getPendingReports() {
  return (await scheduler.loadTodayPendingReports()).filter(r => r.status === 'pending');
}

async function getFailedReports() {
  return (await scheduler.loadTodayPendingReports()).filter(r => r.status === 'failed');
}

module.exports = {
  startShiftHandoverAutomationScheduler: () => scheduler.start(),
  generatePendingReports: (shiftType) => scheduler.generatePendingReports(shiftType),
  checkPendingDeadlines: () => scheduler.checkPendingDeadlines(),
  checkAdminReviewTimeout: () => scheduler.checkReviewTimeouts(),
  cleanupFailedReports: () => scheduler.cleanupFailedReports(),
  loadTodayPendingReports: () => scheduler.loadTodayPendingReports(),
  getPendingReports,
  getFailedReports,
  markPendingAsCompleted: (addr, shift, name) => scheduler.markPendingAsCompleted(addr, shift, name),
  sendAdminNewReportNotification: (report) => scheduler.sendAdminNewReportNotification(report),
  getShiftHandoverSettings: () => scheduler.getSettings(),
  getMoscowTime,
  getMoscowDateString
};
