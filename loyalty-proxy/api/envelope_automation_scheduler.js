const fs = require('fs');
const path = require('path');

// Директории
const ENVELOPE_PENDING_DIR = '/var/www/envelope-pending';
const ENVELOPE_REPORTS_DIR = '/var/www/envelope-reports';
const ENVELOPE_STATE_DIR = '/var/www/envelope-automation-state';
const STATE_FILE = path.join(ENVELOPE_STATE_DIR, 'state.json');
const SHOPS_FILE = '/var/www/shops/shops.json';
const POINTS_SETTINGS_FILE = '/var/www/points-settings/envelope_points_settings.json';

// Интервал проверки: 5 минут
const CHECK_INTERVAL_MS = 5 * 60 * 1000;

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
function getEnvelopeSettings() {
  if (!fs.existsSync(POINTS_SETTINGS_FILE)) {
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
  return JSON.parse(fs.readFileSync(POINTS_SETTINGS_FILE, 'utf8'));
}

/**
 * Загрузка состояния автоматизации
 */
function loadState() {
  if (!fs.existsSync(STATE_FILE)) {
    const defaultState = {
      lastMorningGeneration: null,
      lastEveningGeneration: null,
      lastCleanup: null,
      lastCheck: null
    };
    fs.writeFileSync(STATE_FILE, JSON.stringify(defaultState, null, 2));
    return defaultState;
  }
  return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
}

/**
 * Сохранение состояния
 */
function saveState(state) {
  state.lastCheck = new Date().toISOString();
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

/**
 * Загрузка pending отчетов за сегодня
 */
function loadTodayPendingReports() {
  const moscow = getMoscowTime();
  const today = moscow.toISOString().split('T')[0];
  const reports = [];

  if (!fs.existsSync(ENVELOPE_PENDING_DIR)) {
    return reports;
  }

  const files = fs.readdirSync(ENVELOPE_PENDING_DIR);

  for (const file of files) {
    if (file.startsWith('pending_env_')) {
      const filePath = path.join(ENVELOPE_PENDING_DIR, file);
      try {
        const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
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
function findPendingReport(shopAddress, shiftType, date) {
  if (!fs.existsSync(ENVELOPE_PENDING_DIR)) {
    return null;
  }

  const files = fs.readdirSync(ENVELOPE_PENDING_DIR);

  for (const file of files) {
    if (file.startsWith('pending_env_')) {
      const filePath = path.join(ENVELOPE_PENDING_DIR, file);
      try {
        const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
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
function checkIfEnvelopeSubmitted(shopAddress, shiftType, date) {
  if (!fs.existsSync(ENVELOPE_REPORTS_DIR)) {
    return false;
  }

  const files = fs.readdirSync(ENVELOPE_REPORTS_DIR);

  for (const file of files) {
    if (file.endsWith('.json')) {
      const filePath = path.join(ENVELOPE_REPORTS_DIR, file);
      try {
        const report = JSON.parse(fs.readFileSync(filePath, 'utf8'));

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
 */
async function generatePendingReports(shiftType) {
  console.log(`[Envelope Automation] Создание pending отчетов для ${shiftType}`);

  // 1. Загрузить все магазины
  if (!fs.existsSync(SHOPS_FILE)) {
    console.log('[Envelope] Файл магазинов не найден');
    return 0;
  }

  const shops = JSON.parse(fs.readFileSync(SHOPS_FILE, 'utf8'));

  // 2. Получить настройки
  const settings = getEnvelopeSettings();
  const deadline = shiftType === 'morning' ? settings.morningDeadline : settings.eveningDeadline;

  // 3. Текущая дата
  const moscow = getMoscowTime();
  const today = moscow.toISOString().split('T')[0]; // YYYY-MM-DD

  let created = 0;

  for (const shop of shops) {
    const shopAddress = shop.address;

    // Проверить: уже существует pending отчет?
    const existingPending = findPendingReport(shopAddress, shiftType, today);
    if (existingPending) {
      console.log(`[Envelope] Pending уже существует: ${shopAddress}`);
      continue;
    }

    // Проверить: уже сдан отчет?
    const submitted = checkIfEnvelopeSubmitted(shopAddress, shiftType, today);
    if (submitted) {
      console.log(`[Envelope] Конверт уже сдан: ${shopAddress}`);
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
    fs.writeFileSync(filePath, JSON.stringify(report, null, 2));
    created++;
  }

  console.log(`[Envelope] Создано pending отчетов: ${created}`);
  return created;
}

/**
 * Проверка дедлайнов pending отчетов
 */
async function checkPendingDeadlines() {
  const reports = loadTodayPendingReports();
  const moscow = getMoscowTime();
  const settings = getEnvelopeSettings();

  const failedReports = [];

  for (const report of reports) {
    if (report.status !== 'pending') continue;

    // 1. Проверить: может быть конверт уже сдан?
    const submitted = checkIfEnvelopeSubmitted(
      report.shopAddress,
      report.shiftType,
      report.date
    );

    if (submitted) {
      // Удалить pending файл
      fs.unlinkSync(report._filePath);
      console.log(`[Envelope] Pending удален (сдан): ${report.shopAddress}`);
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
      fs.writeFileSync(report._filePath, JSON.stringify(report, null, 2));

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

  return failedReports;
}

/**
 * Назначение штрафа сотруднику из графика
 */
async function assignPenaltyFromSchedule(report, settings) {
  const { shopAddress, shiftType, date } = report;

  // 1. Загрузить график работы
  const [year, month] = date.split('-');
  const scheduleFile = `/var/www/work-schedules/${year}-${month}.json`;

  if (!fs.existsSync(scheduleFile)) {
    console.log(`[Envelope] График не найден: ${scheduleFile}`);
    return;
  }

  const schedule = JSON.parse(fs.readFileSync(scheduleFile, 'utf8'));

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
  const penaltiesDir = '/var/www/efficiency-penalties';
  if (!fs.existsSync(penaltiesDir)) {
    fs.mkdirSync(penaltiesDir, { recursive: true });
  }

  const penaltiesFile = path.join(penaltiesDir, `${year}-${month}.json`);
  let penalties = { penalties: [] };

  if (fs.existsSync(penaltiesFile)) {
    penalties = JSON.parse(fs.readFileSync(penaltiesFile, 'utf8'));
  }

  // Проверка дубликатов
  const exists = penalties.penalties.some(p => p.sourceId === report.id);
  if (exists) {
    console.log(`[Envelope] Штраф уже существует для: ${report.id}`);
    return;
  }

  penalties.penalties.push(penalty);
  fs.writeFileSync(penaltiesFile, JSON.stringify(penalties, null, 2));

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
      count: count
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
      points: points
    });

    console.log(`[Envelope] Push сотруднику ${employeeName}: ${body}`);
  } catch (error) {
    console.error(`[Envelope] Ошибка отправки push сотруднику ${employeeName}:`, error.message);
  }
}

/**
 * Очистка failed отчетов в конце дня
 */
function cleanupFailedReports() {
  console.log('[Envelope] Очистка pending/failed отчетов (23:59)');

  if (!fs.existsSync(ENVELOPE_PENDING_DIR)) {
    console.log('[Envelope] Директория pending не существует');
    return;
  }

  const files = fs.readdirSync(ENVELOPE_PENDING_DIR);
  let deleted = 0;

  for (const file of files) {
    if (file.startsWith('pending_env_')) {
      fs.unlinkSync(path.join(ENVELOPE_PENDING_DIR, file));
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

  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

/**
 * Главный цикл проверки
 */
function startScheduler() {
  console.log('[Envelope Automation] Запуск scheduler...');

  // Создать директории если их нет
  if (!fs.existsSync(ENVELOPE_PENDING_DIR)) {
    fs.mkdirSync(ENVELOPE_PENDING_DIR, { recursive: true });
    console.log(`[Envelope] Создана директория: ${ENVELOPE_PENDING_DIR}`);
  }
  if (!fs.existsSync(ENVELOPE_STATE_DIR)) {
    fs.mkdirSync(ENVELOPE_STATE_DIR, { recursive: true });
    console.log(`[Envelope] Создана директория: ${ENVELOPE_STATE_DIR}`);
  }

  // Запустить проверку каждые 5 минут
  setInterval(async () => {
    try {
      const moscow = getMoscowTime();
      const settings = getEnvelopeSettings();
      const state = loadState();

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
        saveState(state);
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
        saveState(state);
      }

      // Проверка 3: Дедлайны
      await checkPendingDeadlines();

      // Проверка 4: Очистка в 23:59
      if (currentHour === 23 && currentMinute >= 59) {
        if (state.lastCleanup !== today) {
          cleanupFailedReports();
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
