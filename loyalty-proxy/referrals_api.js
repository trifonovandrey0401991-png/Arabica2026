// =====================================================
// REFERRALS API (Реферальная система)
// =====================================================

const fs = require('fs');
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || DATA_DIR;

const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const CLIENTS_DIR = `${DATA_DIR}/clients`;
const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;
const REFERRALS_VIEWED_FILE = `${DATA_DIR}/referrals-viewed.json`;
const REFERRALS_CACHE_FILE = `${DATA_DIR}/cache/referral-stats/stats.json`;
const CACHE_VALIDITY_MINUTES = 5; // Кэш актуален 5 минут

// Создаем директории если нет
if (!fs.existsSync(POINTS_SETTINGS_DIR)) {
  fs.mkdirSync(POINTS_SETTINGS_DIR, { recursive: true });
}

const cacheDir = path.dirname(REFERRALS_CACHE_FILE);
if (!fs.existsSync(cacheDir)) {
  fs.mkdirSync(cacheDir, { recursive: true });
}

// =====================================================
// ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
// =====================================================

// Получить следующий свободный referralCode (ФАЗА 1.2: с переиспользованием)
function getNextReferralCode() {
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) return 1;

    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));
    const usedCodes = new Set(); // Коды активных сотрудников
    const inactiveCodes = []; // Коды уволенных/неактивных сотрудников

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8');
        const employee = JSON.parse(content);

        if (employee.referralCode) {
          // Если сотрудник активен - код занят
          if (employee.isActive === true || employee.isActive === undefined) {
            usedCodes.add(employee.referralCode);
          } else {
            // Если сотрудник неактивен - код можно переиспользовать
            inactiveCodes.push(employee.referralCode);
          }
        }
      } catch (e) {
        // Игнорируем ошибки чтения
      }
    }

    // Приоритет 1: переиспользуем код уволенного сотрудника
    if (inactiveCodes.length > 0) {
      const recycledCode = Math.min(...inactiveCodes); // Берем наименьший код
      console.log(`♻️ Переиспользуем код ${recycledCode} от неактивного сотрудника`);
      return recycledCode;
    }

    // Приоритет 2: ищем свободный код от 1 до 10000 (увеличен лимит!)
    for (let code = 1; code <= 10000; code++) {
      if (!usedCodes.has(code)) {
        return code;
      }
    }

    return null; // Все коды заняты (маловероятно)
  } catch (error) {
    console.error('Ошибка получения следующего referralCode:', error);
    return 1;
  }
}

// Найти сотрудника по referralCode
function findEmployeeByReferralCode(code) {
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) return null;

    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8');
        const employee = JSON.parse(content);
        if (employee.referralCode === code) {
          return employee;
        }
      } catch (e) {
        // Игнорируем ошибки чтения
      }
    }

    return null;
  } catch (error) {
    console.error('Ошибка поиска по referralCode:', error);
    return null;
  }
}

// Получить всех клиентов
function getAllClients() {
  try {
    if (!fs.existsSync(CLIENTS_DIR)) return [];

    const files = fs.readdirSync(CLIENTS_DIR).filter(f => f.endsWith('.json'));
    const clients = [];

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(CLIENTS_DIR, file), 'utf8');
        const client = JSON.parse(content);
        clients.push(client);
      } catch (e) {
        // Игнорируем ошибки чтения
      }
    }

    return clients;
  } catch (error) {
    console.error('Ошибка получения клиентов:', error);
    return [];
  }
}

// Получить всех сотрудников
function getAllEmployees() {
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) return [];

    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));
    const employees = [];

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8');
        const employee = JSON.parse(content);
        employees.push(employee);
      } catch (e) {
        // Игнорируем ошибки чтения
      }
    }

    return employees;
  } catch (error) {
    console.error('Ошибка получения сотрудников:', error);
    return [];
  }
}

