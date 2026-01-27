// =====================================================
// RATING & FORTUNE WHEEL API
// =====================================================

const fs = require('fs');
const path = require('path');
const { calculateReferralPointsWithMilestone } = require('./referrals_api');
const { calculateFullEfficiency } = require('./efficiency_calc');

const RATINGS_DIR = '/var/www/employee-ratings';
const FORTUNE_WHEEL_DIR = '/var/www/fortune-wheel';
const EMPLOYEES_DIR = '/var/www/employees';
const ATTENDANCE_DIR = '/var/www/attendance';
const EFFICIENCY_DIR = '/var/www/efficiency-penalties';

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
function getShiftsCount(employeeId, month) {
  try {
    const attendanceDir = ATTENDANCE_DIR;
    if (!fs.existsSync(attendanceDir)) return 0;

    const files = fs.readdirSync(attendanceDir);
    let count = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const filePath = path.join(attendanceDir, file);
      const content = fs.readFileSync(filePath, 'utf8');
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
function getFullEfficiency(employeeId, employeeName, month) {
  try {
    // Используем модуль efficiency_calc для полного расчёта
    // shopAddress передаём пустым, так как reviews и RKO привязаны к магазину
    const result = calculateFullEfficiency(employeeId, employeeName, '', month);
    return result;
  } catch (e) {
    console.error('Ошибка подсчета эффективности:', e);
    return { total: 0, breakdown: {} };
  }
}

// Получить баллы за рефералов (с поддержкой милестоунов)
function getReferralPoints(employeeId, month) {
  try {
    const referralsDir = '/var/www/referral-clients';
    if (!fs.existsSync(referralsDir)) return 0;

    const files = fs.readdirSync(referralsDir);
    let count = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;
      const content = fs.readFileSync(path.join(referralsDir, file), 'utf8');
      const client = JSON.parse(content);

      if (client.referredByEmployeeId === employeeId &&
          client.referredAt && client.referredAt.startsWith(month)) {
        count++;
      }
    }

    // Получить настройки баллов за рефералов (новый формат с милестоунами)
    const settingsPath = '/var/www/points-settings/referrals.json';
    let basePoints = 1;
    let milestoneThreshold = 0;
    let milestonePoints = 1;

    if (fs.existsSync(settingsPath)) {
      const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));

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
function getActiveEmployees() {
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) return [];

    const files = fs.readdirSync(EMPLOYEES_DIR);
    const employees = [];

    for (const file of files) {
      if (!file.endsWith('.json')) continue;
      const content = fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8');
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
function calculateRatings(month) {
  const employees = getActiveEmployees();
  const ratings = [];

  for (const emp of employees) {
    // Подсчёт смен для нормализации
    const shiftsCount = getShiftsCount(emp.id, month);

    // ПОЛНАЯ эффективность (все 10 категорий)
    const efficiency = getFullEfficiency(emp.id, emp.name, month);
    const totalPoints = efficiency.total;

    // Рефералы с милестоунами
    const referralPoints = getReferralPoints(emp.id, month);

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

  // Сортировка по нормализованному рейтингу (по убыванию)
  ratings.sort((a, b) => b.normalizedRating - a.normalizedRating);

  // Присвоить позиции
  ratings.forEach((r, i) => {
    r.position = i + 1;
    r.totalEmployees = ratings.length;
  });

  return ratings;
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

// Инициализация API
module.exports = function setupRatingWheelAPI(app) {

  // =====================================================
  // RATING API
  // =====================================================

  // GET /api/ratings - получить рейтинг всех сотрудников за месяц
  app.get('/api/ratings', async (req, res) => {
    try {
      const month = req.query.month || getCurrentMonth();
      console.log(`📊 GET /api/ratings month=${month}`);

      // Проверяем есть ли сохраненный рейтинг
      const filePath = path.join(RATINGS_DIR, `${month}.json`);

      if (fs.existsSync(filePath)) {
        const content = fs.readFileSync(filePath, 'utf8');
        const data = JSON.parse(content);
        return res.json({ success: true, ratings: data.ratings, month, monthName: getMonthName(month) });
      }

      // Рассчитываем рейтинг
      const ratings = calculateRatings(month);

      res.json({
        success: true,
        ratings,
        month,
        monthName: getMonthName(month),
        calculated: true
      });
    } catch (error) {
      console.error('❌ Ошибка получения рейтинга:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/ratings/:employeeId - получить рейтинг сотрудника за несколько месяцев
  app.get('/api/ratings/:employeeId', async (req, res) => {
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

        if (fs.existsSync(filePath)) {
          const content = fs.readFileSync(filePath, 'utf8');
          const data = JSON.parse(content);
          ratings = data.ratings;
        } else {
          ratings = calculateRatings(month);
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

  // POST /api/ratings/calculate - пересчитать и сохранить рейтинг
  app.post('/api/ratings/calculate', async (req, res) => {
    try {
      const month = req.query.month || getCurrentMonth();
      console.log(`🔄 POST /api/ratings/calculate month=${month}`);

      if (!fs.existsSync(RATINGS_DIR)) {
        fs.mkdirSync(RATINGS_DIR, { recursive: true });
      }

      const ratings = calculateRatings(month);

      const filePath = path.join(RATINGS_DIR, `${month}.json`);
      const data = {
        month,
        calculatedAt: new Date().toISOString(),
        ratings
      };

      fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');

      // Выдаем прокрутки топ-3
      await assignWheelSpins(month, ratings.slice(0, 3));

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
  app.get('/api/fortune-wheel/settings', async (req, res) => {
    try {
      console.log('🎡 GET /api/fortune-wheel/settings');

      const settingsDir = FORTUNE_WHEEL_DIR;
      if (!fs.existsSync(settingsDir)) {
        fs.mkdirSync(settingsDir, { recursive: true });
      }

      const filePath = path.join(settingsDir, 'settings.json');

      if (fs.existsSync(filePath)) {
        const content = fs.readFileSync(filePath, 'utf8');
        const settings = JSON.parse(content);
        return res.json({ success: true, sectors: settings.sectors });
      }

      // Возвращаем дефолтные настройки
      const sectors = getDefaultWheelSectors();
      res.json({ success: true, sectors, isDefault: true });
    } catch (error) {
      console.error('❌ Ошибка получения настроек колеса:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/fortune-wheel/settings - обновить настройки секторов
  app.put('/api/fortune-wheel/settings', async (req, res) => {
    try {
      const { sectors } = req.body;
      console.log('🎡 PUT /api/fortune-wheel/settings');

      if (!sectors || !Array.isArray(sectors) || sectors.length !== 15) {
        return res.status(400).json({
          success: false,
          error: 'Необходимо передать массив из 15 секторов'
        });
      }

      if (!fs.existsSync(FORTUNE_WHEEL_DIR)) {
        fs.mkdirSync(FORTUNE_WHEEL_DIR, { recursive: true });
      }

      const filePath = path.join(FORTUNE_WHEEL_DIR, 'settings.json');
      const data = {
        sectors,
        updatedAt: new Date().toISOString()
      };

      fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');

      console.log('✅ Настройки колеса обновлены');
      res.json({ success: true, sectors });
    } catch (error) {
      console.error('❌ Ошибка обновления настроек колеса:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/fortune-wheel/spins/:employeeId - получить доступные прокрутки
  app.get('/api/fortune-wheel/spins/:employeeId', async (req, res) => {
    try {
      const { employeeId } = req.params;
      console.log(`🎡 GET /api/fortune-wheel/spins/${employeeId}`);

      const spinsDir = path.join(FORTUNE_WHEEL_DIR, 'spins');
      if (!fs.existsSync(spinsDir)) {
        return res.json({ success: true, availableSpins: 0, month: null });
      }

      // Ищем прокрутки для этого сотрудника
      const files = fs.readdirSync(spinsDir);
      let totalSpins = 0;
      let latestMonth = null;

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        const content = fs.readFileSync(path.join(spinsDir, file), 'utf8');
        const data = JSON.parse(content);

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
  app.post('/api/fortune-wheel/spin', async (req, res) => {
    try {
      const { employeeId, employeeName } = req.body;
      console.log(`🎡 POST /api/fortune-wheel/spin employee=${employeeId}`);

      if (!employeeId) {
        return res.status(400).json({ success: false, error: 'employeeId обязателен' });
      }

      // Проверяем доступные прокрутки
      const spinsDir = path.join(FORTUNE_WHEEL_DIR, 'spins');
      if (!fs.existsSync(spinsDir)) {
        return res.status(400).json({ success: false, error: 'Нет доступных прокруток' });
      }

      // Находим месяц с доступными прокрутками
      const files = fs.readdirSync(spinsDir);
      let spinMonth = null;
      let spinData = null;
      let spinFilePath = null;

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        const filePath = path.join(spinsDir, file);
        const content = fs.readFileSync(filePath, 'utf8');
        const data = JSON.parse(content);

        if (data.spins && data.spins[employeeId] && data.spins[employeeId].available > 0) {
          spinMonth = file.replace('.json', '');
          spinData = data;
          spinFilePath = filePath;
          break;
        }
      }

      if (!spinData) {
        return res.status(400).json({ success: false, error: 'Нет доступных прокруток' });
      }

      // Получаем настройки секторов
      const settingsPath = path.join(FORTUNE_WHEEL_DIR, 'settings.json');
      let sectors;
      if (fs.existsSync(settingsPath)) {
        const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
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

      // Уменьшаем количество прокруток
      spinData.spins[employeeId].available--;
      spinData.spins[employeeId].used = (spinData.spins[employeeId].used || 0) + 1;
      fs.writeFileSync(spinFilePath, JSON.stringify(spinData, null, 2), 'utf8');

      // Сохраняем в историю
      const historyDir = path.join(FORTUNE_WHEEL_DIR, 'history');
      if (!fs.existsSync(historyDir)) {
        fs.mkdirSync(historyDir, { recursive: true });
      }

      const currentMonth = getCurrentMonth();
      const historyPath = path.join(historyDir, `${currentMonth}.json`);
      let historyData = { records: [] };
      if (fs.existsSync(historyPath)) {
        historyData = JSON.parse(fs.readFileSync(historyPath, 'utf8'));
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
      fs.writeFileSync(historyPath, JSON.stringify(historyData, null, 2), 'utf8');

      console.log(`✅ Прокрутка: ${employeeName} выиграл "${selectedSector.text}"`);

      res.json({
        success: true,
        sector: selectedSector,
        remainingSpins: spinData.spins[employeeId].available,
        spinRecord
      });
    } catch (error) {
      console.error('❌ Ошибка прокрутки колеса:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/fortune-wheel/history - история прокруток
  app.get('/api/fortune-wheel/history', async (req, res) => {
    try {
      const month = req.query.month || getCurrentMonth();
      console.log(`🎡 GET /api/fortune-wheel/history month=${month}`);

      const historyPath = path.join(FORTUNE_WHEEL_DIR, 'history', `${month}.json`);

      if (!fs.existsSync(historyPath)) {
        return res.json({ success: true, records: [], month });
      }

      const content = fs.readFileSync(historyPath, 'utf8');
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
  app.patch('/api/fortune-wheel/history/:id/process', async (req, res) => {
    try {
      const { id } = req.params;
      const { adminName, month } = req.body;
      const targetMonth = month || getCurrentMonth();

      console.log(`🎡 PATCH /api/fortune-wheel/history/${id}/process`);

      const historyPath = path.join(FORTUNE_WHEEL_DIR, 'history', `${targetMonth}.json`);

      if (!fs.existsSync(historyPath)) {
        return res.status(404).json({ success: false, error: 'История не найдена' });
      }

      const content = fs.readFileSync(historyPath, 'utf8');
      const data = JSON.parse(content);

      const record = data.records.find(r => r.id === id);
      if (!record) {
        return res.status(404).json({ success: false, error: 'Запись не найдена' });
      }

      record.isProcessed = true;
      record.processedBy = adminName || 'Администратор';
      record.processedAt = new Date().toISOString();

      fs.writeFileSync(historyPath, JSON.stringify(data, null, 2), 'utf8');

      console.log(`✅ Приз ${id} отмечен как обработанный`);
      res.json({ success: true, record });
    } catch (error) {
      console.error('❌ Ошибка обработки приза:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Rating & Fortune Wheel API initialized');
};

// Вспомогательная функция: выдать прокрутки топ-3
async function assignWheelSpins(month, top3) {
  try {
    const spinsDir = path.join(FORTUNE_WHEEL_DIR, 'spins');
    if (!fs.existsSync(spinsDir)) {
      fs.mkdirSync(spinsDir, { recursive: true });
    }

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
        assignedAt: new Date().toISOString()
      };
    }

    const data = {
      month,
      assignedAt: new Date().toISOString(),
      spins
    };

    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
    console.log(`✅ Прокрутки выданы топ-3 за ${month}`);
  } catch (e) {
    console.error('Ошибка выдачи прокруток:', e);
  }
}
