/**
 * Envelope Automation Scheduler
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

// Директории
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const ENVELOPE_PENDING_DIR = `${DATA_DIR}/envelope-pending`;
const ENVELOPE_REPORTS_DIR = `${DATA_DIR}/envelope-reports`;
const ENVELOPE_STATE_DIR = `${DATA_DIR}/envelope-automation-state`;
const STATE_FILE = path.join(ENVELOPE_STATE_DIR, 'state.json');
const SHOPS_FILE = `${DATA_DIR}/shops/shops.json`;
const POINTS_SETTINGS_FILE = `${DATA_DIR}/points-settings/envelope_points_settings.json`;

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

// Ensure directories exist (async IIFE)
(async () => {
  for (const dir of [ENVELOPE_PENDING_DIR, ENVELOPE_REPORTS_DIR, ENVELOPE_STATE_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

// ============================================
// OPTIMIZATION: Batch loading for scalability
// ============================================

/**
 * Загрузить ВСЕ pending отчёты за дату в Map для O(1) поиска
 * @param {string} date - Дата в формате YYYY-MM-DD
 * @returns {Map<string, object>} Map ключ: "shopAddress|shiftType|date"
 */
async function loadAllPendingReportsForDate(date) {
  const pendingMap = new Map();

  if (!(await fileExists(ENVELOPE_PENDING_DIR))) {
    return pendingMap;
  }

  const files = await fsp.readdir(ENVELOPE_PENDING_DIR);

  for (const file of files) {
    if (!file.startsWith('pending_env_') || !file.endsWith('.json')) continue;

    try {
      const filePath = path.join(ENVELOPE_PENDING_DIR, file);
      const data = JSON.parse(await fsp.readFile(filePath, 'utf8'));

      if (data.date === date) {
        const key = `${data.shopAddress}|${data.shiftType}|${data.date}`;
        data._filePath = filePath;
        pendingMap.set(key, data);
      }
    } catch (error) {
      console.error(`[Envelope] Ошибка чтения ${file}:`, error.message);
    }
  }

  console.log(`[Envelope] Загружено ${pendingMap.size} pending отчётов за ${date}`);
  return pendingMap;
}

/**
 * Загрузить ВСЕ сданные отчёты за дату в Set для O(1) проверки
 * @param {string} date - Дата в формате YYYY-MM-DD
 * @returns {Set<string>} Set ключей: "shopAddress|shiftType|date"
 */
async function loadAllSubmittedReportsForDate(date) {
  const submittedSet = new Set();

  if (!(await fileExists(ENVELOPE_REPORTS_DIR))) {
    return submittedSet;
  }

  const files = await fsp.readdir(ENVELOPE_REPORTS_DIR);

  for (const file of files) {
    if (!file.endsWith('.json')) continue;

    try {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, file);
      const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));

      const reportDate = report.createdAt ? report.createdAt.split('T')[0] : null;

      if (reportDate === date) {
        const key = `${report.shopAddress}|${report.shiftType}|${reportDate}`;
        submittedSet.add(key);
      }
    } catch (error) {
      console.error(`[Envelope] Ошибка чтения ${file}:`, error.message);
    }
  }

  console.log(`[Envelope] Загружено ${submittedSet.size} сданных отчётов за ${date}`);
  return submittedSet;
}

/**
 * Получение московского времени (UTC+3)
 */
function getMoscowTime() {
  const utc = new Date();
  const moscowOffset = 3; // UTC+3
  return new Date(utc.getTime() + moscowOffset * 60 * 60 * 1000);
}

/**
 * Загрузка настроек конвертов
 */