// Подсчитать статистику приглашений для сотрудника
function calculateReferralStats(referralCode, clients) {
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const currentMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const prevMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const prevMonthEnd = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59, 999);

  let today = 0;
  let currentMonth = 0;
  let previousMonth = 0;
  let total = 0;
  const referredClients = [];

  for (const client of clients) {
    if (client.referredBy === referralCode) {
      total++;

      const referredAt = client.referredAt ? new Date(client.referredAt) : null;

      if (referredAt) {
        referredClients.push({
          phone: client.phone,
          name: client.name || client.clientName || '',
          referredAt: client.referredAt
        });

        if (referredAt >= todayStart) {
          today++;
        }
        if (referredAt >= currentMonthStart) {
          currentMonth++;
        }
        if (referredAt >= prevMonthStart && referredAt <= prevMonthEnd) {
          previousMonth++;
        }
      } else {
        // Если нет referredAt, считаем по createdAt
        const createdAt = client.createdAt ? new Date(client.createdAt) : null;
        if (createdAt) {
          referredClients.push({
            phone: client.phone,
            name: client.name || client.clientName || '',
            referredAt: client.createdAt
          });

          if (createdAt >= todayStart) {
            today++;
          }
          if (createdAt >= currentMonthStart) {
            currentMonth++;
          }
          if (createdAt >= prevMonthStart && createdAt <= prevMonthEnd) {
            previousMonth++;
          }
        }
      }
    }
  }

  // Сортируем клиентов по дате (новые первые)
  referredClients.sort((a, b) => new Date(b.referredAt) - new Date(a.referredAt));

  return {
    today,
    currentMonth,
    previousMonth,
    total,
    clients: referredClients
  };
}

// Получить дату последнего просмотра приглашений
function getLastViewedAt() {
  try {
    if (fs.existsSync(REFERRALS_VIEWED_FILE)) {
      const data = JSON.parse(fs.readFileSync(REFERRALS_VIEWED_FILE, 'utf8'));
      return data.lastViewedAt ? new Date(data.lastViewedAt) : null;
    }
    return null;
  } catch (error) {
    console.error('Ошибка чтения lastViewedAt:', error);
    return null;
  }
}

// Сохранить дату последнего просмотра
function saveLastViewedAt(date) {
  try {
    fs.writeFileSync(REFERRALS_VIEWED_FILE, JSON.stringify({
      lastViewedAt: date.toISOString()
    }, null, 2), 'utf8');
    return true;
  } catch (error) {
    console.error('Ошибка записи lastViewedAt:', error);
    return false;
  }
}

// Подсчёт непросмотренных приглашений
function countUnviewedReferrals(clients, employees, lastViewedAt) {
  let totalCount = 0;
  const byEmployee = {};

  // Создаём карту referralCode -> employeeId
  const codeToEmployeeId = {};
  for (const employee of employees) {
    if (employee.referralCode) {
      codeToEmployeeId[employee.referralCode] = employee.id;
    }
  }

  for (const client of clients) {
    if (!client.referredBy) continue;

    const referredAt = client.referredAt ? new Date(client.referredAt) : null;
    if (!referredAt) continue;

    // Если lastViewedAt не задано - считаем все новыми
    // Если задано - считаем только те, что после lastViewedAt
    if (!lastViewedAt || referredAt > lastViewedAt) {
      totalCount++;

      const employeeId = codeToEmployeeId[client.referredBy];
      if (employeeId) {
        byEmployee[employeeId] = (byEmployee[employeeId] || 0) + 1;
      }
    }
  }

  return { count: totalCount, byEmployee };
}

// =====================================================
// АНТИФРОД (ФАЗА 1.3)
// =====================================================

const DAILY_REFERRAL_LIMIT = 20; // Максимум приглашений в день от одного сотрудника
const ANTIFRAUD_LOG_FILE = `${DATA_DIR}/logs/referral-antifraud.log`;

