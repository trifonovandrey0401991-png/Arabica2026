// =====================================================
// RATING & FORTUNE WHEEL API
//
// REFACTORED: Converted from sync to async I/O (2026-02-05)
// =====================================================

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { calculateReferralPointsWithMilestone } = require('./referrals_api');
const { calculateFullEfficiency, initBatchCache, clearBatchCache, calculateFullEfficiencyCached } = require('../efficiency_calc');
const { withLock } = require('../utils/file_lock');
const { requireAuth } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_RATING_WHEEL === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const RATINGS_DIR = path.join(DATA_DIR, 'employee-ratings');
const FORTUNE_WHEEL_DIR = path.join(DATA_DIR, 'fortune-wheel');
const EMPLOYEES_DIR = path.join(DATA_DIR, 'employees');
const ATTENDANCE_DIR = path.join(DATA_DIR, 'attendance');
const EFFICIENCY_DIR = path.join(DATA_DIR, 'efficiency-penalties');

// Хелпер: текущий месяц YYYY-MM
function getCurrentMonth() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

// Хелпер: предыдущий месяц
function getPreviousMonth(monthsBack = 1) {
  const now = new Date();
  now.setMonth(now.getMonth() - monthsBack);
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
}

// Хелпер: название месяца
function getMonthName(monthStr) {
  const months = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
  const [year, month] = monthStr.split('-');
  return `${months[parseInt(month) - 1]} ${year}`;
}

// Получить количество смен сотрудника за месяц (по attendance)
async function getShiftsCount(employeeId, month) {
  try {
    if (!(await fileExists(ATTENDANCE_DIR))) return 0;

    const files = await fsp.readdir(ATTENDANCE_DIR);
    let count = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const filePath = path.join(ATTENDANCE_DIR, file);
      const content = await fsp.readFile(filePath, 'utf8');
      const record = JSON.parse(content);

      // Проверяем что это нужный сотрудник и нужный месяц
      if (record.employeeId === employeeId || record.phone === employeeId) {
        const recordDate = record.timestamp || record.createdAt;
        if (recordDate && recordDate.startsWith(month)) {
          count++;
        }
      }
    }

    return count;
  } catch (e) {
    console.error('Ошибка подсчета смен:', e);
    return 0;
  }
}

// Получить полную эффективность сотрудника за месяц (все 10 категорий)
async function getFullEfficiency(employeeId, employeeName, month) {
  try {
    // Используем модуль efficiency_calc для полного расчёта
    // shopAddress передаём пустым, так как reviews и RKO привязаны к магазину
    const result = await calculateFullEfficiency(employeeId, employeeName, '', month);
    return result;
  } catch (e) {
    console.error('Ошибка подсчета эффективности:', e);
    return { total: 0, breakdown: {} };
  }
}

// Получить баллы за рефералов (с поддержкой милестоунов)
async function getReferralPoints(employeeId, month) {
  try {
    const referralsDir = path.join(DATA_DIR, 'referral-clients');
    if (!(await fileExists(referralsDir))) return 0;

    const files = await fsp.readdir(referralsDir);
    let count = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;
      const content = await fsp.readFile(path.join(referralsDir, file), 'utf8');
      const client = JSON.parse(content);

      if (client.referredByEmployeeId === employeeId &&
          client.referredAt && client.referredAt.startsWith(month)) {
        count++;
      }
    }

    // Получить настройки баллов за рефералов (новый формат с милестоунами)
    const settingsPath = path.join(DATA_DIR, 'points-settings', 'referrals.json');
    let basePoints = 1;
    let milestoneThreshold = 0;
    let milestonePoints = 1;

    if (await fileExists(settingsPath)) {
      const settingsContent = await fsp.readFile(settingsPath, 'utf8');
      const settings = JSON.parse(settingsContent);

      // ОБРАТНАЯ СОВМЕСТИМОСТЬ: старый формат {pointsPerReferral: 1}
      if (settings.pointsPerReferral !== undefined && settings.basePoints === undefined) {
        basePoints = settings.pointsPerReferral;
        milestoneThreshold = 0; // Милестоуны отключены
        milestonePoints = settings.pointsPerReferral;
      } else {
        // Новый формат с милестоунами
        basePoints = settings.basePoints !== undefined ? settings.basePoints : 1;
        milestoneThreshold = settings.milestoneThreshold !== undefined ? settings.milestoneThreshold : 0;
        milestonePoints = settings.milestonePoints !== undefined ? settings.milestonePoints : 1;
      }
    }

    // Рассчитать баллы с учетом милестоунов
    return calculateReferralPointsWithMilestone(count, basePoints, milestoneThreshold, milestonePoints);
  } catch (e) {
    console.error('Ошибка подсчета рефералов:', e);
    return 0;
  }
}

