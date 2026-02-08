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
 */

const fs = require('fs');
const path = require('path');

// Импортируем функции отправки push-уведомлений
let sendPushNotification = null;
let sendPushToPhone = null;
try {
  const notificationsApi = require('../report_notifications_api');
  sendPushNotification = notificationsApi.sendPushNotification;
  sendPushToPhone = notificationsApi.sendPushToPhone;
  console.log('[RecountScheduler] Push notifications enabled');
} catch (e) {
  console.log('[RecountScheduler] Push notifications disabled:', e.message);
}

// Directories
const RECOUNT_REPORTS_DIR = '/var/www/recount-reports';
const SHOPS_DIR = '/var/www/shops';
const WORK_SCHEDULES_DIR = '/var/www/work-schedules';
const EFFICIENCY_PENALTIES_DIR = '/var/www/efficiency-penalties';
const POINTS_SETTINGS_DIR = '/var/www/points-settings';
const RECOUNT_AUTOMATION_STATE_DIR = '/var/www/recount-automation-state';
const STATE_FILE = path.join(RECOUNT_AUTOMATION_STATE_DIR, 'state.json');

// Constants
const PENALTY_CATEGORY = 'recount_missed_penalty';
const PENALTY_CATEGORY_NAME = 'Пропущенный пересчёт';
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
function loadJsonFile(filePath, defaultValue) {
  if (!fs.existsSync(filePath)) {
    return defaultValue;
  }
  try {
    const data = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(data);
  } catch (e) {
    console.error(`[RecountScheduler] Error loading JSON from ${filePath}:`, e.message);
    return defaultValue;
  }
}

function saveJsonFile(filePath, data) {
  try {
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
    return true;
  } catch (e) {
    console.error(`[RecountScheduler] Error saving JSON to ${filePath}:`, e.message);
    return false;
  }
}

// ============================================
// State Management
// ============================================
function loadState() {
  return loadJsonFile(STATE_FILE, {
    lastMorningGeneration: null,
    lastEveningGeneration: null,
    lastCleanup: null,
    lastCheck: null
  });
}

function saveState(state) {
  state.lastCheck = new Date().toISOString();
  saveJsonFile(STATE_FILE, state);
}

// ============================================
// Settings Loading
// ============================================
function getRecountSettings() {
  const defaults = {
    morningStartTime: '08:00',
    morningEndTime: '14:00',
    eveningStartTime: '14:00',
    eveningEndTime: '23:00',
    missedPenalty: -3,
    adminReviewTimeout: 2 // hours
  };

  const settingsFile = path.join(POINTS_SETTINGS_DIR, 'recount_points_settings.json');
  const loaded = loadJsonFile(settingsFile, {});

  // Объединяем загруженные настройки с defaults
  return {
    ...defaults,
    ...loaded,
    // Гарантируем что критичные поля всегда имеют значение
    morningStartTime: loaded.morningStartTime || defaults.morningStartTime,
    morningEndTime: loaded.morningEndTime || defaults.morningEndTime,
    eveningStartTime: loaded.eveningStartTime || defaults.eveningStartTime,
    eveningEndTime: loaded.eveningEndTime || defaults.eveningEndTime,
    missedPenalty: loaded.missedPenalty !== undefined ? loaded.missedPenalty : defaults.missedPenalty,
    adminReviewTimeout: loaded.adminReviewTimeout || defaults.adminReviewTimeout
  };
}

// ============================================
// Shops Loading
// ============================================
function getAllShops() {
  const shopsFile = path.join(SHOPS_DIR, 'shops.json');
  const data = loadJsonFile(shopsFile, { shops: [] });
  return data.shops || [];
}

// ============================================
// Reports Management
// ============================================
function getTodayReportsDir() {
  return RECOUNT_REPORTS_DIR;
}

