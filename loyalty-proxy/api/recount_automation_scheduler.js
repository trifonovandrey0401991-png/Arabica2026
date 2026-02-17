/**
 * Recount Automation Scheduler
 *
 * Автоматизация жизненного цикла отчётов пересчёта:
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
const { getMoscowTime, getMoscowDateString } = require('../utils/moscow_time');
const BaseReportScheduler = require('../utils/base_report_scheduler');
const db = require('../utils/db');

const USE_DB = process.env.USE_DB_RECOUNT === 'true';
const DATA_DIR = process.env.DATA_DIR || '/var/www';

class RecountScheduler extends BaseReportScheduler {
  constructor() {
    super({
      name: 'Recount',
      stateDir: `${DATA_DIR}/recount-automation-state`,
      penaltyCategory: 'recount_missed_penalty',
      penaltyCategoryName: 'Пропущенный пересчёт',
      penaltyPrefix: 'penalty_recount_',
      sourceType: 'recount_report',
      notificationTitle: 'Пересчёты не пройдены',
      notificationBodyFn: (count, shiftLabel) => `${count} магазинов не прошли ${shiftLabel} пересчёт`,
      notificationType: 'recount_failed',
      startupDelayMs: 3000,
    });

    this.RECOUNT_REPORTS_DIR = `${this.DATA_DIR}/recount-reports`;
    this.POINTS_SETTINGS_DIR = `${this.DATA_DIR}/points-settings`;
  }

  // ==================== SETTINGS ====================

  async getSettings() {
    const defaults = {
      morningStartTime: '08:00',
      morningEndTime: '14:00',
      eveningStartTime: '14:00',
      eveningEndTime: '23:00',
      missedPenalty: -3,
      adminReviewTimeout: 2
    };

    const settingsFile = path.join(this.POINTS_SETTINGS_DIR, 'recount_points_settings.json');
    const loaded = await loadJsonFile(settingsFile, {});

    return {
      ...defaults,
      ...loaded,
      morningStartTime: loaded.morningStartTime || defaults.morningStartTime,
      morningEndTime: loaded.morningEndTime || defaults.morningEndTime,
      eveningStartTime: loaded.eveningStartTime || defaults.eveningStartTime,
      eveningEndTime: loaded.eveningEndTime || defaults.eveningEndTime,
      missedPenalty: loaded.missedPenalty !== undefined ? loaded.missedPenalty : defaults.missedPenalty,
      adminReviewTimeout: loaded.adminReviewTimeout || defaults.adminReviewTimeout
    };
  }

  // ==================== REPORTS MANAGEMENT ====================

  async loadTodayReports() {
    const reports = [];
    const today = getMoscowDateString();

    if (!(await fileExists(this.RECOUNT_REPORTS_DIR))) return reports;

    try {
      const files = (await fsp.readdir(this.RECOUNT_REPORTS_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const filePath = path.join(this.RECOUNT_REPORTS_DIR, file);
          const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
          const reportDate = report.createdAt ? report.createdAt.split('T')[0] : null;
          if (reportDate === today || report.status === 'pending' || report.status === 'review') {
            reports.push({ ...report, _filePath: filePath });
          }
        } catch (e) {
          console.error(`${this.tag} Error reading file ${file}:`, e.message);
        }
      }
    } catch (e) {
      console.error(`${this.tag} Error reading reports directory:`, e.message);
    }

    return reports;
  }

  async saveReport(report) {
    const filePath = report._filePath;
    if (!filePath) {
      console.error(`${this.tag} No _filePath in report`);
      return false;
    }
    const dataToSave = { ...report };
    delete dataToSave._filePath;

    // DB dual-write: обновляем статус в БД (только для реальных отчётов, не pending)
    if (USE_DB && report.id && !report.id.startsWith('pending_recount_')) {
      try {
        const dbUpdate = {
          status: dataToSave.status,
          updated_at: new Date().toISOString()
        };
        if (dataToSave.failedAt) dbUpdate.failed_at = dataToSave.failedAt;
        if (dataToSave.rejectedAt) dbUpdate.rejected_at = dataToSave.rejectedAt;
        if (dataToSave.submittedAt) dbUpdate.submitted_at = dataToSave.submittedAt;
        if (dataToSave.reviewDeadline) dbUpdate.review_deadline = dataToSave.reviewDeadline;
        if (dataToSave.employeeName) dbUpdate.employee_name = dataToSave.employeeName;
        if (dataToSave.employeePhone) dbUpdate.employee_phone = dataToSave.employeePhone;
        if (dataToSave.adminRating != null) dbUpdate.admin_rating = dataToSave.adminRating;
        if (dataToSave.adminName) dbUpdate.admin_name = dataToSave.adminName;
        if (dataToSave.ratedAt) dbUpdate.rated_at = dataToSave.ratedAt;

        await db.updateById('recount_reports', report.id, dbUpdate);
        console.log(`${this.tag} DB updated: ${report.id} → ${report.status}`);
      } catch (dbErr) {
        console.error(`${this.tag} DB update error:`, dbErr.message);
      }
    }

    try {
      await writeJsonFile(filePath, dataToSave);
      return true;
    } catch (e) {
      console.error(`${this.tag} Error saving report:`, e.message);
      return false;
    }
  }

  async createPendingReport(shop, shiftType, deadline) {
    if (!(await fileExists(this.RECOUNT_REPORTS_DIR))) {
      await fsp.mkdir(this.RECOUNT_REPORTS_DIR, { recursive: true });
    }

    const now = new Date();
    const reportId = `pending_recount_${shiftType}_${shop.address.replace(/[^a-zA-Z0-9]/g, '_')}_${Date.now()}`;
    const filePath = path.join(this.RECOUNT_REPORTS_DIR, `${reportId}.json`);

    const report = {
      id: reportId,
      shopAddress: shop.address,
      shopName: shop.name,
      shiftType,
      status: 'pending',
      createdAt: now.toISOString(),
      deadline: deadline.toISOString(),
      employeeName: '',
      employeePhone: null,
      answers: [],
      submittedAt: null,
      reviewDeadline: null,
      adminRating: null,
      adminName: null,
      ratedAt: null,
      failedAt: null,
      rejectedAt: null
    };

    await writeJsonFile(filePath, report);
    return report;
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

    const reports = await this.loadTodayReports();

    // Дополнительно проверяем DB на сданные отчёты (которых может не быть в файлах)
    let dbSubmittedSet = new Set();
    if (USE_DB) {
      try {
        const result = await db.query(
          'SELECT shop_address, shift_type FROM recount_reports WHERE date = $1 OR created_at::date = $2::date',
          [today, today]
        );
        for (const row of result.rows) {
          dbSubmittedSet.add(`${row.shop_address}|${row.shift_type}`);
        }
        console.log(`${this.tag} DB: ${dbSubmittedSet.size} submitted reports for ${today}`);
      } catch (dbErr) {
        console.error(`${this.tag} DB check error:`, dbErr.message);
      }
    }

    let created = 0;

    const deadlineTime = shiftType === 'morning' ? settings.morningEndTime : settings.eveningEndTime;
    const startTime = shiftType === 'morning' ? settings.morningStartTime : settings.eveningStartTime;
    const deadline = this.getDeadlineTime(deadlineTime, startTime);

    console.log(`${this.tag} ${shiftType} deadline calculated: ${deadline.toISOString()}`);

    for (const shop of shops) {
      // Проверяем файлы
      const exists = reports.some(r =>
        r.shopAddress === shop.address &&
        r.shiftType === shiftType &&
        (r.status === 'pending' || r.status === 'review' || r.status === 'confirmed')
      );
      if (exists) continue;

      // Проверяем DB
      if (dbSubmittedSet.has(`${shop.address}|${shiftType}`)) continue;

      await this.createPendingReport(shop, shiftType, deadline);
      created++;
      console.log(`${this.tag} Created pending ${shiftType} recount for ${shop.name} (${shop.address})`);
    }

    console.log(`${this.tag} Generated ${created} pending ${shiftType} recounts`);
    return created;
  }

  // ==================== CHECK DEADLINES ====================

  async checkPendingDeadlines() {
    const now = new Date();
    const reports = await this.loadTodayReports();
    const settings = await this.getSettings();
    let failedCount = 0;
    const failedShops = [];

    for (const report of reports) {
      if (report.status !== 'pending') continue;

      const deadline = new Date(report.deadline);

      if (now > deadline) {
        report.status = 'failed';
        report.failedAt = now.toISOString();
        await this.saveReport(report);
        failedCount++;

        failedShops.push({
          shopAddress: report.shopAddress,
          shopName: report.shopName,
          shiftType: report.shiftType,
          deadline: report.deadline
        });

        console.log(`${this.tag} Recount FAILED: ${report.shopName} (${report.shiftType}), deadline was ${report.deadline}`);

        await this.assignPenaltyFromSchedule(
          report,
          settings.missedPenalty,
          (r) => `Не пройден ${r.shiftType === 'morning' ? 'утренний' : 'вечерний'} пересчёт`
        );
      }
    }

    if (failedCount > 0) {
      await this.sendAdminFailedNotification(failedCount, failedShops);
    }

    return failedCount;
  }

  // ==================== CHECK REVIEW TIMEOUTS (override) ====================

  async checkReviewTimeouts() {
    const now = new Date();
    const reports = await this.loadTodayReports();
    let rejectedCount = 0;

    for (const report of reports) {
      if (report.status !== 'review') continue;
      if (!report.reviewDeadline) continue;

      const reviewDeadline = new Date(report.reviewDeadline);

      if (now > reviewDeadline) {
        report.status = 'rejected';
        report.rejectedAt = now.toISOString();
        await this.saveReport(report);
        rejectedCount++;

        console.log(`${this.tag} Recount REJECTED (admin timeout): ${report.shopName} (${report.shiftType}), employee: ${report.employeeName}`);

        await this.assignPenaltyDirect(report);
      }
    }

    return rejectedCount;
  }

  // ==================== ASSIGN PENALTY DIRECT (for rejected) ====================

  async assignPenaltyDirect(report) {
    const settings = await this.getSettings();

    if (!report.employeeName) {
      console.log(`${this.tag} Cannot assign penalty - no employee info in report ${report.id}`);
      return;
    }

    await this.createPenalty({
      employeeId: report.employeePhone || report.id,
      employeeName: report.employeeName,
      shopAddress: report.shopAddress,
      points: settings.missedPenalty,
      reason: `Пересчёт отклонён (админ не проверил вовремя)`,
      sourceId: report.id
    });
  }

  // ==================== CLEANUP ====================

  async cleanupFailedReports() {
    const reports = await this.loadTodayReports();
    let removedCount = 0;

    for (const report of reports) {
      if (report.status === 'failed' && report._filePath) {
        try {
          await fsp.unlink(report._filePath);
          removedCount++;
        } catch (e) {
          console.error(`${this.tag} Error removing file ${report._filePath}:`, e.message);
        }
      }
    }

    if (removedCount > 0) {
      console.log(`${this.tag} Cleanup: removed ${removedCount} failed reports`);
    }

    return removedCount;
  }

  // ==================== API: SET REVIEW STATUS ====================

  async setReportToReview(reportId, employeeId, employeeName) {
    const settings = await this.getSettings();
    const now = new Date();
    const reports = await this.loadTodayReports();

    const report = reports.find(r => r.id === reportId);
    if (!report) {
      console.log(`${this.tag} Report ${reportId} not found`);
      return null;
    }

    const reviewDeadline = new Date(now.getTime() + settings.adminReviewTimeout * 60 * 60 * 1000);

    report.status = 'review';
    report.employeePhone = employeeId;
    report.employeeName = employeeName;
    report.submittedAt = now.toISOString();
    report.reviewDeadline = reviewDeadline.toISOString();

    await this.saveReport(report);

    console.log(`${this.tag} Report ${reportId} set to review, deadline: ${reviewDeadline.toISOString()}`);
    return report;
  }

  // ==================== API: CONFIRM REPORT ====================

  async confirmReport(reportId, rating, adminName) {
    const now = new Date();
    const reports = await this.loadTodayReports();

    const report = reports.find(r => r.id === reportId);
    if (!report) {
      console.log(`${this.tag} Report ${reportId} not found`);
      return null;
    }

    report.status = 'confirmed';
    report.adminRating = rating;
    report.adminName = adminName;
    report.ratedAt = now.toISOString();

    await this.saveReport(report);

    // Send notification to employee
    if (report.employeePhone) {
      await this.sendPushToEmployee(
        report.employeePhone,
        'Пересчёт оценён',
        `Ваш отчёт по пересчёту оценён на ${rating} баллов`,
        { type: 'recount_confirmed', rating: String(rating) }
      );
    }

    console.log(`${this.tag} Report ${reportId} confirmed with rating ${rating}`);
    return report;
  }
}

// Singleton
const scheduler = new RecountScheduler();

// Ensure directories
(async () => {
  for (const dir of [scheduler.RECOUNT_REPORTS_DIR, scheduler.stateDir]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

module.exports = {
  startRecountAutomationScheduler: () => scheduler.start(),
  generatePendingReports: (shiftType) => scheduler.generatePendingReports(shiftType),
  checkPendingDeadlines: () => scheduler.checkPendingDeadlines(),
  checkReviewTimeouts: () => scheduler.checkReviewTimeouts(),
  cleanupFailedReports: () => scheduler.cleanupFailedReports(),
  setReportToReview: (id, empId, empName) => scheduler.setReportToReview(id, empId, empName),
  confirmReport: (id, rating, admin) => scheduler.confirmReport(id, rating, admin),
  loadTodayReports: () => scheduler.loadTodayReports(),
  getRecountSettings: () => scheduler.getSettings(),
  getMoscowTime,
  getMoscowDateString
};