// Получить всех активных сотрудников
async function getActiveEmployees() {
  try {
    if (!(await fileExists(EMPLOYEES_DIR))) return [];

    const files = await fsp.readdir(EMPLOYEES_DIR);
    const employees = [];

    for (const file of files) {
      if (!file.endsWith('.json')) continue;
      const content = await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
      const emp = JSON.parse(content);

      if (!emp.isArchived) {
        employees.push({
          id: emp.id || emp.phone || file.replace('.json', ''),
          name: emp.name || 'Без имени',
          phone: emp.phone || ''
        });
      }
    }

    return employees;
  } catch (e) {
    console.error('Ошибка получения сотрудников:', e);
    return [];
  }
}

// Рассчитать рейтинг для всех сотрудников за месяц
// OPTIMIZED: Загружает все данные ОДИН раз, затем O(n) расчёт
async function calculateRatings(month) {
  const startTime = Date.now();
  console.log(`[Rating] Начало расчёта рейтинга за ${month}`);

  const employees = await getActiveEmployees();
  const ratings = [];

  // OPTIMIZATION: Предзагружаем ВСЕ данные за месяц ОДИН раз
  const cache = await initBatchCache(month);

  // OPTIMIZATION: Загружаем attendance и referral данные ОДИН раз
  const attendanceData = await loadAllAttendanceForMonth(month);
  const referralData = await loadAllReferralsForMonth(month);
  const referralSettings = await loadReferralSettings();

  console.log(`[Rating] Предзагрузка завершена: ${attendanceData.length} attendance, ${referralData.length} referrals`);

  for (const emp of employees) {
    // O(1) подсчёт смен из предзагруженных данных
    const shiftsCount = countShiftsFromCache(emp.id, attendanceData);

    // ПОЛНАЯ эффективность используя кэш (O(n) вместо O(n×m))
    const efficiency = await calculateFullEfficiencyCached(emp.id, emp.name, '', month, cache);
    const totalPoints = efficiency.total;

    // O(1) подсчёт рефералов из предзагруженных данных
    const referralCount = countReferralsFromCache(emp.id, referralData);
    const referralPoints = calculateReferralPointsWithMilestone(
      referralCount,
      referralSettings.basePoints,
      referralSettings.milestoneThreshold,
      referralSettings.milestonePoints
    );

    // Нормализованный рейтинг = (баллы / смены) + рефералы
    const normalizedRating = shiftsCount > 0
      ? (totalPoints / shiftsCount) + referralPoints
      : referralPoints;

    ratings.push({
      employeeId: emp.id,
      employeeName: emp.name,
      totalPoints,
      shiftsCount,
      referralPoints,
      normalizedRating,
      efficiencyBreakdown: efficiency.breakdown, // Детализация по категориям
    });
  }

  // Очищаем batch кэш
  clearBatchCache();

  // Сортировка по нормализованному рейтингу (по убыванию)
  ratings.sort((a, b) => b.normalizedRating - a.normalizedRating);

  // Присвоить позиции
  ratings.forEach((r, i) => {
    r.position = i + 1;
    r.totalEmployees = ratings.length;
  });

  const elapsed = Date.now() - startTime;
  console.log(`[Rating] Расчёт завершён за ${elapsed}ms для ${employees.length} сотрудников`);

  return ratings;
}

// OPTIMIZATION: Загрузить ВСЕ attendance записи за месяц ОДИН раз
async function loadAllAttendanceForMonth(month) {
  const records = [];

  if (!(await fileExists(ATTENDANCE_DIR))) return records;

  try {
    const files = await fsp.readdir(ATTENDANCE_DIR);

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(ATTENDANCE_DIR, file), 'utf8');
        const record = JSON.parse(content);

        const recordDate = record.timestamp || record.createdAt;
        if (recordDate && recordDate.startsWith(month)) {
          records.push(record);
        }
      } catch (e) { /* skip */ }
    }
  } catch (e) {
    console.error('Ошибка загрузки attendance:', e);
  }

  return records;
}

// OPTIMIZATION: Загрузить ВСЕ referral записи за месяц ОДИН раз
async function loadAllReferralsForMonth(month) {
  const referralsDir = path.join(DATA_DIR, 'referral-clients');
  const records = [];

  if (!(await fileExists(referralsDir))) return records;

  try {
    const files = await fsp.readdir(referralsDir);

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fsp.readFile(path.join(referralsDir, file), 'utf8');
        const client = JSON.parse(content);

        if (client.referredAt && client.referredAt.startsWith(month)) {
          records.push(client);
        }
      } catch (e) { /* skip */ }
    }
  } catch (e) {
    console.error('Ошибка загрузки referrals:', e);
  }

  return records;
}

