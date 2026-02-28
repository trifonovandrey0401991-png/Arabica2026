// =====================================================
// EFFICIENCY CALCULATION MODULE
//
// REFACTORED: Converted from sync to async I/O (2026-02-05)
// REFACTORED: Added PostgreSQL support (2026-02-24)
// =====================================================
// Полный расчёт эффективности сотрудника за месяц
// Используются те же формулы что и в Flutter приложении
//
// 13 категорий:
// 1. Shift (пересменка) - rating 1-10
// 2. Recount (пересчёт) - rating 1-10
// 3. ShiftHandover (сдача смены) - rating 1-10
// 4. Attendance (посещаемость) - boolean
// 5. Test (тестирование) - score 0-20
// 6. Reviews (отзывы) - boolean
// 7. ProductSearch (поиск товара) - через efficiency-penalties
// 8. Orders (заказы) - TODO
// 9. RKO (РКО) - boolean
// 10. Tasks (задачи: recurring + regular) - boolean
// 11. AttendancePenalties (автоштрафы: attendance, envelope и др.) - штрафные баллы
// 12. Envelope (конверты - сдача наличных) - boolean
// 13. CoffeeMachine (счётчики кофемашин) - boolean
//
// Настройки: USE_DB_EFFICIENCY=true → PostgreSQL, иначе JSON файлы
// =====================================================

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('./utils/file_helpers');
const { getTaskPointsConfig } = require('./api/task_points_settings_api');
const db = require('./utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const USE_DB = process.env.USE_DB_EFFICIENCY === 'true';

const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;
const SHIFT_REPORTS_DIR = `${DATA_DIR}/shift-reports`;
const RECOUNT_REPORTS_DIR = `${DATA_DIR}/recount-reports`;
const HANDOVER_REPORTS_DIR = `${DATA_DIR}/shift-handovers`;
const ATTENDANCE_DIR = `${DATA_DIR}/attendance`;
const TESTS_DIR = `${DATA_DIR}/test-results`;
const REVIEWS_DIR = `${DATA_DIR}/reviews`;
const PRODUCT_QUESTIONS_DIR = `${DATA_DIR}/product-questions`;
const RKO_DIR = `${DATA_DIR}/rko`;
const TASKS_DIR = `${DATA_DIR}/tasks`;
const RECURRING_TASKS_DIR = `${DATA_DIR}/recurring-tasks`;
const TASK_ASSIGNMENTS_DIR = `${DATA_DIR}/task-assignments`;
const RECURRING_INSTANCES_DIR = `${DATA_DIR}/recurring-task-instances`;
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;
const ENVELOPE_REPORTS_DIR = `${DATA_DIR}/envelope-reports`;
const COFFEE_MACHINE_REPORTS_DIR = `${DATA_DIR}/coffee-machine-reports`;

// =====================================================
// OPTIMIZATION: Cache for batch operations
// =====================================================
let _batchCache = null;
let _batchCacheMonth = null;

/**
 * Get month date range for DB queries
 * @param {string} month - 'YYYY-MM'
 * @returns {{start: string, end: string}} start = 'YYYY-MM-01', end = next month first day
 */
function getMonthRange(month) {
  const [year, mon] = month.split('-').map(Number);
  const start = `${month}-01`;
  const nextMon = mon === 12 ? 1 : mon + 1;
  const nextYear = mon === 12 ? year + 1 : year;
  const end = `${nextYear}-${String(nextMon).padStart(2, '0')}-01`;
  return { start, end };
}

/**
 * Загрузить все файлы из директории, отфильтровав по месяцу (JSON fallback)
 * @returns {Array} Массив распарсенных объектов
 */
async function loadDirectoryForMonth(dirPath, month, dateField) {
  const results = [];

  if (!(await fileExists(dirPath))) {
    return results;
  }

  try {
    const files = await fsp.readdir(dirPath);

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(dirPath, file), 'utf8');
        const data = JSON.parse(content);

        // Filter by month if date field specified
        if (dateField && data[dateField]) {
          if (data[dateField].startsWith(month)) {
            results.push(data);
          }
        } else {
          results.push(data);
        }
      } catch (e) {
        // Skip invalid files
      }
    }
  } catch (e) {
    console.error(`Error loading directory ${dirPath}:`, e);
  }

  return results;
}

/**
 * Инициализация batch кэша - загружает ВСЕ данные за месяц ОДИН раз
 * Вызывается перед расчётом рейтинга для всех сотрудников
 */
