// =====================================================
// ORDER NOTIFICATIONS API - Push-уведомления для заказов
// =====================================================

const fs = require('fs');
const path = require('path');

const FCM_TOKENS_DIR = '/var/www/fcm-tokens';
const EMPLOYEES_DIR = '/var/www/employees';
const ATTENDANCE_DIR = '/var/www/attendance';
const WORK_SCHEDULES_DIR = '/var/www/work-schedules';

// Получить Firebase Admin
function getFirebaseAdmin() {
  try {
    const { admin, firebaseInitialized } = require('./firebase-admin-config');
    if (!firebaseInitialized) {
      console.log('Firebase не инициализирован');
      return null;
    }
    return admin;
  } catch (e) {
    console.log('Ошибка загрузки Firebase:', e.message);
    return null;
  }
}

// Получить телефон сотрудника по его ID
function getEmployeePhone(employeeId) {
  try {
    const employeeFile = path.join(EMPLOYEES_DIR, `${employeeId}.json`);
    if (fs.existsSync(employeeFile)) {
      const employee = JSON.parse(fs.readFileSync(employeeFile, 'utf8'));
      return employee.phone || null;
    }
  } catch (e) {
    // ignore
  }
  return null;
}

// Отправить push-уведомление по телефону
async function sendPushByPhone(phone, title, body, data = {}) {
  const admin = getFirebaseAdmin();
  if (!admin) return false;

  try {
    const normalizedPhone = phone.replace(/[\s+]/g, '');
    const tokenFile = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);

    if (!fs.existsSync(tokenFile)) {
      console.log(`FCM токен не найден для ${normalizedPhone}`);
      return false;
    }

    const tokenData = JSON.parse(fs.readFileSync(tokenFile, 'utf8'));
    if (!tokenData.token) {
      console.log(`Пустой FCM токен для ${normalizedPhone}`);
      return false;
    }

    await admin.messaging().send({
      token: tokenData.token,
      notification: { title, body },
      data: { ...data, click_action: 'FLUTTER_NOTIFICATION_CLICK' },
      android: {
        priority: 'high',
        notification: {
          channelId: 'orders_channel',
          sound: 'default'
        }
      }
    });

    console.log(`Push отправлен: ${normalizedPhone}`);
    return true;
  } catch (e) {
    console.log(`Ошибка отправки push на ${phone}: ${e.message}`);
    return false;
  }
}

// Определить тип смены по времени
function getShiftTypeByTime(date) {
  const hour = date.getHours();
  if (hour >= 8 && hour < 12) return ['morning'];
  if (hour >= 12 && hour < 16) return ['morning', 'day'];
  if (hour >= 16 && hour < 20) return ['day', 'evening'];
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

    try {
      const filePath = path.join(ATTENDANCE_DIR, file);
      const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));

      if (!data || data.date !== dateStr) continue;
      if (!data.records || !Array.isArray(data.records)) continue;

      for (const record of data.records) {
        if (record.shopAddress === shopAddress && record.action === 'check-in') {
          const checkInTime = new Date(record.timestamp);
          if (checkInTime <= date) {
            const employeeId = record.employeeId || data.identifier;
            const phone = getEmployeePhone(employeeId);
            if (phone) {
              employees.push({
                id: employeeId,
                name: record.employeeName || data.identifier,
                phone: phone
              });
            }
          }
        }
      }
    } catch (e) {
      // Пропускаем файлы с ошибками
    }
  }

  return employees;
}

// Получить сотрудников на смене по графику
function getEmployeesFromSchedule(shopAddress, date) {
  const employees = [];
  const monthKey = date.toISOString().slice(0, 7);
  const dateStr = date.toISOString().split('T')[0];

  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);

  if (!fs.existsSync(scheduleFile)) return employees;

  try {
    const schedule = JSON.parse(fs.readFileSync(scheduleFile, 'utf8'));
    if (!schedule || !schedule.entries) return employees;

    const shiftTypes = getShiftTypeByTime(date);

    for (const entry of schedule.entries) {
      if (entry.shopAddress !== shopAddress) continue;
      if (entry.date !== dateStr) continue;
      if (!shiftTypes.includes(entry.shiftType)) continue;

      const phone = getEmployeePhone(entry.employeeId);
      if (phone) {
        employees.push({
          id: entry.employeeId,
          name: entry.employeeName,
          phone: phone
        });
      }
    }
  } catch (e) {
    // Пропускаем ошибки
  }

  return employees;
}

// Найти всех сотрудников на смене в магазине
function findEmployeesOnShift(shopAddress) {
  const now = new Date();

  // 1. Сначала проверяем attendance
  let employees = getEmployeesFromAttendance(shopAddress, now);

  // 2. Если никто не отметился - проверяем график
  if (employees.length === 0) {
    employees = getEmployeesFromSchedule(shopAddress, now);
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

// Отправить push сотрудникам магазина о новом заказе
async function notifyEmployeesAboutNewOrder(order) {
  console.log(`Уведомление сотрудникам о заказе #${order.orderNumber}`);

  const employees = findEmployeesOnShift(order.shopAddress);
  console.log(`Найдено сотрудников на смене: ${employees.length}`);

  if (employees.length === 0) {
    console.log('Нет сотрудников на смене для уведомления');
    return 0;
  }

  let sentCount = 0;
  for (const emp of employees) {
    console.log(`Отправка push сотруднику ${emp.name} (${emp.phone})`);
    const success = await sendPushByPhone(
      emp.phone,
      'Новый заказ!',
      `Заказ #${order.orderNumber} на сумму ${order.totalPrice} руб`,
      {
        type: 'new_order',
        orderId: order.id,
        orderNumber: String(order.orderNumber)
      }
    );
    if (success) sentCount++;
  }

  console.log(`Отправлено уведомлений: ${sentCount}/${employees.length}`);
  return sentCount;
}

// Отправить push клиенту об изменении статуса заказа
async function notifyClientAboutOrderStatus(order) {
  console.log(`Уведомление клиенту о статусе заказа #${order.orderNumber}`);

  let title, body;

  if (order.status === 'accepted') {
    title = 'Заказ принят!';
    body = `Ваш заказ #${order.orderNumber} принят${order.acceptedBy ? ` сотрудником ${order.acceptedBy}` : ''}`;
  } else if (order.status === 'rejected') {
    title = 'Заказ отклонен';
    body = `Ваш заказ #${order.orderNumber} отклонен${order.rejectionReason ? `: ${order.rejectionReason}` : ''}`;
  } else {
    return false;
  }

  const success = await sendPushByPhone(
    order.clientPhone,
    title,
    body,
    {
      type: 'order_status',
      orderId: order.id,
      orderNumber: String(order.orderNumber),
      status: order.status
    }
  );

  return success;
}

module.exports = {
  notifyEmployeesAboutNewOrder,
  notifyClientAboutOrderStatus,
  sendPushByPhone,
  findEmployeesOnShift
};
