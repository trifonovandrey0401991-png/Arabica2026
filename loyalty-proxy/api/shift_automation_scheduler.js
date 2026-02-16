/**
 * Shift Automation Scheduler
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 *
 * Автоматизация жизненного цикла отчётов пересменки:
 * - Автоматическое создание pending отчётов при начале временного окна
 * - Переход pending → failed по истечении дедлайна
 * - Переход review → rejected по истечении adminReviewTimeout
 * - Начисление штрафов за пропуск
 * - Push-уведомления
 * - Очистка failed отчётов в 23:59
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('../utils/async_fs');
const { fileExists } = require('../utils/file_helpers');
const { getMoscowTime, getMoscowDateString, MOSCOW_OFFSET_HOURS } = require('../utils/moscow_time');

// Импортируем функции отправки push-уведомлений
let sendPushNotification = null;
let sendPushToPhone = null;
try {
  const notificationsApi = require('./report_notifications_api');
  sendPushNotification = notificationsApi.sendPushNotification;
  sendPushToPhone = notificationsApi.sendPushToPhone;
  console.log('[ShiftScheduler] Push notifications enabled');
} catch (e) {
  console.log('[ShiftScheduler] Push notifications disabled:', e.message);
}

// Directories
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const SHIFT_REPORTS_DIR = `${DATA_DIR}/shift-reports`;
const SHOPS_DIR = `${DATA_DIR}/shops`;
const WORK_SCHEDULES_DIR = `${DATA_DIR}/work-schedules`;
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;
const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;
const SHIFT_AUTOMATION_STATE_DIR = `${DATA_DIR}/shift-automation-state`;
const SHOP_MANAGERS_FILE = `${DATA_DIR}/shop-managers.json`;
const STATE_FILE = path.join(SHIFT_AUTOMATION_STATE_DIR, 'state.json');

// Constants
const PENALTY_CATEGORY = 'shift_missed_penalty';
const PENALTY_CATEGORY_NAME = 'Пропущенная пересменка';
const CHECK_INTERVAL_MS = 5 * 60 * 1000; // Проверка каждые 5 минут

// ============================================
// Helper: Load JSON file safely (async)
// ============================================
async function loadJsonFile(filePath, defaultValue) {
  if (!(await fileExists(filePath))) {
    return defaultValue;
  }
  try {
    const data = await fsp.readFile(filePath, 'utf8');
    return JSON.parse(data);
  } catch (e) {
    console.error(`[ShiftScheduler] Error loading JSON from ${filePath}:`, e.message);
    return defaultValue;
  }
}

async function saveJsonFile(filePath, data) {
  try {
    await writeJsonFile(filePath, data);
    return true;
  } catch (e) {
    console.error(`[ShiftScheduler] Error saving JSON to ${filePath}:`, e.message);
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
async function getShiftSettings() {
  const settingsFile = path.join(POINTS_SETTINGS_DIR, 'shift_points_settings.json');
  return await loadJsonFile(settingsFile, {
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
    console.error('[ShiftScheduler] Error reading shops directory:', e.message);
  }
  return shops;
}

// ============================================
// Reports Management
// ============================================
function getTodayReportsFile() {
  const today = getMoscowDateString(); // YYYY-MM-DD в московском времени
  return path.join(SHIFT_REPORTS_DIR, `${today}.json`);
}

async function loadTodayReports() {
  return await loadJsonFile(getTodayReportsFile(), []);
}

async function saveTodayReports(reports) {
  return await saveJsonFile(getTodayReportsFile(), reports);
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
async function generatePendingReports(shiftType) {
  const settings = await getShiftSettings();
  const shops = await getAllShops();
  const today = getMoscowDateString();

  if (shops.length === 0) {
    console.log(`[ShiftScheduler] No shops found, skipping ${shiftType} report generation`);
    return 0;
  }

  let reports = await loadTodayReports();
  let created = 0;

  const deadlineTime = shiftType === 'morning'
    ? settings.morningEndTime
    : settings.eveningEndTime;

  // Вычисляем deadline в UTC (deadline - это московское время, конвертируем в UTC)
  const { hours, minutes } = parseTime(deadlineTime);
  const deadlineMoscow = new Date(`${today}T${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:00`);
  // Вычитаем 3 часа чтобы получить UTC
  const deadlineUtc = new Date(deadlineMoscow.getTime() - MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);

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
      deadline: deadlineUtc.toISOString(), // Сохраняем в UTC формате
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
    await saveTodayReports(reports);
  }

  console.log(`[ShiftScheduler] Generated ${created} pending ${shiftType} reports`);
  return created;
}

// ============================================
// 2. Check Pending Deadlines (pending → failed)
// ============================================
async function checkPendingDeadlines() {
  const now = new Date();
  let reports = await loadTodayReports();
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
      await assignPenaltyFromSchedule(report);
    }
  }

  if (failedCount > 0) {
    await saveTodayReports(reports);

    // Send push notification to admin about failed reports
    await sendAdminFailedNotification(failedCount, failedShops);
  }

  return failedCount;
}

// ============================================
// 3. Check Review Timeouts (review → rejected)
// ============================================
async function checkReviewTimeouts() {
  const now = new Date();
  let reports = await loadTodayReports();
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
      await assignPenaltyDirect(report);
    }
  }

  if (rejectedCount > 0) {
    await saveTodayReports(reports);
  }

  return rejectedCount;
}

// ============================================
// 4. Assign Penalty from Work Schedule
// ============================================
async function assignPenaltyFromSchedule(report) {
  const settings = await getShiftSettings();
  const today = getMoscowDateString();
  const monthKey = today.substring(0, 7); // YYYY-MM

  // Load work schedule for this month
  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);
  const schedule = await loadJsonFile(scheduleFile, { entries: [] });

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
  await createPenalty({
    employeeId: entry.employeeId,
    employeeName: entry.employeeName,
    shopAddress: report.shopAddress,
    points: settings.missedPenalty,
    reason: `Не пройдена ${report.shiftType === 'morning' ? 'утренняя' : 'вечерняя'} пересменка`,
    sourceId: report.id
  });
}

// ============================================
// 5. Find Admin (manager) for Shop
// ============================================
async function findAdminForShop(shopAddress) {
  try {
    // 1. Найти shopId по адресу
    const shops = await getAllShops();
    const shop = shops.find(s => s.address === shopAddress);
    if (!shop) {
      console.log(`[ShiftScheduler] Shop not found by address: ${shopAddress}`);
      return null;
    }

    // 2. Найти manager, у которого этот shopId в managedShops
    const managersData = await loadJsonFile(SHOP_MANAGERS_FILE, { developers: [], managers: [], storeManagers: [] });
    const manager = (managersData.managers || []).find(m =>
      (m.managedShops || []).includes(shop.id)
    );

    if (!manager) {
      console.log(`[ShiftScheduler] No manager found for shop ${shop.id} (${shopAddress})`);
      return null;
    }

    return {
      phone: manager.phone,
      name: manager.name || 'Управляющий',
      employeeId: `admin_${manager.phone}`
    };
  } catch (e) {
    console.error(`[ShiftScheduler] Error finding admin for shop:`, e.message);
    return null;
  }
}

// ============================================
// 6. Assign Penalty to Admin (for rejected reports — admin didn't review in time)
// ============================================
async function assignPenaltyDirect(report) {
  const settings = await getShiftSettings();

  // Штраф идёт АДМИНУ (управляющему) магазина, а не сотруднику
  const admin = await findAdminForShop(report.shopAddress);

  if (admin) {
    await createPenalty({
      employeeId: admin.employeeId,
      employeeName: admin.name,
      shopAddress: report.shopAddress,
      points: settings.missedPenalty,
      reason: `Пересменка отклонена (не проверена вовремя). Сотрудник: ${report.employeeName || 'неизвестен'}`,
      sourceId: `${report.id}_admin_penalty`
    });
    console.log(`[ShiftScheduler] Admin penalty assigned to ${admin.name} for shop ${report.shopAddress}`);
  } else {
    console.log(`[ShiftScheduler] Cannot assign admin penalty - no manager found for shop ${report.shopAddress} (report ${report.id})`);
  }
}

// ============================================
// 7. Create Penalty
// ============================================
async function createPenalty({ employeeId, employeeName, shopAddress, points, reason, sourceId }) {
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
  let penalties = await loadJsonFile(penaltiesFile, []);
  if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];

  // Check for duplicate
  const exists = penalties.some(p => p.sourceId === sourceId);
  if (exists) {
    console.log(`[ShiftScheduler] Penalty already exists for ${sourceId}, skipping`);
    return;
  }

  penalties.push(penalty);
  await saveJsonFile(penaltiesFile, penalties);

  console.log(`[ShiftScheduler] Created penalty for ${employeeName}: ${points} points (${reason})`);
}

// ============================================
// 7. Admin Failed Notification
// ============================================
async function sendAdminFailedNotification(count, failedShops) {
  const shiftTypes = [...new Set(failedShops.map(s => s.shiftType))];
  const shiftLabel = shiftTypes.includes('morning') ? 'утреннюю' : 'вечернюю';

  const title = 'Пересменки не пройдены';
  const body = `${count} магазинов не прошли ${shiftLabel} пересменку`;

  console.log(`[ShiftScheduler] PUSH to Admin: ${body}`);

  // Отправляем реальное push-уведомление админам
  if (sendPushNotification) {
    try {
      await sendPushNotification(title, body, {
        type: 'shift_failed',
        count: String(count),
        shiftType: shiftTypes.join(','),
      });
      console.log('[ShiftScheduler] Push notification sent successfully');
    } catch (e) {
      console.error('[ShiftScheduler] Error sending push notification:', e.message);
    }
  } else {
    console.log('[ShiftScheduler] Push notifications not available');
  }
}

// ============================================
// 8. Employee Confirmed Notification
// ============================================
async function sendEmployeeConfirmedNotification(employeePhone, rating) {
  const title = 'Пересменка оценена';
  const body = `Ваш отчёт оценён на ${rating} баллов`;

  console.log(`[ShiftScheduler] PUSH to ${employeePhone}: ${body}`);

  // Отправляем реальное push-уведомление сотруднику
  if (sendPushToPhone && employeePhone) {
    try {
      await sendPushToPhone(employeePhone, title, body, {
        type: 'shift_confirmed',
        rating: String(rating),
      });
      console.log(`[ShiftScheduler] Push notification sent to ${employeePhone}`);
    } catch (e) {
      console.error(`[ShiftScheduler] Error sending push to ${employeePhone}:`, e.message);
    }
  } else {
    console.log('[ShiftScheduler] Push to employee not available');
  }
}

// ============================================
// 9. Cleanup Failed Reports (at 23:59)
// ============================================
async function cleanupFailedReports() {
  let reports = await loadTodayReports();
  const initialCount = reports.length;

  // Remove failed reports
  reports = reports.filter(r => r.status !== 'failed');

  const removedCount = initialCount - reports.length;

  if (removedCount > 0) {
    await saveTodayReports(reports);
    console.log(`[ShiftScheduler] Cleanup: removed ${removedCount} failed reports`);
  }

  return removedCount;
}

// ============================================
// 10. Main Check Function
// ============================================
async function runScheduledChecks() {
  const now = new Date();
  const moscow = getMoscowTime();
  const settings = await getShiftSettings();
  const state = await loadState();

  console.log(`\n[${now.toISOString()}] ShiftScheduler: Running checks... (Moscow time: ${moscow.toISOString()})`);

  // Check if morning window started
  if (isTimeReached(settings.morningStartTime) && !isTimeReached(settings.morningEndTime)) {
    const lastGen = state.lastMorningGeneration;
    if (!lastGen || !isSameDay(new Date(lastGen), now)) {
      const created = await generatePendingReports('morning');
      if (created > 0) {
        state.lastMorningGeneration = now.toISOString();
      }
    }
  }

  // Check if evening window started
  if (isTimeReached(settings.eveningStartTime) && !isTimeReached(settings.eveningEndTime)) {
    const lastGen = state.lastEveningGeneration;
    if (!lastGen || !isSameDay(new Date(lastGen), now)) {
      const created = await generatePendingReports('evening');
      if (created > 0) {
        state.lastEveningGeneration = now.toISOString();
      }
    }
  }

  // Check pending deadlines
  const failed = await checkPendingDeadlines();
  if (failed > 0) {
    console.log(`[ShiftScheduler] ${failed} reports marked as failed`);
  }

  // Check review timeouts
  const rejected = await checkReviewTimeouts();
  if (rejected > 0) {
    console.log(`[ShiftScheduler] ${rejected} reports auto-rejected (admin timeout)`);
  }

  // Cleanup at 23:59 Moscow time
  const moscowHours = moscow.getUTCHours();
  const moscowMinutes = moscow.getUTCMinutes();
  if (moscowHours === 23 && moscowMinutes >= 59) {
    const lastCleanup = state.lastCleanup;
    if (!lastCleanup || !isSameDay(new Date(lastCleanup), now)) {
      await cleanupFailedReports();
      state.lastCleanup = now.toISOString();
    }
  }

  await saveState(state);
  console.log(`[ShiftScheduler] Checks completed\n`);
}

// ============================================
// 11. Scheduler Setup
// ============================================
async function startShiftAutomationScheduler() {
  const settings = await getShiftSettings();
  const moscow = getMoscowTime();

  console.log('Shift Automation Scheduler started');
  console.log(`  - Timezone: Moscow (UTC+3)`);
  console.log(`  - Current Moscow time: ${moscow.toISOString()}`);
  console.log(`  - Morning window: ${settings.morningStartTime} - ${settings.morningEndTime}`);
  console.log(`  - Evening window: ${settings.eveningStartTime} - ${settings.eveningEndTime}`);
  console.log(`  - Admin review timeout: ${settings.adminReviewTimeout} hours`);
  console.log(`  - Missed penalty: ${settings.missedPenalty} points`);
  console.log(`  - Check interval: ${CHECK_INTERVAL_MS / 1000 / 60} minutes`);

  // Run checks every 5 minutes
  let isRunning = false;
  const guardedCheck = async () => {
    if (isRunning) { console.log('[ShiftScheduler] Previous run still active, skipping'); return; }
    isRunning = true;
    try { await runScheduledChecks(); }
    catch (err) { console.error('[ShiftScheduler] Scheduler error:', err.message); }
    finally { isRunning = false; }
  };

  setInterval(guardedCheck, CHECK_INTERVAL_MS);

  // First check after 2 seconds
  setTimeout(guardedCheck, 2000);
}

// ============================================
// 12. API Helper: Set Review Status
// ============================================
async function setReportToReview(reportId, employeeId, employeeName) {
  const settings = await getShiftSettings();
  const now = new Date();
  let reports = await loadTodayReports();

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

  await saveTodayReports(reports);

  console.log(`[ShiftScheduler] Report ${reportId} set to review, deadline: ${reviewDeadline.toISOString()}`);
  return reports[index];
}

// ============================================
// 13. API Helper: Confirm Report
// ============================================
async function confirmReport(reportId, rating, adminName) {
  const now = new Date();
  let reports = await loadTodayReports();

  const index = reports.findIndex(r => r.id === reportId);
  if (index === -1) {
    console.log(`[ShiftScheduler] Report ${reportId} not found`);
    return null;
  }

  reports[index].status = 'confirmed';
  reports[index].rating = rating;
  reports[index].confirmedByAdmin = adminName;
  reports[index].confirmedAt = now.toISOString();

  await saveTodayReports(reports);

  // Send notification to employee
  if (reports[index].employeeId) {
    await sendEmployeeConfirmedNotification(reports[index].employeeId, rating);
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
