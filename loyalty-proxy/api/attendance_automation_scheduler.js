/**
 * Attendance Automation Scheduler
 *
 * Автоматизация жизненного цикла отчётов посещаемости (Я на работе):
 * - Автоматическое создание pending отчётов при начале временного окна
 * - Переход pending → failed по истечении дедлайна
 * - Начисление штрафов за пропуск
 * - Push-уведомления
 * - Очистка failed отчётов в 23:59
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 * REFACTORED: Migrated to BaseReportScheduler (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('../utils/async_fs');
const { fileExists, loadJsonFile } = require('../utils/file_helpers');
const { getMoscowTime, getMoscowDateString, MOSCOW_OFFSET_HOURS } = require('../utils/moscow_time');
const BaseReportScheduler = require('../utils/base_report_scheduler');
const db = require('../utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const USE_DB = process.env.USE_DB_ATTENDANCE === 'true';

class AttendanceScheduler extends BaseReportScheduler {
  constructor() {
    super({
      name: 'Attendance',
      stateDir: `${DATA_DIR}/attendance-automation-state`,
      penaltyCategory: 'attendance_missed_penalty',
      penaltyCategoryName: 'Не отмечен на работе',
      penaltyPrefix: 'penalty_attendance_',
      sourceType: 'attendance',
      notificationTitle: 'Не отмечены на работе',
      notificationBodyFn: (count, shiftLabel) => `${count} магазинов не отметились на ${shiftLabel === 'утренний' ? 'утренней' : 'вечерней'} смене`,
      notificationType: 'attendance_failed',
      startupDelayMs: 6000,
    });

    this.ATTENDANCE_DIR = `${this.DATA_DIR}/attendance`;
    this.ATTENDANCE_PENDING_DIR = `${this.DATA_DIR}/attendance-pending`;
    this.EMPLOYEES_DIR = `${this.DATA_DIR}/employees`;
    this.POINTS_SETTINGS_DIR = `${this.DATA_DIR}/points-settings`;
  }

  // ==================== SETTINGS ====================

  async getSettings() {
    const defaults = {
      onTimePoints: 0.5,
      latePoints: -1,
      morningStartTime: '07:00',
      morningEndTime: '09:00',
      eveningStartTime: '19:00',
      eveningEndTime: '21:00',
      missedPenalty: -2
    };

    const settingsFile = path.join(this.POINTS_SETTINGS_DIR, 'attendance_points_settings.json');
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

    if (!(await fileExists(this.ATTENDANCE_PENDING_DIR))) return reports;

    try {
      const files = (await fsp.readdir(this.ATTENDANCE_PENDING_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const filePath = path.join(this.ATTENDANCE_PENDING_DIR, file);
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
    if (!(await fileExists(this.ATTENDANCE_PENDING_DIR))) {
      await fsp.mkdir(this.ATTENDANCE_PENDING_DIR, { recursive: true });
    }

    const now = new Date();
    const reportId = `pending_attendance_${shiftType}_${shop.address.replace(/[^a-zA-Z0-9]/g, '_')}_${Date.now()}`;
    const filePath = path.join(this.ATTENDANCE_PENDING_DIR, `${reportId}.json`);

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
      markedAt: null,
      failedAt: null,
      isOnTime: null,
      lateMinutes: null
    };

    await writeJsonFile(filePath, report);
    console.log(`${this.tag} Created pending ${shiftType} attendance for ${shop.name} (${shop.address}), deadline: ${deadline.toISOString()}`);
    return report;
  }

  // ==================== CHECK IF ATTENDANCE MARKED ====================

  async checkIfAttendanceMarked(shopAddress, shiftType, today) {
    // DB path
    if (USE_DB) {
      try {
        const result = await db.query(
          `SELECT id, timestamp FROM attendance WHERE shop_address = $1 AND timestamp::date = $2::date`,
          [shopAddress, today]
        );
        for (const row of result.rows) {
          const recordHour = (new Date(row.timestamp).getUTCHours() + MOSCOW_OFFSET_HOURS) % 24;
          const isMorning = recordHour < 14;
          const recordShiftType = isMorning ? 'morning' : 'evening';
          if (recordShiftType === shiftType) return true;
        }
        return false;
      } catch (dbErr) {
        console.error(`${this.tag} DB attendance check error:`, dbErr.message);
        // Fallback to files
      }
    }

    // File path
    if (!(await fileExists(this.ATTENDANCE_DIR))) return false;

    try {
      const files = (await fsp.readdir(this.ATTENDANCE_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const filePath = path.join(this.ATTENDANCE_DIR, file);
          const record = JSON.parse(await fsp.readFile(filePath, 'utf8'));
          const recordDate = record.timestamp ? record.timestamp.split('T')[0] : null;
          if (recordDate === today && record.shopAddress === shopAddress) {
            const recordHour = (new Date(record.timestamp).getUTCHours() + MOSCOW_OFFSET_HOURS) % 24;
            const isMorning = recordHour < 14;
            const recordShiftType = isMorning ? 'morning' : 'evening';
            if (recordShiftType === shiftType) return true;
          }
        } catch (e) {
          // Игнорируем ошибки парсинга отдельных файлов
        }
      }
    } catch (e) {
      console.error(`${this.tag} Error checking attendance:`, e.message);
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

      const alreadyMarked = await this.checkIfAttendanceMarked(shop.address, shiftType, today);
      if (alreadyMarked) {
        console.log(`${this.tag} Attendance already marked for ${shop.name}, skipping`);
        continue;
      }

      await this.createPendingReport(shop, shiftType, deadline);
      created++;
    }

    console.log(`${this.tag} Generated ${created} pending ${shiftType} attendance reports`);
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

      const marked = await this.checkIfAttendanceMarked(report.shopAddress, report.shiftType, today);
      if (marked) {
        console.log(`${this.tag} Attendance marked for ${report.shopName}, removing pending`);
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

        console.log(`${this.tag} Attendance FAILED: ${report.shopName} (${report.shiftType}), deadline was ${report.deadline}`);

        // Assign penalty
        const penalty = await this.assignPenaltyFromSchedule(
          report,
          settings.missedPenalty,
          (r) => `Не отмечен на ${r.shiftType === 'morning' ? 'утренней' : 'вечерней'} смене`
        );

        // Send push to employee
        if (penalty) {
          await this.sendEmployeePenaltyNotification(
            penalty.entityId,
            penalty.employeeName,
            penalty.points,
            report.shopAddress
          );
        }
      }
    }

    if (failedCount > 0) {
      await this.sendAdminFailedNotification(failedCount, failedShops);
    }

    return failedCount;
  }

  // ==================== EMPLOYEE PENALTY NOTIFICATION (unique: searches employees dir) ====================

  async sendEmployeePenaltyNotification(employeeId, employeeName, points, shopAddress) {
    this._initPush();

    if (!this._pushToPhone) {
      console.log(`${this.tag} sendPushToPhone not available, skipping employee notification`);
      return;
    }

    // Найти телефон сотрудника по employeeId
    let employeePhone = null;
    try {
      if (await fileExists(this.EMPLOYEES_DIR)) {
        const files = (await fsp.readdir(this.EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const empData = JSON.parse(await fsp.readFile(path.join(this.EMPLOYEES_DIR, file), 'utf8'));
            if (empData.id === employeeId && empData.phone) {
              employeePhone = empData.phone;
              break;
            }
          } catch (e) {
            // Skip invalid files
          }
        }
      }
    } catch (e) {
      console.error(`${this.tag} Error finding employee phone:`, e.message);
    }

    if (!employeePhone) {
      console.log(`${this.tag} Phone not found for employee ${employeeId}, skipping push notification`);
      return;
    }

    let shortAddress = shopAddress;
    if (shopAddress && shopAddress.length > 30) {
      const parts = shopAddress.split(',');
      shortAddress = parts[0].trim();
    }

    const title = 'Штраф за посещаемость';
    const body = `Вам начислен штраф ${points} баллов за пропуск смены (${shortAddress})`;

    try {
      await this._pushToPhone(employeePhone, title, body, {
        type: 'attendance_penalty',
        employeeId,
        points: String(points),
        shopAddress
      });
      console.log(`${this.tag} Penalty notification sent to ${employeeName} (${employeePhone})`);
    } catch (e) {
      console.error(`${this.tag} Error sending penalty notification to ${employeePhone}:`, e.message);
    }
  }

  // ==================== CLEANUP ====================

  async cleanupFailedReports() {
    let removedCount = 0;

    try {
      if (!(await fileExists(this.ATTENDANCE_PENDING_DIR))) return 0;

      const files = await fsp.readdir(this.ATTENDANCE_PENDING_DIR);
      for (const file of files) {
        if (file.endsWith('.json')) {
          try {
            await fsp.unlink(path.join(this.ATTENDANCE_PENDING_DIR, file));
            removedCount++;
          } catch (e) {
            console.error(`${this.tag} Error removing file ${file}:`, e.message);
          }
        }
      }
    } catch (e) {
      console.error(`${this.tag} Error reading pending directory:`, e.message);
    }

    if (removedCount > 0) {
      console.log(`${this.tag} Cleanup: removed ${removedCount} attendance files`);
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

  // ==================== API HELPERS ====================

  async canMarkAttendance(shopAddress) {
    const pendingReports = await this.loadTodayPendingReports();
    return pendingReports.filter(r => r.status === 'pending').some(r => r.shopAddress === shopAddress);
  }

  async markPendingAsCompleted(shopAddress, shiftType) {
    const reports = await this.loadTodayPendingReports();
    const report = reports.find(r =>
      r.shopAddress === shopAddress &&
      r.shiftType === shiftType &&
      r.status === 'pending'
    );

    if (report && report._filePath && (await fileExists(report._filePath))) {
      await fsp.unlink(report._filePath);
      console.log(`${this.tag} Removed pending report for ${shopAddress} (${shiftType})`);
      return true;
    }
    return false;
  }
}

// Singleton
const scheduler = new AttendanceScheduler();

// Ensure directories
(async () => {
  for (const dir of [scheduler.ATTENDANCE_PENDING_DIR, scheduler.ATTENDANCE_DIR, scheduler.stateDir]) {
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
  startAttendanceAutomationScheduler: () => scheduler.start(),
  generatePendingReports: (shiftType) => scheduler.generatePendingReports(shiftType),
  checkPendingDeadlines: () => scheduler.checkPendingDeadlines(),
  cleanupFailedReports: () => scheduler.cleanupFailedReports(),
  loadTodayPendingReports: () => scheduler.loadTodayPendingReports(),
  getPendingReports,
  getFailedReports,
  canMarkAttendance: (addr) => scheduler.canMarkAttendance(addr),
  markPendingAsCompleted: (addr, shift) => scheduler.markPendingAsCompleted(addr, shift),
  getAttendanceSettings: () => scheduler.getSettings(),
  getMoscowTime,
  getMoscowDateString
};
