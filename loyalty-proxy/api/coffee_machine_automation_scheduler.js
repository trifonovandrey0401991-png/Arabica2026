/**
 * Coffee Machine Automation Scheduler
 *
 * Автоматизация создания pending отчётов по счётчикам кофемашин.
 * По паттерну envelope_automation_scheduler.js.
 *
 * Логика:
 * - Утром: создать pending для утренней смены (для магазинов с кофемашинами)
 * - Вечером: создать pending для вечерней смены
 * - Если дедлайн прошёл и нет отчёта → failed + штраф
 * - 23:59: очистка pending/failed файлов
 */

const fsp = require('fs').promises;
const path = require('path');

// Директории
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const PENDING_DIR = `${DATA_DIR}/coffee-machine-pending`;
const REPORTS_DIR = `${DATA_DIR}/coffee-machine-reports`;
const STATE_DIR = `${DATA_DIR}/coffee-machine-automation-state`;
const STATE_FILE = path.join(STATE_DIR, 'state.json');
const SHOPS_FILE = `${DATA_DIR}/shops/shops.json`;
const SHOP_CONFIGS_DIR = `${DATA_DIR}/coffee-machine-shop-configs`;
const POINTS_SETTINGS_FILE = `${DATA_DIR}/points-settings/coffee_machine_points_settings.json`;

