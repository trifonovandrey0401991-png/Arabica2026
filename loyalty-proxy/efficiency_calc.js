// =====================================================
// EFFICIENCY CALCULATION MODULE
// =====================================================
// Полный расчёт эффективности сотрудника за месяц
// Используются те же формулы что и в Flutter приложении
//
// 10 категорий:
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
//
// Все настройки загружаются из /var/www/points-settings/
// =====================================================

const fs = require('fs');
const path = require('path');

const POINTS_SETTINGS_DIR = '/var/www/points-settings';
const SHIFT_REPORTS_DIR = '/var/www/shift-reports';
const RECOUNT_REPORTS_DIR = '/var/www/recount-reports';
const HANDOVER_REPORTS_DIR = '/var/www/shift-handovers';
const ATTENDANCE_DIR = '/var/www/attendance';
const TESTS_DIR = '/var/www/test-results';
const REVIEWS_DIR = '/var/www/client-reviews';
const PRODUCT_QUESTIONS_DIR = '/var/www/product-questions';
const RKO_DIR = '/var/www/rko';
const TASKS_DIR = '/var/www/tasks';
const RECURRING_TASKS_DIR = '/var/www/recurring-tasks';

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

function loadSettings(filename, defaults) {
  try {
    const filePath = path.join(POINTS_SETTINGS_DIR, filename);
    if (fs.existsSync(filePath)) {
      return JSON.parse(fs.readFileSync(filePath, 'utf8'));
    }
    return defaults;
  } catch (e) {
    console.error(`Error loading settings ${filename}:`, e);
    return defaults;
  }
}

function getShiftSettings() {
  return loadSettings('shift_points_settings.json', {
    minPoints: -3,
    zeroThreshold: 6,
    maxPoints: 2,
    minRating: 1,
    maxRating: 10,
  });
}

function getRecountSettings() {
  return loadSettings('recount_points_settings.json', {
    minPoints: -3,
    zeroThreshold: 6,
    maxPoints: 2,
    minRating: 1,
    maxRating: 10,
  });
}

function getHandoverSettings() {
  return loadSettings('shift_handover_points_settings.json', {
    minPoints: -3,
    zeroThreshold: 7,
    maxPoints: 1,
    minRating: 1,
    maxRating: 10,
  });
}

function getTestSettings() {
  return loadSettings('test_points_settings.json', {
    minPoints: -2.5,
    zeroThreshold: 15,
    maxPoints: 3.5,
    totalQuestions: 20,
  });
}

function getAttendanceSettings() {
  return loadSettings('attendance_points_settings.json', {
    onTimePoints: 1.0,
    latePoints: 0.5,
  });
}