async function initBatchCache(month) {
  if (_batchCacheMonth === month && _batchCache) {
    console.log(`[Efficiency] Используем существующий кэш для ${month}`);
    return _batchCache;
  }

  const startTime = Date.now();
  console.log(`[Efficiency] Инициализация batch кэша для ${month}${USE_DB ? ' (PostgreSQL)' : ' (JSON)'}...`);

  // Load all settings once for batch
  const [shiftSettings, recountSettings, handoverSettings, attendanceSettings, testSettings, envelopeSettings, coffeeMachineSettings, rkoSettings, reviewsSettings] = await Promise.all([
    getShiftSettings(),
    getRecountSettings(),
    getHandoverSettings(),
    getAttendanceSettings(),
    getTestSettings(),
    getEnvelopeSettings(),
    getCoffeeMachineSettings(),
    getRkoSettings(),
    getReviewsSettings(),
  ]);
  const taskConfig = await getTaskPointsConfig();

  const settings = { shiftSettings, recountSettings, handoverSettings, attendanceSettings, testSettings, envelopeSettings, coffeeMachineSettings, rkoSettings, reviewsSettings, taskConfig };

  if (USE_DB) {
    const { start, end } = getMonthRange(month);

    // Load all data from DB in parallel (12 queries, range-based for index usage)
    const [shiftRes, recountRes, handoverRes, attendanceRes, testRes, reviewRes, rkoRes, penaltyRes, envelopeRes, cmRes, taskAssignRes, recurringInstRes] = await Promise.all([
      db.query('SELECT employee_name, employee_phone, shop_address, rating FROM shift_reports WHERE date >= $1 AND date < $2', [start, end]),
      db.query('SELECT employee_name, employee_phone, admin_rating FROM recount_reports WHERE date >= $1 AND date < $2', [start, end]),
      db.query('SELECT employee_name, employee_phone, rating FROM shift_handover_reports WHERE date >= $1 AND date < $2', [start, end]),
      db.query('SELECT employee_name, employee_phone, shop_address, is_on_time FROM attendance WHERE created_at >= $1::timestamptz AND created_at < $2::timestamptz', [start, end]),
      db.query("SELECT data FROM test_results WHERE (data->>'completedAt')::text >= $1 AND (data->>'completedAt')::text < $2", [start, end]),
      db.query('SELECT shop_address, review_type FROM reviews WHERE created_at >= $1::timestamptz AND created_at < $2::timestamptz', [start, end]),
      db.query('SELECT shop_address FROM rko_reports WHERE date >= $1::date AND date < $2::date', [start, end]),
      db.query('SELECT entity_id, employee_phone, points FROM efficiency_penalties WHERE date >= $1::date AND date < $2::date', [start, end]),
      db.query('SELECT employee_name, status FROM envelope_reports WHERE date >= $1 AND date < $2', [start, end]),
      db.query('SELECT employee_name, status FROM coffee_machine_reports WHERE date >= $1::date AND date < $2::date', [start, end]),
      db.query('SELECT ta.assignee_id, ta.status FROM task_assignments ta JOIN tasks t ON ta.task_id = t.id WHERE t.month = $1', [month]),
      db.query('SELECT assignee_id, status FROM recurring_task_instances WHERE date >= $1::date AND date < $2::date', [start, end]),
    ]);

    _batchCache = {
      shiftReports: shiftRes.rows.map(r => ({ employeeName: r.employee_name, employeePhone: r.employee_phone, shopAddress: r.shop_address, adminRating: r.rating })),
      recountReports: recountRes.rows.map(r => ({ employeeName: r.employee_name, employeePhone: r.employee_phone, adminRating: r.admin_rating })),
      handoverReports: handoverRes.rows.map(r => ({ employeeName: r.employee_name, employeePhone: r.employee_phone, rating: r.rating })),
      attendance: attendanceRes.rows.map(r => ({ employeeId: r.employee_phone, phone: r.employee_phone, employeeName: r.employee_name, shopAddress: r.shop_address, isOnTime: r.is_on_time })),
      tests: testRes.rows.map(r => {
        const d = r.data || {};
        return { employeeName: d.employeeName, employeeId: d.employeeId, score: parseInt(d.score) || 0, completedAt: d.completedAt };
      }),
      reviews: reviewRes.rows.map(r => ({ shopAddress: r.shop_address, reviewType: r.review_type })),
      rko: rkoRes.rows.map(r => ({ shopAddress: r.shop_address, hasRko: true })),
      envelopes: envelopeRes.rows.map(r => ({ employeeName: r.employee_name, status: r.status })),
      coffeeMachineReports: cmRes.rows.map(r => ({ employeeName: r.employee_name, status: r.status })),
      penalties: penaltyRes.rows.map(r => ({ entityId: r.entity_id, employeePhone: r.employee_phone, points: parseFloat(r.points) || 0 })),
      taskAssignments: taskAssignRes.rows.map(r => ({ assigneeId: r.assignee_id, status: r.status })),
      recurringInstances: recurringInstRes.rows.map(r => ({ assigneeId: r.assignee_id, status: r.status })),
      settings,
    };
  } else {
    _batchCache = {
      shiftReports: await loadDirectoryForMonth(SHIFT_REPORTS_DIR, month, 'handoverDate'),
      recountReports: await loadDirectoryForMonth(RECOUNT_REPORTS_DIR, month, 'recountDate'),
      handoverReports: await loadDirectoryForMonth(HANDOVER_REPORTS_DIR, month, 'handoverDate'),
      attendance: await loadDirectoryForMonth(ATTENDANCE_DIR, month, 'timestamp'),
      tests: await loadDirectoryForMonth(TESTS_DIR, month, 'completedAt'),
      reviews: await loadDirectoryForMonth(REVIEWS_DIR, month, 'createdAt'),
      productQuestions: await loadDirectoryForMonth(PRODUCT_QUESTIONS_DIR, month, null),
      rko: await loadDirectoryForMonth(RKO_DIR, month, 'date'),
      tasks: await loadDirectoryForMonth(TASKS_DIR, month, null),
      recurringTasks: await loadDirectoryForMonth(RECURRING_TASKS_DIR, month, null),
      envelopes: await loadDirectoryForMonth(ENVELOPE_REPORTS_DIR, month, 'createdAt'),
      coffeeMachineReports: await loadDirectoryForMonth(COFFEE_MACHINE_REPORTS_DIR, month, 'createdAt'),
      penalties: await loadPenaltiesForMonth(month),
      settings,
    };
  }

  _batchCacheMonth = month;

  const elapsed = Date.now() - startTime;
  const totalRecords = Object.values(_batchCache).reduce((sum, arr) => sum + (Array.isArray(arr) ? arr.length : 0), 0);
  console.log(`[Efficiency] Batch кэш инициализирован: ${totalRecords} записей за ${elapsed}ms`);

  return _batchCache;
}

/**
 * Загрузка штрафов за месяц
 */
