/**
 * RKO Automation Scheduler
 *
 * Автоматизация жизненного цикла РКО отчётов (ЗП после смены):
 * - Автоматическое создание pending отчётов при начале временного окна
 * - Переход pending → failed по истечении дедлайна
 * - Начисление штрафов за пропуск
 * - Push-уведомления
 * - Очистка failed отчётов в 23:59
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('../utils/async_fs');

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Импортируем функции отправки push-уведомлений
let sendPushNotification = null;
let sendPushToPhone = null;
try {
  const notificationsApi = require('./report_notifications_api');
  sendPushNotification = notificationsApi.sendPushNotification;
  sendPushToPhone = notificationsApi.sendPushToPhone;
  console.log('[RkoScheduler] Push notifications enabled');
} catch (e) {
  console.log('[RkoScheduler] Push notifications disabled:', e.message);
}

// Directories
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const RKO_REPORTS_DIR = `${DATA_DIR}/rko-reports`;
const RKO_PENDING_DIR = `${DATA_DIR}/rko-pending`;
const SHOPS_DIR = `${DATA_DIR}/shops`;
const WORK_SCHEDULES_DIR = `${DATA_DIR}/work-schedules`;
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;
const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;
const RKO_AUTOMATION_STATE_DIR = `${DATA_DIR}/rko-automation-state`;
const STATE_FILE = path.join(RKO_AUTOMATION_STATE_DIR, 'state.json');

// Constants
const PENALTY_CATEGORY = 'rko_missed_penalty';
const PENALTY_CATEGORY_NAME = 'Пропущенный РКО';
const CHECK_INTERVAL_MS = 5 * 60 * 1000; // Проверка каждые 5 минут
const MOSCOW_OFFSET_HOURS = 3; // UTC+3 для московского времени

// ============================================
// Moscow Time Helper
// ============================================
function getMoscowTime() {
  const now = new Date();
  // Создаём дату в московском времени (UTC+3)
  const moscowTime = new Date(now.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
  return moscowTime;
}

function getMoscowDateString() {
  const moscow = getMoscowTime();
  return moscow.toISOString().split('T')[0]; // YYYY-MM-DD в московском времени
}

// ============================================
// Helper: Load JSON file safely
// ============================================
async function loadJsonFile(filePath, defaultValue) {
  if (!(await fileExists(filePath))) {
    return defaultValue;
  }
  try {
    const data = await fsp.readFile(filePath, 'utf8');
    return JSON.parse(data);
  } catch (e) {
    console.error(`[RkoScheduler] Error loading JSON from ${filePath}:`, e.message);
    return defaultValue;
  }
}

async function saveJsonFile(filePath, data) {
  try {
    await writeJsonFile(filePath, data);
    return true;
  } catch (e) {
    console.error(`[RkoScheduler] Error saving JSON to ${filePath}:`, e.message);
    return false;
  }
}

// ============================================
// State Management
// ============================================
async function loadState() {
  return await loadJsonFile(STATE_FILE, {
    lastMorningGeneration: null,
    lastEveningGeneration: null,
    lastCleanup: null,
    lastCheck: null
  });
}

async function saveState(state) {
  state.lastCheck = new Date().toISOString();
  await saveJsonFile(STATE_FILE, state);
}

// ============================================
// Settings Loading
// ============================================
async function getRkoSettings() {
  const defaults = {
    hasRkoPoints: 1,
    noRkoPoints: -3,
    morningStartTime: '07:00',
    morningEndTime: '14:00',
    eveningStartTime: '14:00',
    eveningEndTime: '23:00',
    missedPenalty: -3
  };

  const settingsFile = path.join(POINTS_SETTINGS_DIR, 'rko_points_settings.json');
  const loaded = await loadJsonFile(settingsFile, {});

  // Объединяем загруженные настройки с defaults
  return {
    ...defaults,
    ...loaded,
    // Гарантируем что критичные поля всегда имеют значение
    morningStartTime: loaded.morningStartTime || defaults.morningStartTime,
    morningEndTime: loaded.morningEndTime || defaults.morningEndTime,
    eveningStartTime: loaded.eveningStartTime || defaults.eveningStartTime,
    eveningEndTime: loaded.eveningEndTime || defaults.eveningEndTime,
    missedPenalty: loaded.missedPenalty !== undefined ? loaded.missedPenalty : defaults.missedPenalty
  };
}

// ============================================
// Shops Loading
// ============================================
async function getAllShops() {
  const shops = [];
  try {
    if (!(await fileExists(SHOPS_DIR))) return shops;
    const files = await fsp.readdir(SHOPS_DIR);
    for (const file of files) {
      if (file.startsWith('shop_') && file.endsWith('.json')) {
        const shop = await loadJsonFile(path.join(SHOPS_DIR, file));
        if (shop && shop.address) {
          shops.push(shop);
        }
      }
    }
  } catch (e) {
    console.error('[RkoScheduler] Error reading shops directory:', e.message);
  }
  return shops;
}

// ============================================
// Pending Reports Management
// ============================================
function getPendingReportsDir() {
  return RKO_PENDING_DIR;
}

async function loadTodayPendingReports() {
  const reportsDir = getPendingReportsDir();
  const reports = [];
  const today = getMoscowDateString();

  if (!(await fileExists(reportsDir))) {
    return reports;
  }

  try {
    const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const filePath = path.join(reportsDir, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const report = JSON.parse(content);

        // Фильтруем только сегодняшние отчёты
        const reportDate = report.createdAt ? report.createdAt.split('T')[0] : null;
        if (reportDate === today || report.status === 'pending') {
          reports.push({ ...report, _filePath: filePath });
        }
      } catch (e) {
        console.error(`[RkoScheduler] Error reading file ${file}:`, e.message);
      }
    }
  } catch (e) {
    console.error('[RkoScheduler] Error reading reports directory:', e.message);
  }

  return reports;
}

async function savePendingReport(report) {
  const filePath = report._filePath;
  if (!filePath) {
    console.error('[RkoScheduler] No _filePath in report');
    return false;
  }

  const dataToSave = { ...report };
  delete dataToSave._filePath;

  return await saveJsonFile(filePath, dataToSave);
}

async function createPendingReport(shop, shiftType, deadline) {
  const reportsDir = getPendingReportsDir();
  if (!(await fileExists(reportsDir))) {
    await fsp.mkdir(reportsDir, { recursive: true });
  }

  const now = new Date();
  const reportId = `pending_rko_${shiftType}_${shop.address.replace(/[^a-zA-Z0-9]/g, '_')}_${Date.now()}`;
  const filePath = path.join(reportsDir, `${reportId}.json`);

  const report = {
    id: reportId,
    shopAddress: shop.address,
    shopName: shop.name,
    shiftType: shiftType,
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

  await saveJsonFile(filePath, report);
  console.log(`[RkoScheduler] Created pending ${shiftType} RKO for ${shop.name} (${shop.address}), deadline: ${deadline.toISOString()}`);
  return report;
}

// ============================================
// Check if RKO was submitted
// ============================================
async function checkIfRkoSubmitted(shopAddress, shiftType, today) {
  const metadataFile = path.join(RKO_REPORTS_DIR, 'rko_metadata.json');
  const metadata = await loadJsonFile(metadataFile, { items: [] });

  // Ищем РКО за сегодня для этого магазина
  const submitted = metadata.items.some(rko => {
    const rkoDate = rko.date ? rko.date.split('T')[0] : null;
    return rkoDate === today &&
           rko.shopAddress === shopAddress &&
           rko.rkoType === 'ЗП после смены';
  });

  return submitted;
}

// ============================================
// Time Helpers
// ============================================
function parseTime(timeStr) {
  const [hours, minutes] = timeStr.split(':').map(Number);
  return { hours, minutes };
}

function isTimeReached(timeStr) {
  const moscow = getMoscowTime();
  const { hours, minutes } = parseTime(timeStr);

  const moscowHours = moscow.getUTCHours();
  const moscowMinutes = moscow.getUTCMinutes();

  return moscowHours > hours ||
         (moscowHours === hours && moscowMinutes >= minutes);
}

/**
 * Проверяет, находимся ли мы внутри временного окна.
 * Корректно обрабатывает ночные интервалы (когда end < start, например 20:00-06:58)
 */