// Загрузить настройки рефералов
async function loadReferralSettings() {
  const settingsPath = path.join(DATA_DIR, 'points-settings', 'referrals.json');

  try {
    if (await fileExists(settingsPath)) {
      const content = await fsp.readFile(settingsPath, 'utf8');
      const settings = JSON.parse(content);

      // ОБРАТНАЯ СОВМЕСТИМОСТЬ
      if (settings.pointsPerReferral !== undefined && settings.basePoints === undefined) {
        return {
          basePoints: settings.pointsPerReferral,
          milestoneThreshold: 0,
          milestonePoints: settings.pointsPerReferral
        };
      }

      return {
        basePoints: settings.basePoints !== undefined ? settings.basePoints : 1,
        milestoneThreshold: settings.milestoneThreshold !== undefined ? settings.milestoneThreshold : 0,
        milestonePoints: settings.milestonePoints !== undefined ? settings.milestonePoints : 1
      };
    }
  } catch (e) {
    console.error('Ошибка загрузки настроек рефералов:', e);
  }

  return { basePoints: 1, milestoneThreshold: 0, milestonePoints: 1 };
}

// O(n) подсчёт смен из кэша вместо O(m) сканирования директории
function countShiftsFromCache(employeeId, attendanceData) {
  let count = 0;

  for (const record of attendanceData) {
    if (record.employeeId === employeeId || record.phone === employeeId) {
      count++;
    }
  }

  return count;
}

// O(n) подсчёт рефералов из кэша
function countReferralsFromCache(employeeId, referralData) {
  let count = 0;

  for (const client of referralData) {
    if (client.referredByEmployeeId === employeeId) {
      count++;
    }
  }

  return count;
}

// Дефолтные секторы колеса
function getDefaultWheelSectors() {
  const colors = [
    '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0', '#9966FF',
    '#FF9F40', '#7CFC00', '#DC143C', '#00CED1', '#FFD700',
    '#8A2BE2', '#20B2AA', '#FF69B4', '#32CD32', '#6495ED'
  ];

  const prizes = [
    'Выходной день', '+500 к премии', 'Бесплатный обед',
    '+300 к премии', 'Сертификат на кофе', '+200 к премии',
    'Раньше уйти', '+100 к премии', 'Десерт в подарок',
    'Скидка 20% на меню', '+150 к премии', 'Кофе бесплатно неделю',
    '+250 к премии', 'Подарок от шефа', 'Позже прийти'
  ];

  return prizes.map((text, i) => ({
    index: i,
    text,
    probability: 1 / 15, // Равная вероятность
    color: colors[i]
  }));
}

// Вспомогательная функция: получить настройки колеса
async function getWheelSettings() {
  try {
    // DB read branch
    if (USE_DB) {
      const row = await db.findById('app_settings', 'fortune_wheel_settings', 'key');
      if (row) {
        const settings = row.data;
        if (!settings.topEmployeesCount) settings.topEmployeesCount = 3;
        return settings;
      }
    }

    const settingsPath = path.join(FORTUNE_WHEEL_DIR, 'settings.json');

    if (await fileExists(settingsPath)) {
      const content = await fsp.readFile(settingsPath, 'utf8');
      const settings = JSON.parse(content);

      // Обратная совместимость: если нет topEmployeesCount, используем дефолт 3
      if (!settings.topEmployeesCount) {
        settings.topEmployeesCount = 3;
      }

      return settings;
    }

    // Дефолтные настройки
    return {
      topEmployeesCount: 3,
      sectors: getDefaultWheelSectors()
    };
  } catch (error) {
    console.error('Ошибка чтения настроек колеса:', error);
    return {
      topEmployeesCount: 3,
      sectors: getDefaultWheelSectors()
    };
  }
}

// Вспомогательная функция: пересчитать прокрутки для текущего месяца
async function recalculateCurrentMonthSpins(month, topCount) {
  try {
    console.log(`🔄 Пересчёт прокруток для месяца ${month}, топ-${topCount} сотрудников`);

    // Читаем текущий рейтинг
    let ratings = null;

    // DB read branch
    if (USE_DB) {
      const row = await db.findById('employee_ratings', month);
      if (row) ratings = row.data.ratings || [];
    }

    if (!ratings) {
      const ratingsPath = path.join(RATINGS_DIR, `${month}.json`);

      if (!(await fileExists(ratingsPath))) {
        console.log(`⚠️ Рейтинг за ${month} не найден, пересчёт прокруток невозможен`);
        return;
      }

      const content = await fsp.readFile(ratingsPath, 'utf8');
      const data = JSON.parse(content);
      ratings = data.ratings || [];
    }

    if (ratings.length === 0) {
      console.log(`⚠️ Рейтинг за ${month} пустой, пересчёт прокруток невозможен`);
      return;
    }

    // Выдаём прокрутки топ-N сотрудникам
    const topN = Math.min(topCount, ratings.length);
    await assignWheelSpins(month, ratings.slice(0, topN));

    console.log(`✅ Прокрутки пересчитаны: топ-${topN} сотрудников получили прокрутки`);
  } catch (error) {
    console.error(`❌ Ошибка пересчёта прокруток для ${month}:`, error);
  }
}

