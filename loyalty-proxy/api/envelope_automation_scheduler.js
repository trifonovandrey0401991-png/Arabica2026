/**
 * Envelope Automation Scheduler
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 * REFACTORED: Migrated to BaseReportScheduler (2026-02-17)
 * REFACTORED: Added PostgreSQL support for loadAllSubmittedReportsForDate (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('../utils/async_fs');
const { fileExists } = require('../utils/file_helpers');
const { getMoscowTime } = require('../utils/moscow_time');
const BaseReportScheduler = require('../utils/base_report_scheduler');
const db = require('../utils/db');
const { loadShopManagers } = require('./shop_managers_api');

const USE_DB = process.env.USE_DB_ENVELOPE === 'true';

// Директории
const DATA_DIR = process.env.DATA_DIR || '/var/www';

class EnvelopeScheduler extends BaseReportScheduler {
  constructor() {
    super({
      name: 'Envelope',
      stateDir: `${DATA_DIR}/envelope-automation-state`,
      penaltyCategory: 'envelope_missed_penalty',
      penaltyCategoryName: 'Конверт - несдан',
      penaltyPrefix: 'penalty_env_',
      sourceType: 'envelope',
      notificationTitle: 'Конверты не сданы',
      notificationBodyFn: (count) => `Конверты не сданы - ${count}`,
      notificationType: 'envelope_failed',
    });

    this.PENDING_DIR = `${this.DATA_DIR}/envelope-pending`;
    this.REPORTS_DIR = `${this.DATA_DIR}/envelope-reports`;
    this.SHOPS_FILE = `${this.DATA_DIR}/shops/shops.json`;
    this.POINTS_SETTINGS_FILE = `${this.DATA_DIR}/points-settings/envelope_points_settings.json`;
  }

  // ==================== SETTINGS ====================

  async getSettings() {
    if (!(await fileExists(this.POINTS_SETTINGS_FILE))) {
      return {
        morningStartTime: '07:00',
        morningEndTime: '09:00',
        morningDeadline: '09:00',
        eveningStartTime: '19:00',
        eveningEndTime: '21:00',
        eveningDeadline: '21:00',
        missedPenalty: -5.0,
        notSubmittedPoints: -5.0,
        adminReviewTimeout: 0
      };
    }
    try {
      return JSON.parse(await fsp.readFile(this.POINTS_SETTINGS_FILE, 'utf8'));
    } catch (e) {
      console.error(`${this.tag} Error parsing points settings:`, e.message);
      return null;
    }
  }

  // ==================== SHOPS (override — reads shops.json) ====================

  async getAllShops() {
    if (!(await fileExists(this.SHOPS_FILE))) {
      console.log(`${this.tag} Файл магазинов не найден`);
      return [];
    }

    const shopsData = JSON.parse(await fsp.readFile(this.SHOPS_FILE, 'utf8'));
    const shops = shopsData.shops || shopsData || [];

    if (!Array.isArray(shops)) {
      console.error(`${this.tag} Ошибка: shops не является массивом, получено:`, typeof shops);
      return [];
    }

    return shops;
  }

  // ==================== BATCH LOADING (unique to envelope) ====================

  /**
   * Загрузить ВСЕ pending отчёты за дату в Map для O(1) поиска
   */
  async loadAllPendingReportsForDate(date) {
    const pendingMap = new Map();

    if (!(await fileExists(this.PENDING_DIR))) {
      return pendingMap;
    }

    const files = await fsp.readdir(this.PENDING_DIR);

    for (const file of files) {
      if (!file.startsWith('pending_env_') || !file.endsWith('.json')) continue;

      try {
        const filePath = path.join(this.PENDING_DIR, file);
        const data = JSON.parse(await fsp.readFile(filePath, 'utf8'));

        if (data.date === date) {
          const key = `${data.shopAddress}|${data.shiftType}|${data.date}`;
          data._filePath = filePath;
          pendingMap.set(key, data);
        }
      } catch (error) {
        console.error(`${this.tag} Ошибка чтения ${file}:`, error.message);
      }
    }

    console.log(`${this.tag} Загружено ${pendingMap.size} pending отчётов за ${date}`);
    return pendingMap;
  }

  /**
   * Загрузить ВСЕ сданные отчёты за дату в Set для O(1) проверки
   */
  async loadAllSubmittedReportsForDate(date) {
    const submittedSet = new Set();

    if (USE_DB) {
      try {
        const result = await db.query(
          'SELECT shop_address, shift_type FROM envelope_reports WHERE date = $1',
          [date]
        );
        for (const row of result.rows) {
          const key = `${row.shop_address}|${row.shift_type}|${date}`;
          submittedSet.add(key);
        }
        console.log(`${this.tag} Загружено ${submittedSet.size} сданных отчётов за ${date} (DB)`);
        return submittedSet;
      } catch (err) {
        console.error(`${this.tag} DB error in loadAllSubmittedReportsForDate:`, err.message);
        // Fallback to files
      }
    }

    if (!(await fileExists(this.REPORTS_DIR))) {
      return submittedSet;
    }

    const files = await fsp.readdir(this.REPORTS_DIR);

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const filePath = path.join(this.REPORTS_DIR, file);
        const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));

        const reportDate = report.createdAt ? report.createdAt.split('T')[0] : null;

        if (reportDate === date) {
          const key = `${report.shopAddress}|${report.shiftType}|${reportDate}`;
          submittedSet.add(key);
        }
      } catch (error) {
        console.error(`${this.tag} Ошибка чтения ${file}:`, error.message);
      }
    }

    console.log(`${this.tag} Загружено ${submittedSet.size} сданных отчётов за ${date}`);
    return submittedSet;
  }

  // ==================== GENERATE PENDING ====================

  async generatePendingReports(shiftType) {
    const startTime = Date.now();
    console.log(`${this.tag} Создание pending отчетов для ${shiftType}`);

    const shops = await this.getAllShops();
    if (shops.length === 0) return 0;

    const settings = await this.getSettings();
    const deadline = shiftType === 'morning' ? settings.morningDeadline : settings.eveningDeadline;

    const moscow = getMoscowTime();
    const today = moscow.toISOString().split('T')[0];

    // OPTIMIZATION: Загрузить ВСЕ данные ОДИН раз
    const pendingMap = await this.loadAllPendingReportsForDate(today);
    const submittedSet = await this.loadAllSubmittedReportsForDate(today);

    let created = 0;
    let skippedPending = 0;
    let skippedSubmitted = 0;

    for (const shop of shops) {
      const shopAddress = shop.address;
      const lookupKey = `${shopAddress}|${shiftType}|${today}`;

      if (pendingMap.has(lookupKey)) {
        skippedPending++;
        continue;
      }

      if (submittedSet.has(lookupKey)) {
        skippedSubmitted++;
        continue;
      }

      const report = {
        id: `pending_env_${shiftType}_${shopAddress.replace(/[^a-zA-Z0-9а-яА-Я]/g, '_')}_${Date.now()}`,
        shopAddress: shopAddress,
        shiftType: shiftType,
        status: 'pending',
        date: today,
        deadline: deadline,
        createdAt: moscow.toISOString(),
        failedAt: null
      };

      const filePath = path.join(this.PENDING_DIR, `${report.id}.json`);
      await writeJsonFile(filePath, report);
      created++;
    }

    const elapsed = Date.now() - startTime;
    console.log(`${this.tag} Создано pending: ${created}, пропущено (pending): ${skippedPending}, пропущено (сдано): ${skippedSubmitted}, время: ${elapsed}ms`);
    return created;
  }

  // ==================== CHECK DEADLINES ====================

  async checkPendingDeadlines() {
    const startTime = Date.now();
    const moscow = getMoscowTime();
    const today = moscow.toISOString().split('T')[0];
    const settings = await this.getSettings();

    const pendingMap = await this.loadAllPendingReportsForDate(today);
    const reports = Array.from(pendingMap.values());

    if (reports.length === 0) {
      return 0;
    }

    const submittedSet = await this.loadAllSubmittedReportsForDate(today);

    const failedReports = [];
    let removedCount = 0;

    for (const report of reports) {
      if (report.status !== 'pending') continue;

      const lookupKey = `${report.shopAddress}|${report.shiftType}|${report.date}`;

      // O(1) проверка: может быть конверт уже сдан?
      if (submittedSet.has(lookupKey)) {
        try {
          await fsp.unlink(report._filePath);
          removedCount++;
        } catch (e) {
          console.error(`${this.tag} Ошибка удаления pending: ${e.message}`);
        }
        continue;
      }

      // Проверить дедлайн
      const [deadlineHours, deadlineMinutes] = report.deadline.split(':').map(Number);
      const deadlineMinutesTotal = deadlineHours * 60 + deadlineMinutes;
      const currentMinutesTotal = moscow.getUTCHours() * 60 + moscow.getUTCMinutes();

      if (currentMinutesTotal >= deadlineMinutesTotal) {
        // Дедлайн прошел!
        report.status = 'failed';
        report.failedAt = moscow.toISOString();

        await writeJsonFile(report._filePath, report);

        // Назначить штраф через базовый класс
        const penalty = await this.assignPenaltyFromSchedule(
          report,
          settings.missedPenalty || settings.notSubmittedPoints,
          (r) => `Не сдан конверт (${r.shiftType === 'morning' ? 'утренняя' : 'вечерняя'} смена)`
        );

        // Push сотруднику
        if (penalty && penalty.employeePhone) {
          const shiftName = report.shiftType === 'morning' ? 'утреннюю' : 'вечернюю';
          await this.sendPushToEmployee(
            penalty.employeePhone,
            'Штраф за несданный конверт',
            `Вам начислен штраф ${penalty.points} баллов за несданный конверт (${shiftName} смена)`,
            { type: 'envelope_penalty', points: String(penalty.points) }
          );
        }

        failedReports.push(report);

        console.log(`${this.tag} Дедлайн истек: ${report.shopAddress} (${report.shiftType})`);
      }
    }

    // Отправить уведомление админу
    if (failedReports.length > 0) {
      await this.sendAdminFailedNotification(failedReports.length, failedReports);
    }

    const elapsed = Date.now() - startTime;
    console.log(`${this.tag} Проверка дедлайнов: ${failedReports.length} failed, ${removedCount} удалено (сданы), время: ${elapsed}ms`);

    return failedReports.length;
  }

  // ==================== FIND MANAGER FOR SHOP ====================

  async findManagerForShop(shopAddress) {
    try {
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

  // ==================== CHECK ADMIN REVIEW TIMEOUT (override) ====================

  async checkReviewTimeouts() {
    const settings = await this.getSettings();
    const timeoutHours = settings.adminReviewTimeout || 0;
    if (timeoutHours <= 0) return 0; // Отключено

    const now = new Date();
    let rejectedCount = 0;

    // DB: найти конверты со статусом 'pending' в envelope_reports старше таймаута
    if (USE_DB) {
      try {
        const cutoff = new Date(now.getTime() - timeoutHours * 60 * 60 * 1000).toISOString();
        const stuckRows = await db.query(
          `SELECT id, shop_address, shift_type, employee_name, employee_phone, created_at
           FROM envelope_reports WHERE status = 'pending'
           AND created_at IS NOT NULL AND created_at < $1`,
          [cutoff]
        );

        for (const row of stuckRows.rows || stuckRows) {
          await db.query(
            `UPDATE envelope_reports SET status = 'rejected', updated_at = $1 WHERE id = $2`,
            [now.toISOString(), row.id]
          );

          // Dual-write: обновить файл
          const filePath = path.join(this.REPORTS_DIR, `${row.id}.json`);
          if (await fileExists(filePath)) {
            try {
              const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
              report.status = 'rejected';
              report.rejectedAt = now.toISOString();
              report.rejectReason = `Автоотклонение: не проверен за ${timeoutHours} ч`;
              await writeJsonFile(filePath, report);
            } catch (e) { /* skip */ }
          }

          // Штраф управляющей
          const manager = await this.findManagerForShop(row.shop_address);
          if (manager) {
            const shiftName = row.shift_type === 'morning' ? 'утренняя' : 'вечерняя';
            await this.createPenalty({
              employeeId: manager.phone,
              employeeName: manager.name,
              employeePhone: manager.phone,
              shopAddress: row.shop_address,
              points: settings.missedPenalty || settings.notSubmittedPoints,
              reason: `Конверт не проверен за ${timeoutHours} ч — ${row.shop_address} (${shiftName} смена)`,
              sourceId: `${row.id}_admin_penalty`
            });
            console.log(`${this.tag} Auto-rejected (admin timeout ${timeoutHours}h): ${row.shop_address}, penalty → manager: ${manager.name}`);
          } else {
            console.log(`${this.tag} Auto-rejected (admin timeout ${timeoutHours}h): ${row.shop_address} — no manager found`);
          }

          rejectedCount++;
        }
      } catch (dbErr) {
        console.error(`${this.tag} DB review timeout check error:`, dbErr.message);
      }
    }

    // File fallback
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

              report.status = 'rejected';
              report.rejectedAt = now.toISOString();
              report.rejectReason = `Автоотклонение: не проверен за ${timeoutHours} ч`;
              await writeJsonFile(filePath, report);

              if (USE_DB) {
                try {
                  await db.query(
                    `UPDATE envelope_reports SET status = 'rejected', updated_at = $1 WHERE id = $2`,
                    [now.toISOString(), report.id]
                  );
                } catch (e) { /* skip */ }
              }

              // Штраф управляющей
              const manager = await this.findManagerForShop(report.shopAddress);
              if (manager) {
                const shiftName = report.shiftType === 'morning' ? 'утренняя' : 'вечерняя';
                await this.createPenalty({
                  employeeId: manager.phone,
                  employeeName: manager.name,
                  employeePhone: manager.phone,
                  shopAddress: report.shopAddress,
                  points: settings.missedPenalty || settings.notSubmittedPoints,
                  reason: `Конверт не проверен за ${timeoutHours} ч — ${report.shopAddress} (${shiftName} смена)`,
                  sourceId: `${report.id}_admin_penalty`
                });
                console.log(`${this.tag} Auto-rejected (file, admin timeout ${timeoutHours}h): ${report.shopAddress}, penalty → manager: ${manager.name}`);
              }

              rejectedCount++;
            } catch (e) { /* skip malformed files */ }
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
    console.log(`${this.tag} Очистка pending/failed отчетов (23:59)`);

    if (!(await fileExists(this.PENDING_DIR))) {
      console.log(`${this.tag} Директория pending не существует`);
      return;
    }

    const files = await fsp.readdir(this.PENDING_DIR);
    let deleted = 0;

    for (const file of files) {
      if (file.startsWith('pending_env_')) {
        await fsp.unlink(path.join(this.PENDING_DIR, file));
        deleted++;
      }
    }

    console.log(`${this.tag} Удалено pending файлов: ${deleted}`);

    // Сбросить state
    const state = {
      lastMorningGeneration: null,
      lastEveningGeneration: null,
      lastCleanup: new Date().toISOString(),
      lastCheck: new Date().toISOString()
    };

    await writeJsonFile(this.stateFile, state);
  }
}

// Singleton
const scheduler = new EnvelopeScheduler();

// Ensure directories exist (async IIFE)
(async () => {
  for (const dir of [scheduler.PENDING_DIR, scheduler.REPORTS_DIR, scheduler.stateDir]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

module.exports = {
  startScheduler: () => scheduler.start()
};