async function loadPenaltiesForMonth(month) {
  if (USE_DB) {
    try {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        'SELECT entity_id, employee_phone, points, date::text FROM efficiency_penalties WHERE date >= $1::date AND date < $2::date',
        [start, end]
      );
      return res.rows.map(r => ({
        entityId: r.entity_id,
        employeePhone: r.employee_phone,
        points: parseFloat(r.points) || 0,
        date: r.date,
      }));
    } catch (e) {
      console.error('[Efficiency] DB loadPenaltiesForMonth error:', e.message);
    }
  }

  // JSON fallback
  const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${month}.json`);
  if (!(await fileExists(filePath))) return [];

  try {
    const content = JSON.parse(await fsp.readFile(filePath, 'utf8'));
    if (Array.isArray(content)) return content;
    return content.penalties || [];
  } catch (e) {
    return [];
  }
}

/**
 * Очистить batch кэш (вызывать после завершения batch операций)
 */
function clearBatchCache() {
  _batchCache = null;
  _batchCacheMonth = null;
  console.log('[Efficiency] Batch кэш очищен');
}

// =====================================================
// HELPER: Линейная интерполяция для rating-based settings
// =====================================================
function interpolateRatingPoints(rating, minRating, maxRating, minPoints, zeroThreshold, maxPoints) {
  if (rating <= minRating) return minPoints;
  if (rating >= maxRating) return maxPoints;

  if (rating <= zeroThreshold) {
    const range = zeroThreshold - minRating;
    if (range === 0) return 0;
    return minPoints + (0 - minPoints) * ((rating - minRating) / range);
  } else {
    const range = maxRating - zeroThreshold;
    if (range === 0) return maxPoints;
    return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
  }
}

// =====================================================
// HELPER: Линейная интерполяция для test settings
// =====================================================
function interpolateTestPoints(score, totalQuestions, minPoints, zeroThreshold, maxPoints) {
  if (score <= 0) return minPoints;
  if (score >= totalQuestions) return maxPoints;

  if (score <= zeroThreshold) {
    return minPoints + (0 - minPoints) * (score / zeroThreshold);
  } else {
    const range = totalQuestions - zeroThreshold;
    return 0 + (maxPoints - 0) * ((score - zeroThreshold) / range);
  }
}

// =====================================================
// LOAD SETTINGS
// =====================================================

async function loadSettings(filename, defaults) {
  if (USE_DB) {
    try {
      const settingsId = filename.replace('_settings.json', '');
      const row = await db.findById('points_settings', settingsId);
      if (row && row.data) return row.data;
    } catch (e) {
      console.error(`[Efficiency] DB settings error (${filename}):`, e.message);
    }
  }

  // JSON fallback
  try {
    const filePath = path.join(POINTS_SETTINGS_DIR, filename);
    if (await fileExists(filePath)) {
      return JSON.parse(await fsp.readFile(filePath, 'utf8'));
    }
    return defaults;
  } catch (e) {
    console.error(`Error loading settings ${filename}:`, e);
    return defaults;
  }
}

async function getShiftSettings() {
  return await loadSettings('shift_points_settings.json', {
    minPoints: -3,
    zeroThreshold: 6,
    maxPoints: 2,
    minRating: 1,
    maxRating: 10,
  });
}

async function getRecountSettings() {
  return await loadSettings('recount_points_settings.json', {
    minPoints: -3,
    zeroThreshold: 6,
    maxPoints: 2,
    minRating: 1,
    maxRating: 10,
  });
}

async function getHandoverSettings() {
  return await loadSettings('shift_handover_points_settings.json', {
    minPoints: -3,
    zeroThreshold: 7,
    maxPoints: 1,
    minRating: 1,
    maxRating: 10,
  });
}

async function getTestSettings() {
  return await loadSettings('test_points_settings.json', {
    minPoints: -2.5,
    zeroThreshold: 15,
    maxPoints: 3.5,
    totalQuestions: 20,
  });
}

async function getAttendanceSettings() {
  return await loadSettings('attendance_points_settings.json', {
    onTimePoints: 1.0,
    latePoints: 0.5,
  });
}

async function getRkoSettings() {
  return await loadSettings('rko_points_settings.json', {
    hasRkoPoints: 1.0,
    noRkoPoints: -3.0,
  });
}

async function getEnvelopeSettings() {
  return await loadSettings('envelope_points_settings.json', {
    submittedPoints: 0,
    notSubmittedPoints: -5,
  });
}

async function getCoffeeMachineSettings() {
  return await loadSettings('coffee_machine_points_settings.json', {
    submittedPoints: 1.0,
    notSubmittedPoints: -3.0,
  });
}

async function getReviewsSettings() {
  return await loadSettings('reviews_points_settings.json', {
    positivePoints: 3,
    negativePoints: -5,
  });
}

// =====================================================
// CALCULATE POINTS FOR EACH CATEGORY
// =====================================================

/**
 * Рассчитать баллы за пересменку (shift report)
 */
async function calculateShiftPoints(employeeId, employeeName, month) {
  try {
    const settings = await getShiftSettings();
    let totalPoints = 0;

    if (USE_DB) {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        'SELECT rating FROM shift_reports WHERE date >= $1 AND date < $2 AND (employee_name = $3 OR employee_phone = $4)',
        [start, end, employeeName, employeeId]
      );
      for (const row of res.rows) {
        if (row.rating && row.rating > 0) {
          totalPoints += interpolateRatingPoints(row.rating, settings.minRating, settings.maxRating, settings.minPoints, settings.zeroThreshold, settings.maxPoints);
        }
      }
    } else {
      if (!(await fileExists(SHIFT_REPORTS_DIR))) return 0;
      const files = await fsp.readdir(SHIFT_REPORTS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await fsp.readFile(path.join(SHIFT_REPORTS_DIR, file), 'utf8');
          const report = JSON.parse(content);
          if ((report.employeeName === employeeName || report.employeePhone === employeeId) &&
              report.handoverDate && report.handoverDate.startsWith(month)) {
            if (report.adminRating && report.adminRating > 0) {
              totalPoints += interpolateRatingPoints(report.adminRating, settings.minRating, settings.maxRating, settings.minPoints, settings.zeroThreshold, settings.maxPoints);
            }
          }
        } catch (e) { /* skip */ }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating shift points:', e);
    return 0;
  }
}

/**
 * Рассчитать баллы за пересчёт (recount report)
 */
async function calculateRecountPoints(employeeId, employeeName, month) {
  try {
    const settings = await getRecountSettings();
    let totalPoints = 0;

    if (USE_DB) {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        'SELECT admin_rating FROM recount_reports WHERE date >= $1 AND date < $2 AND (employee_name = $3 OR employee_phone = $4)',
        [start, end, employeeName, employeeId]
      );
      for (const row of res.rows) {
        if (row.admin_rating && row.admin_rating > 0) {
          totalPoints += interpolateRatingPoints(row.admin_rating, settings.minRating, settings.maxRating, settings.minPoints, settings.zeroThreshold, settings.maxPoints);
        }
      }
    } else {
      if (!(await fileExists(RECOUNT_REPORTS_DIR))) return 0;
      const files = await fsp.readdir(RECOUNT_REPORTS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await fsp.readFile(path.join(RECOUNT_REPORTS_DIR, file), 'utf8');
          const report = JSON.parse(content);
          if ((report.employeeName === employeeName || report.employeePhone === employeeId) &&
              report.recountDate && report.recountDate.startsWith(month)) {
            if (report.adminRating && report.adminRating > 0) {
              totalPoints += interpolateRatingPoints(report.adminRating, settings.minRating, settings.maxRating, settings.minPoints, settings.zeroThreshold, settings.maxPoints);
            }
          }
        } catch (e) { /* skip */ }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating recount points:', e);
    return 0;
  }
}

/**
 * Рассчитать баллы за сдачу смены (shift handover)
 */
async function calculateHandoverPoints(employeeId, employeeName, month) {
  try {
    const settings = await getHandoverSettings();
    let totalPoints = 0;

    if (USE_DB) {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        'SELECT rating FROM shift_handover_reports WHERE date >= $1 AND date < $2 AND (employee_name = $3 OR employee_phone = $4)',
        [start, end, employeeName, employeeId]
      );
      for (const row of res.rows) {
        if (row.rating && row.rating > 0) {
          totalPoints += interpolateRatingPoints(row.rating, settings.minRating, settings.maxRating, settings.minPoints, settings.zeroThreshold, settings.maxPoints);
        }
      }
    } else {
      if (!(await fileExists(HANDOVER_REPORTS_DIR))) return 0;
      const files = await fsp.readdir(HANDOVER_REPORTS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await fsp.readFile(path.join(HANDOVER_REPORTS_DIR, file), 'utf8');
          const report = JSON.parse(content);
          if ((report.employeeName === employeeName || report.employeePhone === employeeId) &&
              report.handoverDate && report.handoverDate.startsWith(month)) {
            if (report.rating && report.rating > 0) {
              totalPoints += interpolateRatingPoints(report.rating, settings.minRating, settings.maxRating, settings.minPoints, settings.zeroThreshold, settings.maxPoints);
            }
          }
        } catch (e) { /* skip */ }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating handover points:', e);
    return 0;
  }
}

/**
 * Рассчитать баллы за посещаемость (attendance)
 */
async function calculateAttendancePoints(employeeId, month) {
  try {
    const settings = await getAttendanceSettings();
    let totalPoints = 0;

    if (USE_DB) {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        'SELECT is_on_time FROM attendance WHERE employee_phone = $1 AND created_at >= $2::timestamptz AND created_at < $3::timestamptz',
        [employeeId, start, end]
      );
      for (const row of res.rows) {
        totalPoints += row.is_on_time ? settings.onTimePoints : settings.latePoints;
      }
    } else {
      if (!(await fileExists(ATTENDANCE_DIR))) return 0;
      const files = await fsp.readdir(ATTENDANCE_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await fsp.readFile(path.join(ATTENDANCE_DIR, file), 'utf8');
          const record = JSON.parse(content);
          if ((record.employeeId === employeeId || record.phone === employeeId)) {
            const recordDate = record.timestamp || record.createdAt;
            if (recordDate && recordDate.startsWith(month)) {
              totalPoints += record.isOnTime ? settings.onTimePoints : settings.latePoints;
            }
          }
        } catch (e) { /* skip */ }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating attendance points:', e);
    return 0;
  }
}

/**
 * Рассчитать баллы за тесты
 */
async function calculateTestPoints(employeeId, employeeName, month) {
  try {
    const settings = await getTestSettings();
    let totalPoints = 0;

    if (USE_DB) {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        "SELECT data FROM test_results WHERE (data->>'completedAt')::text >= $1 AND (data->>'completedAt')::text < $2 AND (data->>'employeeName' = $3 OR data->>'employeeId' = $4)",
        [start, end, employeeName, employeeId]
      );
      for (const row of res.rows) {
        const score = parseInt(row.data?.score) || 0;
        totalPoints += interpolateTestPoints(score, settings.totalQuestions, settings.minPoints, settings.zeroThreshold, settings.maxPoints);
      }
    } else {
      if (!(await fileExists(TESTS_DIR))) return 0;
      const files = await fsp.readdir(TESTS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await fsp.readFile(path.join(TESTS_DIR, file), 'utf8');
          const test = JSON.parse(content);
          if ((test.employeeName === employeeName || test.employeeId === employeeId) &&
              test.completedAt && test.completedAt.startsWith(month)) {
            const score = test.score || 0;
            totalPoints += interpolateTestPoints(score, settings.totalQuestions, settings.minPoints, settings.zeroThreshold, settings.maxPoints);
          }
        } catch (e) { /* skip */ }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating test points:', e);
    return 0;
  }
}

/**
 * Рассчитать баллы за отзывы (reviews)
 */
async function calculateReviewsPoints(shopAddress, month) {
  try {
    const reviewsSettings = await getReviewsSettings();
    let totalPoints = 0;

    if (USE_DB) {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        'SELECT review_type FROM reviews WHERE shop_address = $1 AND created_at >= $2::timestamptz AND created_at < $3::timestamptz',
        [shopAddress, start, end]
      );
      for (const row of res.rows) {
        totalPoints += (row.review_type === 'positive') ? reviewsSettings.positivePoints : reviewsSettings.negativePoints;
      }
    } else {
      if (!(await fileExists(REVIEWS_DIR))) return 0;
      const files = await fsp.readdir(REVIEWS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await fsp.readFile(path.join(REVIEWS_DIR, file), 'utf8');
          const review = JSON.parse(content);
          if (review.shopAddress === shopAddress &&
              review.createdAt && review.createdAt.startsWith(month)) {
            const isPositive = review.reviewType === 'positive';
            totalPoints += isPositive ? reviewsSettings.positivePoints : reviewsSettings.negativePoints;
          }
        } catch (e) { /* skip */ }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating reviews points:', e);
    return 0;
  }
}

/**
 * Рассчитать баллы за поиск товара (product search)
 */
async function calculateProductSearchPoints(employeeId, month) {
  // Points handled via product_questions_penalty_scheduler → efficiency-penalties
  // calculateAttendancePenalties() sums them
  return 0;
}

/**
 * Рассчитать баллы за РКО
 */
async function calculateRkoPoints(shopAddress, month) {
  try {
    const settings = await getRkoSettings();
    let totalPoints = 0;

    if (USE_DB) {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        'SELECT id FROM rko_reports WHERE shop_address = $1 AND date >= $2::date AND date < $3::date',
        [shopAddress, start, end]
      );
      // Each existing RKO report = hasRko points
      for (const _row of res.rows) {
        totalPoints += settings.hasRkoPoints;
      }
    } else {
      if (!(await fileExists(RKO_DIR))) return 0;
      const files = await fsp.readdir(RKO_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await fsp.readFile(path.join(RKO_DIR, file), 'utf8');
          const rko = JSON.parse(content);
          if (rko.shopAddress === shopAddress &&
              rko.date && rko.date.startsWith(month)) {
            const hasRko = rko.hasRko === true;
            totalPoints += hasRko ? settings.hasRkoPoints : settings.noRkoPoints;
          }
        } catch (e) { /* skip */ }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating RKO points:', e);
    return 0;
  }
}

/**
 * Рассчитать баллы за задачи (tasks)
 */
async function calculateTasksPoints(employeeId, month) {
  try {
    let totalPoints = 0;
    const taskConfig = await getTaskPointsConfig();
    const regularBonus = taskConfig.regularTasks?.completionPoints ?? 1;
    const recurringBonus = taskConfig.recurringTasks?.completionPoints ?? 2;

    if (USE_DB) {
      // Regular tasks: approved assignments for tasks in this month
      const assignRes = await db.query(
        'SELECT ta.id FROM task_assignments ta JOIN tasks t ON ta.task_id = t.id WHERE t.month = $1 AND ta.assignee_id = $2 AND ta.status = $3',
        [month, employeeId, 'approved']
      );
      totalPoints += assignRes.rows.length * regularBonus;

      // Recurring tasks: completed instances in this month
      const { start, end } = getMonthRange(month);
      const recurRes = await db.query(
        'SELECT id FROM recurring_task_instances WHERE assignee_id = $1 AND status = $2 AND date >= $3::date AND date < $4::date',
        [employeeId, 'completed', start, end]
      );
      totalPoints += recurRes.rows.length * recurringBonus;
    } else {
      // Regular tasks from JSON
      const assignmentsFile = path.join(TASK_ASSIGNMENTS_DIR, `${month}.json`);
      if (await fileExists(assignmentsFile)) {
        try {
          const content = await fsp.readFile(assignmentsFile, 'utf8');
          const data = JSON.parse(content);
          const assignments = data.assignments || [];
          for (const assignment of assignments) {
            if (assignment.assigneeId === employeeId && assignment.status === 'approved') {
              totalPoints += regularBonus;
            }
          }
        } catch (e) { /* skip */ }
      }

      // Recurring tasks from JSON
      const instancesFile = path.join(RECURRING_INSTANCES_DIR, `${month}.json`);
      if (await fileExists(instancesFile)) {
        try {
          const content = await fsp.readFile(instancesFile, 'utf8');
          const instances = JSON.parse(content);
          const instancesArr = Array.isArray(instances) ? instances : [];
          for (const instance of instancesArr) {
            if (instance.assigneeId === employeeId && instance.status === 'completed') {
              totalPoints += recurringBonus;
            }
          }
        } catch (e) { /* skip */ }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating tasks points:', e);
    return 0;
  }
}

/**
 * Рассчитать все автоматические штрафы (attendance, envelope, etc.)
 */
async function calculateAttendancePenalties(employeeId, employeeName, month) {
  try {
    if (USE_DB) {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        'SELECT SUM(points) as total FROM efficiency_penalties WHERE (entity_id = $1 OR employee_phone = $1 OR entity_id = $4) AND date >= $2::date AND date < $3::date',
        [employeeId, start, end, employeeName || '']
      );
      return parseFloat(res.rows[0]?.total) || 0;
    }

    // JSON fallback
    if (!(await fileExists(EFFICIENCY_PENALTIES_DIR))) return 0;

    const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${month}.json`);
    if (!(await fileExists(penaltiesFile))) return 0;

    const content = await fsp.readFile(penaltiesFile, 'utf8');
    const penaltiesData = JSON.parse(content);
    const penalties = penaltiesData.penalties || penaltiesData;

    if (!Array.isArray(penalties)) return 0;

    let totalPenalty = 0;
    for (const penalty of penalties) {
      const matchesEmployee = (penalty.employeeId === employeeId)
        || (penalty.entityId === employeeId)
        || (employeeName && penalty.entityId === employeeName);
      const matchesMonth = penalty.date && penalty.date.startsWith(month);

      if (matchesEmployee && matchesMonth) {
        totalPenalty += penalty.points || 0;
      }
    }

    return totalPenalty;
  } catch (e) {
    console.error('Error calculating attendance penalties:', e);
    return 0;
  }
}

