// =====================================================
// ORDER TIMEOUT API - Штрафы за просроченные заказы
// =====================================================

const fs = require('fs');
const path = require('path');

// Директории
const POINTS_SETTINGS_DIR = '/var/www/points-settings';
const EFFICIENCY_PENALTIES_DIR = '/var/www/efficiency-penalties';
const ORDERS_DIR = '/var/www/orders';
const ATTENDANCE_DIR = '/var/www/attendance';
const WORK_SCHEDULES_DIR = '/var/www/work-schedules';

// Файл настроек заказов
const ORDER_SETTINGS_FILE = path.join(POINTS_SETTINGS_DIR, 'orders.json');

// Дефолтные настройки
const DEFAULT_ORDER_SETTINGS = {
  timeoutMinutes: 15,
  missedOrderPenalty: -2
};

// Хелперы
function loadJsonFile(filePath, defaultValue = null) {
  try {
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error('Error loading JSON file:', filePath, e.message);
  }
  return defaultValue;
}

function saveJsonFile(filePath, data) {
  try {
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
    return true;
  } catch (e) {
    console.error('Error saving JSON file:', filePath, e.message);
    return false;
  }
}

// Получить настройки заказов
function getOrderSettings() {
  const settings = loadJsonFile(ORDER_SETTINGS_FILE, DEFAULT_ORDER_SETTINGS);
  return { ...DEFAULT_ORDER_SETTINGS, ...settings };
}

// Сохранить настройки заказов
function saveOrderSettings(settings) {
  return saveJsonFile(ORDER_SETTINGS_FILE, settings);
}

// Определить тип смены по времени
function getShiftTypeByTime(date) {
  const hour = date.getHours();
  // Утро: 08:00-16:00, День: 12:00-20:00, Вечер: 16:00-00:00
  if (hour >= 8 && hour < 12) return ['morning'];
  if (hour >= 12 && hour < 16) return ['morning', 'day']; // пересечение
  if (hour >= 16 && hour < 20) return ['day', 'evening']; // пересечение
  if (hour >= 20 || hour < 8) return ['evening'];
  return ['day'];
}

// Получить сотрудников на смене по attendance
function getEmployeesFromAttendance(shopAddress, date) {
  const employees = [];
  const dateStr = date.toISOString().split('T')[0];

  if (!fs.existsSync(ATTENDANCE_DIR)) return employees;

  const files = fs.readdirSync(ATTENDANCE_DIR);
  for (const file of files) {
    if (!file.endsWith('.json')) continue;

    const filePath = path.join(ATTENDANCE_DIR, file);
    const data = loadJsonFile(filePath, null);

    if (!data || data.date !== dateStr) continue;
    if (!data.records || !Array.isArray(data.records)) continue;

    for (const record of data.records) {
      if (record.shopAddress === shopAddress && record.action === 'check-in') {
        // Проверяем, что сотрудник отметился до времени заказа
        const checkInTime = new Date(record.timestamp);
        if (checkInTime <= date) {
          employees.push({
            id: record.employeeId || data.identifier,
            name: record.employeeName || data.identifier
          });
        }
      }
    }
  }

  return employees;
}

// Получить сотрудников на смене по графику
function getEmployeesFromSchedule(shopAddress, date) {
  const employees = [];
  const monthKey = date.toISOString().slice(0, 7); // YYYY-MM
  const dateStr = date.toISOString().split('T')[0];

  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);
  const schedule = loadJsonFile(scheduleFile, null);

  if (!schedule || !schedule.entries) return employees;

  const shiftTypes = getShiftTypeByTime(date);

  for (const entry of schedule.entries) {
    if (entry.shopAddress !== shopAddress) continue;
    if (entry.date !== dateStr) continue;
    if (!shiftTypes.includes(entry.shiftType)) continue;

    employees.push({
      id: entry.employeeId,
      name: entry.employeeName
    });
  }

  return employees;
}

// Найти всех сотрудников на смене
function findEmployeesOnShift(shopAddress, orderTime) {
  // 1. Сначала проверяем attendance
  let employees = getEmployeesFromAttendance(shopAddress, orderTime);

  // 2. Если никто не отметился - проверяем график
  if (employees.length === 0) {
    employees = getEmployeesFromSchedule(shopAddress, orderTime);
  }

  // Убираем дубликаты по ID
  const uniqueEmployees = [];
  const seenIds = new Set();
  for (const emp of employees) {
    if (!seenIds.has(emp.id)) {
      seenIds.add(emp.id);
      uniqueEmployees.push(emp);
    }
  }

  return uniqueEmployees;
}