async function getEnvelopeSettings() {
  if (!(await fileExists(POINTS_SETTINGS_FILE))) {
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
      lastCheck: null
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
 * Загрузка pending отчетов за сегодня
 */
async function loadTodayPendingReports() {
  const moscow = getMoscowTime();
  const today = moscow.toISOString().split('T')[0];
  const reports = [];

  if (!(await fileExists(ENVELOPE_PENDING_DIR))) {
    return reports;
  }

  const files = await fsp.readdir(ENVELOPE_PENDING_DIR);

  for (const file of files) {
    if (file.startsWith('pending_env_')) {
      const filePath = path.join(ENVELOPE_PENDING_DIR, file);
      try {
        const data = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        if (data.date === today) {
          data._filePath = filePath;
          reports.push(data);
        }
      } catch (error) {
        console.error(`[Envelope] Ошибка чтения ${file}:`, error.message);
      }
    }
  }

  return reports;
}

/**
 * Поиск существующего pending отчета
 */
async function findPendingReport(shopAddress, shiftType, date) {
  if (!(await fileExists(ENVELOPE_PENDING_DIR))) {
    return null;
  }

  const files = await fsp.readdir(ENVELOPE_PENDING_DIR);

  for (const file of files) {
    if (file.startsWith('pending_env_')) {
      const filePath = path.join(ENVELOPE_PENDING_DIR, file);
      try {
        const data = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        if (
          data.shopAddress === shopAddress &&
          data.shiftType === shiftType &&
          data.date === date
        ) {
          return data;
        }
      } catch (error) {
        console.error(`[Envelope] Ошибка чтения ${file}:`, error.message);
      }
    }
  }

  return null;
}

/**
 * Проверка: был ли сдан отчет по конверту
 */
async function checkIfEnvelopeSubmitted(shopAddress, shiftType, date) {
  if (!(await fileExists(ENVELOPE_REPORTS_DIR))) {
    return false;
  }

  const files = await fsp.readdir(ENVELOPE_REPORTS_DIR);

  for (const file of files) {
    if (file.endsWith('.json')) {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, file);
      try {
        const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));

        // Проверяем совпадение магазина, смены и даты
        const reportDate = report.createdAt ? report.createdAt.split('T')[0] : null;

        if (
          report.shopAddress === shopAddress &&
          report.shiftType === shiftType &&
          reportDate === date
        ) {
          return true;
        }
      } catch (error) {
        console.error(`[Envelope] Ошибка чтения ${file}:`, error.message);
      }
    }
  }

  return false;
}

/**
 * Создание pending отчетов для всех магазинов
 * OPTIMIZED: Загружает все данные ОДИН раз, затем O(1) проверки
 */
async function generatePendingReports(shiftType) {
  const startTime = Date.now();
  console.log(`[Envelope Automation] Создание pending отчетов для ${shiftType}`);

  // 1. Загрузить все магазины
  if (!(await fileExists(SHOPS_FILE))) {
    console.log('[Envelope] Файл магазинов не найден');
    return 0;
  }

  const shopsData = JSON.parse(await fsp.readFile(SHOPS_FILE, 'utf8'));
  const shops = shopsData.shops || shopsData || [];

  if (!Array.isArray(shops)) {
    console.error('[Envelope] Ошибка: shops не является массивом, получено:', typeof shops);
    return 0;
  }

  // 2. Получить настройки
  const settings = await getEnvelopeSettings();
  const deadline = shiftType === 'morning' ? settings.morningDeadline : settings.eveningDeadline;

  // 3. Текущая дата
  const moscow = getMoscowTime();
  const today = moscow.toISOString().split('T')[0]; // YYYY-MM-DD

  // OPTIMIZATION: Загрузить ВСЕ pending и submitted отчёты ОДИН раз
  const pendingMap = await loadAllPendingReportsForDate(today);
  const submittedSet = await loadAllSubmittedReportsForDate(today);

  let created = 0;
  let skippedPending = 0;
  let skippedSubmitted = 0;

  for (const shop of shops) {
    const shopAddress = shop.address;
    const lookupKey = `${shopAddress}|${shiftType}|${today}`;

    // O(1) проверка: уже существует pending отчет?
    if (pendingMap.has(lookupKey)) {
      skippedPending++;
      continue;
    }

    // O(1) проверка: уже сдан отчет?
    if (submittedSet.has(lookupKey)) {
      skippedSubmitted++;
      continue;
    }

    // Создать pending отчет
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

    // Сохранить
    const filePath = path.join(ENVELOPE_PENDING_DIR, `${report.id}.json`);
    await fsp.writeFile(filePath, JSON.stringify(report, null, 2));
    created++;
  }

  const elapsed = Date.now() - startTime;
  console.log(`[Envelope] Создано pending: ${created}, пропущено (pending): ${skippedPending}, пропущено (сдано): ${skippedSubmitted}, время: ${elapsed}ms`);
  return created;
}

/**
 * Проверка дедлайнов pending отчетов
 * OPTIMIZED: Загружает submitted отчёты ОДИН раз
 */