/**
 * Рассчитать заказы (orders) - TODO: интеграция с Lichi CRM API
 */
async function calculateOrdersPoints(employeeId, month) {
  return 0;
}

/**
 * Рассчитать баллы за конверты (envelope - сдача наличных)
 */
async function calculateEnvelopePoints(employeeName, month) {
  try {
    const settings = await getEnvelopeSettings();
    let totalPoints = 0;

    if (USE_DB) {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        "SELECT status FROM envelope_reports WHERE LOWER(TRIM(employee_name)) = LOWER(TRIM($1)) AND date >= $2 AND date < $3 AND status = 'confirmed'",
        [employeeName, start, end]
      );
      totalPoints += res.rows.length * settings.submittedPoints;
    } else {
      if (!(await fileExists(ENVELOPE_REPORTS_DIR))) return 0;
      const files = await fsp.readdir(ENVELOPE_REPORTS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await fsp.readFile(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8');
          const envelope = JSON.parse(content);
          const nameMatch = envelope.employeeName && employeeName &&
            envelope.employeeName.trim().toLowerCase() === employeeName.trim().toLowerCase();
          if (nameMatch && envelope.createdAt && envelope.createdAt.startsWith(month)) {
            if (envelope.status === 'confirmed') {
              totalPoints += settings.submittedPoints;
            }
          }
        } catch (e) { /* skip */ }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating envelope points:', e);
    return 0;
  }
}

/**
 * Рассчитать баллы за счётчики кофемашин
 */
async function calculateCoffeeMachinePoints(employeeName, month) {
  try {
    const settings = await getCoffeeMachineSettings();
    let totalPoints = 0;

    if (USE_DB) {
      const { start, end } = getMonthRange(month);
      const res = await db.query(
        "SELECT status FROM coffee_machine_reports WHERE LOWER(TRIM(employee_name)) = LOWER(TRIM($1)) AND date >= $2::date AND date < $3::date AND status = 'confirmed'",
        [employeeName, start, end]
      );
      totalPoints += res.rows.length * settings.submittedPoints;
    } else {
      if (!(await fileExists(COFFEE_MACHINE_REPORTS_DIR))) return 0;
      const files = await fsp.readdir(COFFEE_MACHINE_REPORTS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await fsp.readFile(path.join(COFFEE_MACHINE_REPORTS_DIR, file), 'utf8');
          const report = JSON.parse(content);
          const nameMatch = report.employeeName && employeeName &&
            report.employeeName.trim().toLowerCase() === employeeName.trim().toLowerCase();
          if (nameMatch && report.createdAt && report.createdAt.startsWith(month)) {
            if (report.status === 'confirmed') {
              totalPoints += settings.submittedPoints;
            }
          }
        } catch (e) { /* skip */ }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating coffee machine points:', e);
    return 0;
  }
}

// =====================================================
// MAIN FUNCTION: Calculate Full Efficiency
// =====================================================

/**
 * Рассчитать полную эффективность сотрудника за месяц
 *
 * @param {string} employeeId - ID или телефон сотрудника
 * @param {string} employeeName - Имя сотрудника
 * @param {string} shopAddress - Адрес магазина (для отзывов и РКО)
 * @param {string} month - Месяц в формате YYYY-MM
 * @returns {object} - Детальная информация о баллах (13 категорий)
 */
async function calculateFullEfficiency(employeeId, employeeName, shopAddress, month) {
  try {
    const breakdown = {
      shift: await calculateShiftPoints(employeeId, employeeName, month),
      recount: await calculateRecountPoints(employeeId, employeeName, month),
      handover: await calculateHandoverPoints(employeeId, employeeName, month),
      attendance: await calculateAttendancePoints(employeeId, month),
      attendancePenalties: await calculateAttendancePenalties(employeeId, employeeName, month),
      test: await calculateTestPoints(employeeId, employeeName, month),
      reviews: await calculateReviewsPoints(shopAddress, month),
      productSearch: await calculateProductSearchPoints(employeeId, month),
      rko: await calculateRkoPoints(shopAddress, month),
      tasks: await calculateTasksPoints(employeeId, month),
      orders: await calculateOrdersPoints(employeeId, month),
      envelope: await calculateEnvelopePoints(employeeName, month),
      coffeeMachine: await calculateCoffeeMachinePoints(employeeName, month),
    };

    const total = Object.values(breakdown).reduce((sum, v) => sum + v, 0);

    return {
      total,
      breakdown,
    };
  } catch (e) {
    console.error('Error calculating full efficiency:', e);
    return {
      total: 0,
      breakdown: {},
    };
  }
}

// =====================================================
// BATCH OPTIMIZED FUNCTIONS (используют кэш)
// =====================================================

/**
 * Рассчитать баллы за пересменку используя кэш
 */
async function calculateShiftPointsCached(employeeId, employeeName, cache) {
  if (!cache.shiftReports) return 0;

  const settings = cache.settings ? cache.settings.shiftSettings : await getShiftSettings();
  let totalPoints = 0;

  for (const report of cache.shiftReports) {
    if (report.employeeName === employeeName || report.employeePhone === employeeId) {
      if (report.adminRating && report.adminRating > 0) {
        totalPoints += interpolateRatingPoints(
          report.adminRating,
          settings.minRating, settings.maxRating,
          settings.minPoints, settings.zeroThreshold, settings.maxPoints
        );
      }
    }
  }

  return totalPoints;
}

/**
 * Рассчитать баллы за пересчёт используя кэш
 */
async function calculateRecountPointsCached(employeeId, employeeName, cache) {
  if (!cache.recountReports) return 0;

  const settings = cache.settings ? cache.settings.recountSettings : await getRecountSettings();
  let totalPoints = 0;

  for (const report of cache.recountReports) {
    if (report.employeeName === employeeName || report.employeePhone === employeeId) {
      if (report.adminRating && report.adminRating > 0) {
        totalPoints += interpolateRatingPoints(
          report.adminRating,
          settings.minRating, settings.maxRating,
          settings.minPoints, settings.zeroThreshold, settings.maxPoints
        );
      }
    }
  }

  return totalPoints;
}

/**
 * Рассчитать баллы за сдачу смены используя кэш
 */
async function calculateHandoverPointsCached(employeeId, employeeName, cache) {
  if (!cache.handoverReports) return 0;

  const settings = cache.settings ? cache.settings.handoverSettings : await getHandoverSettings();
  let totalPoints = 0;

  for (const report of cache.handoverReports) {
    if (report.employeeName === employeeName || report.employeePhone === employeeId) {
      if (report.rating && report.rating > 0) {
        totalPoints += interpolateRatingPoints(
          report.rating,
          settings.minRating, settings.maxRating,
          settings.minPoints, settings.zeroThreshold, settings.maxPoints
        );
      }
    }
  }

  return totalPoints;
}

/**
 * Рассчитать баллы за посещаемость используя кэш
 */
async function calculateAttendancePointsCached(employeeId, employeeName, cache) {
  if (!cache.attendance) return 0;

  const settings = cache.settings ? cache.settings.attendanceSettings : await getAttendanceSettings();
  let totalPoints = 0;
  const empNameLower = employeeName ? employeeName.trim().toLowerCase() : '';

  for (const record of cache.attendance) {
    const idMatch = record.employeeId && (record.employeeId === employeeId || record.phone === employeeId);
    const nameMatch = empNameLower && record.employeeName && record.employeeName.trim().toLowerCase() === empNameLower;
    if (idMatch || nameMatch) {
      totalPoints += record.isOnTime ? settings.onTimePoints : settings.latePoints;
    }
  }

  return totalPoints;
}

/**
 * Рассчитать штрафы используя кэш
 */
function calculateAttendancePenaltiesCached(employeeId, employeeName, cache) {
  if (!cache.penalties) return 0;

  let totalPoints = 0;

  for (const penalty of cache.penalties) {
    if (
      penalty.entityId === employeeId
      || penalty.employeePhone === employeeId
      || (employeeName && penalty.entityId === employeeName)
    ) {
      totalPoints += penalty.points || 0;
    }
  }

  return totalPoints;
}

/**
 * Рассчитать баллы за тесты используя кэш
 */
async function calculateTestPointsCached(employeeId, employeeName, cache) {
  if (!cache.tests) return 0;

  const settings = cache.settings ? cache.settings.testSettings : await getTestSettings();
  let totalPoints = 0;

  for (const test of cache.tests) {
    if (test.employeeName === employeeName || test.employeeId === employeeId) {
      const score = test.score || 0;
      totalPoints += interpolateTestPoints(
        score, settings.totalQuestions,
        settings.minPoints, settings.zeroThreshold, settings.maxPoints
      );
    }
  }

  return totalPoints;
}

/**
 * Рассчитать баллы за отзывы используя кэш
 */
function calculateReviewsPointsCached(shopAddress, cache) {
  if (!cache.reviews) return 0;

  const reviewsSettings = cache.settings ? cache.settings.reviewsSettings : { positivePoints: 3, negativePoints: -5 };
  let totalPoints = 0;

  for (const review of cache.reviews) {
    if (review.shopAddress === shopAddress) {
      totalPoints += (review.reviewType === 'positive')
        ? reviewsSettings.positivePoints
        : reviewsSettings.negativePoints;
    }
  }

  return totalPoints;
}

/**
 * Рассчитать баллы за РКО используя кэш
 */
function calculateRkoPointsCached(shopAddress, cache) {
  if (!cache.rko) return 0;

  const rkoSettings = cache.settings ? cache.settings.rkoSettings : { hasRkoPoints: 1.0 };
  let totalPoints = 0;

  for (const rko of cache.rko) {
    if (rko.shopAddress === shopAddress) {
      totalPoints += rko.hasRko ? rkoSettings.hasRkoPoints : 0;
    }
  }

  return totalPoints;
}

/**
 * Рассчитать баллы за задачи используя кэш
 */
function calculateTasksPointsCached(employeeId, cache) {
  const taskConfig = cache.settings ? cache.settings.taskConfig : {};
  const regularBonus = taskConfig.regularTasks?.completionPoints ?? 1;
  const recurringBonus = taskConfig.recurringTasks?.completionPoints ?? 2;
  let totalPoints = 0;

  // Regular tasks
  if (cache.taskAssignments) {
    for (const a of cache.taskAssignments) {
      if (a.assigneeId === employeeId && a.status === 'approved') {
        totalPoints += regularBonus;
      }
    }
  }

  // Recurring tasks
  if (cache.recurringInstances) {
    for (const i of cache.recurringInstances) {
      if (i.assigneeId === employeeId && i.status === 'completed') {
        totalPoints += recurringBonus;
      }
    }
  }

  return totalPoints;
}

/**
 * Рассчитать баллы за конверты используя кэш
 */
async function calculateEnvelopePointsCached(employeeName, cache) {
  if (!cache.envelopes) return 0;

  const settings = cache.settings ? cache.settings.envelopeSettings : await getEnvelopeSettings();
  let totalPoints = 0;

  for (const envelope of cache.envelopes) {
    const nameMatch = envelope.employeeName && employeeName &&
      envelope.employeeName.trim().toLowerCase() === employeeName.trim().toLowerCase();
    if (nameMatch && envelope.status === 'confirmed') {
      totalPoints += settings.submittedPoints;
    }
  }

  return totalPoints;
}

/**
 * Рассчитать баллы за кофемашины используя кэш
 */
async function calculateCoffeeMachinePointsCached(employeeName, cache) {
  if (!cache.coffeeMachineReports) return 0;

  const settings = cache.settings ? cache.settings.coffeeMachineSettings : await getCoffeeMachineSettings();
  let totalPoints = 0;

  for (const report of cache.coffeeMachineReports) {
    const nameMatch = report.employeeName && employeeName &&
      report.employeeName.trim().toLowerCase() === employeeName.trim().toLowerCase();
    if (nameMatch && report.status === 'confirmed') {
      totalPoints += settings.submittedPoints;
    }
  }

  return totalPoints;
}

/**
 * Determine employee's shop addresses from cache data
 * Looks at shift reports and attendance to find which shops the employee worked at
 */
function resolveEmployeeShops(employeeId, employeeName, shopAddress, cache) {
  // If shopAddress explicitly provided, use it
  if (shopAddress) return [shopAddress];

  const shops = new Set();
  const empNameLower = employeeName ? employeeName.trim().toLowerCase() : '';

  // From shift reports
  if (cache.shiftReports) {
    for (const r of cache.shiftReports) {
      if (!r.shopAddress) continue;
      const idMatch = r.employeePhone && r.employeePhone === employeeId;
      const nameMatch = empNameLower && r.employeeName && r.employeeName.trim().toLowerCase() === empNameLower;
      if (idMatch || nameMatch) shops.add(r.shopAddress);
    }
  }

  // From attendance
  if (cache.attendance) {
    for (const r of cache.attendance) {
      if (!r.shopAddress) continue;
      const idMatch = r.employeeId && (r.employeeId === employeeId || r.phone === employeeId);
      const nameMatch = empNameLower && r.employeeName && r.employeeName.trim().toLowerCase() === empNameLower;
      if (idMatch || nameMatch) shops.add(r.shopAddress);
    }
  }

  return [...shops];
}

/**
 * Calculate reviews points across multiple shops
 */
function calculateReviewsPointsMultiShop(shops, cache) {
  if (!cache.reviews || shops.length === 0) return 0;
  let totalPoints = 0;
  for (const shop of shops) {
    totalPoints += calculateReviewsPointsCached(shop, cache);
  }
  return totalPoints;
}

/**
 * Calculate RKO points across multiple shops
 */
function calculateRkoPointsMultiShop(shops, cache) {
  if (!cache.rko || shops.length === 0) return 0;
  let totalPoints = 0;
  for (const shop of shops) {
    totalPoints += calculateRkoPointsCached(shop, cache);
  }
  return totalPoints;
}

/**
 * Рассчитать эффективность используя кэш (для batch операций)
 * All 13 categories calculated from cache — no extra file/DB reads
 */
async function calculateFullEfficiencyCached(employeeId, employeeName, shopAddress, month, cache) {
  try {
    // Determine employee's shops from cache data if shopAddress not provided
    const empShops = resolveEmployeeShops(employeeId, employeeName, shopAddress, cache);

    const breakdown = {
      shift: await calculateShiftPointsCached(employeeId, employeeName, cache),
      recount: await calculateRecountPointsCached(employeeId, employeeName, cache),
      handover: await calculateHandoverPointsCached(employeeId, employeeName, cache),
      attendance: await calculateAttendancePointsCached(employeeId, employeeName, cache),
      attendancePenalties: calculateAttendancePenaltiesCached(employeeId, employeeName, cache),
      test: await calculateTestPointsCached(employeeId, employeeName, cache),
      reviews: calculateReviewsPointsMultiShop(empShops, cache),
      productSearch: 0, // Handled via efficiency-penalties
      rko: calculateRkoPointsMultiShop(empShops, cache),
      tasks: calculateTasksPointsCached(employeeId, cache),
      orders: 0, // TODO: Lichi CRM
      envelope: await calculateEnvelopePointsCached(employeeName, cache),
      coffeeMachine: await calculateCoffeeMachinePointsCached(employeeName, cache),
    };

    const total = Object.values(breakdown).reduce((sum, v) => sum + v, 0);

    return { total, breakdown };
  } catch (e) {
    console.error('Error in calculateFullEfficiencyCached:', e);
    return { total: 0, breakdown: {} };
  }
}

/**
 * BATCH: Рассчитать эффективность для ВСЕХ сотрудников за один проход
 * Загружает данные ОДИН раз, затем O(n) расчёт для каждого сотрудника
 *
 * @param {Array} employees - Массив объектов сотрудников [{id, name, shopAddress}]
 * @param {string} month - Месяц в формате YYYY-MM
 * @returns {Map<string, object>} Map employeeId -> {total, breakdown}
 */
async function calculateBatchEfficiency(employees, month) {
  const startTime = Date.now();
  console.log(`[Efficiency] Batch расчёт для ${employees.length} сотрудников за ${month}`);

  // Init cache — loads ALL data once
  const cache = await initBatchCache(month);

  const results = new Map();

  for (const emp of employees) {
    const efficiency = await calculateFullEfficiencyCached(
      emp.id || emp.phone,
      emp.name,
      emp.shopAddress,
      month,
      cache
    );
    results.set(emp.id || emp.phone, efficiency);
  }

  const elapsed = Date.now() - startTime;
  console.log(`[Efficiency] Batch расчёт завершён за ${elapsed}ms`);

  // Clear cache after batch
  clearBatchCache();

  return results;
}

module.exports = {
  calculateFullEfficiency,
  calculateShiftPoints,
  calculateRecountPoints,
  calculateHandoverPoints,
  calculateAttendancePoints,
  calculateAttendancePenalties,
  calculateTestPoints,
  calculateReviewsPoints,
  calculateProductSearchPoints,
  calculateRkoPoints,
  calculateTasksPoints,
  calculateOrdersPoints,
  calculateEnvelopePoints,
  calculateCoffeeMachinePoints,
  // Batch optimized functions
  initBatchCache,
  clearBatchCache,
  calculateBatchEfficiency,
  calculateFullEfficiencyCached,
};