// Создать штраф за просроченный заказ
function createOrderPenalty(employee, order, settings) {
  const now = new Date();

  return {
    id: `penalty_order_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    type: 'employee',
    entityId: employee.id,
    entityName: employee.name,
    shopAddress: order.shopAddress,
    employeeName: employee.name,
    category: 'missed_order',
    categoryName: 'Пропущенный заказ',
    date: now.toISOString().split('T')[0],
    points: settings.missedOrderPenalty,
    reason: `Заказ #${order.orderNumber} не принят за ${settings.timeoutMinutes} мин`,
    sourceId: order.id,
    createdAt: now.toISOString()
  };
}

// Сохранить штрафы
function savePenalties(penalties) {
  if (penalties.length === 0) return;

  const now = new Date();
  const yearMonth = now.toISOString().slice(0, 7);
  const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${yearMonth}.json`);

  if (!fs.existsSync(EFFICIENCY_PENALTIES_DIR)) {
    fs.mkdirSync(EFFICIENCY_PENALTIES_DIR, { recursive: true });
  }

  let existingPenalties = loadJsonFile(penaltiesFile, []);
  if (!Array.isArray(existingPenalties)) existingPenalties = [];

  existingPenalties = existingPenalties.concat(penalties);
  saveJsonFile(penaltiesFile, existingPenalties);

  console.log(`Saved ${penalties.length} order penalties`);
}

// Проверить просроченные заказы
function checkExpiredOrders() {
  console.log('Checking for expired orders...');

  const settings = getOrderSettings();
  const now = new Date();
  const timeoutMs = settings.timeoutMinutes * 60 * 1000;

  if (!fs.existsSync(ORDERS_DIR)) {
    console.log('Orders directory does not exist');
    return;
  }

  const files = fs.readdirSync(ORDERS_DIR);
  let expiredCount = 0;
  const allPenalties = [];

  for (const file of files) {
    if (!file.endsWith('.json') || file === 'order-counter.json') continue;

    const filePath = path.join(ORDERS_DIR, file);
    const order = loadJsonFile(filePath, null);

    if (!order) continue;
    if (order.status !== 'pending') continue;

    const createdAt = new Date(order.createdAt);
    const expiresAt = new Date(createdAt.getTime() + timeoutMs);

    if (now >= expiresAt) {
      console.log(`Order #${order.orderNumber} expired (created: ${order.createdAt})`);

      // Меняем статус на unconfirmed
      order.status = 'unconfirmed';
      order.expiredAt = now.toISOString();
      saveJsonFile(filePath, order);

      // Находим сотрудников на смене
      const employees = findEmployeesOnShift(order.shopAddress, createdAt);
      console.log(`Found ${employees.length} employees on shift at ${order.shopAddress}`);

      // Создаем штрафы для каждого
      for (const emp of employees) {
        const penalty = createOrderPenalty(emp, order, settings);
        allPenalties.push(penalty);
        console.log(`- Penalty for ${emp.name}: ${settings.missedOrderPenalty} points`);
      }

      expiredCount++;
    }
  }

  // Сохраняем все штрафы
  if (allPenalties.length > 0) {
    savePenalties(allPenalties);
  }

  if (expiredCount > 0) {
    console.log(`Processed ${expiredCount} expired orders, created ${allPenalties.length} penalties`);
  }
}

// Настройка API и scheduler
function setupOrderTimeoutAPI(app) {
  // GET /api/points-settings/orders - получить настройки
  app.get('/api/points-settings/orders', (req, res) => {
    console.log('GET /api/points-settings/orders');
    const settings = getOrderSettings();
    res.json({ success: true, settings });
  });

  // PUT /api/points-settings/orders - обновить настройки
  app.put('/api/points-settings/orders', (req, res) => {
    console.log('PUT /api/points-settings/orders');
    const { timeoutMinutes, missedOrderPenalty } = req.body;

    const settings = {
      timeoutMinutes: timeoutMinutes || DEFAULT_ORDER_SETTINGS.timeoutMinutes,
      missedOrderPenalty: missedOrderPenalty || DEFAULT_ORDER_SETTINGS.missedOrderPenalty
    };

    if (saveOrderSettings(settings)) {
      res.json({ success: true, settings });
    } else {
      res.status(500).json({ success: false, error: 'Failed to save settings' });
    }
  });

  // Запускаем scheduler каждую минуту
  console.log('Starting order timeout scheduler (every 60 seconds)...');
  setInterval(checkExpiredOrders, 60 * 1000);

  // Первый запуск через 10 секунд после старта
  setTimeout(checkExpiredOrders, 10 * 1000);

  console.log('Order Timeout API initialized');
}

module.exports = { setupOrderTimeoutAPI };
