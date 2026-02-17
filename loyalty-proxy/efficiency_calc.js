// =====================================================
// EFFICIENCY CALCULATION MODULE
//
// REFACTORED: Converted from sync to async I/O (2026-02-05)
// =====================================================
// Полный расчёт эффективности сотрудника за месяц
// Используются те же формулы что и в Flutter приложении
//
// 12 категорий:
// 1. Shift (пересменка) - rating 1-10
// 2. Recount (пересчёт) - rating 1-10
// 3. ShiftHandover (сдача смены) - rating 1-10
// 4. Attendance (посещаемость) - boolean
// 5. Test (тестирование) - score 0-20
// 6. Reviews (отзывы) - boolean
// 7. ProductSearch (поиск товара) - boolean
// 8. Orders (заказы) - boolean
// 9. RKO (РКО) - boolean
// 10. Tasks (задачи: recurring + regular) - boolean
// 11. AttendancePenalties (автоштрафы: attendance, envelope и др.) - штрафные баллы
// 12. Envelope (конверты - сдача наличных) - boolean
//
// Все настройки загружаются из /var/www/points-settings/
// =====================================================

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('./utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

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
// Кэш для batch операций - загружаем данные ОДИН раз при расчёте рейтинга всех сотрудников
let _batchCache = null;
let _batchCacheMonth = null;

/**
 * Загрузить все файлы из директории, отфильтровав по месяцу
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

        // Фильтруем по месяцу если указано поле даты
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
  console.log(`[Efficiency] Инициализация batch кэша для ${month}...`);

  // OPTIMIZATION: Загружаем settings ОДИН раз для batch (вместо N раз на сотрудника)
  const [shiftSettings, recountSettings, handoverSettings, attendanceSettings, testSettings, envelopeSettings, coffeeMachineSettings] = await Promise.all([
    getShiftSettings(),
    getRecountSettings(),
    getHandoverSettings(),
    getAttendanceSettings(),
    getTestSettings(),
    getEnvelopeSettings(),
    getCoffeeMachineSettings(),
  ]);

  _batchCache = {
    shiftReports: await loadDirectoryForMonth(SHIFT_REPORTS_DIR, month, 'handoverDate'),
    recountReports: await loadDirectoryForMonth(RECOUNT_REPORTS_DIR, month, 'recountDate'),
    handoverReports: await loadDirectoryForMonth(HANDOVER_REPORTS_DIR, month, 'handoverDate'),
    attendance: await loadDirectoryForMonth(ATTENDANCE_DIR, month, 'timestamp'),
    tests: await loadDirectoryForMonth(TESTS_DIR, month, 'completedAt'),
    reviews: await loadDirectoryForMonth(REVIEWS_DIR, month, 'createdAt'),
    productQuestions: await loadDirectoryForMonth(PRODUCT_QUESTIONS_DIR, month, null), // Загружаем все, фильтруем потом
    rko: await loadDirectoryForMonth(RKO_DIR, month, 'date'),
    tasks: await loadDirectoryForMonth(TASKS_DIR, month, null),
    recurringTasks: await loadDirectoryForMonth(RECURRING_TASKS_DIR, month, null),
    envelopes: await loadDirectoryForMonth(ENVELOPE_REPORTS_DIR, month, 'createdAt'),
    coffeeMachineReports: await loadDirectoryForMonth(COFFEE_MACHINE_REPORTS_DIR, month, 'createdAt'),
    penalties: await loadPenaltiesForMonth(month),
    // Cached settings (loaded once, used for all employees)
    settings: { shiftSettings, recountSettings, handoverSettings, attendanceSettings, testSettings, envelopeSettings, coffeeMachineSettings },
  };

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
  const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${month}.json`);

  if (!(await fileExists(filePath))) {
    return [];
  }

  try {
    const content = JSON.parse(await fsp.readFile(filePath, 'utf8'));
    // Support both formats: ARRAY [...] and OBJECT {penalties: [...]}
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
    // Интерполяция от minPoints до 0
    const range = zeroThreshold - minRating;
    if (range === 0) return 0;
    return minPoints + (0 - minPoints) * ((rating - minRating) / range);
  } else {
    // Интерполяция от 0 до maxPoints
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
    // Интерполяция от minPoints до 0
    return minPoints + (0 - minPoints) * (score / zeroThreshold);
  } else {
    // Интерполяция от 0 до maxPoints
    const range = totalQuestions - zeroThreshold;
    return 0 + (maxPoints - 0) * ((score - zeroThreshold) / range);
  }
}

// =====================================================
// LOAD SETTINGS
// =====================================================

async function loadSettings(filename, defaults) {
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

// Для reviews, productSearch, orders используем binary логику (нет отдельных файлов)
const DEFAULT_REVIEWS_POINTS = { positivePoints: 1.5, negativePoints: -1.5 };
const DEFAULT_PRODUCT_SEARCH_POINTS = { answeredPoints: 1.0, missedPoints: 0 };
const DEFAULT_ORDERS_POINTS = { acceptedPoints: 1.0, rejectedPoints: 0 };

// =====================================================
// CALCULATE POINTS FOR EACH CATEGORY
// =====================================================

/**
 * Рассчитать баллы за пересменку (shift report)
 */
async function calculateShiftPoints(employeeId, employeeName, month) {
  try {
    if (!(await fileExists(SHIFT_REPORTS_DIR))) return 0;

    const settings = await getShiftSettings();
    const files = await fsp.readdir(SHIFT_REPORTS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(SHIFT_REPORTS_DIR, file), 'utf8');
        const report = JSON.parse(content);

        // Проверяем что это нужный сотрудник и месяц
        if ((report.employeeName === employeeName || report.employeePhone === employeeId) &&
            report.handoverDate && report.handoverDate.startsWith(month)) {

          // Если есть оценка - считаем баллы
          if (report.adminRating && report.adminRating > 0) {
            const points = interpolateRatingPoints(
              report.adminRating,
              settings.minRating,
              settings.maxRating,
              settings.minPoints,
              settings.zeroThreshold,
              settings.maxPoints
            );
            totalPoints += points;
          }
        }
      } catch (e) {
        // Skip invalid file
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
    if (!(await fileExists(RECOUNT_REPORTS_DIR))) return 0;

    const settings = await getRecountSettings();
    const files = await fsp.readdir(RECOUNT_REPORTS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(RECOUNT_REPORTS_DIR, file), 'utf8');
        const report = JSON.parse(content);

        if ((report.employeeName === employeeName || report.employeePhone === employeeId) &&
            report.recountDate && report.recountDate.startsWith(month)) {

          if (report.adminRating && report.adminRating > 0) {
            const points = interpolateRatingPoints(
              report.adminRating,
              settings.minRating,
              settings.maxRating,
              settings.minPoints,
              settings.zeroThreshold,
              settings.maxPoints
            );
            totalPoints += points;
          }
        }
      } catch (e) {
        // Skip invalid file
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
    if (!(await fileExists(HANDOVER_REPORTS_DIR))) return 0;

    const settings = await getHandoverSettings();
    const files = await fsp.readdir(HANDOVER_REPORTS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(HANDOVER_REPORTS_DIR, file), 'utf8');
        const report = JSON.parse(content);

        if ((report.employeeName === employeeName || report.employeePhone === employeeId) &&
            report.handoverDate && report.handoverDate.startsWith(month)) {

          if (report.rating && report.rating > 0) {
            const points = interpolateRatingPoints(
              report.rating,
              settings.minRating,
              settings.maxRating,
              settings.minPoints,
              settings.zeroThreshold,
              settings.maxPoints
            );
            totalPoints += points;
          }
        }
      } catch (e) {
        // Skip invalid file
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
    if (!(await fileExists(ATTENDANCE_DIR))) return 0;

    const settings = await getAttendanceSettings();
    const files = await fsp.readdir(ATTENDANCE_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(ATTENDANCE_DIR, file), 'utf8');
        const record = JSON.parse(content);

        if ((record.employeeId === employeeId || record.phone === employeeId)) {
          const recordDate = record.timestamp || record.createdAt;
          if (recordDate && recordDate.startsWith(month)) {
            // Проверяем вовремя или опоздал
            const points = record.isOnTime ? settings.onTimePoints : settings.latePoints;
            totalPoints += points;
          }
        }
      } catch (e) {
        // Skip invalid file
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
    if (!(await fileExists(TESTS_DIR))) return 0;

    const settings = await getTestSettings();
    const files = await fsp.readdir(TESTS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(TESTS_DIR, file), 'utf8');
        const test = JSON.parse(content);

        if ((test.employeeName === employeeName || test.employeeId === employeeId) &&
            test.completedAt && test.completedAt.startsWith(month)) {

          const score = test.score || 0;
          const points = interpolateTestPoints(
            score,
            settings.totalQuestions,
            settings.minPoints,
            settings.zeroThreshold,
            settings.maxPoints
          );
          totalPoints += points;
        }
      } catch (e) {
        // Skip invalid file
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
    if (!(await fileExists(REVIEWS_DIR))) return 0;

    const files = await fsp.readdir(REVIEWS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(REVIEWS_DIR, file), 'utf8');
        const review = JSON.parse(content);

        if (review.shopAddress === shopAddress &&
            review.createdAt && review.createdAt.startsWith(month)) {

          // Положительный отзыв = +баллы, отрицательный = -баллы
          const isPositive = review.reviewType === 'positive';
          const points = isPositive
            ? DEFAULT_REVIEWS_POINTS.positivePoints
            : DEFAULT_REVIEWS_POINTS.negativePoints;
          totalPoints += points;
        }
      } catch (e) {
        // Skip invalid file
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
  // Баллы за поиск товара рассчитываются через product_questions_penalty_scheduler
  // и записываются в efficiency-penalties/YYYY-MM.json
  // calculateAttendancePenalties() уже суммирует их оттуда
  return 0;
}

/**
 * Рассчитать баллы за РКО
 */
async function calculateRkoPoints(shopAddress, month) {
  try {
    if (!(await fileExists(RKO_DIR))) return 0;

    const settings = await getRkoSettings();
    const files = await fsp.readdir(RKO_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(RKO_DIR, file), 'utf8');
        const rko = JSON.parse(content);

        if (rko.shopAddress === shopAddress &&
            rko.date && rko.date.startsWith(month)) {

          // Есть РКО = баллы, нет РКО = штраф
          const hasRko = rko.hasRko === true;
          const points = hasRko ? settings.hasRkoPoints : settings.noRkoPoints;
          totalPoints += points;
        }
      } catch (e) {
        // Skip invalid file
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

    // Разовые задачи — читаем назначения из task-assignments/YYYY-MM.json
    const assignmentsFile = path.join(TASK_ASSIGNMENTS_DIR, `${month}.json`);
    if (await fileExists(assignmentsFile)) {
      try {
        const content = await fsp.readFile(assignmentsFile, 'utf8');
        const data = JSON.parse(content);
        const assignments = data.assignments || [];

        for (const assignment of assignments) {
          if (assignment.assigneeId === employeeId && assignment.status === 'approved') {
            totalPoints += 1.0;
          }
        }
      } catch (e) {
        // Skip invalid file
      }
    }

    // Циклические задачи — читаем инстансы из recurring-task-instances/YYYY-MM.json
    const instancesFile = path.join(RECURRING_INSTANCES_DIR, `${month}.json`);
    if (await fileExists(instancesFile)) {
      try {
        const content = await fsp.readFile(instancesFile, 'utf8');
        const instances = JSON.parse(content);
        const instancesArr = Array.isArray(instances) ? instances : [];

        for (const instance of instancesArr) {
          if (instance.assigneeId === employeeId && instance.status === 'completed') {
            totalPoints += 1.0;
          }
        }
      } catch (e) {
        // Skip invalid file
      }
    }

    // Штрафы за просроченные задачи обрабатываются через
    // tasks_api/recurring_tasks_api → efficiency-penalties
    return totalPoints;
  } catch (e) {
    console.error('Error calculating tasks points:', e);
    return 0;
  }
}

/**
 * Рассчитать все автоматические штрафы (attendance, envelope, etc.)
 * Читает файл /var/www/efficiency-penalties/YYYY-MM.json
 */
async function calculateAttendancePenalties(employeeId, month) {
  try {
    if (!(await fileExists(EFFICIENCY_PENALTIES_DIR))) return 0;

    // Читаем файл штрафов за месяц
    const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${month}.json`);
    if (!(await fileExists(penaltiesFile))) return 0;

    const content = await fsp.readFile(penaltiesFile, 'utf8');
    const penaltiesData = JSON.parse(content);
    const penalties = penaltiesData.penalties || penaltiesData;

    if (!Array.isArray(penalties)) return 0;

    // Фильтруем штрафы для этого сотрудника за этот месяц
    // Проверяем оба поля: entityId (новый формат) и employeeId (старый формат)
    let totalPenalty = 0;
    for (const penalty of penalties) {
      const matchesEmployee = (penalty.employeeId === employeeId) || (penalty.entityId === employeeId);
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
  // TODO: Получить заказы из Lichi CRM API
  // Пока возвращаем 0
  return 0;
}

/**
 * Рассчитать баллы за конверты (envelope - сдача наличных)
 *
 * @param {string} employeeName - Имя сотрудника (envelope-reports не содержат employeeId)
 * @param {string} month - Месяц в формате YYYY-MM
 * @returns {number} - Сумма баллов за конверты
 */
async function calculateEnvelopePoints(employeeName, month) {
  try {
    if (!(await fileExists(ENVELOPE_REPORTS_DIR))) return 0;

    const settings = await getEnvelopeSettings();
    const files = await fsp.readdir(ENVELOPE_REPORTS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(ENVELOPE_REPORTS_DIR, file), 'utf8');
        const envelope = JSON.parse(content);

        // Фильтруем по имени сотрудника (case-insensitive) и месяцу
        const nameMatch = envelope.employeeName && employeeName &&
          envelope.employeeName.trim().toLowerCase() === employeeName.trim().toLowerCase();

        if (nameMatch && envelope.createdAt && envelope.createdAt.startsWith(month)) {
          // Бонус за подтверждённый конверт
          if (envelope.status === 'confirmed') {
            totalPoints += settings.submittedPoints;
          }
          // Штрафы за несданные конверты обрабатываются через
          // envelope_automation_scheduler → efficiency-penalties
        }
      } catch (e) {
        // Skip invalid file
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
 *
 * @param {string} employeeName - Имя сотрудника
 * @param {string} month - Месяц в формате YYYY-MM
 * @returns {number} - Сумма баллов
 */
async function calculateCoffeeMachinePoints(employeeName, month) {
  try {
    if (!(await fileExists(COFFEE_MACHINE_REPORTS_DIR))) return 0;

    const settings = await getCoffeeMachineSettings();
    const files = await fsp.readdir(COFFEE_MACHINE_REPORTS_DIR);
    let totalPoints = 0;

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
          // Штрафы за несданные — через coffee_machine_automation_scheduler → efficiency-penalties
        }
      } catch (e) {
        // Skip invalid file
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
 * @returns {object} - Детальная информация о баллах (12 категорий)
 */
async function calculateFullEfficiency(employeeId, employeeName, shopAddress, month) {
  try {
    const breakdown = {
      shift: await calculateShiftPoints(employeeId, employeeName, month),
      recount: await calculateRecountPoints(employeeId, employeeName, month),
      handover: await calculateHandoverPoints(employeeId, employeeName, month),
      attendance: await calculateAttendancePoints(employeeId, month),
      attendancePenalties: await calculateAttendancePenalties(employeeId, month),
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
async function calculateAttendancePointsCached(employeeId, cache) {
  if (!cache.attendance) return 0;

  const settings = cache.settings ? cache.settings.attendanceSettings : await getAttendanceSettings();
  let totalPoints = 0;

  for (const record of cache.attendance) {
    if (record.employeeId === employeeId || record.phone === employeeId) {
      totalPoints += record.isOnTime ? settings.onTimePoints : settings.latePoints;
    }
  }

  return totalPoints;
}

/**
 * Рассчитать штрафы используя кэш
 */
function calculateAttendancePenaltiesCached(employeeId, cache) {
  if (!cache.penalties) return 0;

  let totalPoints = 0;

  for (const penalty of cache.penalties) {
    if (penalty.entityId === employeeId || penalty.employeePhone === employeeId) {
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

  let totalPoints = 0;

  for (const review of cache.reviews) {
    if (review.shopAddress === shopAddress) {
      const points = (review.reviewType === 'positive')
        ? DEFAULT_REVIEWS_POINTS.positivePoints
        : DEFAULT_REVIEWS_POINTS.negativePoints;
      totalPoints += points;
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
    // Штрафы за несданные — через envelope_automation_scheduler → efficiency-penalties
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
    // Штрафы за несданные — через coffee_machine_automation_scheduler → efficiency-penalties
  }

  return totalPoints;
}

/**
 * Рассчитать эффективность используя кэш (для batch операций)
 */
async function calculateFullEfficiencyCached(employeeId, employeeName, shopAddress, month, cache) {
  try {
    const breakdown = {
      shift: await calculateShiftPointsCached(employeeId, employeeName, cache),
      recount: await calculateRecountPointsCached(employeeId, employeeName, cache),
      handover: await calculateHandoverPointsCached(employeeId, employeeName, cache),
      attendance: await calculateAttendancePointsCached(employeeId, cache),
      attendancePenalties: calculateAttendancePenaltiesCached(employeeId, cache),
      test: await calculateTestPointsCached(employeeId, employeeName, cache),
      reviews: calculateReviewsPointsCached(shopAddress, cache),
      productSearch: await calculateProductSearchPoints(employeeId, month), // Оставляем без кэша пока
      rko: await calculateRkoPoints(shopAddress, month), // Оставляем без кэша пока
      tasks: await calculateTasksPoints(employeeId, month), // Оставляем без кэша пока
      orders: await calculateOrdersPoints(employeeId, month), // Оставляем без кэша пока
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

  // Инициализируем кэш - загружает ВСЕ данные ОДИН раз
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

  // Очищаем кэш после batch операции
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
