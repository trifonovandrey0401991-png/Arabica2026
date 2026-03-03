/**
 * Coffee Machine Automation Scheduler
 *
 * По паттерну envelope_automation_scheduler.js.
 *
 * REFACTORED: Migrated to BaseReportScheduler (2026-02-17)
 * REFACTORED: Added PostgreSQL support for loadAllSubmittedForDate (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('../utils/async_fs');
const { fileExists } = require('../utils/file_helpers');
const { getMoscowTime } = require('../utils/moscow_time');
const BaseReportScheduler = require('../utils/base_report_scheduler');
const db = require('../utils/db');
const { loadShopManagers } = require('./shop_managers_api');
const { generateId } = require('../utils/id_generator');

const USE_DB = process.env.USE_DB_COFFEE_MACHINE === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';

class CoffeeMachineScheduler extends BaseReportScheduler {
  constructor() {
    super({
      name: 'CoffeeMachine',
      stateDir: `${DATA_DIR}/coffee-machine-automation-state`,
      penaltyCategory: 'coffee_machine_missed_penalty',
      penaltyCategoryName: 'Счётчик кофемашин - несдан',
      penaltyPrefix: 'penalty_cm_',
      sourceType: 'coffee_machine',
      notificationTitle: 'Счётчики кофемашин не сданы',
      notificationBodyFn: (count) => `Счётчики кофемашин не сданы - ${count}`,
      notificationType: 'coffee_machine_failed',
    });

    this.PENDING_DIR = `${this.DATA_DIR}/coffee-machine-pending`;
    this.REPORTS_DIR = `${this.DATA_DIR}/coffee-machine-reports`;
    this.SHOPS_FILE = `${this.DATA_DIR}/shops/shops.json`;
    this.SHOP_CONFIGS_DIR = `${this.DATA_DIR}/coffee-machine-shop-configs`;
    this.POINTS_SETTINGS_FILE = `${this.DATA_DIR}/points-settings/coffee_machine_points_settings.json`;
  }

  // ==================== SETTINGS ====================

  async getSettings() {
    if (!(await fileExists(this.POINTS_SETTINGS_FILE))) {
      return {
        morningStartTime: '07:00',
        morningEndTime: '12:00',
        morningDeadline: '12:00',
        eveningStartTime: '14:00',
        eveningEndTime: '22:00',
        eveningDeadline: '22:00',
        submittedPoints: 1.0,
        notSubmittedPoints: -3.0,
        missedPenalty: -3.0,
        adminReviewTimeoutHours: 4,
      };
    }
    try {
      return JSON.parse(await fsp.readFile(this.POINTS_SETTINGS_FILE, 'utf8'));
    } catch (e) {
      console.error(`${this.tag} Error parsing points settings:`, e.message);
      return null;
    }
  }

  // ==================== FIND MANAGER FOR SHOP ====================

  /**
   * Найти управляющую по адресу магазина
   * shop_address → shop_id → manager (from shop_managers)
   * @returns {{ name: string, phone: string } | null}
   */
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
      if (!shopId && await fileExists(this.SHOPS_FILE)) {
        try {
          const shopsData = JSON.parse(await fsp.readFile(this.SHOPS_FILE, 'utf8'));
          const shops = shopsData.shops || shopsData || [];
          const shop = shops.find(s => s.address === shopAddress);
          if (shop) shopId = shop.id;
        } catch (e) { /* skip */ }
      }

      if (!shopId) {
        console.log(`${this.tag} Shop not found for address: ${shopAddress}`);
        return null;
      }

      // 2. Найти управляющую, у которой этот магазин в managedShops
      const managersData = await loadShopManagers();
      const managers = managersData.managers || [];

      const manager = managers.find(m =>
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

  // ==================== SHOPS (override — only shops with coffee machines) ====================

  async getAllShops() {
    if (!(await fileExists(this.SHOPS_FILE))) return [];

    let shopsData;
    try {
      shopsData = JSON.parse(await fsp.readFile(this.SHOPS_FILE, 'utf8'));
    } catch (e) {
      console.error(`${this.tag} Error parsing shops file:`, e.message);
      return [];
    }
    const shops = shopsData.shops || shopsData || [];
    if (!Array.isArray(shops)) return [];

    // Фильтр: только магазины с настроенными кофемашинами
    if (!(await fileExists(this.SHOP_CONFIGS_DIR))) return [];

    const configFiles = (await fsp.readdir(this.SHOP_CONFIGS_DIR)).filter(f => f.endsWith('.json'));
    const configuredShops = new Set();

    for (const file of configFiles) {
      try {
        const config = JSON.parse(await fsp.readFile(path.join(this.SHOP_CONFIGS_DIR, file), 'utf8'));
        if (config.machineTemplateIds && config.machineTemplateIds.length > 0) {
          configuredShops.add(config.shopAddress);
        }
      } catch (e) {
        console.error(`${this.tag} Error reading config ${file}:`, e.message);
      }
    }

    return shops.filter(s => configuredShops.has(s.address));
  }

  // ==================== BATCH LOADING ====================

  async loadAllPendingForDate(date) {
    const pendingMap = new Map();
    if (!(await fileExists(this.PENDING_DIR))) return pendingMap;

    const files = await fsp.readdir(this.PENDING_DIR);
    for (const file of files) {
      if (!file.startsWith('pending_cm_') || !file.endsWith('.json')) continue;
      try {
        const filePath = path.join(this.PENDING_DIR, file);
        const data = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        if (data.date === date) {
          const key = `${data.shopAddress}|${data.shiftType}|${data.date}`;
          data._filePath = filePath;
          pendingMap.set(key, data);
        }
      } catch (e) {
        console.error(`${this.tag} Error reading pending ${file}:`, e.message);
      }
    }
    return pendingMap;
  }

  async loadAllSubmittedForDate(date) {
    const submittedSet = new Set();

    if (USE_DB) {
      try {
        const result = await db.query(
          'SELECT shop_address, shift_type FROM coffee_machine_reports WHERE date = $1',
          [date]
        );
        for (const row of result.rows) {
          const key = `${row.shop_address}|${row.shift_type}|${date}`;
          submittedSet.add(key);
        }
        console.log(`${this.tag} Загружено ${submittedSet.size} сданных отчётов за ${date} (DB)`);
        return submittedSet;
      } catch (err) {
        console.error(`${this.tag} DB error in loadAllSubmittedForDate:`, err.message);
        // Fallback to files
      }
    }

    if (!(await fileExists(this.REPORTS_DIR))) return submittedSet;

    const files = await fsp.readdir(this.REPORTS_DIR);
    for (const file of files) {
      if (!file.endsWith('.json')) continue;
      try {
        const filePath = path.join(this.REPORTS_DIR, file);
        const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        const reportDate = report.date || (report.createdAt ? report.createdAt.split('T')[0] : null);
        if (reportDate === date) {
          const key = `${report.shopAddress}|${report.shiftType}|${reportDate}`;
          submittedSet.add(key);
        }
      } catch (e) {
        // skip
      }
    }
    return submittedSet;
  }

  // ==================== GENERATE PENDING ====================

  async generatePendingReports(shiftType) {
    const startTime = Date.now();
    console.log(`${this.tag} Создание pending для ${shiftType}`);

    const shops = await this.getAllShops();
    if (shops.length === 0) {
      console.log(`${this.tag} Нет магазинов с настроенными кофемашинами`);
      return 0;
    }

    const settings = await this.getSettings();
    const deadline = shiftType === 'morning' ? settings.morningDeadline : settings.eveningDeadline;

    const moscow = getMoscowTime();
    const today = moscow.toISOString().split('T')[0];

    const pendingMap = await this.loadAllPendingForDate(today);
    const submittedSet = await this.loadAllSubmittedForDate(today);

    let created = 0;

    for (const shop of shops) {
      const shopAddress = shop.address;
      const lookupKey = `${shopAddress}|${shiftType}|${today}`;

      if (pendingMap.has(lookupKey) || submittedSet.has(lookupKey)) {
        continue;
      }

      const report = {
        id: generateId(`pending_cm_${shiftType}_${shopAddress.replace(/[^a-zA-Z0-9а-яА-Я]/g, '_')}`),
        shopAddress,
        shiftType,
        status: 'pending',
        date: today,
        deadline,
        createdAt: moscow.toISOString(),
        failedAt: null,
      };

      const filePath = path.join(this.PENDING_DIR, `${report.id}.json`);
      await writeJsonFile(filePath, report);
      created++;
    }

    const elapsed = Date.now() - startTime;
    console.log(`${this.tag} Создано pending: ${created}, время: ${elapsed}ms`);
    return created;
  }

  // ==================== CHECK DEADLINES ====================

  async checkPendingDeadlines() {
    const moscow = getMoscowTime();
    const today = moscow.toISOString().split('T')[0];
    const settings = await this.getSettings();

    const pendingMap = await this.loadAllPendingForDate(today);
    const reports = Array.from(pendingMap.values());
    if (reports.length === 0) return 0;

    const submittedSet = await this.loadAllSubmittedForDate(today);
    const failedReports = [];

    for (const report of reports) {
      if (report.status !== 'pending') continue;

      const lookupKey = `${report.shopAddress}|${report.shiftType}|${report.date}`;

      // Уже сдан — удалить pending
      if (submittedSet.has(lookupKey)) {
        try { await fsp.unlink(report._filePath); } catch (e) { /* ignore */ }
        continue;
      }

      // Проверить дедлайн
      const [dH, dM] = report.deadline.split(':').map(Number);
      const deadlineMinutes = dH * 60 + dM;
      const currentMinutes = moscow.getUTCHours() * 60 + moscow.getUTCMinutes();

      if (currentMinutes >= deadlineMinutes) {
        report.status = 'failed';
        report.failedAt = moscow.toISOString();
        await writeJsonFile(report._filePath, report);

        // Штраф через базовый класс
        const penalty = await this.assignPenaltyFromSchedule(
          report,
          settings.missedPenalty || settings.notSubmittedPoints,
          (r) => `Не сдан счётчик кофемашин (${r.shiftType === 'morning' ? 'утренняя' : 'вечерняя'} смена)`
        );

        // Push сотруднику
        if (penalty && penalty.employeePhone) {
          const shiftName = report.shiftType === 'morning' ? 'утреннюю' : 'вечернюю';
          await this.sendPushToEmployee(
            penalty.employeePhone,
            'Штраф за несданный счётчик',
            `Вам начислен штраф ${penalty.points} баллов за несданный счётчик кофемашин (${shiftName} смена)`,
            { type: 'coffee_machine_penalty', points: String(penalty.points) }
          );
        }

        failedReports.push(report);
        console.log(`${this.tag} Дедлайн истёк: ${report.shopAddress} (${report.shiftType})`);
      }
    }

    if (failedReports.length > 0) {
      await this.sendAdminFailedNotification(failedReports.length, failedReports);
    }

    return failedReports.length;
  }

  // ==================== CHECK ADMIN REVIEW TIMEOUT (override) ====================

  async checkReviewTimeouts() {
    const now = new Date();
    const settings = await this.getSettings();
    const timeoutHours = settings.adminReviewTimeoutHours || 4;
    let rejectedCount = 0;

    // DB check: find reports with status 'pending' older than timeout
    if (USE_DB) {
      try {
        const cutoff = new Date(now.getTime() - timeoutHours * 60 * 60 * 1000);
        const stuckRows = await db.query(
          `SELECT id, shop_address, shift_type, employee_name, employee_phone, created_at
           FROM coffee_machine_reports WHERE status = 'pending'
           AND created_at IS NOT NULL AND created_at < $1`,
          [cutoff.toISOString()]
        );

        for (const row of stuckRows.rows || stuckRows) {
          await db.query(
            `UPDATE coffee_machine_reports SET status = 'confirmed', confirmed_at = $1, auto_rated = true, reject_reason = $2, updated_at = $1 WHERE id = $3`,
            [now.toISOString(), `Авто-подтверждение: админ не проверил за ${timeoutHours} ч`, row.id]
          );

          // Also update JSON file if exists
          const filePath = path.join(this.REPORTS_DIR, `${row.id.replace(/[^a-zA-Z0-9_-]/g, '_')}.json`);
          if (await fileExists(filePath)) {
            try {
              const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
              report.status = 'confirmed';
              report.confirmedAt = now.toISOString();
              report.autoRated = true;
              report.rejectReason = `Авто-подтверждение: админ не проверил за ${timeoutHours} ч`;
              await writeJsonFile(filePath, report);
            } catch (e) { /* skip */ }
          }

          // Assign penalty to MANAGER (управляющая), not employee
          const manager = await this.findManagerForShop(row.shop_address);
          const shiftName = row.shift_type === 'morning' ? 'утренняя' : 'вечерняя';

          if (manager) {
            const penalty = await this.createPenalty({
              employeeId: manager.phone,
              employeeName: manager.name,
              employeePhone: manager.phone,
              shopAddress: row.shop_address,
              points: settings.missedPenalty || settings.notSubmittedPoints,
              reason: `Не проверен счётчик кофемашин за ${timeoutHours} ч — ${row.shop_address} (${shiftName} смена)`,
              sourceId: row.id
            });

            // Push notification to manager
            if (penalty) {
              await this.sendPushToEmployee(
                manager.phone,
                'Штраф: не проверен счётчик',
                `Вам начислен штраф ${penalty.points} баллов — отчёт ${row.employee_name} не проверен за ${timeoutHours} ч (${shiftName} смена, ${row.shop_address})`,
                { type: 'coffee_machine_auto_rejected' }
              );
            }
            console.log(`${this.tag} AUTO-CONFIRMED (admin timeout ${timeoutHours}h): ${row.shop_address} (${row.shift_type}), penalty → manager: ${manager.name}`);
          } else {
            console.log(`${this.tag} AUTO-CONFIRMED (admin timeout ${timeoutHours}h): ${row.shop_address} (${row.shift_type}) — no manager found, penalty skipped`);
          }

          rejectedCount++;
        }
      } catch (dbErr) {
        console.error(`${this.tag} DB review timeout check error:`, dbErr.message);
      }
    }

    // File fallback: check JSON report files
    if (!USE_DB || rejectedCount === 0) {
      try {
        if (await fileExists(this.REPORTS_DIR)) {
          const files = await fsp.readdir(this.REPORTS_DIR);
          const cutoff = new Date(now.getTime() - timeoutHours * 60 * 60 * 1000);

          for (const file of files) {
            if (!file.endsWith('.json')) continue;
            try {
              const filePath = path.join(this.REPORTS_DIR, file);
              const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));

              if (report.status !== 'pending') continue;
              if (!report.createdAt) continue;

              const createdAt = new Date(report.createdAt);
              if (createdAt >= cutoff) continue;

              report.status = 'confirmed';
              report.confirmedAt = now.toISOString();
              report.autoRated = true;
              report.rejectReason = `Авто-подтверждение: админ не проверил за ${timeoutHours} ч`;
              await writeJsonFile(filePath, report);

              // DB update if available
              if (USE_DB) {
                try {
                  await db.query(
                    `UPDATE coffee_machine_reports SET status = 'confirmed', confirmed_at = $1, auto_rated = true, reject_reason = $2, updated_at = $1 WHERE id = $3`,
                    [now.toISOString(), report.rejectReason, report.id]
                  );
                } catch (e) { /* skip */ }
              }

              // Assign penalty to MANAGER (управляющая), not employee
              const manager = await this.findManagerForShop(report.shopAddress);
              const shiftName = report.shiftType === 'morning' ? 'утренняя' : 'вечерняя';

              if (manager) {
                const penalty = await this.createPenalty({
                  employeeId: manager.phone,
                  employeeName: manager.name,
                  employeePhone: manager.phone,
                  shopAddress: report.shopAddress,
                  points: settings.missedPenalty || settings.notSubmittedPoints,
                  reason: `Не проверен счётчик кофемашин за ${timeoutHours} ч — ${report.shopAddress} (${shiftName} смена)`,
                  sourceId: report.id
                });

                if (penalty) {
                  await this.sendPushToEmployee(
                    manager.phone,
                    'Штраф: не проверен счётчик',
                    `Вам начислен штраф ${penalty.points} баллов — отчёт ${report.employeeName} не проверен за ${timeoutHours} ч (${shiftName} смена, ${report.shopAddress})`,
                    { type: 'coffee_machine_auto_rejected' }
                  );
                }
                console.log(`${this.tag} AUTO-CONFIRMED (file, admin timeout ${timeoutHours}h): ${report.shopAddress} (${report.shiftType}), penalty → manager: ${manager.name}`);
              } else {
                console.log(`${this.tag} AUTO-CONFIRMED (file, admin timeout ${timeoutHours}h): ${report.shopAddress} (${report.shiftType}) — no manager found, penalty skipped`);
              }

              rejectedCount++;
            } catch (e) {
              // skip malformed files
            }
          }
        }
      } catch (e) {
        console.error(`${this.tag} File review timeout check error:`, e.message);
      }
    }

    return rejectedCount;
  }

  // ==================== CLEANUP ====================

  async cleanupFailedReports() {
    console.log(`${this.tag} Очистка pending/failed отчётов (23:59)`);

    if (!(await fileExists(this.PENDING_DIR))) return;

    const files = await fsp.readdir(this.PENDING_DIR);
    let deleted = 0;

    for (const file of files) {
      if (file.startsWith('pending_cm_')) {
        await fsp.unlink(path.join(this.PENDING_DIR, file));
        deleted++;
      }
    }

    console.log(`${this.tag} Удалено pending файлов: ${deleted}`);

    const state = {
      lastMorningGeneration: null,
      lastEveningGeneration: null,
      lastCleanup: new Date().toISOString(),
      lastCheck: new Date().toISOString(),
    };
    await writeJsonFile(this.stateFile, state);
  }
}

// Singleton
const scheduler = new CoffeeMachineScheduler();

// Ensure directories
(async () => {
  for (const dir of [scheduler.PENDING_DIR, scheduler.REPORTS_DIR, scheduler.stateDir, scheduler.SHOP_CONFIGS_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

// API exports
function getPendingReports() {
  return scheduler.loadAllPendingForDate(getMoscowTime().toISOString().split('T')[0]);
}

function getFailedReports() {
  return scheduler.loadAllPendingForDate(getMoscowTime().toISOString().split('T')[0])
    .then(map => Array.from(map.values()).filter(r => r.status === 'failed'));
}

module.exports = {
  startCoffeeMachineAutomation: () => scheduler.start(),
  getPendingReports,
  getFailedReports,
};