function isWithinTimeWindow(startTimeStr, endTimeStr) {
  const moscow = getMoscowTime();
  const start = parseTime(startTimeStr);
  const end = parseTime(endTimeStr);

  const moscowHours = moscow.getUTCHours();
  const moscowMinutes = moscow.getUTCMinutes();
  const currentMinutes = moscowHours * 60 + moscowMinutes;
  const startMinutes = start.hours * 60 + start.minutes;
  const endMinutes = end.hours * 60 + end.minutes;

  // Ночной интервал (например 20:00 - 06:58)
  if (endMinutes < startMinutes) {
    // Мы в интервале если: текущее время >= начала ИЛИ текущее время < конца
    return currentMinutes >= startMinutes || currentMinutes < endMinutes;
  }

  // Дневной интервал (например 07:00 - 19:58)
  return currentMinutes >= startMinutes && currentMinutes < endMinutes;
}

function isSameDay(date1, date2) {
  const moscow1 = new Date(date1.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
  const moscow2 = new Date(date2.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
  return moscow1.toISOString().split('T')[0] === moscow2.toISOString().split('T')[0];
}

function getDeadlineTime(timeStr, startTimeStr = null) {
  const { hours, minutes } = parseTime(timeStr);
  const moscow = getMoscowTime();
  const today = getMoscowDateString();

  // Проверяем, ночной ли это интервал (дедлайн раньше старта)
  let isNightInterval = false;
  if (startTimeStr) {
    const start = parseTime(startTimeStr);
    const endMinutes = hours * 60 + minutes;
    const startMinutes = start.hours * 60 + start.minutes;
    isNightInterval = endMinutes < startMinutes;
  }

  // Если ночной интервал - дедлайн завтра
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

// ============================================
// 1. Generate Pending Reports
// ============================================
async function generatePendingReports(shiftType) {
  const settings = await getRkoSettings();
  const shops = await getAllShops();
  const today = getMoscowDateString();

  if (shops.length === 0) {
    console.log(`[RkoScheduler] No shops found, skipping ${shiftType} report generation`);
    return 0;
  }

  const pendingReports = await loadTodayPendingReports();
  let created = 0;

  const deadlineTime = shiftType === 'morning'
    ? settings.morningEndTime
    : settings.eveningEndTime;
  const startTime = shiftType === 'morning'
    ? settings.morningStartTime
    : settings.eveningStartTime;

  const deadline = getDeadlineTime(deadlineTime, startTime);

  console.log(`[RkoScheduler] ${shiftType} deadline calculated: ${deadline.toISOString()}`);

  for (const shop of shops) {
    // Check if pending report already exists for this shop/shift
    const existsPending = pendingReports.some(r =>
      r.shopAddress === shop.address &&
      r.shiftType === shiftType &&
      r.status === 'pending'
    );

    if (existsPending) continue;

    // Check if RKO was already submitted today for this shop
    const alreadySubmitted = await checkIfRkoSubmitted(shop.address, shiftType, today);
    if (alreadySubmitted) {
      console.log(`[RkoScheduler] RKO already submitted for ${shop.name}, skipping`);
      continue;
    }

    // Create pending report
    await createPendingReport(shop, shiftType, deadline);
    created++;
  }

  console.log(`[RkoScheduler] Generated ${created} pending ${shiftType} RKOs`);
  return created;
}

// ============================================
// 2. Check Pending Deadlines (pending → failed)
// ============================================
async function checkPendingDeadlines() {
  const now = new Date();
  const today = getMoscowDateString();
  const reports = await loadTodayPendingReports();
  let failedCount = 0;
  const failedShops = [];

  for (const report of reports) {
    if (report.status !== 'pending') continue;

    const deadline = new Date(report.deadline);

    // Check if RKO was submitted in the meantime
    const submitted = await checkIfRkoSubmitted(report.shopAddress, report.shiftType, today);
    if (submitted) {
      // Mark as completed and remove pending
      console.log(`[RkoScheduler] RKO submitted for ${report.shopName}, removing pending`);
      if (report._filePath && (await fileExists(report._filePath))) {
        await fsp.unlink(report._filePath);
      }
      continue;
    }

    if (now > deadline) {
      // Deadline passed - mark as failed
      report.status = 'failed';
      report.failedAt = now.toISOString();
      await savePendingReport(report);
      failedCount++;

      failedShops.push({
        shopAddress: report.shopAddress,
        shopName: report.shopName,
        shiftType: report.shiftType,
        deadline: report.deadline
      });

      console.log(`[RkoScheduler] RKO FAILED: ${report.shopName} (${report.shiftType}), deadline was ${report.deadline}`);

      // Assign penalty to employee from work schedule
      await assignPenaltyFromSchedule(report);
    }
  }

  if (failedCount > 0) {
    // Send push notification to admin about failed reports
    await sendAdminFailedNotification(failedCount, failedShops);
  }

  return failedCount;
}

// ============================================
// 3. Assign Penalty from Work Schedule
// ============================================
async function assignPenaltyFromSchedule(report) {
  const settings = await getRkoSettings();
  const today = getMoscowDateString();
  const monthKey = today.substring(0, 7); // YYYY-MM

  // Load work schedule for this month
  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);
  const schedule = await loadJsonFile(scheduleFile, { entries: [] });

  if (!schedule.entries || schedule.entries.length === 0) {
    console.log(`[RkoScheduler] No work schedule found for ${monthKey}, cannot assign penalty`);
    return;
  }

  // Find employee assigned to this shop/shift/date
  const entry = schedule.entries.find(e =>
    e.shopAddress === report.shopAddress &&
    e.date === today &&
    e.shiftType === report.shiftType
  );

  if (!entry) {
    console.log(`[RkoScheduler] No schedule entry found for ${report.shopAddress}, ${today}, ${report.shiftType}`);
    return;
  }

  // Create penalty
  await createPenalty({
    employeeId: entry.employeeId,
    employeeName: entry.employeeName,
    shopAddress: report.shopAddress,
    points: settings.missedPenalty,
    reason: `Не сдан ${report.shiftType === 'morning' ? 'утренний' : 'вечерний'} РКО`,
    sourceId: report.id
  });
}

// ============================================
// 4. Create Penalty
// ============================================
async function createPenalty({ employeeId, employeeName, shopAddress, points, reason, sourceId }) {
  const now = new Date();
  const today = getMoscowDateString();
  const monthKey = today.substring(0, 7);

  const penalty = {
    id: `penalty_rko_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    type: 'employee',
    entityId: employeeId,
    entityName: employeeName,
    shopAddress: shopAddress,
    employeeName: employeeName,
    category: PENALTY_CATEGORY,
    categoryName: PENALTY_CATEGORY_NAME,
    date: today,
    points: points,
    reason: reason,
    sourceId: sourceId,
    sourceType: 'rko_report',
    createdAt: now.toISOString()
  };

  // Load existing penalties
  const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);
  let penalties = await loadJsonFile(penaltiesFile, []);
  if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];

  // Check for duplicate
  const exists = penalties.some(p => p.sourceId === sourceId);
  if (exists) {
    console.log(`[RkoScheduler] Penalty already exists for ${sourceId}, skipping`);
    return;
  }

  penalties.push(penalty);
  await saveJsonFile(penaltiesFile, penalties);

  console.log(`[RkoScheduler] Created penalty for ${employeeName}: ${points} points (${reason})`);
}

// ============================================
// 5. Admin Failed Notification
// ============================================
async function sendAdminFailedNotification(count, failedShops) {
  const shiftTypes = [...new Set(failedShops.map(s => s.shiftType))];
  const shiftLabel = shiftTypes.includes('morning') ? 'утренний' : 'вечерний';

  const title = 'РКО не сданы';
  const body = `${count} магазинов не сдали ${shiftLabel} РКО`;

  console.log(`[RkoScheduler] PUSH to Admin: ${body}`);

  if (sendPushNotification) {
    try {
      await sendPushNotification(title, body, {
        type: 'rko_failed',
        count: String(count),
        shiftType: shiftTypes.join(','),
      });
      console.log('[RkoScheduler] Push notification sent successfully');
    } catch (e) {
      console.error('[RkoScheduler] Error sending push notification:', e.message);
    }
  } else {
    console.log('[RkoScheduler] Push notifications not available');
  }
}

// ============================================
// 6. Cleanup ALL Reports (at 23:59)
// ============================================
async function cleanupFailedReports() {
  // Удаляем ВСЕ файлы в папке pending (и failed, и оставшиеся pending)
  let removedCount = 0;

  try {
    if (await fileExists(RKO_PENDING_DIR)) {
      const files = await fsp.readdir(RKO_PENDING_DIR);
      for (const file of files) {
        if (file.endsWith('.json')) {
          try {
            await fsp.unlink(path.join(RKO_PENDING_DIR, file));
            removedCount++;
          } catch (e) {
            console.error(`[RkoScheduler] Error removing file ${file}:`, e.message);
          }
        }
      }
    }
  } catch (e) {
    console.error('[RkoScheduler] Error reading pending directory:', e.message);
  }

  if (removedCount > 0) {
    console.log(`[RkoScheduler] Cleanup: removed ${removedCount} RKO files`);
  }

  // Также сбрасываем state для нового дня
  const emptyState = {
    lastMorningGeneration: null,
    lastEveningGeneration: null,
    lastCleanup: new Date().toISOString(),
    lastCheck: new Date().toISOString()
  };
  await saveState(emptyState);
  console.log('[RkoScheduler] State reset for new day');

  return removedCount;
}

// ============================================
// 7. Main Check Function
// ============================================
async function runScheduledChecks() {
  const now = new Date();
  const moscow = getMoscowTime();
  const settings = await getRkoSettings();
  const state = await loadState();

  console.log(`\n[${now.toISOString()}] RkoScheduler: Running checks... (Moscow time: ${moscow.toISOString()})`);
  console.log(`[RkoScheduler] Settings: morning ${settings.morningStartTime}-${settings.morningEndTime}, evening ${settings.eveningStartTime}-${settings.eveningEndTime}`);

  // Check if morning window is active
  if (isWithinTimeWindow(settings.morningStartTime, settings.morningEndTime)) {
    const lastGen = state.lastMorningGeneration;
    if (!lastGen || !isSameDay(new Date(lastGen), now)) {
      console.log(`[RkoScheduler] Morning window active (${settings.morningStartTime} - ${settings.morningEndTime}), generating reports...`);
      const created = await generatePendingReports('morning');
      if (created > 0) {
        state.lastMorningGeneration = now.toISOString();
      }
    }
  }

  // Check if evening window is active
  if (isWithinTimeWindow(settings.eveningStartTime, settings.eveningEndTime)) {
    const lastGen = state.lastEveningGeneration;
    if (!lastGen || !isSameDay(new Date(lastGen), now)) {
      console.log(`[RkoScheduler] Evening window active (${settings.eveningStartTime} - ${settings.eveningEndTime}), generating reports...`);
      const created = await generatePendingReports('evening');
      if (created > 0) {
        state.lastEveningGeneration = now.toISOString();
      }
    }
  }

  // Check pending deadlines
  const failed = await checkPendingDeadlines();
  if (failed > 0) {
    console.log(`[RkoScheduler] ${failed} RKOs marked as failed`);
  }

  // Cleanup: проверяем что уже новый день и cleanup не был сделан сегодня
  // Срабатывает после полуночи (00:00-06:00) если cleanup не был сделан
  const moscowHours = moscow.getUTCHours();
  const lastCleanup = state.lastCleanup;
  const lastCleanupDate = lastCleanup ? new Date(lastCleanup) : null;
  const todayMoscow = getMoscowDateString();
  const lastCleanupMoscow = lastCleanupDate
    ? new Date(lastCleanupDate.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000).toISOString().split('T')[0]
    : null;

  // Cleanup если: новый день И (нет lastCleanup ИЛИ lastCleanup был в прошлом дне) И время 00:00-06:00
  if (moscowHours >= 0 && moscowHours < 6 && lastCleanupMoscow !== todayMoscow) {
    console.log(`[RkoScheduler] Running daily cleanup (last cleanup: ${lastCleanupMoscow}, today: ${todayMoscow})`);
    await cleanupFailedReports();
    // cleanupFailedReports сбрасывает state, перезагружаем его
    const newState = await loadState();
    await saveState(newState);
    console.log(`[RkoScheduler] Checks completed\n`);
    return; // Выходим чтобы не перезаписать state
  }

  await saveState(state);
  console.log(`[RkoScheduler] Checks completed\n`);
}

// ============================================
// 8. Scheduler Setup
// ============================================
async function startRkoAutomationScheduler() {
  const settings = await getRkoSettings();
  const moscow = getMoscowTime();

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('RKO Automation Scheduler started');
  console.log(`  - Timezone: Moscow (UTC+3)`);
  console.log(`  - Current Moscow time: ${moscow.toISOString()}`);
  console.log(`  - Morning window: ${settings.morningStartTime} - ${settings.morningEndTime}`);
  console.log(`  - Evening window: ${settings.eveningStartTime} - ${settings.eveningEndTime}`);
  console.log(`  - Missed penalty: ${settings.missedPenalty} points`);
  console.log(`  - Check interval: ${CHECK_INTERVAL_MS / 1000 / 60} minutes`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Run checks every 5 minutes
  let isRunning = false;
  const guardedCheck = async () => {
    if (isRunning) { console.log('[RkoScheduler] Previous run still active, skipping'); return; }
    isRunning = true;
    try { await runScheduledChecks(); }
    catch (err) { console.error('[RkoScheduler] Scheduler error:', err.message); }
    finally { isRunning = false; }
  };

  setInterval(guardedCheck, CHECK_INTERVAL_MS);

  // First check after 4 seconds (slightly offset from other schedulers)
  setTimeout(guardedCheck, 4000);
}

// ============================================
// 9. API Helper: Get Pending Reports
// ============================================
async function getPendingReports() {
  const reports = await loadTodayPendingReports();
  return reports.filter(r => r.status === 'pending');
}

async function getFailedReports() {
  const reports = await loadTodayPendingReports();
  return reports.filter(r => r.status === 'failed');
}

// ============================================
// Exports
// ============================================
module.exports = {
  startRkoAutomationScheduler,
  generatePendingReports,
  checkPendingDeadlines,
  cleanupFailedReports,
  loadTodayPendingReports,
  getPendingReports,
  getFailedReports,
  getRkoSettings,
  getMoscowTime,
  getMoscowDateString
};