// Проверка лимита приглашений для referralCode
function checkReferralLimit(referralCode) {
  try {
    const clients = getAllClients();
    const today = new Date();
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());

    // Считаем приглашения от этого кода сегодня
    let todayCount = 0;
    for (const client of clients) {
      if (client.referredBy === referralCode) {
        const referredAt = client.referredAt ? new Date(client.referredAt) :
                          (client.createdAt ? new Date(client.createdAt) : null);
        if (referredAt && referredAt >= todayStart) {
          todayCount++;
        }
      }
    }

    const limitExceeded = todayCount >= DAILY_REFERRAL_LIMIT;

    if (limitExceeded) {
      const employee = findEmployeeByReferralCode(referralCode);
      const employeeName = employee ? employee.name : `Код ${referralCode}`;
      console.warn(`⚠️ АНТИФРОД: Превышен лимит приглашений для ${employeeName}: ${todayCount}/${DAILY_REFERRAL_LIMIT}`);

      // Логируем в файл
      logAntifraud(`LIMIT_EXCEEDED: referralCode=${referralCode}, employee=${employeeName}, count=${todayCount}`);
    }

    return {
      allowed: !limitExceeded,
      todayCount,
      limit: DAILY_REFERRAL_LIMIT,
      remaining: Math.max(0, DAILY_REFERRAL_LIMIT - todayCount)
    };
  } catch (error) {
    console.error('Ошибка проверки лимита рефералов:', error);
    // В случае ошибки разрешаем (не блокируем легитимных пользователей)
    return { allowed: true, todayCount: 0, limit: DAILY_REFERRAL_LIMIT, remaining: DAILY_REFERRAL_LIMIT };
  }
}

// Логирование подозрительной активности
function logAntifraud(message) {
  try {
    const logDir = path.dirname(ANTIFRAUD_LOG_FILE);
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }

    const timestamp = new Date().toISOString();
    const logLine = `[${timestamp}] ${message}\n`;

    fs.appendFileSync(ANTIFRAUD_LOG_FILE, logLine, 'utf8');
  } catch (error) {
    console.error('Ошибка записи в лог антифрода:', error);
  }
}

// =====================================================
// КЭШИРОВАНИЕ СТАТИСТИКИ (ФАЗА 1.1)
// =====================================================

// Прочитать кэш статистики
function readStatsCache() {
  try {
    if (fs.existsSync(REFERRALS_CACHE_FILE)) {
      const data = JSON.parse(fs.readFileSync(REFERRALS_CACHE_FILE, 'utf8'));
      return data;
    }
    return null;
  } catch (error) {
    console.error('Ошибка чтения кэша статистики:', error);
    return null;
  }
}

// Проверить актуальность кэша
function isCacheValid(cache) {
  if (!cache || !cache.lastUpdated) return false;

  const cacheTime = new Date(cache.lastUpdated);
  const now = new Date();
  const diffMinutes = (now - cacheTime) / (1000 * 60);

  return diffMinutes < CACHE_VALIDITY_MINUTES;
}

// Пересчитать и сохранить кэш статистики
function rebuildStatsCache() {
  try {
    console.log('🔄 Пересчет кэша статистики рефералов...');

    const employees = getAllEmployees();
    const clients = getAllClients();
    const statsMap = {};

    // Считаем статистику для каждого сотрудника с referralCode
    for (const employee of employees) {
      if (employee.referralCode) {
        const stats = calculateReferralStats(employee.referralCode, clients);
        statsMap[employee.id] = {
          employeeId: employee.id,
          employeeName: employee.name,
          referralCode: employee.referralCode,
          today: stats.today,
          currentMonth: stats.currentMonth,
          previousMonth: stats.previousMonth,
          total: stats.total,
          clients: stats.clients // Сохраняем список клиентов в кэше
        };
      }
    }

    const cache = {
      lastUpdated: new Date().toISOString(),
      stats: statsMap,
      totalClients: clients.length,
      unassignedCount: clients.filter(c => !c.referredBy).length
    };

    fs.writeFileSync(REFERRALS_CACHE_FILE, JSON.stringify(cache, null, 2), 'utf8');
    console.log(`✅ Кэш статистики обновлен: ${Object.keys(statsMap).length} сотрудников`);

    return cache;
  } catch (error) {
    console.error('❌ Ошибка пересчета кэша:', error);
    return null;
  }
}

// Получить статистику (с кэшированием)
function getCachedStats(forceRefresh = false) {
  const cache = readStatsCache();

  // Если кэш валиден и не требуется принудительное обновление
  if (!forceRefresh && cache && isCacheValid(cache)) {
    console.log('✅ Используем кэш статистики (актуален)');
    return cache;
  }

  // Иначе пересчитываем
  return rebuildStatsCache();
}