async function checkPendingDeadlines() {
  const startTime = Date.now();
  const moscow = getMoscowTime();
  const today = moscow.toISOString().split('T')[0];
  const settings = await getEnvelopeSettings();

  // OPTIMIZATION: Загрузить ВСЕ pending отчёты за сегодня через batch функцию
  const pendingMap = await loadAllPendingReportsForDate(today);
  const reports = Array.from(pendingMap.values());

  if (reports.length === 0) {
    return [];
  }

  // OPTIMIZATION: Загрузить ВСЕ submitted отчёты ОДИН раз
  const submittedSet = await loadAllSubmittedReportsForDate(today);

  const failedReports = [];
  let removedCount = 0;

  for (const report of reports) {
    if (report.status !== 'pending') continue;

    const lookupKey = `${report.shopAddress}|${report.shiftType}|${report.date}`;

    // O(1) проверка: может быть конверт уже сдан?
    if (submittedSet.has(lookupKey)) {
      // Удалить pending файл
      try {
        await fsp.unlink(report._filePath);
        removedCount++;
      } catch (e) {
        console.error(`[Envelope] Ошибка удаления pending: ${e.message}`);
      }
      continue;
    }

    // 2. Проверить дедлайн
    const [deadlineHours, deadlineMinutes] = report.deadline.split(':').map(Number);
    const deadlineMinutesTotal = deadlineHours * 60 + deadlineMinutes;
    const currentMinutesTotal = moscow.getUTCHours() * 60 + moscow.getUTCMinutes();

    if (currentMinutesTotal >= deadlineMinutesTotal) {
      // Дедлайн прошел!
      report.status = 'failed';
      report.failedAt = moscow.toISOString();

      // Сохранить изменения
      await fsp.writeFile(report._filePath, JSON.stringify(report, null, 2));

      // Назначить штраф
      await assignPenaltyFromSchedule(report, settings);

      failedReports.push(report);

      console.log(`[Envelope] Дедлайн истек: ${report.shopAddress} (${report.shiftType})`);
    }
  }

  // Отправить уведомление админу
  if (failedReports.length > 0) {
    await sendAdminFailedNotification(failedReports.length);
  }

  const elapsed = Date.now() - startTime;
  console.log(`[Envelope] Проверка дедлайнов: ${failedReports.length} failed, ${removedCount} удалено (сданы), время: ${elapsed}ms`);

  return failedReports;
}

/**
 * Назначение штрафа сотруднику из графика
 */