// Вспомогательная функция: выдать прокрутки топ-3
async function assignWheelSpins(month, top3) {
  try {
    const spinsDir = path.join(FORTUNE_WHEEL_DIR, 'spins');
    await fsp.mkdir(spinsDir, { recursive: true });

    // Вычисляем срок истечения: конец следующего месяца после награждаемого
    const [year, monthNum] = month.split('-').map(Number);
    const expiryDate = new Date(year, monthNum + 1, 0, 23, 59, 59); // Последний день следующего месяца
    const expiresAt = expiryDate.toISOString();

    const filePath = path.join(spinsDir, `${month}.json`);
    const spins = {};

    for (let i = 0; i < top3.length; i++) {
      const emp = top3[i];
      const spinCount = i === 0 ? 2 : 1; // 1 место = 2 прокрутки, 2-3 = 1

      spins[emp.employeeId] = {
        employeeName: emp.employeeName,
        position: i + 1,
        available: spinCount,
        used: 0,
        assignedAt: new Date().toISOString(),
        expiresAt
      };
    }

    const data = {
      month,
      assignedAt: new Date().toISOString(),
      expiresAt, // Глобальный срок истечения для всех прокруток
      spins
    };

    await writeJsonFile(filePath, data);

    // DB dual-write
    if (USE_DB) {
      const dbKey = `fortune_wheel_spins_${month}`;
      try { await db.upsert('app_settings', { key: dbKey, data: data, updated_at: new Date().toISOString() }, 'key'); }
      catch (dbErr) { console.error('DB save fortune_wheel_spins error:', dbErr.message); }
    }

    console.log(`✅ Прокрутки выданы топ-3 за ${month} (истекают: ${expiresAt})`);
  } catch (e) {
    console.error('Ошибка выдачи прокруток:', e);
  }
}