// Инвалидировать кэш (вызывается при создании клиента с referredBy)
function invalidateStatsCache() {
  try {
    if (fs.existsSync(REFERRALS_CACHE_FILE)) {
      fs.unlinkSync(REFERRALS_CACHE_FILE);
      console.log('🗑️ Кэш статистики инвалидирован');
    }
  } catch (error) {
    console.error('Ошибка инвалидации кэша:', error);
  }
}

// =====================================================
// ЭКСПОРТ ФУНКЦИИ НАСТРОЙКИ API
// =====================================================

function setupReferralsAPI(app) {

  // GET /api/referrals/unviewed-count - количество непросмотренных приглашений
  app.get('/api/referrals/unviewed-count', (req, res) => {
    try {
      console.log('GET /api/referrals/unviewed-count');

      const clients = getAllClients();
      const employees = getAllEmployees();
      const lastViewedAt = getLastViewedAt();

      const result = countUnviewedReferrals(clients, employees, lastViewedAt);

      res.json({
        success: true,
        count: result.count,
        byEmployee: result.byEmployee
      });
    } catch (error) {
      console.error('Ошибка получения непросмотренных:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/referrals/mark-as-viewed - отметить приглашения как просмотренные
  app.post('/api/referrals/mark-as-viewed', (req, res) => {
    try {
      console.log('POST /api/referrals/mark-as-viewed');

      const success = saveLastViewedAt(new Date());

      res.json({ success });
    } catch (error) {
      console.error('Ошибка отметки как просмотренные:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/referrals/next-code - получить следующий свободный код
  app.get('/api/referrals/next-code', (req, res) => {
    try {
      console.log('GET /api/referrals/next-code');
      const nextCode = getNextReferralCode();
      res.json({ success: true, nextCode });
    } catch (error) {
      console.error('Ошибка получения следующего кода:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/referrals/validate-code/:code - валидация кода (ФАЗА 1.2: лимит 10000)
  app.get('/api/referrals/validate-code/:code', (req, res) => {
    try {
      const code = parseInt(req.params.code, 10);
      console.log(`GET /api/referrals/validate-code/${code}`);

      if (isNaN(code) || code < 1 || code > 10000) {
        return res.json({ success: true, valid: false, message: 'Код должен быть от 1 до 10000' });
      }

      const employee = findEmployeeByReferralCode(code);

      if (employee) {
        res.json({
          success: true,
          valid: true,
          employee: {
            id: employee.id,
            name: employee.name,
            referralCode: employee.referralCode
          }
        });
      } else {
        res.json({ success: true, valid: false, message: 'Сотрудник с таким кодом не найден' });
      }
    } catch (error) {
      console.error('Ошибка валидации кода:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/referrals/stats - статистика всех сотрудников (с кэшированием)
  app.get('/api/referrals/stats', (req, res) => {
    try {
      const forceRefresh = req.query.refresh === 'true';
      console.log(`GET /api/referrals/stats (refresh=${forceRefresh})`);

      const cache = getCachedStats(forceRefresh);

      if (!cache) {
        return res.status(500).json({ success: false, error: 'Не удалось получить статистику' });
      }

      // Преобразуем statsMap в массив для клиента
      const employeeStats = Object.values(cache.stats).map(stat => ({
        employeeId: stat.employeeId,
        employeeName: stat.employeeName,
        referralCode: stat.referralCode,
        today: stat.today,
        currentMonth: stat.currentMonth,
        previousMonth: stat.previousMonth,
        total: stat.total
      }));

      // Сортируем по общему количеству (убывание)
      employeeStats.sort((a, b) => b.total - a.total);

      res.json({
        success: true,
        totalClients: cache.totalClients,
        unassignedCount: cache.unassignedCount,
        employeeStats,
        cached: true,
        lastUpdated: cache.lastUpdated
      });
    } catch (error) {
      console.error('Ошибка получения статистики:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/referrals/stats/:employeeId - статистика одного сотрудника (с кэшированием)
  app.get('/api/referrals/stats/:employeeId', (req, res) => {
    try {
      const { employeeId } = req.params;
      const forceRefresh = req.query.refresh === 'true';
      console.log(`GET /api/referrals/stats/${employeeId} (refresh=${forceRefresh})`);

      // Ищем сотрудника
      const employeeFile = path.join(EMPLOYEES_DIR, `${employeeId}.json`);
      if (!fs.existsSync(employeeFile)) {
        return res.status(404).json({ success: false, error: 'Сотрудник не найден' });
      }

      const employee = JSON.parse(fs.readFileSync(employeeFile, 'utf8'));

      if (!employee.referralCode) {
        return res.json({
          success: true,
          employeeId: employee.id,
          employeeName: employee.name,
          referralCode: null,
          stats: {
            today: 0,
            currentMonth: 0,
            previousMonth: 0,
            total: 0,
            clients: []
          },
          cached: false
        });
      }

      // Пытаемся получить из кэша
      const cache = getCachedStats(forceRefresh);

      if (cache && cache.stats[employeeId]) {
        const cachedStats = cache.stats[employeeId];
        res.json({
          success: true,
          employeeId: employee.id,
          employeeName: employee.name,
          referralCode: employee.referralCode,
          stats: {
            today: cachedStats.today,
            currentMonth: cachedStats.currentMonth,
            previousMonth: cachedStats.previousMonth,
            total: cachedStats.total,
            clients: cachedStats.clients
          },
          cached: true,
          lastUpdated: cache.lastUpdated
        });
      } else {
        // Если кэша нет или сотрудник не в кэше - считаем напрямую
        console.warn(`⚠️ Сотрудник ${employeeId} не найден в кэше, считаем напрямую`);
        const clients = getAllClients();
        const stats = calculateReferralStats(employee.referralCode, clients);

        res.json({
          success: true,
          employeeId: employee.id,
          employeeName: employee.name,
          referralCode: employee.referralCode,
          stats,
          cached: false
        });
      }
    } catch (error) {
      console.error('Ошибка получения статистики сотрудника:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/referrals/clients/:referralCode - список клиентов сотрудника по коду
  app.get('/api/referrals/clients/:referralCode', (req, res) => {
    try {
      const code = parseInt(req.params.referralCode, 10);
      console.log(`GET /api/referrals/clients/${code}`);

      if (isNaN(code)) {
        return res.status(400).json({ success: false, error: 'Некорректный код' });
      }

      const clients = getAllClients();
      const referredClients = clients
        .filter(c => c.referredBy === code)
        .map(c => ({
          phone: c.phone,
          name: c.name || c.clientName || '',
          referredAt: c.referredAt || c.createdAt
        }))
        .sort((a, b) => new Date(b.referredAt) - new Date(a.referredAt));

      res.json({
        success: true,
        referralCode: code,
        clients: referredClients,
        total: referredClients.length
      });
    } catch (error) {
      console.error('Ошибка получения клиентов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/referrals/unassigned - количество неучтенных клиентов
  app.get('/api/referrals/unassigned', (req, res) => {
    try {
      console.log('GET /api/referrals/unassigned');

      const clients = getAllClients();
      const unassigned = clients.filter(c => !c.referredBy);

      res.json({
        success: true,
        count: unassigned.length,
        clients: unassigned.map(c => ({
          phone: c.phone,
          name: c.name || c.clientName || '',
          createdAt: c.createdAt
        })).sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
      });
    } catch (error) {
      console.error('Ошибка получения неучтенных:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/points-settings/referrals - настройки баллов за приглашения
  app.get('/api/points-settings/referrals', (req, res) => {
    try {
      console.log('GET /api/points-settings/referrals');

      const settingsFile = path.join(POINTS_SETTINGS_DIR, 'referrals.json');

      if (fs.existsSync(settingsFile)) {
        const settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));

        // ОБРАТНАЯ СОВМЕСТИМОСТЬ: старый формат {pointsPerReferral: 1} -> новый формат
        if (settings.pointsPerReferral !== undefined && settings.basePoints === undefined) {
          const compatibleSettings = {
            basePoints: settings.pointsPerReferral,
            milestoneThreshold: 0, // Милестоуны отключены
            milestonePoints: settings.pointsPerReferral,
            updatedAt: settings.updatedAt || new Date().toISOString()
          };
          res.json({ success: true, settings: compatibleSettings });
        } else {
          // Новый формат уже есть
          res.json({ success: true, settings });
        }
      } else {
        // Дефолтные настройки (новый формат)
        const defaultSettings = {
          basePoints: 1,
          milestoneThreshold: 0, // Милестоуны отключены по умолчанию
          milestonePoints: 1,
          updatedAt: new Date().toISOString()
        };
        res.json({ success: true, settings: defaultSettings });
      }
    } catch (error) {
      console.error('Ошибка получения настроек:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/referrals - обновить настройки
  app.post('/api/points-settings/referrals', (req, res) => {
    try {
      console.log('POST /api/points-settings/referrals:', req.body);

      const settingsFile = path.join(POINTS_SETTINGS_DIR, 'referrals.json');

      // Новый формат: базовые баллы + милестоуны
      const settings = {
        basePoints: req.body.basePoints !== undefined ? req.body.basePoints : 1,
        milestoneThreshold: req.body.milestoneThreshold !== undefined ? req.body.milestoneThreshold : 0,
        milestonePoints: req.body.milestonePoints !== undefined ? req.body.milestonePoints : 1,
        updatedAt: new Date().toISOString()
      };

      fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2), 'utf8');

      console.log(`✅ Настройки сохранены: base=${settings.basePoints}, threshold=${settings.milestoneThreshold}, milestone=${settings.milestonePoints}`);
      res.json({ success: true, settings });
    } catch (error) {
      console.error('Ошибка сохранения настроек:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/referrals/employee-points/:employeeId - баллы сотрудника за текущий месяц
  app.get('/api/referrals/employee-points/:employeeId', (req, res) => {
    try {
      const { employeeId } = req.params;
      console.log(`GET /api/referrals/employee-points/${employeeId}`);

      // Получаем настройки баллов (новый формат с милестоунами)
      const settingsFile = path.join(POINTS_SETTINGS_DIR, 'referrals.json');
      let basePoints = 1;
      let milestoneThreshold = 0;
      let milestonePoints = 1;

      if (fs.existsSync(settingsFile)) {
        const settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));

        // ОБРАТНАЯ СОВМЕСТИМОСТЬ: старый формат {pointsPerReferral: 1}
        if (settings.pointsPerReferral !== undefined && settings.basePoints === undefined) {
          basePoints = settings.pointsPerReferral;
          milestoneThreshold = 0; // Милестоуны отключены
          milestonePoints = settings.pointsPerReferral;
        } else {
          // Новый формат
          basePoints = settings.basePoints !== undefined ? settings.basePoints : 1;
          milestoneThreshold = settings.milestoneThreshold !== undefined ? settings.milestoneThreshold : 0;
          milestonePoints = settings.milestonePoints !== undefined ? settings.milestonePoints : 1;
        }
      }

      // Ищем сотрудника
      const employeeFile = path.join(EMPLOYEES_DIR, `${employeeId}.json`);
      if (!fs.existsSync(employeeFile)) {
        return res.status(404).json({ success: false, error: 'Сотрудник не найден' });
      }

      const employee = JSON.parse(fs.readFileSync(employeeFile, 'utf8'));

      if (!employee.referralCode) {
        return res.json({
          success: true,
          currentMonthPoints: 0,
          previousMonthPoints: 0,
          currentMonthReferrals: 0,
          previousMonthReferrals: 0,
          pointsPerReferral: basePoints,
          basePoints,
          milestoneThreshold,
          milestonePoints
        });
      }

      const clients = getAllClients();
      const stats = calculateReferralStats(employee.referralCode, clients);

      // Рассчитываем баллы с учетом милестоунов
      const currentMonthPoints = calculateReferralPointsWithMilestone(
        stats.currentMonth,
        basePoints,
        milestoneThreshold,
        milestonePoints
      );

      const previousMonthPoints = calculateReferralPointsWithMilestone(
        stats.previousMonth,
        basePoints,
        milestoneThreshold,
        milestonePoints
      );

      res.json({
        success: true,
        currentMonthPoints,
        previousMonthPoints,
        currentMonthReferrals: stats.currentMonth,
        previousMonthReferrals: stats.previousMonth,
        pointsPerReferral: basePoints, // Для обратной совместимости со старым клиентом
        basePoints,
        milestoneThreshold,
        milestonePoints
      });
    } catch (error) {
      console.error('Ошибка получения баллов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PATCH /api/clients/:phone/referral-status - обновить статус реферала (ФАЗА 2.1)
  app.patch('/api/clients/:phone/referral-status', (req, res) => {
    try {
      const { phone } = req.params;
      const { status } = req.body;

      console.log(`PATCH /api/clients/${phone}/referral-status -> ${status}`);

      // Валидация статуса
      const validStatuses = ['registered', 'first_purchase', 'active'];
      if (!validStatuses.includes(status)) {
        return res.status(400).json({
          success: false,
          error: `Некорректный статус. Допустимые: ${validStatuses.join(', ')}`
        });
      }

      const normalizedPhone = phone.replace(/[\s\+]/g, '');
      const sanitizedPhone = normalizedPhone.replace(/[^0-9]/g, '_');
      const clientFile = path.join(CLIENTS_DIR, `${sanitizedPhone}.json`);

      if (!fs.existsSync(clientFile)) {
        return res.status(404).json({ success: false, error: 'Клиент не найден' });
      }

      const client = JSON.parse(fs.readFileSync(clientFile, 'utf8'));

      // Обновляем статус только если есть referredBy
      if (!client.referredBy) {
        return res.status(400).json({
          success: false,
          error: 'Клиент не является рефералом'
        });
      }

      client.referralStatus = status;
      client.updatedAt = new Date().toISOString();

      // Добавляем в историю
      if (!client.referralStatusHistory) {
        client.referralStatusHistory = [];
      }
      client.referralStatusHistory.push({
        status,
        date: new Date().toISOString()
      });

      fs.writeFileSync(clientFile, JSON.stringify(client, null, 2), 'utf8');

      console.log(`✅ Статус реферала обновлен: ${phone} -> ${status}`);
      res.json({ success: true, client });
    } catch (error) {
      console.error('Ошибка обновления статуса реферала:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('Referrals API initialized');
}

// =====================================================
// РАСЧЕТ БАЛЛОВ С МИЛЕСТОУНАМИ (ЭКСПОРТИРУЕМАЯ УТИЛИТА)
// =====================================================

/**
 * Рассчитать баллы с учетом милестоунов (каждый N-й клиент получает бонус вместо базовых баллов)
 *
 * @param {number} referralsCount - количество приглашенных клиентов
 * @param {number} basePoints - базовые баллы за каждого клиента
 * @param {number} milestoneThreshold - каждый N-й клиент получает бонус (0 = отключено)
 * @param {number} milestonePoints - бонусные баллы за каждого N-го клиента
 * @returns {number} - итоговое количество баллов
 *
 * Примеры:
 * - 10 клиентов, base=1, threshold=5, milestone=3:
 *   клиенты 1,2,3,4,6,7,8,9 = 8*1 = 8
 *   клиенты 5,10 = 2*3 = 6
 *   ИТОГО: 14 баллов
 *
 * - 10 клиентов, base=1, threshold=0 (отключено), milestone=3:
 *   все 10 клиентов = 10*1 = 10 баллов (старое поведение)
 */
function calculateReferralPointsWithMilestone(referralsCount, basePoints, milestoneThreshold, milestonePoints) {
  // Если threshold = 0, милестоуны отключены - используем старую логику
  if (milestoneThreshold === 0) {
    return referralsCount * basePoints;
  }

  let totalPoints = 0;

  for (let i = 1; i <= referralsCount; i++) {
    // Каждый N-й клиент получает milestone вместо base
    if (i % milestoneThreshold === 0) {
      totalPoints += milestonePoints;
    } else {
      totalPoints += basePoints;
    }
  }

  return totalPoints;
}

// Экспортируем функцию настройки API и утилиты
module.exports = setupReferralsAPI;
module.exports.invalidateStatsCache = invalidateStatsCache;
module.exports.checkReferralLimit = checkReferralLimit;
module.exports.calculateReferralPointsWithMilestone = calculateReferralPointsWithMilestone;