async function assignPenaltyFromSchedule(report, settings) {
  const { shopAddress, shiftType, date } = report;

  // 1. Загрузить график работы
  const [year, month] = date.split('-');
  const scheduleFile = `${DATA_DIR}/work-schedules/${year}-${month}.json`;

  if (!(await fileExists(scheduleFile))) {
    console.log(`[Envelope] График не найден: ${scheduleFile}`);
    return;
  }

  const schedule = JSON.parse(await fsp.readFile(scheduleFile, 'utf8'));

  // 2. Найти сотрудника
  const entry = schedule.entries.find(e =>
    e.shopAddress === shopAddress &&
    e.date === date &&
    e.shiftType === shiftType
  );

  if (!entry) {
    console.log(`[Envelope] Сотрудник не найден в графике: ${shopAddress}, ${date}, ${shiftType}`);
    return;
  }

  // 3. Создать штраф
  const penalty = {
    id: `penalty_env_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    type: 'employee',
    entityId: entry.employeeId,
    entityName: entry.employeeName,
    shopAddress: shopAddress,
    employeeName: entry.employeeName,
    employeePhone: entry.phone || null,
    category: 'envelope_missed_penalty',
    categoryName: 'Конверт - несдан',
    date: date,
    shiftType: shiftType,
    points: settings.missedPenalty || settings.notSubmittedPoints,
    reason: `Не сдан конверт (${shiftType === 'morning' ? 'утренняя' : 'вечерняя'} смена)`,
    sourceId: report.id,
    sourceType: 'envelope',
    createdAt: new Date().toISOString()
  };

  // 4. Сохранить в efficiency-penalties
  const penaltiesDir = `${DATA_DIR}/efficiency-penalties`;
  if (!(await fileExists(penaltiesDir))) {
    await fsp.mkdir(penaltiesDir, { recursive: true });
  }

  const penaltiesFile = path.join(penaltiesDir, `${year}-${month}.json`);
  let penalties = { penalties: [] };

  if (await fileExists(penaltiesFile)) {
    const raw = JSON.parse(await fsp.readFile(penaltiesFile, 'utf8'));
    // Обратная совместимость: файл может содержать [] (массив) или {penalties: []} (объект)
    if (Array.isArray(raw)) {
      penalties = { penalties: raw };
    } else {
      penalties = raw;
    }
  }

  // Проверка дубликатов
  const penaltyList = penalties.penalties || [];
  const exists = penaltyList.some(p => p.sourceId === report.id);
  if (exists) {
    console.log(`[Envelope] Штраф уже существует для: ${report.id}`);
    return;
  }

  penalties.penalties.push(penalty);
  await fsp.writeFile(penaltiesFile, JSON.stringify(penalties, null, 2));

  console.log(`[Envelope] Штраф назначен: ${entry.employeeName} (${penalty.points} баллов)`);

  // 5. Отправить push сотруднику
  if (entry.phone) {
    await sendEmployeePenaltyNotification(entry.phone, entry.employeeName, penalty.points, shiftType);
  }
}

/**
 * Отправка push-уведомления админу
 */
async function sendAdminFailedNotification(count) {
  try {
    const { sendPushNotification } = require('./report_notifications_api');

    const title = 'Конверты не сданы';
    const body = `Конверты не сданы - ${count}`;

    await sendPushNotification(title, body, {
      type: 'envelope_failed',
      count: String(count)
    });

    console.log(`[Envelope] Push админу: ${body}`);
  } catch (error) {
    console.error('[Envelope] Ошибка отправки push админу:', error.message);
  }
}

/**
 * Отправка push-уведомления сотруднику
 */
async function sendEmployeePenaltyNotification(phone, employeeName, points, shiftType) {
  try {
    const { sendPushToPhone } = require('./report_notifications_api');

    const title = 'Штраф за несданный конверт';
    const shiftName = shiftType === 'morning' ? 'утреннюю' : 'вечернюю';
    const body = `Вам начислен штраф ${points} баллов за несданный конверт (${shiftName} смена)`;

    await sendPushToPhone(phone, title, body, {
      type: 'envelope_penalty',
      points: String(points)
    });

    console.log(`[Envelope] Push сотруднику ${employeeName}: ${body}`);
  } catch (error) {
    console.error(`[Envelope] Ошибка отправки push сотруднику ${employeeName}:`, error.message);
  }
}

/**
 * Очистка failed отчетов в конце дня
 */
async function cleanupFailedReports() {
  console.log('[Envelope] Очистка pending/failed отчетов (23:59)');

  if (!(await fileExists(ENVELOPE_PENDING_DIR))) {
    console.log('[Envelope] Директория pending не существует');
    return;
  }

  const files = await fsp.readdir(ENVELOPE_PENDING_DIR);
  let deleted = 0;

  for (const file of files) {
    if (file.startsWith('pending_env_')) {
      await fsp.unlink(path.join(ENVELOPE_PENDING_DIR, file));
      deleted++;
    }
  }

  console.log(`[Envelope] Удалено pending файлов: ${deleted}`);

  // Сбросить state
  const state = {
    lastMorningGeneration: null,
    lastEveningGeneration: null,
    lastCleanup: new Date().toISOString(),
    lastCheck: new Date().toISOString()
  };

  await fsp.writeFile(STATE_FILE, JSON.stringify(state, null, 2));
}

/**
 * Главный цикл проверки
 */
async function startScheduler() {
  console.log('[Envelope Automation] Запуск scheduler...');

  // Создать директории если их нет
  if (!(await fileExists(ENVELOPE_PENDING_DIR))) {
    await fsp.mkdir(ENVELOPE_PENDING_DIR, { recursive: true });
    console.log(`[Envelope] Создана директория: ${ENVELOPE_PENDING_DIR}`);
  }
  if (!(await fileExists(ENVELOPE_STATE_DIR))) {
    await fsp.mkdir(ENVELOPE_STATE_DIR, { recursive: true });
    console.log(`[Envelope] Создана директория: ${ENVELOPE_STATE_DIR}`);
  }

  // Запустить проверку каждые 5 минут
  setInterval(async () => {
    try {
      const moscow = getMoscowTime();
      const settings = await getEnvelopeSettings();
      const state = await loadState();

      const currentHour = moscow.getUTCHours();
      const currentMinute = moscow.getUTCMinutes();
      const today = moscow.toISOString().split('T')[0];

      // Проверка 1: Создание утренних pending (07:00)
      const [morningStartHour, morningStartMinute] = settings.morningStartTime.split(':').map(Number);
      if (
        currentHour === morningStartHour &&
        currentMinute >= morningStartMinute &&
        currentMinute < morningStartMinute + 5 &&
        state.lastMorningGeneration !== today
      ) {
        await generatePendingReports('morning');
        state.lastMorningGeneration = today;
        await saveState(state);
      }

      // Проверка 2: Создание вечерних pending (19:00)
      const [eveningStartHour, eveningStartMinute] = settings.eveningStartTime.split(':').map(Number);
      if (
        currentHour === eveningStartHour &&
        currentMinute >= eveningStartMinute &&
        currentMinute < eveningStartMinute + 5 &&
        state.lastEveningGeneration !== today
      ) {
        await generatePendingReports('evening');
        state.lastEveningGeneration = today;
        await saveState(state);
      }

      // Проверка 3: Дедлайны
      await checkPendingDeadlines();

      // Проверка 4: Очистка в 23:59
      if (currentHour === 23 && currentMinute >= 59) {
        if (state.lastCleanup !== today) {
          await cleanupFailedReports();
        }
      }

    } catch (error) {
      console.error('[Envelope Automation] Ошибка:', error);
    }
  }, CHECK_INTERVAL_MS);

  console.log('[Envelope Automation] Scheduler запущен (проверка каждые 5 минут)');
}

module.exports = {
  startScheduler
};
