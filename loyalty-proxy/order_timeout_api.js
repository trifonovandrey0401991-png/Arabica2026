// =====================================================
// ORDER TIMEOUT API - Штрафы за просроченные заказы
//
// REFACTORED: Converted from sync to async I/O (2026-02-05)
// =====================================================

const fsp = require('fs').promises;
const path = require('path');
const { sendPushNotification } = require('./report_notifications_api');

// Директории
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;
const ORDERS_DIR = `${DATA_DIR}/orders`;
const ATTENDANCE_DIR = `${DATA_DIR}/attendance`;
const WORK_SCHEDULES_DIR = `${DATA_DIR}/work-schedules`;

// Файл настроек заказов
const ORDER_SETTINGS_FILE = path.join(POINTS_SETTINGS_DIR, 'orders.json');

// Дефолтные настройки
const DEFAULT_ORDER_SETTINGS = {
  timeoutMinutes: 15,
  missedOrderPenalty: -2
};

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Хелперы
async function loadJsonFile(filePath, defaultValue = null) {
  try {
    if (await fileExists(filePath)) {
      const content = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error('Error loading JSON file:', filePath, e.message);
  }
  return defaultValue;
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
    console.error('Error saving JSON file:', filePath, e.message);
    return false;
  }
}

// Получить настройки заказов
async function getOrderSettings() {
  const settings = await loadJsonFile(ORDER_SETTINGS_FILE, DEFAULT_ORDER_SETTINGS);
  return { ...DEFAULT_ORDER_SETTINGS, ...settings };
}

// Сохранить настройки заказов
async function saveOrderSettings(settings) {
  return await saveJsonFile(ORDER_SETTINGS_FILE, settings);
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
async function getEmployeesFromAttendance(shopAddress, date) {
  const employees = [];
  const dateStr = date.toISOString().split('T')[0];

  if (!(await fileExists(ATTENDANCE_DIR))) return employees;

  const files = await fsp.readdir(ATTENDANCE_DIR);
  for (const file of files) {
    if (!file.endsWith('.json')) continue;

    const filePath = path.join(ATTENDANCE_DIR, file);
    const data = await loadJsonFile(filePath, null);

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
async function getEmployeesFromSchedule(shopAddress, date) {
  const employees = [];
  const monthKey = date.toISOString().slice(0, 7); // YYYY-MM
  const dateStr = date.toISOString().split('T')[0];

  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);
  const schedule = await loadJsonFile(scheduleFile, null);

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
async function findEmployeesOnShift(shopAddress, orderTime) {
  // 1. Сначала проверяем attendance
  let employees = await getEmployeesFromAttendance(shopAddress, orderTime);

  // 2. Если никто не отметился - проверяем график
  if (employees.length === 0) {
    employees = await getEmployeesFromSchedule(shopAddress, orderTime);
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
    reason: `Заказ ${order.orderNumber} не принят за ${settings.timeoutMinutes} мин`,
    sourceId: order.id,
    createdAt: now.toISOString()
  };
}

// Сохранить штрафы
async function savePenalties(penalties) {
  if (penalties.length === 0) return;

  const now = new Date();
  const yearMonth = now.toISOString().slice(0, 7);
  const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${yearMonth}.json`);

  if (!(await fileExists(EFFICIENCY_PENALTIES_DIR))) {
    await fsp.mkdir(EFFICIENCY_PENALTIES_DIR, { recursive: true });
  }

  let existingPenalties = await loadJsonFile(penaltiesFile, []);
  if (!Array.isArray(existingPenalties)) existingPenalties = [];

  existingPenalties = existingPenalties.concat(penalties);
  await saveJsonFile(penaltiesFile, existingPenalties);

  console.log(`Saved ${penalties.length} order penalties`);
}

// Проверить просроченные заказы
async function checkExpiredOrders() {
  console.log('Checking for expired orders...');

  const settings = await getOrderSettings();
  const now = new Date();
  const timeoutMs = settings.timeoutMinutes * 60 * 1000;

  if (!(await fileExists(ORDERS_DIR))) {
    console.log('Orders directory does not exist');
    return;
  }

  const files = await fsp.readdir(ORDERS_DIR);
  let expiredCount = 0;
  const allPenalties = [];

  for (const file of files) {
    if (!file.endsWith('.json') || file === 'order-counter.json') continue;

    const filePath = path.join(ORDERS_DIR, file);
    const order = await loadJsonFile(filePath, null);

    if (!order) continue;
    if (order.status !== 'pending') continue;

    const createdAt = new Date(order.createdAt);
    const expiresAt = new Date(createdAt.getTime() + timeoutMs);

    if (now >= expiresAt) {
      console.log(`Order #${order.orderNumber} expired (created: ${order.createdAt})`);

      // Меняем статус на unconfirmed
      order.status = 'unconfirmed';
      order.expiredAt = now.toISOString();
      await saveJsonFile(filePath, order);

      // Push-уведомление админам о неподтверждённом заказе
      try {
        const clientName = order.clientName || order.clientPhone || 'Клиент';
        sendPushNotification(
          'Неподтверждённый заказ',
          `Заказ от ${clientName} не был принят вовремя`,
          { type: 'order_unconfirmed', orderId: order.id }
        ).catch(err => console.error('Ошибка push о неподтверждённом заказе:', err.message));
        console.log(`✅ Push о неподтверждённом заказе #${order.orderNumber} отправлен админам`);
      } catch (pushErr) {
        console.error('❌ Ошибка отправки push о неподтверждённом заказе:', pushErr.message);
      }

      // Находим сотрудников на смене
      const employees = await findEmployeesOnShift(order.shopAddress, createdAt);
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
    await savePenalties(allPenalties);
  }

  if (expiredCount > 0) {
    console.log(`Processed ${expiredCount} expired orders, created ${allPenalties.length} penalties`);
  }
}

// Настройка API и scheduler
function setupOrderTimeoutAPI(app) {
  // GET /api/points-settings/orders - получить настройки
  app.get('/api/points-settings/orders', async (req, res) => {
    try {
      console.log('GET /api/points-settings/orders');
      const settings = await getOrderSettings();
      res.json({ success: true, settings });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/points-settings/orders - обновить настройки
  app.put('/api/points-settings/orders', async (req, res) => {
    try {
      console.log('PUT /api/points-settings/orders');
      const { timeoutMinutes, missedOrderPenalty } = req.body;

      const settings = {
        timeoutMinutes: timeoutMinutes || DEFAULT_ORDER_SETTINGS.timeoutMinutes,
        missedOrderPenalty: missedOrderPenalty || DEFAULT_ORDER_SETTINGS.missedOrderPenalty
      };

      if (await saveOrderSettings(settings)) {
        res.json({ success: true, settings });
      } else {
        res.status(500).json({ success: false, error: 'Failed to save settings' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
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
