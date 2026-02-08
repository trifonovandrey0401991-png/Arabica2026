/**
 * Attendance Automation Scheduler
 *
 * Автоматизация жизненного цикла отчётов посещаемости (Я на работе):
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

// Импортируем функции отправки push-уведомлений
let sendPushNotification = null;
let sendPushToPhone = null;
try {
  const notificationsApi = require('./report_notifications_api');
  sendPushNotification = notificationsApi.sendPushNotification;
  sendPushToPhone = notificationsApi.sendPushToPhone;
  console.log('[AttendanceScheduler] Push notifications enabled');
} catch (e) {
  console.log('[AttendanceScheduler] Push notifications disabled:', e.message);
}

// Directories
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const ATTENDANCE_DIR = `${DATA_DIR}/attendance`;
const ATTENDANCE_PENDING_DIR = `${DATA_DIR}/attendance-pending`;
const SHOPS_DIR = `${DATA_DIR}/shops`;
const WORK_SCHEDULES_DIR = `${DATA_DIR}/work-schedules`;
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;
const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;
const ATTENDANCE_AUTOMATION_STATE_DIR = `${DATA_DIR}/attendance-automation-state`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const STATE_FILE = path.join(ATTENDANCE_AUTOMATION_STATE_DIR, 'state.json');

// Constants
const PENALTY_CATEGORY = 'attendance_missed_penalty';
const PENALTY_CATEGORY_NAME = 'Не отмечен на работе';
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
    console.error(`[AttendanceScheduler] Error loading JSON from ${filePath}:`, e.message);
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
    console.error(`[AttendanceScheduler] Error saving JSON to ${filePath}:`, e.message);
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
async function getAttendanceSettings() {
  const defaults = {
    onTimePoints: 0.5,
    latePoints: -1,
    morningStartTime: '07:00',
    morningEndTime: '09:00',
    eveningStartTime: '19:00',
    eveningEndTime: '21:00',
    missedPenalty: -2
  };

  const settingsFile = path.join(POINTS_SETTINGS_DIR, 'attendance_points_settings.json');
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
  const shopsFile = path.join(SHOPS_DIR, 'shops.json');
  const data = await loadJsonFile(shopsFile, { shops: [] });
  return data.shops || [];
}

// ============================================
// Pending Reports Management
// ============================================
function getPendingReportsDir() {
  return ATTENDANCE_PENDING_DIR;
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
        console.error(`[AttendanceScheduler] Error reading file ${file}:`, e.message);
      }
    }
  } catch (e) {
    console.error('[AttendanceScheduler] Error reading reports directory:', e.message);
  }

  return reports;
}

async function savePendingReport(report) {
  const filePath = report._filePath;
  if (!filePath) {
    console.error('[AttendanceScheduler] No _filePath in report');
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
  const reportId = `pending_attendance_${shiftType}_${shop.address.replace(/[^a-zA-Z0-9]/g, '_')}_${Date.now()}`;
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
    markedAt: null,
    failedAt: null,
    isOnTime: null,
    lateMinutes: null
  };

  await saveJsonFile(filePath, report);
  console.log(`[AttendanceScheduler] Created pending ${shiftType} attendance for ${shop.name} (${shop.address}), deadline: ${deadline.toISOString()}`);
  return report;
}

// ============================================
// Check if Attendance was marked
// ============================================
async function checkIfAttendanceMarked(shopAddress, shiftType, today) {
  if (!(await fileExists(ATTENDANCE_DIR))) {
    return false;
  }

  try {
    const files = (await fsp.readdir(ATTENDANCE_DIR)).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const filePath = path.join(ATTENDANCE_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const record = JSON.parse(content);

        const recordDate = record.timestamp ? record.timestamp.split('T')[0] : null;
        if (recordDate === today && record.shopAddress === shopAddress) {
          // Определяем смену по времени отметки
          const recordHour = new Date(record.timestamp).getUTCHours() + MOSCOW_OFFSET_HOURS;
          const isMorning = recordHour < 14;
          const recordShiftType = isMorning ? 'morning' : 'evening';

          if (recordShiftType === shiftType) {
            return true;
          }
        }
      } catch (e) {
        // Игнорируем ошибки парсинга отдельных файлов
      }
    }
  } catch (e) {
    console.error('[AttendanceScheduler] Error checking attendance:', e.message);
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

  // Дневной интервал (например 07:00 - 09:00)
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
  const settings = await getAttendanceSettings();
  const shops = await getAllShops();
  const today = getMoscowDateString();

  if (shops.length === 0) {
    console.log(`[AttendanceScheduler] No shops found, skipping ${shiftType} report generation`);
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

  console.log(`[AttendanceScheduler] ${shiftType} deadline calculated: ${deadline.toISOString()}`);

  for (const shop of shops) {
    // Check if pending report already exists for this shop/shift
    const existsPending = pendingReports.some(r =>
      r.shopAddress === shop.address &&
      r.shiftType === shiftType &&
      r.status === 'pending'
    );

    if (existsPending) continue;

    // Check if attendance was already marked today for this shop
    const alreadyMarked = await checkIfAttendanceMarked(shop.address, shiftType, today);
    if (alreadyMarked) {
      console.log(`[AttendanceScheduler] Attendance already marked for ${shop.name}, skipping`);
      continue;
    }

    // Create pending report
    await createPendingReport(shop, shiftType, deadline);
    created++;
  }

  console.log(`[AttendanceScheduler] Generated ${created} pending ${shiftType} attendance reports`);
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

    // Check if attendance was marked in the meantime
    const marked = await checkIfAttendanceMarked(report.shopAddress, report.shiftType, today);
    if (marked) {
      // Mark as completed and remove pending
      console.log(`[AttendanceScheduler] Attendance marked for ${report.shopName}, removing pending`);
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

      console.log(`[AttendanceScheduler] Attendance FAILED: ${report.shopName} (${report.shiftType}), deadline was ${report.deadline}`);

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
  const settings = await getAttendanceSettings();
  const today = getMoscowDateString();
  const monthKey = today.substring(0, 7); // YYYY-MM

  // Load work schedule for this month
  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);
  const schedule = await loadJsonFile(scheduleFile, { entries: [] });

  if (!schedule.entries || schedule.entries.length === 0) {
    console.log(`[AttendanceScheduler] No work schedule found for ${monthKey}, cannot assign penalty`);
    return;
  }

  // Find employee assigned to this shop/shift/date
  const entry = schedule.entries.find(e =>
    e.shopAddress === report.shopAddress &&
    e.date === today &&
    e.shiftType === report.shiftType
  );

  if (!entry) {
    console.log(`[AttendanceScheduler] No schedule entry found for ${report.shopAddress}, ${today}, ${report.shiftType}`);
    return;
  }

  // Create penalty and send notification to employee
  await createPenalty({
    employeeId: entry.employeeId,
    employeeName: entry.employeeName,
    shopAddress: report.shopAddress,
    points: settings.missedPenalty,
    reason: `Не отмечен на ${report.shiftType === 'morning' ? 'утренней' : 'вечерней'} смене`,
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
    id: `penalty_attendance_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
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
    sourceType: 'attendance',
    createdAt: now.toISOString()
  };

  // Load existing penalties
  const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);
  let penalties = await loadJsonFile(penaltiesFile, []);
  if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];

  // Check for duplicate
  const exists = penalties.some(p => p.sourceId === sourceId);
  if (exists) {
    console.log(`[AttendanceScheduler] Penalty already exists for ${sourceId}, skipping`);
    return;
  }

  penalties.push(penalty);
  await saveJsonFile(penaltiesFile, penalties);

  console.log(`[AttendanceScheduler] Created penalty for ${employeeName}: ${points} points (${reason})`);

  // Отправляем push-уведомление сотруднику о штрафе
  await sendEmployeePenaltyNotification(employeeId, employeeName, points, shopAddress);
}

// ============================================
// 4.1 Send Penalty Notification to Employee
// ============================================
async function sendEmployeePenaltyNotification(employeeId, employeeName, points, shopAddress) {
  if (!sendPushToPhone) {
    console.log('[AttendanceScheduler] sendPushToPhone not available, skipping employee notification');
    return;
  }

  // Найти телефон сотрудника по employeeId
  let employeePhone = null;
  try {
    if (await fileExists(EMPLOYEES_DIR)) {
      const files = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const empData = JSON.parse(await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8'));
          if (empData.id === employeeId && empData.phone) {
            employeePhone = empData.phone;
            break;
          }
        } catch (e) {
          // Skip invalid files
        }
      }
    }
  } catch (e) {
    console.error('[AttendanceScheduler] Error finding employee phone:', e.message);
  }

  if (!employeePhone) {
    console.log(`[AttendanceScheduler] Phone not found for employee ${employeeId}, skipping push notification`);
    return;
  }

  // Форматируем адрес магазина (сокращаем если длинный)
  let shortAddress = shopAddress;
  if (shopAddress && shopAddress.length > 30) {
    // Берём название города/населенного пункта
    const parts = shopAddress.split(',');
    shortAddress = parts[0].trim();
  }

  const title = 'Штраф за посещаемость';
  const body = `Вам начислен штраф ${points} баллов за пропуск смены (${shortAddress})`;

  try {
    await sendPushToPhone(employeePhone, title, body, {
      type: 'attendance_penalty',
      employeeId: employeeId,
      points: String(points),
      shopAddress: shopAddress
    });
    console.log(`[AttendanceScheduler] Penalty notification sent to ${employeeName} (${employeePhone})`);
  } catch (e) {
    console.error(`[AttendanceScheduler] Error sending penalty notification to ${employeePhone}:`, e.message);
  }
}

// ============================================
// 5. Admin Failed Notification
// ============================================
async function sendAdminFailedNotification(count, failedShops) {
  const shiftTypes = [...new Set(failedShops.map(s => s.shiftType))];
  const shiftLabel = shiftTypes.includes('morning') ? 'утренней' : 'вечерней';

  const title = 'Не отмечены на работе';
  const body = `${count} магазинов не отметились на ${shiftLabel} смене`;

  console.log(`[AttendanceScheduler] PUSH to Admin: ${body}`);

  if (sendPushNotification) {
    try {
      await sendPushNotification(title, body, {
        type: 'attendance_failed',
        count: String(count),
        shiftType: shiftTypes.join(','),
      });
      console.log('[AttendanceScheduler] Push notification sent successfully');
    } catch (e) {
      console.error('[AttendanceScheduler] Error sending push notification:', e.message);
    }
  } else {
    console.log('[AttendanceScheduler] Push notifications not available');
  }
}

// ============================================
// 6. Cleanup ALL Reports (at 23:59)
// ============================================
async function cleanupFailedReports() {
  // Удаляем ВСЕ файлы в папке pending (и failed, и оставшиеся pending)
  let removedCount = 0;

  try {
    if (!(await fileExists(ATTENDANCE_PENDING_DIR))) {
      return 0;
    }

    const files = await fsp.readdir(ATTENDANCE_PENDING_DIR);
    for (const file of files) {
      if (file.endsWith('.json')) {
        try {
          await fsp.unlink(path.join(ATTENDANCE_PENDING_DIR, file));
          removedCount++;
        } catch (e) {
          console.error(`[AttendanceScheduler] Error removing file ${file}:`, e.message);
        }
      }
    }
  } catch (e) {
    console.error('[AttendanceScheduler] Error reading pending directory:', e.message);
  }

  if (removedCount > 0) {
    console.log(`[AttendanceScheduler] Cleanup: removed ${removedCount} attendance files`);
  }

  // Также сбрасываем state для нового дня
  const emptyState = {
    lastMorningGeneration: null,
    lastEveningGeneration: null,
    lastCleanup: new Date().toISOString(),
    lastCheck: new Date().toISOString()
  };
  await saveState(emptyState);
  console.log('[AttendanceScheduler] State reset for new day');

  return removedCount;
}

// ============================================
// 7. Main Check Function
// ============================================
async function runScheduledChecks() {
  const now = new Date();
  const moscow = getMoscowTime();
  const settings = await getAttendanceSettings();
  const state = await loadState();

  console.log(`\n[${now.toISOString()}] AttendanceScheduler: Running checks... (Moscow time: ${moscow.toISOString()})`);
  console.log(`[AttendanceScheduler] Settings: morning ${settings.morningStartTime}-${settings.morningEndTime}, evening ${settings.eveningStartTime}-${settings.eveningEndTime}`);

  // Check if morning window is active
  if (isWithinTimeWindow(settings.morningStartTime, settings.morningEndTime)) {
    const lastGen = state.lastMorningGeneration;
    if (!lastGen || !isSameDay(new Date(lastGen), now)) {
      console.log(`[AttendanceScheduler] Morning window active (${settings.morningStartTime} - ${settings.morningEndTime}), generating reports...`);
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
      console.log(`[AttendanceScheduler] Evening window active (${settings.eveningStartTime} - ${settings.eveningEndTime}), generating reports...`);
      const created = await generatePendingReports('evening');
      if (created > 0) {
        state.lastEveningGeneration = now.toISOString();
      }
    }
  }

  // Check pending deadlines
  const failed = await checkPendingDeadlines();
  if (failed > 0) {
    console.log(`[AttendanceScheduler] ${failed} attendance reports marked as failed`);
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
  console.log(`[AttendanceScheduler] Checks completed\n`);
}

// ============================================
// 8. Scheduler Setup
// ============================================
async function startAttendanceAutomationScheduler() {
  const settings = await getAttendanceSettings();
  const moscow = getMoscowTime();

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Attendance Automation Scheduler started');
  console.log(`  - Timezone: Moscow (UTC+3)`);
  console.log(`  - Current Moscow time: ${moscow.toISOString()}`);
  console.log(`  - Morning window: ${settings.morningStartTime} - ${settings.morningEndTime}`);
  console.log(`  - Evening window: ${settings.eveningStartTime} - ${settings.eveningEndTime}`);
  console.log(`  - Missed penalty: ${settings.missedPenalty} points`);
  console.log(`  - Check interval: ${CHECK_INTERVAL_MS / 1000 / 60} minutes`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Run checks every 5 minutes
  setInterval(async () => {
    await runScheduledChecks();
  }, CHECK_INTERVAL_MS);

  // First check after 6 seconds (slightly offset from other schedulers)
  setTimeout(async () => {
    await runScheduledChecks();
  }, 6000);
}

// ============================================
// 9. API Helper: Get Pending/Failed Reports
// ============================================
async function getPendingReports() {
  const reports = await loadTodayPendingReports();
  return reports.filter(r => r.status === 'pending');
}

async function getFailedReports() {
  const reports = await loadTodayPendingReports();
  return reports.filter(r => r.status === 'failed');
}

/**
 * Check if shop has pending attendance report (can mark attendance)
 */
async function canMarkAttendance(shopAddress) {
  const pendingReports = await getPendingReports();
  return pendingReports.some(r => r.shopAddress === shopAddress);
}

/**
 * Mark pending report as completed (when attendance is submitted)
 */
async function markPendingAsCompleted(shopAddress, shiftType) {
  const reports = await loadTodayPendingReports();
  const report = reports.find(r =>
    r.shopAddress === shopAddress &&
    r.shiftType === shiftType &&
    r.status === 'pending'
  );

  if (report && report._filePath && (await fileExists(report._filePath))) {
    await fsp.unlink(report._filePath);
    console.log(`[AttendanceScheduler] Removed pending report for ${shopAddress} (${shiftType})`);
    return true;
  }
  return false;
}

// ============================================
// Exports
// ============================================
module.exports = {
  startAttendanceAutomationScheduler,
  generatePendingReports,
  checkPendingDeadlines,
  cleanupFailedReports,
  loadTodayPendingReports,
  getPendingReports,
  getFailedReports,
  canMarkAttendance,
  markPendingAsCompleted,
  getAttendanceSettings,
  getMoscowTime,
  getMoscowDateString
};
