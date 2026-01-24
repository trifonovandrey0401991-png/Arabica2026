/**
 * Shift Automation Scheduler
 *
 * Автоматизация жизненного цикла отчётов пересменки:
 * - Автоматическое создание pending отчётов при начале временного окна
 * - Переход pending → failed по истечении дедлайна
 * - Переход review → rejected по истечении adminReviewTimeout
 * - Начисление штрафов за пропуск
 * - Push-уведомления
 * - Очистка failed отчётов в 23:59
 */

const fs = require('fs');
const path = require('path');

// Directories
const SHIFT_REPORTS_DIR = '/var/www/shift-reports';
const SHOPS_DIR = '/var/www/shops';
const WORK_SCHEDULES_DIR = '/var/www/work-schedules';
const EFFICIENCY_PENALTIES_DIR = '/var/www/efficiency-penalties';
const POINTS_SETTINGS_DIR = '/var/www/points-settings';
const SHIFT_AUTOMATION_STATE_DIR = '/var/www/shift-automation-state';
const STATE_FILE = path.join(SHIFT_AUTOMATION_STATE_DIR, 'state.json');

// Constants
const PENALTY_CATEGORY = 'shift_missed_penalty';
const PENALTY_CATEGORY_NAME = 'Пропущенная пересменка';
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
    console.error(`[ShiftScheduler] Error loading JSON from ${filePath}:`, e.message);
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
    console.error(`[ShiftScheduler] Error saving JSON to ${filePath}:`, e.message);
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
function getShiftSettings() {
  const settingsFile = path.join(POINTS_SETTINGS_DIR, 'shift_points_settings.json');
  return loadJsonFile(settingsFile, {
    morningStartTime: '07:00',
    morningEndTime: '13:00',
    eveningStartTime: '14:00',
    eveningEndTime: '23:00',
    missedPenalty: -3,
    adminReviewTimeout: 2 // hours
  });
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
function getTodayReportsFile() {
  const today = getMoscowDateString(); // YYYY-MM-DD в московском времени
  return path.join(SHIFT_REPORTS_DIR, `${today}.json`);
}

function loadTodayReports() {
  return loadJsonFile(getTodayReportsFile(), []);
}

function saveTodayReports(reports) {
  return saveJsonFile(getTodayReportsFile(), reports);
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
  const targetHour = hours;
  const targetMinute = minutes;

  // Получаем часы и минуты в московском времени
  const moscowHours = moscow.getUTCHours();
  const moscowMinutes = moscow.getUTCMinutes();

  return moscowHours > targetHour ||
         (moscowHours === targetHour && moscowMinutes >= targetMinute);
}

function isSameDay(date1, date2) {
  // Конвертируем обе даты в московское время для сравнения
  const moscow1 = new Date(date1.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
  const moscow2 = new Date(date2.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
  return moscow1.toISOString().split('T')[0] === moscow2.toISOString().split('T')[0];
}

function getDeadlineTime(timeStr) {
  // Создаём дедлайн в московском времени
  const { hours, minutes } = parseTime(timeStr);
  const today = getMoscowDateString();
  // Формируем строку дедлайна в московском времени и конвертируем обратно в UTC
  const deadlineStr = `${today}T${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:00`;
  // Парсим как московское время, получаем UTC
  const deadlineLocal = new Date(deadlineStr);
  // Вычитаем смещение чтобы получить UTC время
  return new Date(deadlineLocal.getTime() - MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
}

// ============================================
// 1. Generate Pending Reports
// ============================================
function generatePendingReports(shiftType) {
  const settings = getShiftSettings();
  const shops = getAllShops();
  const today = getMoscowDateString();

  if (shops.length === 0) {
    console.log(`[ShiftScheduler] No shops found, skipping ${shiftType} report generation`);
    return 0;
  }

  let reports = loadTodayReports();
  let created = 0;

  const deadlineTime = shiftType === 'morning'
    ? settings.morningEndTime
    : settings.eveningEndTime;

  for (const shop of shops) {
    // Check if pending report already exists for this shop/shift
    const exists = reports.some(r =>
      r.shopAddress === shop.address &&
      r.shiftType === shiftType &&
      r.status === 'pending'
    );

    if (exists) continue;

    // Create pending report
    const report = {
      id: `pending_${shiftType}_${shop.address}_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`,
      shopAddress: shop.address,
      shopName: shop.name,
      shiftType: shiftType,
      status: 'pending',
      createdAt: new Date().toISOString(),
      deadline: `${today}T${deadlineTime}:00`,
      employeeName: null,
      employeeId: null,
      answers: [],
      submittedAt: null,
      reviewDeadline: null,
      confirmedAt: null,
      rating: null,
      confirmedByAdmin: null,
      failedAt: null,
      rejectedAt: null
    };

    reports.push(report);
    created++;
    console.log(`[ShiftScheduler] Created pending ${shiftType} report for ${shop.name} (${shop.address})`);
  }

  if (created > 0) {
    saveTodayReports(reports);
  }

  console.log(`[ShiftScheduler] Generated ${created} pending ${shiftType} reports`);
  return created;
}

// ============================================
// 2. Check Pending Deadlines (pending → failed)
// ============================================
function checkPendingDeadlines() {
  const now = new Date();
  let reports = loadTodayReports();
  let failedCount = 0;
  const failedShops = [];

  for (let i = 0; i < reports.length; i++) {
    const report = reports[i];

    if (report.status !== 'pending') continue;

    const deadline = new Date(report.deadline);

    if (now > deadline) {
      // Deadline passed - mark as failed
      reports[i].status = 'failed';
      reports[i].failedAt = now.toISOString();
      failedCount++;

      failedShops.push({
        shopAddress: report.shopAddress,
        shopName: report.shopName,
        shiftType: report.shiftType,
        deadline: report.deadline
      });

      console.log(`[ShiftScheduler] Report FAILED: ${report.shopName} (${report.shiftType}), deadline was ${report.deadline}`);

      // Assign penalty to employee from work schedule
      assignPenaltyFromSchedule(report);
    }
  }

  if (failedCount > 0) {
    saveTodayReports(reports);

    // Send push notification to admin about failed reports
    sendAdminFailedNotification(failedCount, failedShops);
  }

  return failedCount;
}

// ============================================
// 3. Check Review Timeouts (review → rejected)
// ============================================
function checkReviewTimeouts() {
  const now = new Date();
  let reports = loadTodayReports();
  let rejectedCount = 0;

  for (let i = 0; i < reports.length; i++) {
    const report = reports[i];

    if (report.status !== 'review') continue;
    if (!report.reviewDeadline) continue;

    const reviewDeadline = new Date(report.reviewDeadline);

    if (now > reviewDeadline) {
      // Review timeout - mark as rejected
      reports[i].status = 'rejected';
      reports[i].rejectedAt = now.toISOString();
      rejectedCount++;

      console.log(`[ShiftScheduler] Report REJECTED (admin timeout): ${report.shopName} (${report.shiftType}), employee: ${report.employeeName}`);

      // Assign penalty
      assignPenaltyDirect(report);
    }
  }

  if (rejectedCount > 0) {
    saveTodayReports(reports);
  }

  return rejectedCount;
}

// ============================================
// 4. Assign Penalty from Work Schedule
// ============================================
function assignPenaltyFromSchedule(report) {
  const settings = getShiftSettings();
  const today = getMoscowDateString();
  const monthKey = today.substring(0, 7); // YYYY-MM

  // Load work schedule for this month
  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);
  const schedule = loadJsonFile(scheduleFile, { entries: [] });

  if (!schedule.entries || schedule.entries.length === 0) {
    console.log(`[ShiftScheduler] No work schedule found for ${monthKey}, cannot assign penalty`);
    return;
  }

  // Find employee assigned to this shop/shift/date
  const entry = schedule.entries.find(e =>
    e.shopAddress === report.shopAddress &&
    e.date === today &&
    e.shiftType === report.shiftType
  );

  if (!entry) {
    console.log(`[ShiftScheduler] No schedule entry found for ${report.shopAddress}, ${today}, ${report.shiftType}`);
    return;
  }

  // Create penalty
  createPenalty({
    employeeId: entry.employeeId,
    employeeName: entry.employeeName,
    shopAddress: report.shopAddress,
    points: settings.missedPenalty,
    reason: `Не пройдена ${report.shiftType === 'morning' ? 'утренняя' : 'вечерняя'} пересменка`,
    sourceId: report.id
  });
}

// ============================================
// 5. Assign Penalty Direct (for rejected reports)
// ============================================
function assignPenaltyDirect(report) {
  const settings = getShiftSettings();

  if (!report.employeeId || !report.employeeName) {
    console.log(`[ShiftScheduler] Cannot assign penalty - no employee info in report ${report.id}`);
    return;
  }

  createPenalty({
    employeeId: report.employeeId,
    employeeName: report.employeeName,
    shopAddress: report.shopAddress,
    points: settings.missedPenalty,
    reason: `Пересменка отклонена (админ не проверил вовремя)`,
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
    id: `penalty_shift_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
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
    sourceType: 'shift_report',
    createdAt: now.toISOString()
  };

  // Load existing penalties
  const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);
  let penalties = loadJsonFile(penaltiesFile, []);

  // Check for duplicate
  const exists = penalties.some(p => p.sourceId === sourceId);
  if (exists) {
    console.log(`[ShiftScheduler] Penalty already exists for ${sourceId}, skipping`);
    return;
  }

  penalties.push(penalty);
  saveJsonFile(penaltiesFile, penalties);

  console.log(`[ShiftScheduler] Created penalty for ${employeeName}: ${points} points (${reason})`);
}

// ============================================
// 7. Admin Failed Notification
// ============================================
function sendAdminFailedNotification(count, failedShops) {
  // TODO: Integrate with Firebase push notifications
  const shiftTypes = [...new Set(failedShops.map(s => s.shiftType))];
  const shiftLabel = shiftTypes.includes('morning') ? 'утреннюю' : 'вечернюю';

  console.log(`[ShiftScheduler] 📢 PUSH to Admin: ${count} магазинов не прошли ${shiftLabel} пересменку`);

  // Integration point for push notifications
  // sendPushToAdmins({
  //   title: 'Пересменки не пройдены',
  //   body: `${count} магазинов не прошли ${shiftLabel} пересменку`
  // });
}

// ============================================
// 8. Employee Confirmed Notification
// ============================================
function sendEmployeeConfirmedNotification(employeePhone, rating) {
  // TODO: Integrate with Firebase push notifications
  console.log(`[ShiftScheduler] 📢 PUSH to ${employeePhone}: Ваш отчёт оценён на ${rating} баллов`);

  // Integration point for push notifications
  // sendPushToEmployee(employeePhone, {
  //   title: 'Пересменка - оценка',
  //   body: `Ваш отчёт оценён на ${rating} баллов`
  // });
}

// ============================================
// 9. Cleanup Failed Reports (at 23:59)
// ============================================
function cleanupFailedReports() {
  let reports = loadTodayReports();
  const initialCount = reports.length;

  // Remove failed reports
  reports = reports.filter(r => r.status !== 'failed');

  const removedCount = initialCount - reports.length;

  if (removedCount > 0) {
    saveTodayReports(reports);
    console.log(`[ShiftScheduler] Cleanup: removed ${removedCount} failed reports`);
  }

  return removedCount;
}

// ============================================
// 10. Main Check Function
// ============================================
function runScheduledChecks() {
  const now = new Date();
  const moscow = getMoscowTime();
  const settings = getShiftSettings();
  const state = loadState();

  console.log(`\n[${now.toISOString()}] ShiftScheduler: Running checks... (Moscow time: ${moscow.toISOString()})`);

  // Check if morning window started
  if (isTimeReached(settings.morningStartTime) && !isTimeReached(settings.morningEndTime)) {
    const lastGen = state.lastMorningGeneration;
    if (!lastGen || !isSameDay(new Date(lastGen), now)) {
      const created = generatePendingReports('morning');
      if (created > 0) {
        state.lastMorningGeneration = now.toISOString();
      }
    }
  }

  // Check if evening window started
  if (isTimeReached(settings.eveningStartTime) && !isTimeReached(settings.eveningEndTime)) {
    const lastGen = state.lastEveningGeneration;
    if (!lastGen || !isSameDay(new Date(lastGen), now)) {
      const created = generatePendingReports('evening');
      if (created > 0) {
        state.lastEveningGeneration = now.toISOString();
      }
    }
  }

  // Check pending deadlines
  const failed = checkPendingDeadlines();
  if (failed > 0) {
    console.log(`[ShiftScheduler] ${failed} reports marked as failed`);
  }

  // Check review timeouts
  const rejected = checkReviewTimeouts();
  if (rejected > 0) {
    console.log(`[ShiftScheduler] ${rejected} reports auto-rejected (admin timeout)`);
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
  console.log(`[ShiftScheduler] Checks completed\n`);
}

// ============================================
// 11. Scheduler Setup
// ============================================
function startShiftAutomationScheduler() {
  const settings = getShiftSettings();
  const moscow = getMoscowTime();

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Shift Automation Scheduler started');
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

  // First check after 2 seconds
  setTimeout(() => {
    runScheduledChecks();
  }, 2000);
}

// ============================================
// 12. API Helper: Set Review Status
// ============================================
function setReportToReview(reportId, employeeId, employeeName) {
  const settings = getShiftSettings();
  const now = new Date();
  let reports = loadTodayReports();

  const index = reports.findIndex(r => r.id === reportId);
  if (index === -1) {
    console.log(`[ShiftScheduler] Report ${reportId} not found`);
    return null;
  }

  // Calculate review deadline
  const reviewDeadline = new Date(now.getTime() + settings.adminReviewTimeout * 60 * 60 * 1000);

  reports[index].status = 'review';
  reports[index].employeeId = employeeId;
  reports[index].employeeName = employeeName;
  reports[index].submittedAt = now.toISOString();
  reports[index].reviewDeadline = reviewDeadline.toISOString();

  saveTodayReports(reports);

  console.log(`[ShiftScheduler] Report ${reportId} set to review, deadline: ${reviewDeadline.toISOString()}`);
  return reports[index];
}

// ============================================
// 13. API Helper: Confirm Report
// ============================================
function confirmReport(reportId, rating, adminName) {
  const now = new Date();
  let reports = loadTodayReports();

  const index = reports.findIndex(r => r.id === reportId);
  if (index === -1) {
    console.log(`[ShiftScheduler] Report ${reportId} not found`);
    return null;
  }

  reports[index].status = 'confirmed';
  reports[index].rating = rating;
  reports[index].confirmedByAdmin = adminName;
  reports[index].confirmedAt = now.toISOString();

  saveTodayReports(reports);

  // Send notification to employee
  if (reports[index].employeeId) {
    sendEmployeeConfirmedNotification(reports[index].employeeId, rating);
  }

  console.log(`[ShiftScheduler] Report ${reportId} confirmed with rating ${rating}`);
  return reports[index];
}

// ============================================
// Exports
// ============================================
module.exports = {
  startShiftAutomationScheduler,
  generatePendingReports,
  checkPendingDeadlines,
  checkReviewTimeouts,
  cleanupFailedReports,
  setReportToReview,
  confirmReport,
  loadTodayReports,
  saveTodayReports,
  getShiftSettings,
  getMoscowTime,
  getMoscowDateString
};