// Инициализация API
module.exports = function setupRatingWheelAPI(app) {

  // =====================================================
  // RATING API
  // =====================================================

  // GET /api/ratings - получить рейтинг всех сотрудников за месяц
  app.get('/api/ratings', requireAuth, async (req, res) => {
    try {
      const month = req.query.month || getCurrentMonth();
      const forceRefresh = req.query.forceRefresh === 'true';
      console.log(`📊 GET /api/ratings month=${month} forceRefresh=${forceRefresh}`);

      // Создать директорию если не существует
      await fsp.mkdir(RATINGS_DIR, { recursive: true });

      const filePath = path.join(RATINGS_DIR, `${month}.json`);

      // Проверяем нужно ли использовать кэш
      const currentMonth = getCurrentMonth();
      const shouldCache = month !== currentMonth; // Кэшируем только завершённые месяцы

      // Проверяем есть ли сохраненный рейтинг (если не forceRefresh)
      if (!forceRefresh) {
        // DB read branch
        if (USE_DB) {
          const row = await db.findById('employee_ratings', month);
          if (row) {
            console.log(`✅ Рейтинг загружен из DB (month: ${month})`);
            return res.json({
              success: true,
              ratings: row.data.ratings,
              month,
              monthName: getMonthName(month),
              cached: true,
              calculatedAt: row.data.calculatedAt
            });
          }
        }

        if (await fileExists(filePath)) {
          const content = await fsp.readFile(filePath, 'utf8');
          const data = JSON.parse(content);
          console.log(`✅ Рейтинг загружен из кэша (calculatedAt: ${data.calculatedAt})`);
          return res.json({
            success: true,
            ratings: data.ratings,
            month,
            monthName: getMonthName(month),
            cached: true,
            calculatedAt: data.calculatedAt
          });
        }
      }

      // Рассчитываем рейтинг
      console.log(`🔄 Расчёт рейтинга за ${month}...`);
      const ratings = await calculateRatings(month);

      // Сохраняем в кэш если нужно
      if (shouldCache) {
        const data = {
          month,
          calculatedAt: new Date().toISOString(),
          ratings
        };
        await writeJsonFile(filePath, data);
        console.log(`💾 Рейтинг сохранён в кэш: ${filePath}`);

        // DB dual-write
        if (USE_DB) {
          try { await db.upsert('employee_ratings', { id: month, data: data, updated_at: new Date().toISOString() }); }
          catch (dbErr) { console.error('DB save employee_ratings error:', dbErr.message); }
        }
      }

      res.json({
        success: true,
        ratings,
        month,
        monthName: getMonthName(month),
        calculated: true,
        cached: false
      });
    } catch (error) {
      console.error('❌ Ошибка получения рейтинга:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/ratings/:employeeId - получить рейтинг сотрудника за несколько месяцев
  app.get('/api/ratings/:employeeId', requireAuth, async (req, res) => {
    try {
      const { employeeId } = req.params;
      const monthsCount = parseInt(req.query.months) || 3;

      console.log(`📊 GET /api/ratings/${employeeId} months=${monthsCount}`);

      const result = [];

      for (let i = 0; i < monthsCount; i++) {
        const month = i === 0 ? getCurrentMonth() : getPreviousMonth(i);

        // Получаем рейтинг за месяц
        let ratings;
        const filePath = path.join(RATINGS_DIR, `${month}.json`);

        // DB read branch
        let foundInDb = false;
        if (USE_DB) {
          const row = await db.findById('employee_ratings', month);
          if (row) {
            ratings = row.data.ratings;
            foundInDb = true;
          }
        }

        if (!foundInDb && (await fileExists(filePath))) {
          const content = await fsp.readFile(filePath, 'utf8');
          const data = JSON.parse(content);
          ratings = data.ratings;
        } else if (!foundInDb) {
          ratings = await calculateRatings(month);
        }

        // Находим сотрудника
        const employeeRating = ratings.find(r => r.employeeId === employeeId);

        if (employeeRating) {
          result.push({
            month,
            monthName: getMonthName(month),
            ...employeeRating
          });
        } else {
          result.push({
            month,
            monthName: getMonthName(month),
            employeeId,
            position: 0,
            totalEmployees: ratings.length,
            totalPoints: 0,
            shiftsCount: 0,
            referralPoints: 0,
            normalizedRating: 0
          });
        }
      }

      res.json({ success: true, history: result });
    } catch (error) {
      console.error('❌ Ошибка получения рейтинга сотрудника:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/ratings/cache - очистить кэш рейтингов
  app.delete('/api/ratings/cache', requireAuth, async (req, res) => {
    try {
      const month = req.query.month; // Если не указан - удалить все
      console.log(`🗑️ DELETE /api/ratings/cache month=${month || 'all'}`);

      if (!(await fileExists(RATINGS_DIR))) {
        return res.json({ success: true, message: 'Кэш уже пуст' });
      }

      if (month) {
        // Удалить кэш для конкретного месяца
        const filePath = path.join(RATINGS_DIR, `${month}.json`);
        if (await fileExists(filePath)) {
          await fsp.unlink(filePath);
        }
        // DB delete
        if (USE_DB) {
          try { await db.deleteById('employee_ratings', month); }
          catch (dbErr) { console.error('DB delete employee_ratings error:', dbErr.message); }
        }
        console.log(`✅ Кэш рейтинга за ${month} удалён`);
        return res.json({ success: true, message: `Кэш за ${month} удалён` });
      } else {
        // Удалить весь кэш
        const files = await fsp.readdir(RATINGS_DIR);
        let deletedCount = 0;
        for (const file of files) {
          if (file.endsWith('.json')) {
            await fsp.unlink(path.join(RATINGS_DIR, file));
            const monthKey = file.replace('.json', '');
            // DB delete
            if (USE_DB) {
              try { await db.deleteById('employee_ratings', monthKey); }
              catch (dbErr) { console.error('DB delete employee_ratings error:', dbErr.message); }
            }
            deletedCount++;
          }
        }
        console.log(`✅ Удалено ${deletedCount} файлов кэша`);
        return res.json({ success: true, message: `Удалено ${deletedCount} файлов кэша` });
      }
    } catch (error) {
      console.error('❌ Ошибка очистки кэша:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/ratings/calculate - пересчитать и сохранить рейтинг
  app.post('/api/ratings/calculate', requireAuth, async (req, res) => {
    try {
      const month = req.query.month || getCurrentMonth();
      console.log(`🔄 POST /api/ratings/calculate month=${month}`);

      await fsp.mkdir(RATINGS_DIR, { recursive: true });

      const ratings = await calculateRatings(month);

      const filePath = path.join(RATINGS_DIR, `${month}.json`);
      const data = {
        month,
        calculatedAt: new Date().toISOString(),
        ratings
      };

      await writeJsonFile(filePath, data);

      // DB dual-write
      if (USE_DB) {
        try { await db.upsert('employee_ratings', { id: month, data: data, updated_at: new Date().toISOString() }); }
        catch (dbErr) { console.error('DB save employee_ratings error:', dbErr.message); }
      }

      // Читаем topEmployeesCount из настроек и выдаем прокрутки топ-N
      const wheelSettings = await getWheelSettings();
      const topCount = wheelSettings.topEmployeesCount || 3;

      console.log(`🎡 Выдача прокруток топ-${topCount} сотрудникам`);
      await assignWheelSpins(month, ratings.slice(0, topCount));

      console.log(`✅ Рейтинг за ${month} рассчитан и сохранен`);
      res.json({ success: true, ratings, month });
    } catch (error) {
      console.error('❌ Ошибка расчета рейтинга:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // =====================================================
  // FORTUNE WHEEL API
  // =====================================================

  // GET /api/fortune-wheel/settings - получить настройки секторов
  app.get('/api/fortune-wheel/settings', requireAuth, async (req, res) => {
    try {
      console.log('🎡 GET /api/fortune-wheel/settings');

      await fsp.mkdir(FORTUNE_WHEEL_DIR, { recursive: true });

      // DB read branch
      if (USE_DB) {
        const row = await db.findById('app_settings', 'fortune_wheel_settings', 'key');
        if (row) {
          const settings = row.data;
          if (!settings.topEmployeesCount) settings.topEmployeesCount = 3;
          return res.json({
            success: true,
            sectors: settings.sectors,
            topEmployeesCount: settings.topEmployeesCount
          });
        }
      }

      const filePath = path.join(FORTUNE_WHEEL_DIR, 'settings.json');

      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        const settings = JSON.parse(content);

        // Обратная совместимость: если нет topEmployeesCount, вернуть дефолт
        if (!settings.topEmployeesCount) {
          settings.topEmployeesCount = 3;
        }

        return res.json({
          success: true,
          sectors: settings.sectors,
          topEmployeesCount: settings.topEmployeesCount
        });
      }

      // Возвращаем дефолтные настройки
      const sectors = getDefaultWheelSectors();
      res.json({ success: true, sectors, topEmployeesCount: 3, isDefault: true });
    } catch (error) {
      console.error('❌ Ошибка получения настроек колеса:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/fortune-wheel/settings - обновить настройки секторов (используется приложением)
  app.post('/api/fortune-wheel/settings', requireAuth, async (req, res) => {
    try {
      const { sectors, topEmployeesCount } = req.body;
      console.log('🎡 POST /api/fortune-wheel/settings');

      if (!sectors || !Array.isArray(sectors) || sectors.length !== 15) {
        return res.status(400).json({
          success: false,
          error: 'Необходимо передать массив из 15 секторов'
        });
      }

      // Валидация topEmployeesCount: ограничение 1-10, дефолт 3
      const validatedCount = topEmployeesCount !== undefined
        ? Math.max(1, Math.min(10, topEmployeesCount))
        : 3;

      await fsp.mkdir(FORTUNE_WHEEL_DIR, { recursive: true });

      const filePath = path.join(FORTUNE_WHEEL_DIR, 'settings.json');
      const data = {
        topEmployeesCount: validatedCount,
        sectors,
        updatedAt: new Date().toISOString()
      };

      await writeJsonFile(filePath, data);

      // DB dual-write
      if (USE_DB) {
        try { await db.upsert('app_settings', { key: 'fortune_wheel_settings', data: data, updated_at: data.updatedAt }, 'key'); }
        catch (dbErr) { console.error('DB save fortune_wheel_settings error:', dbErr.message); }
      }

      console.log(`✅ Настройки колеса обновлены (топ-${validatedCount})`);

      // Автоматически пересчитываем прокрутки для текущего месяца
      const currentMonth = getCurrentMonth();
      await recalculateCurrentMonthSpins(currentMonth, validatedCount);

      res.json({ success: true, sectors, topEmployeesCount: validatedCount });
    } catch (error) {
      console.error('❌ Ошибка обновления настроек колеса:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/fortune-wheel/settings - обновить настройки секторов
  app.put('/api/fortune-wheel/settings', requireAuth, async (req, res) => {
    try {
      const { sectors, topEmployeesCount } = req.body;
      console.log('🎡 PUT /api/fortune-wheel/settings');

      if (!sectors || !Array.isArray(sectors) || sectors.length !== 15) {
        return res.status(400).json({
          success: false,
          error: 'Необходимо передать массив из 15 секторов'
        });
      }

      // Валидация topEmployeesCount: ограничение 1-10, дефолт 3
      const validatedCount = topEmployeesCount !== undefined
        ? Math.max(1, Math.min(10, topEmployeesCount))
        : 3;

      await fsp.mkdir(FORTUNE_WHEEL_DIR, { recursive: true });

      const filePath = path.join(FORTUNE_WHEEL_DIR, 'settings.json');
      const data = {
        topEmployeesCount: validatedCount,
        sectors,
        updatedAt: new Date().toISOString()
      };

      await writeJsonFile(filePath, data);

      // DB dual-write
      if (USE_DB) {
        try { await db.upsert('app_settings', { key: 'fortune_wheel_settings', data: data, updated_at: data.updatedAt }, 'key'); }
        catch (dbErr) { console.error('DB save fortune_wheel_settings error:', dbErr.message); }
      }

      console.log(`✅ Настройки колеса обновлены (топ-${validatedCount})`);

      // Автоматически пересчитываем прокрутки для текущего месяца
      const currentMonth = getCurrentMonth();
      await recalculateCurrentMonthSpins(currentMonth, validatedCount);

      res.json({ success: true, sectors, topEmployeesCount: validatedCount });
    } catch (error) {
      console.error('❌ Ошибка обновления настроек колеса:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/fortune-wheel/spins/:employeeId - получить доступные прокрутки
  app.get('/api/fortune-wheel/spins/:employeeId', requireAuth, async (req, res) => {
    try {
      const { employeeId } = req.params;
      console.log(`🎡 GET /api/fortune-wheel/spins/${employeeId}`);

      const now = new Date();
      let totalSpins = 0;
      let latestMonth = null;

      // DB read branch
      if (USE_DB) {
        const rows = await db.query(
          `SELECT "key", "data" FROM "app_settings" WHERE "key" LIKE 'fortune_wheel_spins_%' ORDER BY "key" DESC`
        );
        for (const row of rows.rows) {
          const data = row.data;
          const expiresAt = data.expiresAt || data.spins?.[employeeId]?.expiresAt;
          if (expiresAt && new Date(expiresAt) < now) continue;
          if (data.spins && data.spins[employeeId]) {
            const empSpins = data.spins[employeeId];
            if (empSpins.available > 0) {
              totalSpins += empSpins.available;
              const monthKey = row.key.replace('fortune_wheel_spins_', '');
              if (!latestMonth || monthKey > latestMonth) latestMonth = monthKey;
            }
          }
        }
        return res.json({ success: true, availableSpins: totalSpins, month: latestMonth });
      }

      const spinsDir = path.join(FORTUNE_WHEEL_DIR, 'spins');
      if (!(await fileExists(spinsDir))) {
        return res.json({ success: true, availableSpins: 0, month: null });
      }

      // Ищем прокрутки для этого сотрудника
      const files = await fsp.readdir(spinsDir);

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        const content = await fsp.readFile(path.join(spinsDir, file), 'utf8');
        const data = JSON.parse(content);

        // Проверяем срок истечения
        const expiresAt = data.expiresAt || data.spins?.[employeeId]?.expiresAt;
        if (expiresAt && new Date(expiresAt) < now) {
          console.log(`⏰ Прокрутки для ${file} истекли (${expiresAt})`);
          continue; // Пропускаем истёкшие прокрутки
        }

        if (data.spins && data.spins[employeeId]) {
          const empSpins = data.spins[employeeId];
          if (empSpins.available > 0) {
            totalSpins += empSpins.available;
            if (!latestMonth || file > latestMonth) {
              latestMonth = file.replace('.json', '');
            }
          }
        }
      }

      res.json({
        success: true,
        availableSpins: totalSpins,
        month: latestMonth
      });
    } catch (error) {
      console.error('❌ Ошибка получения прокруток:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/fortune-wheel/spin - прокрутить колесо
  app.post('/api/fortune-wheel/spin', requireAuth, async (req, res) => {
    try {
      const { employeeId, employeeName } = req.body;
      console.log(`🎡 POST /api/fortune-wheel/spin employee=${employeeId}`);

      if (!employeeId) {
        return res.status(400).json({ success: false, error: 'employeeId обязателен' });
      }

      // H-03 fix: блокировка по employeeId для предотвращения race condition
      const lockPath = path.join(FORTUNE_WHEEL_DIR, `spin-lock-${employeeId}`);
      const result = await withLock(lockPath, async () => {
        // Проверяем доступные прокрутки
        const spinsDir = path.join(FORTUNE_WHEEL_DIR, 'spins');
        if (!(await fileExists(spinsDir))) {
          return { status: 400, body: { success: false, error: 'Нет доступных прокруток' } };
        }

        const now = new Date();

        // Находим месяц с доступными прокрутками
        const files = await fsp.readdir(spinsDir);
        let spinMonth = null;
        let spinData = null;
        let spinFilePath = null;

        for (const file of files) {
          if (!file.endsWith('.json')) continue;
          const filePath = path.join(spinsDir, file);
          const content = await fsp.readFile(filePath, 'utf8');
          const data = JSON.parse(content);

          // Проверяем срок истечения
          const expiresAt = data.expiresAt || data.spins?.[employeeId]?.expiresAt;
          if (expiresAt && new Date(expiresAt) < now) {
            console.log(`⏰ Прокрутки для ${file} истекли (${expiresAt}), пропускаем`);
            continue;
          }

          if (data.spins && data.spins[employeeId] && data.spins[employeeId].available > 0) {
            spinMonth = file.replace('.json', '');
            spinData = data;
            spinFilePath = filePath;
            break;
          }
        }

        if (!spinData) {
          return { status: 400, body: { success: false, error: 'Нет доступных прокруток или прокрутки истекли' } };
        }

        // Получаем настройки секторов
        const settingsPath = path.join(FORTUNE_WHEEL_DIR, 'settings.json');
        let sectors;
        if (await fileExists(settingsPath)) {
          const settingsContent = await fsp.readFile(settingsPath, 'utf8');
          const settings = JSON.parse(settingsContent);
          sectors = settings.sectors;
        } else {
          sectors = getDefaultWheelSectors();
        }

        // Выбираем случайный сектор по вероятности
        const totalProb = sectors.reduce((sum, s) => sum + s.probability, 0);
        let random = Math.random() * totalProb;
        let selectedSector = sectors[0];

        for (const sector of sectors) {
          random -= sector.probability;
          if (random <= 0) {
            selectedSector = sector;
            break;
          }
        }

        // Уменьшаем количество прокруток (атомарно внутри lock)
        spinData.spins[employeeId].available--;
        spinData.spins[employeeId].used = (spinData.spins[employeeId].used || 0) + 1;
        await writeJsonFile(spinFilePath, spinData, { useLock: false });

        // DB dual-write (spins)
        if (USE_DB) {
          const dbSpinKey = `fortune_wheel_spins_${spinMonth}`;
          try { await db.upsert('app_settings', { key: dbSpinKey, data: spinData, updated_at: new Date().toISOString() }, 'key'); }
          catch (dbErr) { console.error('DB save fortune_wheel_spins error:', dbErr.message); }
        }

        // Сохраняем в историю
        const historyDir = path.join(FORTUNE_WHEEL_DIR, 'history');
        await fsp.mkdir(historyDir, { recursive: true });

        const currentMonth = getCurrentMonth();
        const historyPath = path.join(historyDir, `${currentMonth}.json`);
        let historyData = { records: [] };
        if (await fileExists(historyPath)) {
          const historyContent = await fsp.readFile(historyPath, 'utf8');
          historyData = JSON.parse(historyContent);
        }

        const spinRecord = {
          id: `spin_${Date.now()}`,
          employeeId,
          employeeName: employeeName || 'Сотрудник',
          rewardMonth: spinMonth,
          position: spinData.spins[employeeId].position,
          sectorIndex: selectedSector.index,
          prize: selectedSector.text,
          spunAt: new Date().toISOString(),
          isProcessed: false,
          processedBy: null,
          processedAt: null
        };

        historyData.records.push(spinRecord);
        await writeJsonFile(historyPath, historyData, { useLock: false });

        // DB dual-write (history)
        if (USE_DB) {
          const dbHistKey = `fortune_wheel_history_${currentMonth}`;
          try { await db.upsert('app_settings', { key: dbHistKey, data: historyData, updated_at: new Date().toISOString() }, 'key'); }
          catch (dbErr) { console.error('DB save fortune_wheel_history error:', dbErr.message); }
        }

        console.log(`✅ Прокрутка: ${employeeName} выиграл "${selectedSector.text}"`);

        return {
          status: 200,
          body: {
            success: true,
            sector: selectedSector,
            remainingSpins: spinData.spins[employeeId].available,
            spinRecord
          }
        };
      });

      res.status(result.status).json(result.body);
    } catch (error) {
      console.error('❌ Ошибка прокрутки колеса:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/fortune-wheel/history - история прокруток
  app.get('/api/fortune-wheel/history', requireAuth, async (req, res) => {
    try {
      const month = req.query.month || getCurrentMonth();
      console.log(`🎡 GET /api/fortune-wheel/history month=${month}`);

      // DB read branch
      if (USE_DB) {
        const dbHistKey = `fortune_wheel_history_${month}`;
        const row = await db.findById('app_settings', dbHistKey, 'key');
        if (row) {
          const records = (row.data.records || []).sort((a, b) =>
            new Date(b.spunAt) - new Date(a.spunAt)
          );
          return res.json({ success: true, records, month, monthName: getMonthName(month) });
        }
      }

      const historyPath = path.join(FORTUNE_WHEEL_DIR, 'history', `${month}.json`);

      if (!(await fileExists(historyPath))) {
        return res.json({ success: true, records: [], month });
      }

      const content = await fsp.readFile(historyPath, 'utf8');
      const data = JSON.parse(content);

      // Сортируем по дате (новые первые)
      const records = (data.records || []).sort((a, b) =>
        new Date(b.spunAt) - new Date(a.spunAt)
      );

      res.json({ success: true, records, month, monthName: getMonthName(month) });
    } catch (error) {
      console.error('❌ Ошибка получения истории:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PATCH /api/fortune-wheel/history/:id/process - отметить приз обработанным
  app.patch('/api/fortune-wheel/history/:id/process', requireAuth, async (req, res) => {
    try {
      const { id } = req.params;
      const { adminName, month } = req.body;
      const targetMonth = month || getCurrentMonth();

      console.log(`🎡 PATCH /api/fortune-wheel/history/${id}/process`);

      const historyPath = path.join(FORTUNE_WHEEL_DIR, 'history', `${targetMonth}.json`);

      if (!(await fileExists(historyPath))) {
        return res.status(404).json({ success: false, error: 'История не найдена' });
      }

      const content = await fsp.readFile(historyPath, 'utf8');
      const data = JSON.parse(content);

      const record = data.records.find(r => r.id === id);
      if (!record) {
        return res.status(404).json({ success: false, error: 'Запись не найдена' });
      }

      record.isProcessed = true;
      record.processedBy = adminName || 'Администратор';
      record.processedAt = new Date().toISOString();

      await writeJsonFile(historyPath, data);

      // DB dual-write
      if (USE_DB) {
        const dbHistKey = `fortune_wheel_history_${targetMonth}`;
        try { await db.upsert('app_settings', { key: dbHistKey, data: data, updated_at: new Date().toISOString() }, 'key'); }
        catch (dbErr) { console.error('DB save fortune_wheel_history error:', dbErr.message); }
      }

      console.log(`✅ Приз ${id} отмечен как обработанный`);
      res.json({ success: true, record });
    } catch (error) {
      console.error('❌ Ошибка обработки приза:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Rating & Fortune Wheel API initialized${USE_DB ? ' [DB mode]' : ''}`);
};
