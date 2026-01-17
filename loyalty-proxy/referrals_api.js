// =====================================================
// REFERRALS API (Реферальная система)
// =====================================================

const fs = require('fs');
const path = require('path');

const EMPLOYEES_DIR = '/var/www/employees';
const CLIENTS_DIR = '/var/www/clients';
const POINTS_SETTINGS_DIR = '/var/www/points-settings';
const REFERRALS_VIEWED_FILE = '/var/www/referrals-viewed.json';

// Создаем директорию для настроек если нет
if (!fs.existsSync(POINTS_SETTINGS_DIR)) {
  fs.mkdirSync(POINTS_SETTINGS_DIR, { recursive: true });
}

// =====================================================
// ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
// =====================================================

// Получить следующий свободный referralCode
function getNextReferralCode() {
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) return 1;

    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));
    const usedCodes = new Set();

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8');
        const employee = JSON.parse(content);
        if (employee.referralCode) {
          usedCodes.add(employee.referralCode);
        }
      } catch (e) {
        // Игнорируем ошибки чтения
      }
    }

    // Ищем первый свободный код от 1 до 1000
    for (let code = 1; code <= 1000; code++) {
      if (!usedCodes.has(code)) {
        return code;
      }
    }

    return null; // Все коды заняты
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
// ЭКСПОРТ ФУНКЦИИ НАСТРОЙКИ API
// =====================================================

module.exports = function setupReferralsAPI(app) {

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

  // GET /api/referrals/validate-code/:code - валидация кода
  app.get('/api/referrals/validate-code/:code', (req, res) => {
    try {
      const code = parseInt(req.params.code, 10);
      console.log(`GET /api/referrals/validate-code/${code}`);

      if (isNaN(code) || code < 1 || code > 1000) {
        return res.json({ success: true, valid: false, message: 'Код должен быть от 1 до 1000' });
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

  // GET /api/referrals/stats - статистика всех сотрудников
  app.get('/api/referrals/stats', (req, res) => {
    try {
      console.log('GET /api/referrals/stats');

      const employees = getAllEmployees();
      const clients = getAllClients();
      const totalClients = clients.length;

      // Считаем неучтенных клиентов (без referredBy)
      const unassignedCount = clients.filter(c => !c.referredBy).length;

      // Собираем статистику по каждому сотруднику с referralCode
      const employeeStats = [];

      for (const employee of employees) {
        if (employee.referralCode) {
          const stats = calculateReferralStats(employee.referralCode, clients);
          employeeStats.push({
            employeeId: employee.id,
            employeeName: employee.name,
            referralCode: employee.referralCode,
            today: stats.today,
            currentMonth: stats.currentMonth,
            previousMonth: stats.previousMonth,
            total: stats.total
          });
        }
      }

      // Сортируем по общему количеству (убывание)
      employeeStats.sort((a, b) => b.total - a.total);

      res.json({
        success: true,
        totalClients,
        unassignedCount,
        employeeStats
      });
    } catch (error) {
      console.error('Ошибка получения статистики:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/referrals/stats/:employeeId - статистика одного сотрудника
  app.get('/api/referrals/stats/:employeeId', (req, res) => {
    try {
      const { employeeId } = req.params;
      console.log(`GET /api/referrals/stats/${employeeId}`);

      // Ищем сотрудника
      const employeeFile = path.join(EMPLOYEES_DIR, `${employeeId}.json`);
      if (!fs.existsSync(employeeFile)) {
        return res.status(404).json({ success: false, error: 'Сотрудник не найден' });
      }

      const employee = JSON.parse(fs.readFileSync(employeeFile, 'utf8'));

      if (!employee.referralCode) {
        return res.json({
          success: true,
          stats: {
            today: 0,
            currentMonth: 0,
            previousMonth: 0,
            total: 0,
            clients: []
          }
        });
      }

      const clients = getAllClients();
      const stats = calculateReferralStats(employee.referralCode, clients);

      res.json({
        success: true,
        employeeId: employee.id,
        employeeName: employee.name,
        referralCode: employee.referralCode,
        stats
      });
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
        res.json({ success: true, settings });
      } else {
        // Дефолтные настройки
        const defaultSettings = {
          pointsPerReferral: 1,
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

      const settings = {
        pointsPerReferral: req.body.pointsPerReferral || 1,
        updatedAt: new Date().toISOString()
      };

      fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2), 'utf8');

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

      // Получаем настройки баллов
      const settingsFile = path.join(POINTS_SETTINGS_DIR, 'referrals.json');
      let pointsPerReferral = 1;

      if (fs.existsSync(settingsFile)) {
        const settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
        pointsPerReferral = settings.pointsPerReferral || 1;
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
          previousMonthReferrals: 0
        });
      }

      const clients = getAllClients();
      const stats = calculateReferralStats(employee.referralCode, clients);

      res.json({
        success: true,
        currentMonthPoints: stats.currentMonth * pointsPerReferral,
        previousMonthPoints: stats.previousMonth * pointsPerReferral,
        currentMonthReferrals: stats.currentMonth,
        previousMonthReferrals: stats.previousMonth,
        pointsPerReferral
      });
    } catch (error) {
      console.error('Ошибка получения баллов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('Referrals API initialized');
};