function loadTodayReports() {
  const reportsDir = getTodayReportsDir();
  const reports = [];
  const today = getMoscowDateString();

  if (!fs.existsSync(reportsDir)) {
    return reports;
  }

  try {
    const files = fs.readdirSync(reportsDir).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const filePath = path.join(reportsDir, file);
        const content = fs.readFileSync(filePath, 'utf8');
        const report = JSON.parse(content);

        // Фильтруем только сегодняшние отчёты
        const reportDate = report.createdAt ? report.createdAt.split('T')[0] : null;
        if (reportDate === today || report.status === 'pending') {
          reports.push({ ...report, _filePath: filePath });
        }
      } catch (e) {
        console.error(`[RecountScheduler] Error reading file ${file}:`, e.message);
      }
    }
  } catch (e) {
    console.error('[RecountScheduler] Error reading reports directory:', e.message);
  }

  return reports;
}

function saveReport(report) {
  const filePath = report._filePath;
  if (!filePath) {
    console.error('[RecountScheduler] No _filePath in report');
    return false;
  }

  const dataToSave = { ...report };
  delete dataToSave._filePath;

  return saveJsonFile(filePath, dataToSave);
}

function createPendingReport(shop, shiftType, deadline) {
  const reportsDir = getTodayReportsDir();
  if (!fs.existsSync(reportsDir)) {
    fs.mkdirSync(reportsDir, { recursive: true });
  }

  const now = new Date();
  const reportId = `pending_recount_${shiftType}_${shop.address.replace(/[^a-zA-Z0-9]/g, '_')}_${Date.now()}`;
  const filePath = path.join(reportsDir, `${reportId}.json`);

  const report = {
    id: reportId,
    shopAddress: shop.address,
    shopName: shop.name,
    shiftType: shiftType,
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

  saveJsonFile(filePath, report);
  return report;
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
function generatePendingReports(shiftType) {
  const settings = getRecountSettings();
  const shops = getAllShops();
  const today = getMoscowDateString();

  if (shops.length === 0) {
    console.log(`[RecountScheduler] No shops found, skipping ${shiftType} report generation`);
    return 0;
  }

  const reports = loadTodayReports();
  let created = 0;

  const deadlineTime = shiftType === 'morning'
    ? settings.morningEndTime
    : settings.eveningEndTime;
  const startTime = shiftType === 'morning'
    ? settings.morningStartTime
    : settings.eveningStartTime;

  const deadline = getDeadlineTime(deadlineTime, startTime);

  console.log(`[RecountScheduler] ${shiftType} deadline calculated: ${deadline.toISOString()}`);


  for (const shop of shops) {
    // Check if pending report already exists for this shop/shift
    const exists = reports.some(r =>
      r.shopAddress === shop.address &&
      r.shiftType === shiftType &&
      (r.status === 'pending' || r.status === 'review' || r.status === 'confirmed')
    );

    if (exists) continue;

    // Create pending report
    createPendingReport(shop, shiftType, deadline);
    created++;
    console.log(`[RecountScheduler] Created pending ${shiftType} recount for ${shop.name} (${shop.address})`);
  }

  console.log(`[RecountScheduler] Generated ${created} pending ${shiftType} recounts`);
  return created;
}

// ============================================
// 2. Check Pending Deadlines (pending → failed)
// ============================================
async function checkPendingDeadlines() {
  const now = new Date();
  const reports = loadTodayReports();
  let failedCount = 0;
  const failedShops = [];

  for (const report of reports) {
    if (report.status !== 'pending') continue;

    const deadline = new Date(report.deadline);

    if (now > deadline) {
      // Deadline passed - mark as failed
      report.status = 'failed';
      report.failedAt = now.toISOString();
      saveReport(report);
      failedCount++;

      failedShops.push({
        shopAddress: report.shopAddress,
        shopName: report.shopName,
        shiftType: report.shiftType,
        deadline: report.deadline
      });

      console.log(`[RecountScheduler] Recount FAILED: ${report.shopName} (${report.shiftType}), deadline was ${report.deadline}`);

      // Assign penalty to employee from work schedule
      assignPenaltyFromSchedule(report);
    }
  }

  if (failedCount > 0) {
    // Send push notification to admin about failed reports
    await sendAdminFailedNotification(failedCount, failedShops);
  }

  return failedCount;
}

// ============================================
// 3. Check Review Timeouts (review → rejected)
// ============================================
function checkReviewTimeouts() {
  const now = new Date();
  const reports = loadTodayReports();
  let rejectedCount = 0;

  for (const report of reports) {
    if (report.status !== 'review') continue;
    if (!report.reviewDeadline) continue;

    const reviewDeadline = new Date(report.reviewDeadline);

    if (now > reviewDeadline) {
      // Review timeout - mark as rejected
      report.status = 'rejected';
      report.rejectedAt = now.toISOString();
      saveReport(report);
      rejectedCount++;

      console.log(`[RecountScheduler] Recount REJECTED (admin timeout): ${report.shopName} (${report.shiftType}), employee: ${report.employeeName}`);

      // Assign penalty
      assignPenaltyDirect(report);
    }
  }

  return rejectedCount;
}

// ============================================
// 4. Assign Penalty from Work Schedule
// ============================================
function assignPenaltyFromSchedule(report) {
  const settings = getRecountSettings();
  const today = getMoscowDateString();
  const monthKey = today.substring(0, 7); // YYYY-MM

  // Load work schedule for this month
  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);
  const schedule = loadJsonFile(scheduleFile, { entries: [] });

  if (!schedule.entries || schedule.entries.length === 0) {
    console.log(`[RecountScheduler] No work schedule found for ${monthKey}, cannot assign penalty`);
    return;
  }

  // Find employee assigned to this shop/shift/date
  const entry = schedule.entries.find(e =>
    e.shopAddress === report.shopAddress &&
    e.date === today &&
    e.shiftType === report.shiftType
  );

  if (!entry) {
    console.log(`[RecountScheduler] No schedule entry found for ${report.shopAddress}, ${today}, ${report.shiftType}`);
    return;
  }

  // Create penalty
  createPenalty({
    employeeId: entry.employeeId,
    employeeName: entry.employeeName,
    shopAddress: report.shopAddress,
    points: settings.missedPenalty,
    reason: `Не пройден ${report.shiftType === 'morning' ? 'утренний' : 'вечерний'} пересчёт`,
    sourceId: report.id
  });
}

// ============================================
// 5. Assign Penalty Direct (for rejected reports)
// ============================================
function assignPenaltyDirect(report) {
  const settings = getRecountSettings();

  if (!report.employeeName) {
    console.log(`[RecountScheduler] Cannot assign penalty - no employee info in report ${report.id}`);
    return;
  }

  createPenalty({
    employeeId: report.employeePhone || report.id,
    employeeName: report.employeeName,
    shopAddress: report.shopAddress,
    points: settings.missedPenalty,
    reason: `Пересчёт отклонён (админ не проверил вовремя)`,
    sourceId: report.id
  });
}

// ============================================
// 6. Create Penalty
// ============================================
function createPenalty({ employeeId, employeeName, shopAddress, points, reason, sourceId }) {
  const now = new Date();
  const today = getMoscowDateString();
  const monthKey = today.substring(0, 7);

  const penalty = {
    id: `penalty_recount_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
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
    sourceType: 'recount_report',
    createdAt: now.toISOString()
  };

  // Load existing penalties
  const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);
  let penalties = loadJsonFile(penaltiesFile, []);

  // Check for duplicate
  const exists = penalties.some(p => p.sourceId === sourceId);
  if (exists) {
    console.log(`[RecountScheduler] Penalty already exists for ${sourceId}, skipping`);
    return;
  }

  penalties.push(penalty);
  saveJsonFile(penaltiesFile, penalties);

  console.log(`[RecountScheduler] Created penalty for ${employeeName}: ${points} points (${reason})`);
}

// ============================================
// 7. Admin Failed Notification
// ============================================
async function sendAdminFailedNotification(count, failedShops) {
  const shiftTypes = [...new Set(failedShops.map(s => s.shiftType))];
  const shiftLabel = shiftTypes.includes('morning') ? 'утренний' : 'вечерний';

  const title = 'Пересчёты не пройдены';
  const body = `${count} магазинов не прошли ${shiftLabel} пересчёт`;

  console.log(`[RecountScheduler] PUSH to Admin: ${body}`);

  if (sendPushNotification) {
    try {
      await sendPushNotification(title, body, {
        type: 'recount_failed',
        count: String(count),
        shiftType: shiftTypes.join(','),
      });
      console.log('[RecountScheduler] Push notification sent successfully');
    } catch (e) {
      console.error('[RecountScheduler] Error sending push notification:', e.message);
    }
  } else {
    console.log('[RecountScheduler] Push notifications not available');
  }
}

// ============================================
// 8. Employee Confirmed Notification
// ============================================
async function sendEmployeeConfirmedNotification(employeePhone, rating) {
  const title = 'Пересчёт оценён';
  const body = `Ваш отчёт по пересчёту оценён на ${rating} баллов`;

  console.log(`[RecountScheduler] PUSH to ${employeePhone}: ${body}`);

  if (sendPushToPhone && employeePhone) {
    try {
      await sendPushToPhone(employeePhone, title, body, {
        type: 'recount_confirmed',
        rating: String(rating),
      });
      console.log(`[RecountScheduler] Push notification sent to ${employeePhone}`);
    } catch (e) {
      console.error(`[RecountScheduler] Error sending push to ${employeePhone}:`, e.message);
    }
  } else {
    console.log('[RecountScheduler] Push to employee not available');
  }
}

// ============================================
// 9. Cleanup Failed Reports (at 23:59)
// ============================================
function cleanupFailedReports() {
  const reports = loadTodayReports();
  let removedCount = 0;

  for (const report of reports) {
    if (report.status === 'failed' && report._filePath) {
      try {
        fs.unlinkSync(report._filePath);
        removedCount++;
      } catch (e) {
        console.error(`[RecountScheduler] Error removing file ${report._filePath}:`, e.message);
      }
    }
  }

  if (removedCount > 0) {
    console.log(`[RecountScheduler] Cleanup: removed ${removedCount} failed reports`);
  }

  return removedCount;
}

// ============================================
// 10. Main Check Function
// ============================================
async function runScheduledChecks() {
  const now = new Date();
  const moscow = getMoscowTime();
  const settings = getRecountSettings();
  const state = loadState();

  console.log(`\n[${now.toISOString()}] RecountScheduler: Running checks... (Moscow time: ${moscow.toISOString()})`);

  // Check if morning window is active (using new function that handles night intervals)
  if (isWithinTimeWindow(settings.morningStartTime, settings.morningEndTime)) {
    const lastGen = state.lastMorningGeneration;
    if (!lastGen || !isSameDay(new Date(lastGen), now)) {
      console.log(`[RecountScheduler] Morning window active (${settings.morningStartTime} - ${settings.morningEndTime}), generating reports...`);
      const created = generatePendingReports('morning');
      if (created > 0) {
        state.lastMorningGeneration = now.toISOString();
      }
    }
  }

  // Check if evening window is active (using new function that handles night intervals)
  if (isWithinTimeWindow(settings.eveningStartTime, settings.eveningEndTime)) {
    const lastGen = state.lastEveningGeneration;
    if (!lastGen || !isSameDay(new Date(lastGen), now)) {
      console.log(`[RecountScheduler] Evening window active (${settings.eveningStartTime} - ${settings.eveningEndTime}), generating reports...`);
      const created = generatePendingReports('evening');
      if (created > 0) {
        state.lastEveningGeneration = now.toISOString();
      }
    }
  }

  // Check pending deadlines
  const failed = await checkPendingDeadlines();
  if (failed > 0) {
    console.log(`[RecountScheduler] ${failed} recounts marked as failed`);
  }

  // Check review timeouts
  const rejected = checkReviewTimeouts();
  if (rejected > 0) {
    console.log(`[RecountScheduler] ${rejected} recounts auto-rejected (admin timeout)`);
  }

  // Cleanup at 23:59 Moscow time
  const moscowHours = moscow.getUTCHours();
  const moscowMinutes = moscow.getUTCMinutes();
  if (moscowHours === 23 && moscowMinutes >= 59) {
    const lastCleanup = state.lastCleanup;
    if (!lastCleanup || !isSameDay(new Date(lastCleanup), now)) {
      cleanupFailedReports();
      state.lastCleanup = now.toISOString();
    }
  }

  saveState(state);
  console.log(`[RecountScheduler] Checks completed\n`);
}

// ============================================
// 11. Scheduler Setup
// ============================================
function startRecountAutomationScheduler() {
  const settings = getRecountSettings();
  const moscow = getMoscowTime();

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Recount Automation Scheduler started');
  console.log(`  - Timezone: Moscow (UTC+3)`);
  console.log(`  - Current Moscow time: ${moscow.toISOString()}`);
  console.log(`  - Morning window: ${settings.morningStartTime} - ${settings.morningEndTime}`);
  console.log(`  - Evening window: ${settings.eveningStartTime} - ${settings.eveningEndTime}`);
  console.log(`  - Admin review timeout: ${settings.adminReviewTimeout} hours`);
  console.log(`  - Missed penalty: ${settings.missedPenalty} points`);
  console.log(`  - Check interval: ${CHECK_INTERVAL_MS / 1000 / 60} minutes`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Run checks every 5 minutes
  setInterval(() => {
    runScheduledChecks();
  }, CHECK_INTERVAL_MS);

  // First check after 3 seconds (slightly offset from shift scheduler)
  setTimeout(() => {
    runScheduledChecks();
  }, 3000);
}

// ============================================
// 12. API Helper: Set Review Status
// ============================================
function setReportToReview(reportId, employeeId, employeeName) {
  const settings = getRecountSettings();
  const now = new Date();
  const reports = loadTodayReports();

  const report = reports.find(r => r.id === reportId);
  if (!report) {
    console.log(`[RecountScheduler] Report ${reportId} not found`);
    return null;
  }

  // Calculate review deadline
  const reviewDeadline = new Date(now.getTime() + settings.adminReviewTimeout * 60 * 60 * 1000);

  report.status = 'review';
  report.employeePhone = employeeId;
  report.employeeName = employeeName;
  report.submittedAt = now.toISOString();
  report.reviewDeadline = reviewDeadline.toISOString();

  saveReport(report);

  console.log(`[RecountScheduler] Report ${reportId} set to review, deadline: ${reviewDeadline.toISOString()}`);
  return report;
}

// ============================================
// 13. API Helper: Confirm Report
// ============================================
function confirmReport(reportId, rating, adminName) {
  const now = new Date();
  const reports = loadTodayReports();

  const report = reports.find(r => r.id === reportId);
  if (!report) {
    console.log(`[RecountScheduler] Report ${reportId} not found`);
    return null;
  }

  report.status = 'confirmed';
  report.adminRating = rating;
  report.adminName = adminName;
  report.ratedAt = now.toISOString();

  saveReport(report);

  // Send notification to employee
  if (report.employeePhone) {
    sendEmployeeConfirmedNotification(report.employeePhone, rating);
  }

  console.log(`[RecountScheduler] Report ${reportId} confirmed with rating ${rating}`);
  return report;
}

// ============================================
// Exports
// ============================================
module.exports = {
  startRecountAutomationScheduler,
  generatePendingReports,
  checkPendingDeadlines,
  checkReviewTimeouts,
  cleanupFailedReports,
  setReportToReview,
  confirmReport,
  loadTodayReports,
  getRecountSettings,
  getMoscowTime,
  getMoscowDateString
};
