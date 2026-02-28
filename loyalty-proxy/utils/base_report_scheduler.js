/**
 * Base Report Scheduler
 *
 * Базовый класс для шедулеров отчётов. Содержит общую логику:
 * - Управление состоянием (loadState/saveState)
 * - Загрузка магазинов (getAllShops — индивидуальные файлы shop_*.json)
 * - Хелперы времени (parseTime, isWithinTimeWindow, isSameDay, getDeadlineTime)
 * - Создание штрафов (createPenalty, assignPenaltyFromSchedule)
 * - Push-уведомления (sendAdminFailedNotification)
 * - Guarded interval (защита от параллельного запуска)
 * - Шаблон runScheduledChecks (утренние/вечерние окна + дедлайны + cleanup)
 *
 * Используется 7 шедулерами: rko, shift, recount, shift_handover,
 * attendance, envelope, coffee_machine.
 * (product_questions имеет другую архитектуру и не использует этот класс)
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('./async_fs');
const { withLock } = require('./file_lock');
const { fileExists, loadJsonFile } = require('./file_helpers');
const { getMoscowTime, getMoscowDateString, MOSCOW_OFFSET_HOURS } = require('./moscow_time');
const db = require('./db');

const USE_DB_EFFICIENCY = process.env.USE_DB_EFFICIENCY === 'true';

class BaseReportScheduler {
  /**
   * @param {Object} config
   * @param {string} config.name - Имя шедулера для логов, например 'Rko'
   * @param {string} config.stateDir - Путь к директории состояния
   * @param {Object} [config.defaultState] - Начальное состояние
   * @param {string} config.penaltyCategory - Код категории штрафа
   * @param {string} config.penaltyCategoryName - Название категории штрафа
   * @param {string} config.penaltyPrefix - Префикс ID штрафа, например 'penalty_rko_'
   * @param {string} config.sourceType - Тип источника, например 'rko_report'
   * @param {string} config.notificationTitle - Заголовок push при failed
   * @param {Function} config.notificationBodyFn - (count, shiftLabel) => string
   * @param {string} config.notificationType - Тип push-данных, например 'rko_failed'
   * @param {number} [config.checkIntervalMs=300000] - Интервал проверки (мс)
   * @param {number} [config.startupDelayMs=2000] - Задержка первого запуска (мс)
   * @param {string} [config.shopsDir] - Путь к магазинам (по умолчанию DATA_DIR/shops)
   */
  constructor(config) {
    this.name = config.name;
    this.tag = `[${config.name}Scheduler]`;

    this.DATA_DIR = process.env.DATA_DIR || '/var/www';
    this.SHOPS_DIR = config.shopsDir || `${this.DATA_DIR}/shops`;
    this.WORK_SCHEDULES_DIR = `${this.DATA_DIR}/work-schedules`;
    this.EFFICIENCY_PENALTIES_DIR = `${this.DATA_DIR}/efficiency-penalties`;

    this.stateDir = config.stateDir;
    this.stateFile = path.join(config.stateDir, 'state.json');
    this.defaultState = config.defaultState || {
      lastMorningGeneration: null,
      lastEveningGeneration: null,
      lastCleanup: null,
      lastCheck: null
    };

    this.penaltyCategory = config.penaltyCategory;
    this.penaltyCategoryName = config.penaltyCategoryName;
    this.penaltyPrefix = config.penaltyPrefix;
    this.sourceType = config.sourceType;

    this.checkIntervalMs = config.checkIntervalMs || 5 * 60 * 1000;
    this.startupDelayMs = config.startupDelayMs || 2000;

    this.notificationTitle = config.notificationTitle;
    this.notificationBodyFn = config.notificationBodyFn;
    this.notificationType = config.notificationType;

    // Push notification functions (lazy-load)
    this._pushNotification = null;
    this._pushToPhone = null;
    this._pushInitialized = false;

    this._isRunning = false;
  }

  // ==================== PUSH INIT ====================

  _initPush() {
    if (this._pushInitialized) return;
    this._pushInitialized = true;
    try {
      const pushService = require('./push_service');
      this._pushNotification = (title, body, data) =>
        pushService.sendPushToAllAdmins(title, body, data, 'reports_channel');
      this._pushToPhone = (phone, title, body, data) =>
        pushService.sendPushToPhone(phone, title, body, data, 'reports_channel');
      console.log(`${this.tag} Push notifications enabled`);
    } catch (e) {
      console.log(`${this.tag} Push notifications disabled: ${e.message}`);
    }
  }

  // ==================== STATE MANAGEMENT ====================

  async loadState() {
    return await loadJsonFile(this.stateFile, { ...this.defaultState });
  }

  async saveState(state) {
    state.lastCheck = new Date().toISOString();
    await writeJsonFile(this.stateFile, state);
  }

  // ==================== SHOPS ====================

  /**
   * Загрузить все магазины из индивидуальных файлов shop_*.json
   * Переопредели если нужна другая логика (например shops.json)
   */
  async getAllShops() {
    const shops = [];
    try {
      if (!(await fileExists(this.SHOPS_DIR))) return shops;
      const files = await fsp.readdir(this.SHOPS_DIR);
      for (const file of files) {
        if (file.startsWith('shop_') && file.endsWith('.json')) {
          const shop = await loadJsonFile(path.join(this.SHOPS_DIR, file));
          if (shop && shop.address) {
            shops.push(shop);
          }
        }
      }
    } catch (e) {
      console.error(`${this.tag} Error reading shops directory:`, e.message);
    }
    return shops;
  }

  // ==================== TIME HELPERS ====================

  parseTime(timeStr) {
    const [hours, minutes] = timeStr.split(':').map(Number);
    return { hours, minutes };
  }

  /**
   * Проверяет, находимся ли мы внутри временного окна.
   * Корректно обрабатывает ночные интервалы (когда end < start)
   */
  isWithinTimeWindow(startTimeStr, endTimeStr) {
    const moscow = getMoscowTime();
    const start = this.parseTime(startTimeStr);
    const end = this.parseTime(endTimeStr);

    const currentMinutes = moscow.getUTCHours() * 60 + moscow.getUTCMinutes();
    const startMinutes = start.hours * 60 + start.minutes;
    const endMinutes = end.hours * 60 + end.minutes;

    // Ночной интервал (например 20:00 - 06:58)
    if (endMinutes < startMinutes) {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }

    // Дневной интервал (например 07:00 - 19:58)
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  /**
   * Проверка: достигнуто ли указанное время (московское)
   */
  isTimeReached(timeStr) {
    const moscow = getMoscowTime();
    const { hours, minutes } = this.parseTime(timeStr);
    const moscowHours = moscow.getUTCHours();
    const moscowMinutes = moscow.getUTCMinutes();
    return moscowHours > hours || (moscowHours === hours && moscowMinutes >= minutes);
  }

  isSameDay(date1, date2) {
    const moscow1 = new Date(date1.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
    const moscow2 = new Date(date2.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
    return moscow1.toISOString().split('T')[0] === moscow2.toISOString().split('T')[0];
  }

  /**
   * Вычислить время дедлайна (UTC Date)
   * @param {string} timeStr - Время дедлайна "HH:MM" (московское)
   * @param {string} [startTimeStr] - Время начала окна (для определения ночных интервалов)
   */
  getDeadlineTime(timeStr, startTimeStr = null) {
    const { hours, minutes } = this.parseTime(timeStr);
    const moscow = getMoscowTime();
    const today = getMoscowDateString();

    // Проверяем ночной интервал (дедлайн раньше старта → завтра)
    let isNightInterval = false;
    if (startTimeStr) {
      const start = this.parseTime(startTimeStr);
      const endMinutes = hours * 60 + minutes;
      const startMinutes = start.hours * 60 + start.minutes;
      isNightInterval = endMinutes < startMinutes;
    }

    let deadlineDate = today;
    if (isNightInterval) {
      const tomorrow = new Date(moscow);
      tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
      deadlineDate = tomorrow.toISOString().split('T')[0];
    }

    const deadlineStr = `${deadlineDate}T${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:00`;
    const deadlineLocal = new Date(deadlineStr);
    return new Date(deadlineLocal.getTime() - MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
  }

  // ==================== PENALTY ====================

  /**
   * Создать штраф сотруднику
   * @returns {Object|null} Созданный штраф или null если дубликат
   */
  async createPenalty({ employeeId, employeeName, employeePhone, shopAddress, points, reason, sourceId }) {
    const now = new Date();
    const today = getMoscowDateString();
    const monthKey = today.substring(0, 7);

    const penalty = {
      id: `${this.penaltyPrefix}${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'employee',
      entityId: employeeId,
      entityName: employeeName,
      shopAddress: shopAddress,
      employeeName: employeeName,
      category: this.penaltyCategory,
      categoryName: this.penaltyCategoryName,
      date: today,
      points: points,
      reason: reason,
      sourceId: sourceId,
      sourceType: this.sourceType,
      createdAt: now.toISOString()
    };

    if (employeePhone) {
      penalty.employeePhone = employeePhone;
    }

    // Ensure directory
    if (!(await fileExists(this.EFFICIENCY_PENALTIES_DIR))) {
      await fsp.mkdir(this.EFFICIENCY_PENALTIES_DIR, { recursive: true });
    }

    // Read-check-write under lock to prevent race condition (parallel scheduler runs)
    const penaltiesFile = path.join(this.EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);
    const lockResult = await withLock(penaltiesFile, async () => {
      let penalties = await loadJsonFile(penaltiesFile, []);
      if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];

      // Duplicate check
      if (penalties.some(p => p.sourceId === sourceId)) {
        console.log(`${this.tag} Penalty already exists for ${sourceId}, skipping`);
        return null;
      }

      penalties.push(penalty);
      await writeJsonFile(penaltiesFile, penalties, { useLock: false }); // already inside lock
      return penalty;
    });

    if (!lockResult) return null;

    // DB dual-write
    if (USE_DB_EFFICIENCY) {
      try {
        await db.upsert('efficiency_penalties', {
          id: penalty.id,
          type: penalty.type || 'employee',
          entity_id: penalty.entityId || null,
          entity_name: penalty.entityName || null,
          shop_address: penalty.shopAddress || null,
          employee_name: penalty.employeeName || null,
          employee_phone: penalty.employeePhone || null,
          employee_id: null,
          category: penalty.category,
          category_name: penalty.categoryName || null,
          date: penalty.date || null,
          shift_type: null,
          points: penalty.points != null ? penalty.points : 0,
          reason: penalty.reason || null,
          source_id: penalty.sourceId || null,
          source_type: penalty.sourceType || null,
          late_minutes: null,
          created_at: penalty.createdAt || new Date().toISOString(),
          updated_at: new Date().toISOString()
        });
      } catch (dbErr) {
        console.error(`${this.tag} DB penalty insert error:`, dbErr.message);
      }
    }

    console.log(`${this.tag} Created penalty for ${employeeName}: ${points} points (${reason})`);
    return penalty;
  }

  /**
   * Назначить штраф сотруднику из рабочего графика
   * @param {Object} report - Отчёт с shopAddress, shiftType, id
   * @param {number} penaltyPoints - Количество баллов штрафа
   * @param {Function} reasonFn - (report) => string — формирует текст причины
   * @returns {Object|null} Созданный штраф или null
   */
  async assignPenaltyFromSchedule(report, penaltyPoints, reasonFn) {
    const today = getMoscowDateString();
    const monthKey = today.substring(0, 7);

    const scheduleFile = path.join(this.WORK_SCHEDULES_DIR, `${monthKey}.json`);
    const schedule = await loadJsonFile(scheduleFile, { entries: [] });

    if (!schedule.entries || schedule.entries.length === 0) {
      console.log(`${this.tag} No work schedule found for ${monthKey}, cannot assign penalty`);
      return null;
    }

    // Найти сотрудника по магазину/дате/смене
    const entry = schedule.entries.find(e =>
      e.shopAddress === report.shopAddress &&
      e.date === today &&
      e.shiftType === report.shiftType
    );

    if (!entry) {
      console.log(`${this.tag} No schedule entry found for ${report.shopAddress}, ${today}, ${report.shiftType}`);
      return null;
    }

    return await this.createPenalty({
      employeeId: entry.employeeId,
      employeeName: entry.employeeName,
      employeePhone: entry.phone || entry.employeePhone,
      shopAddress: report.shopAddress,
      points: penaltyPoints,
      reason: reasonFn(report),
      sourceId: report.id
    });
  }

  // ==================== NOTIFICATIONS ====================

  /**
   * Push-уведомление админу о несданных отчётах
   */
  async sendAdminFailedNotification(count, failedShops) {
    this._initPush();

    const shiftTypes = [...new Set(failedShops.map(s => s.shiftType))];
    const shiftLabel = shiftTypes.includes('morning') ? 'утренний' : 'вечерний';

    const title = this.notificationTitle;
    const body = this.notificationBodyFn(count, shiftLabel);

    console.log(`${this.tag} PUSH to Admin: ${body}`);

    if (this._pushNotification) {
      try {
        await this._pushNotification(title, body, {
          type: this.notificationType,
          count: String(count),
          shiftType: shiftTypes.join(','),
        });
        console.log(`${this.tag} Push notification sent successfully`);
      } catch (e) {
        console.error(`${this.tag} Error sending push notification:`, e.message);
      }
    } else {
      console.log(`${this.tag} Push notifications not available`);
    }
  }

  /**
   * Push-уведомление сотруднику
   */
  async sendPushToEmployee(phone, title, body, data) {
    this._initPush();

    if (this._pushToPhone && phone) {
      try {
        await this._pushToPhone(phone, title, body, data);
        console.log(`${this.tag} Push sent to ${phone}`);
      } catch (e) {
        console.error(`${this.tag} Error sending push to ${phone}:`, e.message);
      }
    }
  }

  // ==================== MUST OVERRIDE ====================

  /**
   * Загрузить настройки шедулера (time windows, penalty points и т.д.)
   * @returns {Object} Настройки с полями morningStartTime, morningEndTime,
   *                    eveningStartTime, eveningEndTime, missedPenalty
   */
  async getSettings() {
    throw new Error(`${this.tag} Must override getSettings()`);
  }

  /**
   * Создать pending отчёты для указанного типа смены
   * @param {string} shiftType - 'morning' или 'evening'
   * @returns {number} Количество созданных отчётов
   */
  async generatePendingReports(shiftType) {
    throw new Error(`${this.tag} Must override generatePendingReports()`);
  }

  /**
   * Проверить дедлайны pending отчётов, перевести в failed
   * @returns {number} Количество failed отчётов
   */
  async checkPendingDeadlines() {
    throw new Error(`${this.tag} Must override checkPendingDeadlines()`);
  }

  /**
   * Очистка pending/failed отчётов (вызывается в 23:59)
   */
  async cleanupFailedReports() {
    throw new Error(`${this.tag} Must override cleanupFailedReports()`);
  }

  // ==================== OPTIONAL OVERRIDE ====================

  /**
   * Проверить таймауты review (review → rejected)
   * По умолчанию — нет проверки. Переопредели в shift/recount/shift_handover.
   * @returns {number} Количество rejected отчётов
   */
  async checkReviewTimeouts() {
    return 0;
  }

  // ==================== MAIN LOOP ====================

  /**
   * Основной цикл проверки (Template Method)
   * Переопредели если нужна нестандартная логика (например RKO cleanup)
   */
  async runScheduledChecks() {
    const now = new Date();
    const moscow = getMoscowTime();
    const settings = await this.getSettings();
    const state = await this.loadState();

    console.log(`\n[${now.toISOString()}] ${this.tag} Running checks... (Moscow time: ${moscow.toISOString()})`);

    // Check pending deadlines FIRST — mark stale pending reports as failed before generating new ones
    // This ensures stale files from previous days don't block new report creation
    const failed = await this.checkPendingDeadlines();
    if (failed > 0) {
      console.log(`${this.tag} ${failed} reports marked as failed`);
    }

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

    // Check review timeouts (optional — override in subclass)
    const rejected = await this.checkReviewTimeouts();
    if (rejected > 0) {
      console.log(`${this.tag} ${rejected} reports auto-rejected (admin timeout)`);
    }

    // Cleanup at ~23:55-23:59 Moscow time (wider window to not miss with 5-min interval)
    const moscowHours = moscow.getUTCHours();
    const moscowMinutes = moscow.getUTCMinutes();
    if (moscowHours === 23 && moscowMinutes >= 55) {
      const lastCleanup = state.lastCleanup;
      if (!lastCleanup || !this.isSameDay(new Date(lastCleanup), now)) {
        await this.cleanupFailedReports();
        state.lastCleanup = now.toISOString();
      }
    }

    await this.saveState(state);
    console.log(`${this.tag} Checks completed\n`);
  }

  // ==================== START ====================

  /**
   * Запустить шедулер с guarded interval
   */
  async start() {
    this._initPush();

    const settings = await this.getSettings();
    const moscow = getMoscowTime();

    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`${this.name} Automation Scheduler started`);
    console.log(`  - Timezone: Moscow (UTC+3)`);
    console.log(`  - Current Moscow time: ${moscow.toISOString()}`);
    console.log(`  - Morning window: ${settings.morningStartTime} - ${settings.morningEndTime}`);
    console.log(`  - Evening window: ${settings.eveningStartTime} - ${settings.eveningEndTime}`);
    if (settings.adminReviewTimeout) {
      console.log(`  - Admin review timeout: ${settings.adminReviewTimeout} hours`);
    }
    console.log(`  - Missed penalty: ${settings.missedPenalty} points`);
    console.log(`  - Check interval: ${this.checkIntervalMs / 1000 / 60} minutes`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // Guarded interval — защита от параллельного запуска + таймаут от зависания
    const MAX_RUN_MS = 10 * 60 * 1000; // 10 минут макс на один запуск
    const guardedCheck = async () => {
      if (this._isRunning) {
        // Проверяем таймаут — если предыдущий запуск завис дольше MAX_RUN_MS, сбрасываем
        if (this._runStartedAt && (Date.now() - this._runStartedAt > MAX_RUN_MS)) {
          console.error(`${this.tag} Previous run exceeded ${MAX_RUN_MS / 60000}min timeout, force-resetting`);
          this._isRunning = false;
        } else {
          console.log(`${this.tag} Previous run still active, skipping`);
          return;
        }
      }
      this._isRunning = true;
      this._runStartedAt = Date.now();
      try {
        await this.runScheduledChecks();
      } catch (err) {
        console.error(`${this.tag} Scheduler error:`, err.message);
      } finally {
        this._isRunning = false;
        this._runStartedAt = null;
      }
    };

    setInterval(guardedCheck, this.checkIntervalMs);
    setTimeout(guardedCheck, this.startupDelayMs);
  }
}

// Re-export utilities for convenience
BaseReportScheduler.getMoscowTime = getMoscowTime;
BaseReportScheduler.getMoscowDateString = getMoscowDateString;
BaseReportScheduler.MOSCOW_OFFSET_HOURS = MOSCOW_OFFSET_HOURS;
BaseReportScheduler.loadJsonFile = loadJsonFile;
BaseReportScheduler.fileExists = fileExists;
BaseReportScheduler.writeJsonFile = writeJsonFile;

module.exports = BaseReportScheduler;