// Интервал проверки: 5 минут
const CHECK_INTERVAL_MS = 5 * 60 * 1000;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directories exist
(async () => {
  for (const dir of [PENDING_DIR, REPORTS_DIR, STATE_DIR, SHOP_CONFIGS_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

/**
 * Получение московского времени (UTC+3)
 */
function getMoscowTime() {
  const utc = new Date();
  const moscowOffset = 3;
  return new Date(utc.getTime() + moscowOffset * 60 * 60 * 1000);
}

/**
 * Загрузка настроек баллов для кофемашин
 */
async function getCoffeeMachineSettings() {
  if (!(await fileExists(POINTS_SETTINGS_FILE))) {
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
  return JSON.parse(await fsp.readFile(POINTS_SETTINGS_FILE, 'utf8'));
}

/**
 * Загрузка состояния автоматизации
 */
async function loadState() {
  if (!(await fileExists(STATE_FILE))) {
    const defaultState = {
      lastMorningGeneration: null,
      lastEveningGeneration: null,
      lastCleanup: null,
      lastCheck: null,
    };
    await fsp.writeFile(STATE_FILE, JSON.stringify(defaultState, null, 2));
    return defaultState;
  }
  return JSON.parse(await fsp.readFile(STATE_FILE, 'utf8'));
}

/**
 * Сохранение состояния
 */
async function saveState(state) {
  state.lastCheck = new Date().toISOString();
  await fsp.writeFile(STATE_FILE, JSON.stringify(state, null, 2));
}

/**
 * Загрузить магазины, у которых настроены кофемашины
 */
async function getShopsWithCoffeeMachines() {
  // 1. Загрузить все магазины
  if (!(await fileExists(SHOPS_FILE))) {
    return [];
  }
  const shopsData = JSON.parse(await fsp.readFile(SHOPS_FILE, 'utf8'));
  const shops = shopsData.shops || shopsData || [];
  if (!Array.isArray(shops)) return [];

  // 2. Загрузить конфиги кофемашин
  if (!(await fileExists(SHOP_CONFIGS_DIR))) {
    return [];
  }
  const configFiles = (await fsp.readdir(SHOP_CONFIGS_DIR)).filter(f => f.endsWith('.json'));
  const configuredShops = new Set();

  for (const file of configFiles) {
    try {
      const config = JSON.parse(await fsp.readFile(path.join(SHOP_CONFIGS_DIR, file), 'utf8'));
      if (config.machineTemplateIds && config.machineTemplateIds.length > 0) {
        configuredShops.add(config.shopAddress);
      }
    } catch (e) {
      // skip
    }
  }

  // 3. Вернуть только магазины с настроенными машинами
  return shops.filter(s => configuredShops.has(s.address));
}

/**
 * Загрузить все pending за дату
 */
async function loadAllPendingForDate(date) {
  const pendingMap = new Map();
  if (!(await fileExists(PENDING_DIR))) return pendingMap;

  const files = await fsp.readdir(PENDING_DIR);
  for (const file of files) {
    if (!file.startsWith('pending_cm_') || !file.endsWith('.json')) continue;
    try {
      const filePath = path.join(PENDING_DIR, file);
      const data = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      if (data.date === date) {
        const key = `${data.shopAddress}|${data.shiftType}|${data.date}`;
        data._filePath = filePath;
        pendingMap.set(key, data);
      }
    } catch (e) {
      // skip
    }
  }
  return pendingMap;
}

/**
 * Загрузить все сданные отчёты за дату
 */
async function loadAllSubmittedForDate(date) {
  const submittedSet = new Set();
  if (!(await fileExists(REPORTS_DIR))) return submittedSet;

  const files = await fsp.readdir(REPORTS_DIR);
  for (const file of files) {
    if (!file.endsWith('.json')) continue;
    try {
      const filePath = path.join(REPORTS_DIR, file);
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

/**
 * Создание pending отчётов для магазинов с кофемашинами
 */
async function generatePendingReports(shiftType) {
  const startTime = Date.now();
  console.log(`[CoffeeMachine Automation] Создание pending для ${shiftType}`);

  const shops = await getShopsWithCoffeeMachines();
  if (shops.length === 0) {
    console.log('[CoffeeMachine] Нет магазинов с настроенными кофемашинами');
    return 0;
  }

  const settings = await getCoffeeMachineSettings();
  const deadline = shiftType === 'morning' ? settings.morningDeadline : settings.eveningDeadline;

  const moscow = getMoscowTime();
  const today = moscow.toISOString().split('T')[0];

  const pendingMap = await loadAllPendingForDate(today);
  const submittedSet = await loadAllSubmittedForDate(today);

  let created = 0;

  for (const shop of shops) {
    const shopAddress = shop.address;
    const lookupKey = `${shopAddress}|${shiftType}|${today}`;

    if (pendingMap.has(lookupKey) || submittedSet.has(lookupKey)) {
      continue;
    }

    const report = {
      id: `pending_cm_${shiftType}_${shopAddress.replace(/[^a-zA-Z0-9а-яА-Я]/g, '_')}_${Date.now()}`,
      shopAddress,
      shiftType,
      status: 'pending',
      date: today,
      deadline,
      createdAt: moscow.toISOString(),
      failedAt: null,
    };

    const filePath = path.join(PENDING_DIR, `${report.id}.json`);
    await fsp.writeFile(filePath, JSON.stringify(report, null, 2));
    created++;
  }

  const elapsed = Date.now() - startTime;
  console.log(`[CoffeeMachine] Создано pending: ${created}, время: ${elapsed}ms`);
  return created;
}

/**
 * Проверка дедлайнов pending отчётов
 */
async function checkPendingDeadlines() {
  const moscow = getMoscowTime();
  const today = moscow.toISOString().split('T')[0];
  const settings = await getCoffeeMachineSettings();

  const pendingMap = await loadAllPendingForDate(today);
  const reports = Array.from(pendingMap.values());
  if (reports.length === 0) return [];

  const submittedSet = await loadAllSubmittedForDate(today);
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
      await fsp.writeFile(report._filePath, JSON.stringify(report, null, 2));

      await assignPenalty(report, settings);
      failedReports.push(report);

      console.log(`[CoffeeMachine] Дедлайн истёк: ${report.shopAddress} (${report.shiftType})`);
    }
  }

  if (failedReports.length > 0) {
    await sendAdminFailedNotification(failedReports.length);
  }

  return failedReports;
}

/**
 * Назначение штрафа сотруднику из графика
 */
async function assignPenalty(report, settings) {
  const { shopAddress, shiftType, date } = report;

  const [year, month] = date.split('-');
  const scheduleFile = `${DATA_DIR}/work-schedules/${year}-${month}.json`;

  if (!(await fileExists(scheduleFile))) return;

  const schedule = JSON.parse(await fsp.readFile(scheduleFile, 'utf8'));
  const entry = schedule.entries.find(e =>
    e.shopAddress === shopAddress &&
    e.date === date &&
    e.shiftType === shiftType
  );

  if (!entry) return;

  const penalty = {
    id: `penalty_cm_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    type: 'employee',
    entityId: entry.employeeId,
    entityName: entry.employeeName,
    shopAddress,
    employeeName: entry.employeeName,
    employeePhone: entry.phone || null,
    category: 'coffee_machine_missed_penalty',
    categoryName: 'Счётчик кофемашин - несдан',
    date,
    shiftType,
    points: settings.missedPenalty || settings.notSubmittedPoints,
    reason: `Не сдан счётчик кофемашин (${shiftType === 'morning' ? 'утренняя' : 'вечерняя'} смена)`,
    sourceId: report.id,
    sourceType: 'coffee_machine',
    createdAt: new Date().toISOString(),
  };

  const penaltiesDir = `${DATA_DIR}/efficiency-penalties`;
  if (!(await fileExists(penaltiesDir))) {
    await fsp.mkdir(penaltiesDir, { recursive: true });
  }

  const penaltiesFile = path.join(penaltiesDir, `${year}-${month}.json`);
  let penalties = { penalties: [] };

  if (await fileExists(penaltiesFile)) {
    const raw = JSON.parse(await fsp.readFile(penaltiesFile, 'utf8'));
    penalties = Array.isArray(raw) ? { penalties: raw } : raw;
  }

  // Проверка дубликатов
  const exists = (penalties.penalties || []).some(p => p.sourceId === report.id);
  if (exists) return;

  penalties.penalties.push(penalty);
  await fsp.writeFile(penaltiesFile, JSON.stringify(penalties, null, 2));

  console.log(`[CoffeeMachine] Штраф назначен: ${entry.employeeName} (${penalty.points} баллов)`);

  if (entry.phone) {
    await sendEmployeePenaltyNotification(entry.phone, entry.employeeName, penalty.points, shiftType);
  }
}

/**
 * Push-уведомление админу о несданных отчётах
 */
async function sendAdminFailedNotification(count) {
  try {
    const { sendPushNotification } = require('./report_notifications_api');
    await sendPushNotification(
      'Счётчики кофемашин не сданы',
      `Счётчики кофемашин не сданы - ${count}`,
      { type: 'coffee_machine_failed', count: String(count) }
    );
  } catch (error) {
    console.error('[CoffeeMachine] Ошибка push админу:', error.message);
  }
}

/**
 * Push-уведомление сотруднику о штрафе
 */
async function sendEmployeePenaltyNotification(phone, employeeName, points, shiftType) {
  try {
    const { sendPushToPhone } = require('./report_notifications_api');
    const shiftName = shiftType === 'morning' ? 'утреннюю' : 'вечернюю';
    await sendPushToPhone(
      phone,
      'Штраф за несданный счётчик',
      `Вам начислен штраф ${points} баллов за несданный счётчик кофемашин (${shiftName} смена)`,
      { type: 'coffee_machine_penalty', points: String(points) }
    );
  } catch (error) {
    console.error(`[CoffeeMachine] Ошибка push сотруднику ${employeeName}:`, error.message);
  }
}

/**
 * Очистка pending/failed в конце дня
 */
async function cleanupPendingReports() {
  console.log('[CoffeeMachine] Очистка pending/failed отчётов (23:59)');

  if (!(await fileExists(PENDING_DIR))) return;

  const files = await fsp.readdir(PENDING_DIR);
  let deleted = 0;

  for (const file of files) {
    if (file.startsWith('pending_cm_')) {
      await fsp.unlink(path.join(PENDING_DIR, file));
      deleted++;
    }
  }

  console.log(`[CoffeeMachine] Удалено pending файлов: ${deleted}`);

  const state = {
    lastMorningGeneration: null,
    lastEveningGeneration: null,
    lastCleanup: new Date().toISOString(),
    lastCheck: new Date().toISOString(),
  };
  await fsp.writeFile(STATE_FILE, JSON.stringify(state, null, 2));
}

/**
 * Главный цикл проверки
 */
async function startCoffeeMachineAutomation() {
  console.log('[CoffeeMachine Automation] Запуск scheduler...');

  for (const dir of [PENDING_DIR, STATE_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }

  setInterval(async () => {
    try {
      const moscow = getMoscowTime();
      const settings = await getCoffeeMachineSettings();
      const state = await loadState();

      const currentHour = moscow.getUTCHours();
      const currentMinute = moscow.getUTCMinutes();
      const today = moscow.toISOString().split('T')[0];

      // Утренние pending
      const [mStartH, mStartM] = settings.morningStartTime.split(':').map(Number);
      if (
        currentHour === mStartH &&
        currentMinute >= mStartM &&
        currentMinute < mStartM + 5 &&
        state.lastMorningGeneration !== today
      ) {
        await generatePendingReports('morning');
        state.lastMorningGeneration = today;
        await saveState(state);
      }

      // Вечерние pending
      const [eStartH, eStartM] = settings.eveningStartTime.split(':').map(Number);
      if (
        currentHour === eStartH &&
        currentMinute >= eStartM &&
        currentMinute < eStartM + 5 &&
        state.lastEveningGeneration !== today
      ) {
        await generatePendingReports('evening');
        state.lastEveningGeneration = today;
        await saveState(state);
      }

      // Проверка дедлайнов
      await checkPendingDeadlines();

      // Очистка в 23:59
      if (currentHour === 23 && currentMinute >= 59) {
        if (state.lastCleanup !== today) {
          await cleanupPendingReports();
        }
      }
    } catch (error) {
      console.error('[CoffeeMachine Automation] Ошибка:', error);
    }
  }, CHECK_INTERVAL_MS);

  console.log('[CoffeeMachine Automation] Scheduler запущен (проверка каждые 5 минут)');
}

// Экспорт для API (pending/failed endpoints)
function getPendingReports() {
  return loadAllPendingForDate(getMoscowTime().toISOString().split('T')[0]);
}

function getFailedReports() {
  return loadAllPendingForDate(getMoscowTime().toISOString().split('T')[0])
    .then(map => Array.from(map.values()).filter(r => r.status === 'failed'));
}

module.exports = {
  startCoffeeMachineAutomation,
  getPendingReports,
  getFailedReports,
};
