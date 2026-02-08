/**
 * Shift Handover Automation Scheduler
 *
 * Автоматизация жизненного цикла отчётов "Сдача смены":
 * - Автоматическое создание pending отчётов при начале временного окна
 * - Переход pending → failed по истечении дедлайна
 * - Переход awaiting_review → rejected по таймауту adminReviewTimeout
 * - Push-уведомления админу
 * - Очистка failed отчётов в 23:59
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

// Импортируем функции отправки push-уведомлений
let sendPushNotification = null;
let sendPushToPhone = null;
try {
  const notificationsApi = require('../report_notifications_api');
  sendPushNotification = notificationsApi.sendPushNotification;
  sendPushToPhone = notificationsApi.sendPushToPhone;
  console.log('[ShiftHandoverScheduler] Push notifications enabled');
} catch (e) {
  console.log('[ShiftHandoverScheduler] Push notifications disabled:', e.message);
}

// Directories
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const SHIFT_HANDOVER_REPORTS_DIR = `${DATA_DIR}/shift-handover-reports`;
const SHIFT_HANDOVER_PENDING_DIR = `${DATA_DIR}/shift-handover-pending`;
const SHOPS_DIR = `${DATA_DIR}/shops`;
const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;
const SHIFT_HANDOVER_STATE_DIR = `${DATA_DIR}/shift-handover-automation-state`;
const STATE_FILE = path.join(SHIFT_HANDOVER_STATE_DIR, 'state.json');
const WORK_SCHEDULES_DIR = `${DATA_DIR}/work-schedules`;
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;

// Penalty Constants
const PENALTY_CATEGORY = 'shift_handover_missed_penalty';
const PENALTY_CATEGORY_NAME = 'Сдача смены - пропуск';

// Constants
const CHECK_INTERVAL_MS = 5 * 60 * 1000; // Проверка каждые 5 минут
const MOSCOW_OFFSET_HOURS = 3; // UTC+3 для московского времени

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// ============================================
// Moscow Time Helper
// ============================================
function getMoscowTime() {
  const now = new Date();
  const moscowTime = new Date(now.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
  return moscowTime;
}

function getMoscowDateString() {
  const moscow = getMoscowTime();
  return moscow.toISOString().split('T')[0];
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
    console.error(`[ShiftHandoverScheduler] Error loading JSON from ${filePath}:`, e.message);
    return defaultValue;
  }
}

async function saveJsonFile(filePath, data) {
  try {
    const dir = path.dirname(filePath);
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
    await fsp.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');
    return true;
  } catch (e) {
    console.error(`[ShiftHandoverScheduler] Error saving JSON to ${filePath}:`, e.message);
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
    lastAdminTimeoutCheck: null,
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
async function getShiftHandoverSettings() {
  const defaults = {
    minPoints: -3,
    zeroThreshold: 7,
    maxPoints: 1,
    morningStartTime: '07:00',
    morningEndTime: '14:00',
    eveningStartTime: '14:00',
    eveningEndTime: '23:00',
    missedPenalty: -3,
    adminReviewTimeout: 4 // часы
  };

  const settingsFile = path.join(POINTS_SETTINGS_DIR, 'shift_handover_points_settings.json');
  const loaded = await loadJsonFile(settingsFile, {});

  return {
    ...defaults,
    ...loaded,
    morningStartTime: loaded.morningStartTime || defaults.morningStartTime,
    morningEndTime: loaded.morningEndTime || defaults.morningEndTime,
    eveningStartTime: loaded.eveningStartTime || defaults.eveningStartTime,
    eveningEndTime: loaded.eveningEndTime || defaults.eveningEndTime,
    missedPenalty: loaded.missedPenalty !== undefined ? loaded.missedPenalty : defaults.missedPenalty,
    adminReviewTimeout: loaded.adminReviewTimeout !== undefined ? loaded.adminReviewTimeout : defaults.adminReviewTimeout
  };
}

// ============================================
// Shops Loading
// ============================================
async function getAllShops() {
  const shopsFile = path.join(SHOPS_DIR, 'shops.json');
  const data = await loadJsonFile(shopsFile, { shops: [] });
  return data.shops || [];
}

// ============================================
// Pending Reports Management
// ============================================
async function ensureDirectoryExists(dir) {
  if (!(await fileExists(dir))) {
    await fsp.mkdir(dir, { recursive: true });
  }
}

async function loadTodayPendingReports() {
  await ensureDirectoryExists(SHIFT_HANDOVER_PENDING_DIR);
  const reports = [];
  const today = getMoscowDateString();

  try {
    const files = (await fsp.readdir(SHIFT_HANDOVER_PENDING_DIR)).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const filePath = path.join(SHIFT_HANDOVER_PENDING_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const report = JSON.parse(content);

        // Фильтруем только сегодняшние отчёты
        const reportDate = report.date || (report.createdAt ? report.createdAt.split('T')[0] : null);
        if (reportDate === today) {
          reports.push({ ...report, _filePath: filePath });
        }
      } catch (e) {
        console.error(`[ShiftHandoverScheduler] Error reading file ${file}:`, e.message);
      }
    }
  } catch (e) {
    console.error('[ShiftHandoverScheduler] Error reading pending directory:', e.message);
  }

  return reports;
}

async function savePendingReport(report) {
  const filePath = report._filePath;
  if (!filePath) {
    console.error('[ShiftHandoverScheduler] No _filePath in report');
    return false;
  }

  const dataToSave = { ...report };
  delete dataToSave._filePath;

  return await saveJsonFile(filePath, dataToSave);
}

async function createPendingReport(shop, shiftType, deadline) {
  await ensureDirectoryExists(SHIFT_HANDOVER_PENDING_DIR);

  const now = new Date();
  const today = getMoscowDateString();
  const reportId = `pending_sh_${shiftType}_${shop.address.replace(/[^a-zA-Z0-9а-яА-ЯёЁ]/g, '_')}_${Date.now()}`;
  const filePath = path.join(SHIFT_HANDOVER_PENDING_DIR, `${reportId}.json`);

  const report = {
    id: reportId,
    shopAddress: shop.address,
    shopName: shop.name,
    shiftType: shiftType,
    shiftLabel: shiftType === 'morning' ? 'Утро' : 'Вечер',
    status: 'pending',
    date: today,
    deadline: deadline,
    createdAt: now.toISOString(),
    completedBy: null,
    completedAt: null,
    failedAt: null
  };

  await saveJsonFile(filePath, report);
  console.log(`[ShiftHandoverScheduler] Created pending ${shiftType} shift handover for ${shop.name}, deadline: ${deadline}`);
  return report;
}

// ============================================
// Check if Shift Handover was submitted
// ============================================
async function checkIfShiftHandoverSubmitted(shopAddress, shiftType, today) {
  await ensureDirectoryExists(SHIFT_HANDOVER_REPORTS_DIR);

  try {
    const files = (await fsp.readdir(SHIFT_HANDOVER_REPORTS_DIR)).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const filePath = path.join(SHIFT_HANDOVER_REPORTS_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const report = JSON.parse(content);

        const reportDate = report.createdAt ? report.createdAt.split('T')[0] : null;

        // Определяем смену по времени создания отчёта
        let reportShiftType = 'morning';
        if (report.createdAt) {
          const createdHour = new Date(report.createdAt).getHours();
          reportShiftType = createdHour >= 14 ? 'evening' : 'morning';
        }

        if (reportDate === today &&
            report.shopAddress === shopAddress &&
            reportShiftType === shiftType) {
          return true;
        }
      } catch (e) {
        // Пропускаем некорректные файлы
      }
    }
  } catch (e) {
    console.error('[ShiftHandoverScheduler] Error checking submitted reports:', e.message);
  }

  return false;
}

// ============================================
// Time Helpers
// ============================================
function parseTime(timeStr) {
  const [hours, minutes] = timeStr.split(':').map(Number);
  return { hours, minutes };
}

function isWithinTimeWindow(startTimeStr, endTimeStr) {
  const moscow = getMoscowTime();
  const start = parseTime(startTimeStr);
  const end = parseTime(endTimeStr);

  const moscowHours = moscow.getUTCHours();
  const moscowMinutes = moscow.getUTCMinutes();
  const currentMinutes = moscowHours * 60 + moscowMinutes;
  const startMinutes = start.hours * 60 + start.minutes;
  const endMinutes = end.hours * 60 + end.minutes;

  if (endMinutes < startMinutes) {
    return currentMinutes >= startMinutes || currentMinutes < endMinutes;
  }

  return currentMinutes >= startMinutes && currentMinutes < endMinutes;
}

function isSameDay(date1, date2) {
  const moscow1 = new Date(date1.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
  const moscow2 = new Date(date2.getTime() + MOSCOW_OFFSET_HOURS * 60 * 60 * 1000);
  return moscow1.toISOString().split('T')[0] === moscow2.toISOString().split('T')[0];
}

function getDeadlineTimeStr(timeStr) {
  return timeStr; // Возвращаем время в формате "HH:MM"
}

// ============================================
// 1. Generate Pending Reports
// ============================================
async function generatePendingReports(shiftType) {
  const settings = await getShiftHandoverSettings();
  const shops = await getAllShops();
  const today = getMoscowDateString();

  if (shops.length === 0) {
    console.log(`[ShiftHandoverScheduler] No shops found, skipping ${shiftType} report generation`);
    return 0;
  }

  const pendingReports = await loadTodayPendingReports();
  let created = 0;

  const deadlineTime = shiftType === 'morning'
    ? settings.morningEndTime
    : settings.eveningEndTime;

  console.log(`[ShiftHandoverScheduler] Generating ${shiftType} reports, deadline: ${deadlineTime}`);

  for (const shop of shops) {
    // Check if pending report already exists
    const existsPending = pendingReports.some(r =>
      r.shopAddress === shop.address &&
      r.shiftType === shiftType &&
      r.status === 'pending'
    );

    if (existsPending) continue;

    // Check if already submitted today
    const alreadySubmitted = await checkIfShiftHandoverSubmitted(shop.address, shiftType, today);
    if (alreadySubmitted) {
      console.log(`[ShiftHandoverScheduler] Shift handover already submitted for ${shop.name} (${shiftType}), skipping`);
      continue;
    }

    // Create pending report
    await createPendingReport(shop, shiftType, deadlineTime);
    created++;
  }

  console.log(`[ShiftHandoverScheduler] Generated ${created} pending ${shiftType} shift handovers`);
  return created;
}

// ============================================
// 2. Check Pending Deadlines (pending → failed)
// ============================================
async function checkPendingDeadlines() {
  const moscow = getMoscowTime();
  const today = getMoscowDateString();
  const reports = await loadTodayPendingReports();
  let failedCount = 0;
  const failedShops = [];

  const moscowHours = moscow.getUTCHours();
  const moscowMinutes = moscow.getUTCMinutes();
  const currentMinutes = moscowHours * 60 + moscowMinutes;

  for (const report of reports) {
    if (report.status !== 'pending') continue;

    // Check if submitted in the meantime
    const submitted = await checkIfShiftHandoverSubmitted(report.shopAddress, report.shiftType, today);
    if (submitted) {
      console.log(`[ShiftHandoverScheduler] Shift handover submitted for ${report.shopName}, removing pending`);
      if (report._filePath && (await fileExists(report._filePath))) {
        await fsp.unlink(report._filePath);
      }
      continue;
    }

    // Parse deadline
    const deadline = parseTime(report.deadline);
    const deadlineMinutes = deadline.hours * 60 + deadline.minutes;

    if (currentMinutes >= deadlineMinutes) {
      // Deadline passed - mark as failed
      report.status = 'failed';
      report.failedAt = new Date().toISOString();
      await savePendingReport(report);
      failedCount++;

      failedShops.push({
        shopAddress: report.shopAddress,
        shopName: report.shopName,
        shiftType: report.shiftType,
        deadline: report.deadline
      });

      console.log(`[ShiftHandoverScheduler] FAILED: ${report.shopName} (${report.shiftType}), deadline was ${report.deadline}`);

      // Assign penalty to employee from work schedule
      await assignPenaltyFromSchedule(report);
    }
  }

  if (failedCount > 0) {
    await sendAdminFailedNotification(failedCount, failedShops);
  }

  return failedCount;
}

// ============================================
// 3. Check Admin Review Timeout (awaiting_review → rejected)
// ============================================
async function checkAdminReviewTimeout() {
  const settings = await getShiftHandoverSettings();
  const timeoutHours = settings.adminReviewTimeout;
  const now = new Date();
  let rejectedCount = 0;
  const rejectedReports = [];

  await ensureDirectoryExists(SHIFT_HANDOVER_REPORTS_DIR);

  try {
    const files = (await fsp.readdir(SHIFT_HANDOVER_REPORTS_DIR)).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const filePath = path.join(SHIFT_HANDOVER_REPORTS_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const report = JSON.parse(content);

        // Только отчёты со статусом pending (ожидают проверки)
        if (report.status !== 'pending') continue;

        // Проверяем время создания
        const createdAt = new Date(report.createdAt);
        const hoursPassed = (now - createdAt) / (1000 * 60 * 60);

        if (hoursPassed >= timeoutHours) {
          // Таймаут истёк - переводим в rejected
          report.status = 'rejected';
          report.expiredAt = now.toISOString();
          report.rejectionReason = `Таймаут проверки (${timeoutHours} ч)`;

          await saveJsonFile(filePath, report);
          rejectedCount++;

          rejectedReports.push({
            id: report.id,
            shopAddress: report.shopAddress,
            employeeName: report.employeeName,
            createdAt: report.createdAt
          });

          console.log(`[ShiftHandoverScheduler] REJECTED (timeout): ${report.shopAddress} by ${report.employeeName}`);
        }
      } catch (e) {
        // Пропускаем некорректные файлы
      }
    }
  } catch (e) {
    console.error('[ShiftHandoverScheduler] Error checking admin timeout:', e.message);
  }

  if (rejectedCount > 0) {
    await sendAdminRejectedNotification(rejectedCount, rejectedReports);
  }

  return rejectedCount;
}

// ============================================
// 4. Cleanup Failed Reports (at 23:59)
// ============================================
async function cleanupFailedReports() {
  let removedCount = 0;

  try {
    if (await fileExists(SHIFT_HANDOVER_PENDING_DIR)) {
      const files = await fsp.readdir(SHIFT_HANDOVER_PENDING_DIR);
      for (const file of files) {
        if (file.endsWith('.json')) {
          try {
            await fsp.unlink(path.join(SHIFT_HANDOVER_PENDING_DIR, file));
            removedCount++;
          } catch (e) {
            console.error(`[ShiftHandoverScheduler] Error removing file ${file}:`, e.message);
          }
        }
      }
    }
  } catch (e) {
    console.error('[ShiftHandoverScheduler] Error reading pending directory:', e.message);
  }

  if (removedCount > 0) {
    console.log(`[ShiftHandoverScheduler] Cleanup: removed ${removedCount} pending/failed files`);
  }

  // Reset state for new day
  const emptyState = {
    lastMorningGeneration: null,
    lastEveningGeneration: null,
    lastAdminTimeoutCheck: null,
    lastCleanup: new Date().toISOString(),
    lastCheck: new Date().toISOString()
  };
  await saveState(emptyState);
  console.log('[ShiftHandoverScheduler] State reset for new day');

  return removedCount;
}

// ============================================
// 5. Assign Penalty from Work Schedule
// ============================================
async function assignPenaltyFromSchedule(report) {
  const settings = await getShiftHandoverSettings();
  const today = getMoscowDateString();
  const monthKey = today.substring(0, 7); // YYYY-MM

  // Load work schedule for this month
  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);
  const schedule = await loadJsonFile(scheduleFile, { entries: [] });

  if (!schedule.entries || schedule.entries.length === 0) {
    console.log(`[ShiftHandoverScheduler] No work schedule found for ${monthKey}, cannot assign penalty`);
    return null;
  }

  // Find employee assigned to this shop/shift/date
  const entry = schedule.entries.find(e =>
    e.shopAddress && report.shopAddress &&
    e.shopAddress.toLowerCase().trim() === report.shopAddress.toLowerCase().trim() &&
    e.date === today &&
    e.shiftType === report.shiftType
  );

  if (!entry) {
    console.log(`[ShiftHandoverScheduler] No schedule entry found for ${report.shopAddress}, ${today}, ${report.shiftType}`);
    return null;
  }

  // Create penalty
  const penalty = await createPenalty({
    employeeId: entry.employeeId,
    employeeName: entry.employeeName,
    employeePhone: entry.phone || entry.employeePhone,
    shopAddress: report.shopAddress,
    points: settings.missedPenalty,
    reason: `Не сдана ${report.shiftType === 'morning' ? 'утренняя' : 'вечерняя'} смена`,
    sourceId: report.id
  });

  // Send push notification to employee
  if (penalty && entry.phone) {
    await sendEmployeePenaltyNotification(entry.phone, entry.employeeName, settings.missedPenalty, report.shiftType);
  }

  return penalty;
}

// ============================================
// 6. Create Penalty
// ============================================
async function createPenalty({ employeeId, employeeName, employeePhone, shopAddress, points, reason, sourceId }) {
  const now = new Date();
  const today = getMoscowDateString();
  const monthKey = today.substring(0, 7);

  const penalty = {
    id: `penalty_sh_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    type: 'employee',
    entityId: employeeId,
    entityName: employeeName,
    shopAddress: shopAddress,
    employeeName: employeeName,
    employeePhone: employeePhone,
    category: PENALTY_CATEGORY,
    categoryName: PENALTY_CATEGORY_NAME,
    date: today,
    points: points,
    reason: reason,
    sourceId: sourceId,
    sourceType: 'shift_handover',
    createdAt: now.toISOString()
  };

  // Ensure directory exists
  await ensureDirectoryExists(EFFICIENCY_PENALTIES_DIR);

  // Load existing penalties
  const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);
  let penalties = await loadJsonFile(penaltiesFile, []);

  // Check for duplicate
  const exists = penalties.some(p => p.sourceId === sourceId);
  if (exists) {
    console.log(`[ShiftHandoverScheduler] Penalty already exists for ${sourceId}, skipping`);
    return null;
  }

  penalties.push(penalty);
  await saveJsonFile(penaltiesFile, penalties);

  console.log(`[ShiftHandoverScheduler] Created penalty for ${employeeName}: ${points} points (${reason})`);
  return penalty;
}

// ============================================
// 7. Employee Penalty Notification
// ============================================
async function sendEmployeePenaltyNotification(employeePhone, employeeName, points, shiftType) {
  const shiftLabel = shiftType === 'morning' ? 'утреннюю' : 'вечернюю';
  const title = 'Штраф за пропуск сдачи смены';
  const body = `Вам начислен штраф ${points} баллов за пропуск ${shiftLabel} сдачи смены`;

  console.log(`[ShiftHandoverScheduler] PUSH to ${employeePhone}: ${body}`);

  if (sendPushToPhone) {
    try {
      await sendPushToPhone(employeePhone, title, body, {
        type: 'shift_handover_penalty',
        points: String(points),
        shiftType: shiftType,
      });
      console.log(`[ShiftHandoverScheduler] Penalty notification sent to ${employeePhone}`);
    } catch (e) {
      console.error(`[ShiftHandoverScheduler] Error sending penalty notification to ${employeePhone}:`, e.message);
    }
  } else {
    console.log('[ShiftHandoverScheduler] sendPushToPhone not available');
  }
}

// ============================================
// 8. Admin Notifications
// ============================================
async function sendAdminFailedNotification(count, failedShops) {
  const shiftTypes = [...new Set(failedShops.map(s => s.shiftType))];
  const shiftLabel = shiftTypes.includes('morning') ? 'утренняя' : 'вечерняя';

  const title = 'Смены не сданы';
  const body = `${count} магазинов не сдали ${shiftLabel} смену`;

  console.log(`[ShiftHandoverScheduler] PUSH to Admin: ${body}`);

  if (sendPushNotification) {
    try {
      await sendPushNotification(title, body, {
        type: 'shift_handover_failed',
        count: String(count),
        shiftType: shiftTypes.join(','),
      });
      console.log('[ShiftHandoverScheduler] Push notification sent successfully');
    } catch (e) {
      console.error('[ShiftHandoverScheduler] Error sending push notification:', e.message);
    }
  }
}

async function sendAdminRejectedNotification(count, rejectedReports) {
  const title = 'Отчёты отклонены';
  const body = `${count} отчётов о сдаче смены отклонены по таймауту`;

  console.log(`[ShiftHandoverScheduler] PUSH to Admin: ${body}`);

  if (sendPushNotification) {
    try {
      await sendPushNotification(title, body, {
        type: 'shift_handover_rejected',
        count: String(count),
      });
      console.log('[ShiftHandoverScheduler] Push notification sent successfully');
    } catch (e) {
      console.error('[ShiftHandoverScheduler] Error sending push notification:', e.message);
    }
  }
}

// Уведомление админу о новом отчёте (вызывается из API при сдаче смены)
async function sendAdminNewReportNotification(report) {
  const title = 'Новая сдача смены';
  const body = `${report.employeeName} сдал смену (${report.shopAddress})`;

  console.log(`[ShiftHandoverScheduler] PUSH to Admin: ${body}`);

  if (sendPushNotification) {
    try {
      await sendPushNotification(title, body, {
        type: 'shift_handover_submitted',
        reportId: report.id,
        shopAddress: report.shopAddress,
        employeeName: report.employeeName,
      });
    } catch (e) {
      console.error('[ShiftHandoverScheduler] Error sending push notification:', e.message);
    }
  }
}

// ============================================
// 6. Main Check Function
// ============================================
async function runScheduledChecks() {
  const now = new Date();
  const moscow = getMoscowTime();
  const settings = await getShiftHandoverSettings();
  const state = await loadState();

  console.log(`\n[${now.toISOString()}] ShiftHandoverScheduler: Running checks... (Moscow: ${moscow.toISOString()})`);
  console.log(`[ShiftHandoverScheduler] Settings: morning ${settings.morningStartTime}-${settings.morningEndTime}, evening ${settings.eveningStartTime}-${settings.eveningEndTime}, adminTimeout: ${settings.adminReviewTimeout}h`);

  // Check if morning window is active
  if (isWithinTimeWindow(settings.morningStartTime, settings.morningEndTime)) {
    const lastGen = state.lastMorningGeneration;
    if (!lastGen || !isSameDay(new Date(lastGen), now)) {
      console.log(`[ShiftHandoverScheduler] Morning window active, generating reports...`);
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
      console.log(`[ShiftHandoverScheduler] Evening window active, generating reports...`);
      const created = await generatePendingReports('evening');
      if (created > 0) {
        state.lastEveningGeneration = now.toISOString();
      }
    }
  }

  // Check pending deadlines (pending → failed)
  const failed = await checkPendingDeadlines();
  if (failed > 0) {
    console.log(`[ShiftHandoverScheduler] ${failed} shift handovers marked as failed`);
  }

  // Check admin review timeout (every check)
  const rejected = await checkAdminReviewTimeout();
  if (rejected > 0) {
    console.log(`[ShiftHandoverScheduler] ${rejected} reports rejected due to admin timeout`);
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
  console.log(`[ShiftHandoverScheduler] Checks completed\n`);
}

// ============================================
// 7. Scheduler Setup
// ============================================
async function startShiftHandoverAutomationScheduler() {
  const settings = await getShiftHandoverSettings();
  const moscow = getMoscowTime();

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Shift Handover Automation Scheduler started');
  console.log(`  - Timezone: Moscow (UTC+3)`);
  console.log(`  - Current Moscow time: ${moscow.toISOString()}`);
  console.log(`  - Morning window: ${settings.morningStartTime} - ${settings.morningEndTime}`);
  console.log(`  - Evening window: ${settings.eveningStartTime} - ${settings.eveningEndTime}`);
  console.log(`  - Admin review timeout: ${settings.adminReviewTimeout} hours`);
  console.log(`  - Check interval: ${CHECK_INTERVAL_MS / 1000 / 60} minutes`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Run checks every 5 minutes
  setInterval(async () => {
    await runScheduledChecks();
  }, CHECK_INTERVAL_MS);

  // First check after 6 seconds (offset from other schedulers)
  setTimeout(async () => {
    await runScheduledChecks();
  }, 6000);
}

// ============================================
// 8. API Helpers
// ============================================
async function getPendingReports() {
  return (await loadTodayPendingReports()).filter(r => r.status === 'pending');
}

async function getFailedReports() {
  return (await loadTodayPendingReports()).filter(r => r.status === 'failed');
}

// Отметить pending как выполненный (вызывается когда сотрудник сдаёт смену)
async function markPendingAsCompleted(shopAddress, shiftType, employeeName) {
  const reports = await loadTodayPendingReports();

  for (const report of reports) {
    if (report.shopAddress === shopAddress &&
        report.shiftType === shiftType &&
        report.status === 'pending') {
      // Удаляем pending файл
      if (report._filePath && (await fileExists(report._filePath))) {
        await fsp.unlink(report._filePath);
        console.log(`[ShiftHandoverScheduler] Marked pending as completed: ${shopAddress} (${shiftType}) by ${employeeName}`);
        return true;
      }
    }
  }

  return false;
}

// ============================================
// Exports
// ============================================
module.exports = {
  startShiftHandoverAutomationScheduler,
  generatePendingReports,
  checkPendingDeadlines,
  checkAdminReviewTimeout,
  cleanupFailedReports,
  loadTodayPendingReports,
  getPendingReports,
  getFailedReports,
  markPendingAsCompleted,
  sendAdminNewReportNotification,
  getShiftHandoverSettings,
  getMoscowTime,
  getMoscowDateString
};