function getRkoSettings() {
  return loadSettings('rko_points_settings.json', {
    hasRkoPoints: 1.0,
    noRkoPoints: -3.0,
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
function calculateShiftPoints(employeeId, employeeName, month) {
  try {
    if (!fs.existsSync(SHIFT_REPORTS_DIR)) return 0;

    const settings = getShiftSettings();
    const files = fs.readdirSync(SHIFT_REPORTS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const content = fs.readFileSync(path.join(SHIFT_REPORTS_DIR, file), 'utf8');
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
function calculateRecountPoints(employeeId, employeeName, month) {
  try {
    if (!fs.existsSync(RECOUNT_REPORTS_DIR)) return 0;

    const settings = getRecountSettings();
    const files = fs.readdirSync(RECOUNT_REPORTS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const content = fs.readFileSync(path.join(RECOUNT_REPORTS_DIR, file), 'utf8');
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
function calculateHandoverPoints(employeeId, employeeName, month) {
  try {
    if (!fs.existsSync(HANDOVER_REPORTS_DIR)) return 0;

    const settings = getHandoverSettings();
    const files = fs.readdirSync(HANDOVER_REPORTS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const content = fs.readFileSync(path.join(HANDOVER_REPORTS_DIR, file), 'utf8');
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
function calculateAttendancePoints(employeeId, month) {
  try {
    if (!fs.existsSync(ATTENDANCE_DIR)) return 0;

    const settings = getAttendanceSettings();
    const files = fs.readdirSync(ATTENDANCE_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const content = fs.readFileSync(path.join(ATTENDANCE_DIR, file), 'utf8');
      const record = JSON.parse(content);

      if ((record.employeeId === employeeId || record.phone === employeeId)) {
        const recordDate = record.timestamp || record.createdAt;
        if (recordDate && recordDate.startsWith(month)) {
          // Проверяем вовремя или опоздал
          const points = record.isOnTime ? settings.onTimePoints : settings.latePoints;
          totalPoints += points;
        }
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
function calculateTestPoints(employeeId, employeeName, month) {
  try {
    if (!fs.existsSync(TESTS_DIR)) return 0;

    const settings = getTestSettings();
    const files = fs.readdirSync(TESTS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const content = fs.readFileSync(path.join(TESTS_DIR, file), 'utf8');
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
function calculateReviewsPoints(shopAddress, month) {
  try {
    if (!fs.existsSync(REVIEWS_DIR)) return 0;

    const files = fs.readdirSync(REVIEWS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const content = fs.readFileSync(path.join(REVIEWS_DIR, file), 'utf8');
      const review = JSON.parse(content);

      if (review.shopAddress === shopAddress &&
          review.date && review.date.startsWith(month)) {

        // Положительный отзыв (rating >= 4) = +баллы, отрицательный = -баллы
        const isPositive = review.rating && review.rating >= 4;
        const points = isPositive
          ? DEFAULT_REVIEWS_POINTS.positivePoints
          : DEFAULT_REVIEWS_POINTS.negativePoints;
        totalPoints += points;
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
function calculateProductSearchPoints(employeeId, month) {
  try {
    if (!fs.existsSync(PRODUCT_QUESTIONS_DIR)) return 0;

    const files = fs.readdirSync(PRODUCT_QUESTIONS_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const content = fs.readFileSync(path.join(PRODUCT_QUESTIONS_DIR, file), 'utf8');
      const question = JSON.parse(content);

      if (question.employeeId === employeeId &&
          question.createdAt && question.createdAt.startsWith(month)) {

        // Если ответил - баллы, не ответил - 0
        const answered = question.status === 'answered';
        const points = answered
          ? DEFAULT_PRODUCT_SEARCH_POINTS.answeredPoints
          : DEFAULT_PRODUCT_SEARCH_POINTS.missedPoints;
        totalPoints += points;
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating product search points:', e);
    return 0;
  }
}

/**
 * Рассчитать баллы за РКО
 */
function calculateRkoPoints(shopAddress, month) {
  try {
    if (!fs.existsSync(RKO_DIR)) return 0;

    const settings = getRkoSettings();
    const files = fs.readdirSync(RKO_DIR);
    let totalPoints = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const content = fs.readFileSync(path.join(RKO_DIR, file), 'utf8');
      const rko = JSON.parse(content);

      if (rko.shopAddress === shopAddress &&
          rko.date && rko.date.startsWith(month)) {

        // Есть РКО = баллы, нет РКО = штраф
        const hasRko = rko.hasRko === true;
        const points = hasRko ? settings.hasRkoPoints : settings.noRkoPoints;
        totalPoints += points;
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
function calculateTasksPoints(employeeId, month) {
  try {
    let totalPoints = 0;

    // Разовые задачи
    if (fs.existsSync(TASKS_DIR)) {
      const files = fs.readdirSync(TASKS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;

        const content = fs.readFileSync(path.join(TASKS_DIR, file), 'utf8');
        const task = JSON.parse(content);

        if (task.assignedTo === employeeId &&
            task.completedAt && task.completedAt.startsWith(month)) {
          // TODO: добавить настройки баллов за задачи
          totalPoints += 1.0; // Временно фиксированный балл
        }
      }
    }

    // Циклические задачи
    if (fs.existsSync(RECURRING_TASKS_DIR)) {
      const files = fs.readdirSync(RECURRING_TASKS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;

        const content = fs.readFileSync(path.join(RECURRING_TASKS_DIR, file), 'utf8');
        const task = JSON.parse(content);

        if (task.assignedTo === employeeId) {
          // Подсчитать выполненные задачи за месяц
          const completions = task.completions || [];
          for (const completion of completions) {
            if (completion.completedAt && completion.completedAt.startsWith(month)) {
              totalPoints += 1.0; // Временно фиксированный балл
            }
          }
        }
      }
    }

    return totalPoints;
  } catch (e) {
    console.error('Error calculating tasks points:', e);
    return 0;
  }
}

/**
 * Рассчитать заказы (orders) - TODO: интеграция с Lichi CRM API
 */
function calculateOrdersPoints(employeeId, month) {
  // TODO: Получить заказы из Lichi CRM API
  // Пока возвращаем 0
  return 0;
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
 * @returns {object} - Детальная информация о баллах
 */
function calculateFullEfficiency(employeeId, employeeName, shopAddress, month) {
  try {
    const breakdown = {
      shift: calculateShiftPoints(employeeId, employeeName, month),
      recount: calculateRecountPoints(employeeId, employeeName, month),
      handover: calculateHandoverPoints(employeeId, employeeName, month),
      attendance: calculateAttendancePoints(employeeId, month),
      test: calculateTestPoints(employeeId, employeeName, month),
      reviews: calculateReviewsPoints(shopAddress, month),
      productSearch: calculateProductSearchPoints(employeeId, month),
      rko: calculateRkoPoints(shopAddress, month),
      tasks: calculateTasksPoints(employeeId, month),
      orders: calculateOrdersPoints(employeeId, month),
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

module.exports = {
  calculateFullEfficiency,
  calculateShiftPoints,
  calculateRecountPoints,
  calculateHandoverPoints,
  calculateAttendancePoints,
  calculateTestPoints,
  calculateReviewsPoints,
  calculateProductSearchPoints,
  calculateRkoPoints,
  calculateTasksPoints,
  calculateOrdersPoints,
};
