/**
 * RKO Automation Scheduler
 *
 * Автоматизация жизненного цикла РКО отчётов (ЗП после смены):
 * - Автоматическое создание pending отчётов при начале временного окна
 * - Переход pending → failed по истечении дедлайна
 * - Начисление штрафов за пропуск
 * - Push-уведомления
 * - Очистка failed отчётов в 00:00-06:00
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

const USE_DB = process.env.USE_DB_RKO === 'true';
const DATA_DIR = process.env.DATA_DIR || '/var/www';

class RkoScheduler extends BaseReportScheduler {
  constructor() {
    super({
      name: 'Rko',
      stateDir: `${DATA_DIR}/rko-automation-state`,
      penaltyCategory: 'rko_missed_penalty',
      penaltyCategoryName: 'Пропущенный РКО',
      penaltyPrefix: 'penalty_rko_',
      sourceType: 'rko_report',
      notificationTitle: 'РКО не сданы',
      notificationBodyFn: (count, shiftLabel) => `${count} магазинов не сдали ${shiftLabel} РКО`,
      notificationType: 'rko_failed',
      startupDelayMs: 4000,
    });

    this.RKO_REPORTS_DIR = `${this.DATA_DIR}/rko-reports`;
    this.RKO_PENDING_DIR = `${this.DATA_DIR}/rko-pending`;
    this.POINTS_SETTINGS_DIR = `${this.DATA_DIR}/points-settings`;
  }

  // ==================== SETTINGS ====================

  async getSettings() {
    const defaults = {
      hasRkoPoints: 1,
      noRkoPoints: -3,
      morningStartTime: '07:00',
      morningEndTime: '14:00',
      eveningStartTime: '14:00',
      eveningEndTime: '23:00',
      missedPenalty: -3
    };

    const settingsFile = path.join(this.POINTS_SETTINGS_DIR, 'rko_points_settings.json');
    const loaded = await loadJsonFile(settingsFile, {});

    return {
      ...defaults,
      ...loaded,
      morningStartTime: loaded.morningStartTime || defaults.morningStartTime,
      morningEndTime: loaded.morningEndTime || defaults.morningEndTime,
      eveningStartTime: loaded.eveningStartTime || defaults.eveningStartTime,
      eveningEndTime: loaded.eveningEndTime || defaults.eveningEndTime,
      missedPenalty: loaded.missedPenalty !== undefined ? loaded.missedPenalty : defaults.missedPenalty
    };
  }

  // ==================== PENDING REPORTS ====================

  async loadTodayPendingReports() {
    const reports = [];
    const today = getMoscowDateString();

    if (!(await fileExists(this.RKO_PENDING_DIR))) return reports;

    try {
      const files = (await fsp.readdir(this.RKO_PENDING_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const filePath = path.join(this.RKO_PENDING_DIR, file);
          const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
          const reportDate = report.createdAt ? report.createdAt.split('T')[0] : null;
          if (reportDate === today || report.status === 'pending') {
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
    if (!(await fileExists(this.RKO_PENDING_DIR))) {
      await fsp.mkdir(this.RKO_PENDING_DIR, { recursive: true });
    }

    const now = new Date();
    const reportId = `pending_rko_${shiftType}_${shop.address.replace(/[^a-zA-Z0-9]/g, '_')}_${Date.now()}`;
    const filePath = path.join(this.RKO_PENDING_DIR, `${reportId}.json`);

    const report = {
      id: reportId,
      shopAddress: shop.address,
      shopName: shop.name,
      shiftType,
      status: 'pending',
      rkoType: 'ЗП после смены',
      createdAt: now.toISOString(),
      deadline: deadline.toISOString(),
      employeeName: '',
      employeePhone: null,
      amount: null,
      submittedAt: null,
      failedAt: null
    };

    await writeJsonFile(filePath, report);
    console.log(`${this.tag} Created pending ${shiftType} RKO for ${shop.name} (${shop.address}), deadline: ${deadline.toISOString()}`);
    return report;
  }

  // ==================== CHECK IF SUBMITTED ====================

  async checkIfRkoSubmitted(shopAddress, shiftType, today) {
    // DB check first (if available)
    if (USE_DB) {
      try {
        const result = await db.query(
          'SELECT COUNT(*) as cnt FROM rko_reports WHERE shop_address = $1 AND date = $2',
          [shopAddress, today]
        );
        if (parseInt(result.rows[0].cnt) > 0) return true;
      } catch (dbErr) {
        console.error(`${this.tag} DB check error:`, dbErr.message);
      }
    }

    // File fallback
    const metadataFile = path.join(this.RKO_REPORTS_DIR, 'rko_metadata.json');
    const metadata = await loadJsonFile(metadataFile, { items: [] });

    return metadata.items.some(rko => {
      const rkoDate = rko.date ? rko.date.split('T')[0] : null;
      return rkoDate === today &&
             rko.shopAddress === shopAddress &&
             rko.rkoType === 'ЗП после смены';
    });
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
    const startTime = shiftType === 'morning' ? settings.morningStartTime : settings.eveningStartTime;
    const deadline = this.getDeadlineTime(deadlineTime, startTime);

    console.log(`${this.tag} ${shiftType} deadline calculated: ${deadline.toISOString()}`);

    for (const shop of shops) {
      const existsPending = pendingReports.some(r =>
        r.shopAddress === shop.address &&
        r.shiftType === shiftType &&
        r.status === 'pending'
      );
      if (existsPending) continue;

      const alreadySubmitted = await this.checkIfRkoSubmitted(shop.address, shiftType, today);
      if (alreadySubmitted) {
        console.log(`${this.tag} RKO already submitted for ${shop.name}, skipping`);
        continue;
      }

      await this.createPendingReport(shop, shiftType, deadline);
      created++;
    }

    console.log(`${this.tag} Generated ${created} pending ${shiftType} RKOs`);
    return created;
  }

  // ==================== CHECK DEADLINES ====================

  async checkPendingDeadlines() {
    const now = new Date();
    const today = getMoscowDateString();
    const reports = await this.loadTodayPendingReports();
    const settings = await this.getSettings();
    let failedCount = 0;
    const failedShops = [];

    for (const report of reports) {
      if (report.status !== 'pending') continue;

      const deadline = new Date(report.deadline);

      const submitted = await this.checkIfRkoSubmitted(report.shopAddress, report.shiftType, today);
      if (submitted) {
        console.log(`${this.tag} RKO submitted for ${report.shopName}, removing pending`);
        if (report._filePath && (await fileExists(report._filePath))) {
          await fsp.unlink(report._filePath);
        }
        continue;
      }

      if (now > deadline) {
        report.status = 'failed';
        report.failedAt = now.toISOString();
        await this.savePendingReport(report);
        failedCount++;

        failedShops.push({
          shopAddress: report.shopAddress,
          shopName: report.shopName,
          shiftType: report.shiftType,
          deadline: report.deadline
        });

        console.log(`${this.tag} RKO FAILED: ${report.shopName} (${report.shiftType}), deadline was ${report.deadline}`);

        await this.assignPenaltyFromSchedule(
          report,
          settings.missedPenalty,
          (r) => `Не сдан ${r.shiftType === 'morning' ? 'утренний' : 'вечерний'} РКО`
        );
      }
    }

    if (failedCount > 0) {
      await this.sendAdminFailedNotification(failedCount, failedShops);
    }

    return failedCount;
  }

  // ==================== CLEANUP ====================

  async cleanupFailedReports() {
    let removedCount = 0;

    try {
      if (await fileExists(this.RKO_PENDING_DIR)) {
        const files = await fsp.readdir(this.RKO_PENDING_DIR);
        for (const file of files) {
          if (file.endsWith('.json')) {
            try {
              await fsp.unlink(path.join(this.RKO_PENDING_DIR, file));
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
      console.log(`${this.tag} Cleanup: removed ${removedCount} RKO files`);
    }

    const emptyState = {
      lastMorningGeneration: null,
      lastEveningGeneration: null,
      lastCleanup: new Date().toISOString(),
      lastCheck: new Date().toISOString()
    };
    await this.saveState(emptyState);
    console.log(`${this.tag} State reset for new day`);

    return removedCount;
  }

  // ==================== OVERRIDE: CUSTOM SCHEDULED CHECKS (cleanup at 00:00-06:00) ====================

  async runScheduledChecks() {
    const now = new Date();
    const moscow = getMoscowTime();
    const settings = await this.getSettings();
    const state = await this.loadState();

    console.log(`\n[${now.toISOString()}] ${this.tag} Running checks... (Moscow time: ${moscow.toISOString()})`);
    console.log(`${this.tag} Settings: morning ${settings.morningStartTime}-${settings.morningEndTime}, evening ${settings.eveningStartTime}-${settings.eveningEndTime}`);

    // Morning window
    if (this.isWithinTimeWindow(settings.morningStartTime, settings.morningEndTime)) {
      const lastGen = state.lastMorningGeneration;
      if (!lastGen || !this.isSameDay(new Date(lastGen), now)) {
        console.log(`${this.tag} Morning window active (${settings.morningStartTime} - ${settings.morningEndTime}), generating reports...`);
        const created = await this.generatePendingReports('morning');
        if (created > 0) {
          state.lastMorningGeneration = now.toISOString();
        }
      }
    }

    // Evening window
    if (this.isWithinTimeWindow(settings.eveningStartTime, settings.eveningEndTime)) {
      const lastGen = state.lastEveningGeneration;
      if (!lastGen || !this.isSameDay(new Date(lastGen), now)) {
        console.log(`${this.tag} Evening window active (${settings.eveningStartTime} - ${settings.eveningEndTime}), generating reports...`);
        const created = await this.generatePendingReports('evening');
        if (created > 0) {
          state.lastEveningGeneration = now.toISOString();
        }
      }
    }

    // Check pending deadlines
    const failed = await this.checkPendingDeadlines();
    if (failed > 0) {
      console.log(`${this.tag} ${failed} RKOs marked as failed`);
    }

    // Cleanup: 00:00-06:00 (вместо стандартного 23:59)
    const moscowHours = moscow.getUTCHours();
    const lastCleanup = state.lastCleanup;
    const lastCleanupDate = lastCleanup ? new Date(lastCleanup) : null;
    const todayMoscow = getMoscowDateString();
    const lastCleanupMoscow = lastCleanupDate
      ? new Date(lastCleanupDate.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000).toISOString().split('T')[0]
      : null;

    if (moscowHours >= 0 && moscowHours < 6 && lastCleanupMoscow !== todayMoscow) {
      console.log(`${this.tag} Running daily cleanup (last cleanup: ${lastCleanupMoscow}, today: ${todayMoscow})`);
      await this.cleanupFailedReports();
      const newState = await this.loadState();
      await this.saveState(newState);
      console.log(`${this.tag} Checks completed\n`);
      return;
    }

    await this.saveState(state);
    console.log(`${this.tag} Checks completed\n`);
  }
}

// Singleton
const scheduler = new RkoScheduler();

// Ensure directories
(async () => {
  for (const dir of [scheduler.RKO_PENDING_DIR, scheduler.RKO_REPORTS_DIR, scheduler.stateDir]) {
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
  startRkoAutomationScheduler: () => scheduler.start(),
  generatePendingReports: (shiftType) => scheduler.generatePendingReports(shiftType),
  checkPendingDeadlines: () => scheduler.checkPendingDeadlines(),
  cleanupFailedReports: () => scheduler.cleanupFailedReports(),
  loadTodayPendingReports: () => scheduler.loadTodayPendingReports(),
  getPendingReports,
  getFailedReports,
  getRkoSettings: () => scheduler.getSettings(),
  getMoscowTime,
  getMoscowDateString
};
