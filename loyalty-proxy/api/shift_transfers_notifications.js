/**
 * SHIFT TRANSFERS NOTIFICATIONS API
 * Система push-уведомлений для замен смены
 *
 * Типы уведомлений:
 * - shift_transfer_created - Новый запрос на замену смены
 * - shift_transfer_accepted - Сотрудник принял запрос
 * - shift_transfer_rejected - Сотрудник отклонил запрос
 * - shift_transfer_pending_approval - Требуется одобрение админа
 * - shift_transfer_approved - Админ одобрил замену
 * - shift_transfer_declined - Админ отклонил замену
 */

const fs = require('fs');
const path = require('path');

// Константы
const FCM_TOKENS_DIR = '/var/www/fcm-tokens';
const EMPLOYEES_DIR = '/var/www/employees';

// ==================== УТИЛИТЫ ====================

/**
 * Получить Firebase Admin SDK
 * @returns {Object|null} Firebase Admin или null
 */
function getFirebaseAdmin() {
  try {
    const { admin, firebaseInitialized } = require('../firebase-admin-config');
    if (!firebaseInitialized) {
      console.log('⚠️  Firebase не инициализирован');
      return null;
    }
    return admin;
  } catch (e) {
    console.error('❌ Ошибка загрузки Firebase:', e.message);
    return null;
  }
}

/**
 * Получить данные сотрудника по ID
 * @param {string} employeeId - ID сотрудника
 * @returns {Object|null} Данные сотрудника или null
 */
function getEmployeeById(employeeId) {
  try {
    const employeeFile = path.join(EMPLOYEES_DIR, `${employeeId}.json`);
    if (fs.existsSync(employeeFile)) {
      const content = fs.readFileSync(employeeFile, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error(`❌ Ошибка чтения сотрудника ${employeeId}:`, e.message);
  }
  return null;
}

/**
 * Получить список всех сотрудников (для broadcast)
 * @param {string} excludeEmployeeId - ID сотрудника, которого нужно исключить
 * @returns {Array} Массив сотрудников
 */
function getAllEmployees(excludeEmployeeId = null) {
  const employees = [];
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) {
      console.log('⚠️  Папка сотрудников не существует');
      return employees;
    }

    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const filePath = path.join(EMPLOYEES_DIR, file);
        const content = fs.readFileSync(filePath, 'utf8');
        const employee = JSON.parse(content);

        // Исключаем указанного сотрудника
        if (excludeEmployeeId && employee.id === excludeEmployeeId) {
          continue;
        }

        employees.push(employee);
      } catch (e) {
        console.error(`❌ Ошибка чтения файла ${file}:`, e.message);
      }
    }
  } catch (e) {
    console.error('❌ Ошибка получения списка сотрудников:', e.message);
  }

  return employees;
}

/**
 * Получить список всех администраторов
 * @returns {Array} Массив администраторов
 */
function getAllAdmins() {
  const admins = [];
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) {
      console.log('⚠️  Папка сотрудников не существует');
      return admins;
    }

    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const filePath = path.join(EMPLOYEES_DIR, file);
        const content = fs.readFileSync(filePath, 'utf8');
        const employee = JSON.parse(content);

        // Только администраторы
        if (employee.isAdmin === true) {
          admins.push(employee);
        }
      } catch (e) {
        console.error(`❌ Ошибка чтения файла ${file}:`, e.message);
      }
    }
  } catch (e) {
    console.error('❌ Ошибка получения списка админов:', e.message);
  }

  console.log(`✅ Найдено ${admins.length} администраторов`);
  return admins;
}

/**
 * Получить FCM токен сотрудника по телефону
 * @param {string} phone - Номер телефона
 * @returns {string|null} FCM токен или null
 */
function getFcmTokenByPhone(phone) {
  try {
    const normalizedPhone = phone.replace(/[\s+]/g, '');
    const tokenFile = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);

    if (!fs.existsSync(tokenFile)) {
      return null;
    }

    const tokenData = JSON.parse(fs.readFileSync(tokenFile, 'utf8'));
    return tokenData.token || null;
  } catch (e) {
    console.error(`❌ Ошибка получения токена для ${phone}:`, e.message);
    return null;
  }
}

/**
 * Отправить push-уведомление одному пользователю
 * @param {string} phone - Номер телефона
 * @param {string} title - Заголовок уведомления
 * @param {string} body - Текст уведомления
 * @param {Object} data - Дополнительные данные
 * @returns {Promise<boolean>} true если отправлено успешно
 */
async function sendPushToPhone(phone, title, body, data = {}) {
  const admin = getFirebaseAdmin();
  if (!admin) {
    console.log('⚠️  Firebase не доступен, уведомление не отправлено');
    return false;
  }

  const token = getFcmTokenByPhone(phone);
  if (!token) {
    console.log(`⚠️  FCM токен не найден для ${phone}`);
    return false;
  }

  try {
    await admin.messaging().send({
      token: token,
      notification: {
        title: title,
        body: body,
      },
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'shift_transfers_channel',
        },
      },
    });

    console.log(`✅ Push отправлен: ${phone.substring(0, 5)}***`);
    return true;
  } catch (e) {
    console.error(`❌ Ошибка отправки push на ${phone}:`, e.message);
    return false;
  }
}

/**
 * Отправить push нескольким пользователям
 * @param {Array} employees - Массив сотрудников с полем phone
 * @param {string} title - Заголовок
 * @param {string} body - Текст
 * @param {Object} data - Дополнительные данные
 * @returns {Promise<number>} Количество успешных отправок
 */
async function sendPushToMultiple(employees, title, body, data = {}) {
  let successCount = 0;

  for (const employee of employees) {
    if (!employee.phone) {
      console.log(`⚠️  У сотрудника ${employee.name || employee.id} нет телефона`);
      continue;
    }

    const success = await sendPushToPhone(employee.phone, title, body, data);
    if (success) successCount++;
  }

  console.log(`✅ Отправлено ${successCount}/${employees.length} уведомлений`);
  return successCount;
}

/**
 * Форматировать дату для отображения
 * @param {string} dateString - Дата в формате ISO или YYYY-MM-DD
 * @returns {string} Форматированная дата
 */
function formatDate(dateString) {
  try {
    const date = new Date(dateString);
    const day = date.getDate();
    const month = date.getMonth() + 1;
    return `${day}.${month}`;
  } catch (e) {
    return dateString;
  }
}

/**
 * Форматировать тип смены для отображения
 * @param {string} shiftType - Тип смены (morning, day, evening)
 * @returns {string} Текстовое представление
 */
function formatShiftType(shiftType) {
  const types = {
    morning: 'Утро',
    day: 'День',
    evening: 'Вечер',
  };
  return types[shiftType] || shiftType;
}

// ==================== ФУНКЦИИ УВЕДОМЛЕНИЙ ====================

/**
 * 1. Уведомление при создании запроса (POST)
 * Если toEmployeeId указан → уведомить только его
 * Если toEmployeeId = null (broadcast) → уведомить ВСЕХ (кроме отправителя)
 */
async function notifyTransferCreated(transfer) {
  console.log(`📤 Уведомление о создании запроса на замену: ${transfer.id}`);

  const title = 'Новая замена смены';
  const shiftTypeText = formatShiftType(transfer.shiftType);
  const dateText = formatDate(transfer.shiftDate);
  const body = `${transfer.fromEmployeeName} предлагает взять смену ${shiftTypeText} на ${dateText} в ${transfer.shopName}`;

  const data = {
    type: 'shift_transfer_created',
    transferId: transfer.id,
    action: 'view_request',
  };

  let recipients = [];

  // Если указан конкретный сотрудник
  if (transfer.toEmployeeId) {
    const targetEmployee = getEmployeeById(transfer.toEmployeeId);
    if (targetEmployee) {
      recipients = [targetEmployee];
      console.log(`📨 Отправка конкретному сотруднику: ${targetEmployee.name}`);
    } else {
      console.log(`⚠️  Сотрудник ${transfer.toEmployeeId} не найден`);
    }
  }
  // Broadcast - всем сотрудникам (кроме отправителя)
  else {
    recipients = getAllEmployees(transfer.fromEmployeeId);
    console.log(`📨 Broadcast: отправка ${recipients.length} сотрудникам`);
  }

  if (recipients.length === 0) {
    console.log('⚠️  Нет получателей для уведомления');
    return 0;
  }

  return await sendPushToMultiple(recipients, title, body, data);
}

/**
 * 2. Уведомление при принятии запроса сотрудником (accept)
 * - Уведомить отправителя (fromEmployeeId)
 * - Уведомить ВСЕХ админов
 * @param {Object} transfer - Данные запроса
 * @param {string} acceptedByEmployeeId - ID принявшего сотрудника
 * @param {string} acceptedByEmployeeName - Имя принявшего сотрудника
 */
async function notifyTransferAccepted(transfer, acceptedByEmployeeId, acceptedByEmployeeName) {
  console.log(`✅ Уведомление о принятии запроса: ${transfer.id} сотрудником ${acceptedByEmployeeName}`);

  // Используем переданные параметры или данные из transfer (для обратной совместимости)
  const employeeName = acceptedByEmployeeName || transfer.acceptedByEmployeeName;

  let sentCount = 0;

  // 1. Уведомление отправителю
  const fromEmployee = getEmployeeById(transfer.fromEmployeeId);
  if (fromEmployee && fromEmployee.phone) {
    const title = 'Ваш запрос принят';
    const body = `${employeeName} согласился взять вашу смену`;
    const data = {
      type: 'shift_transfer_accepted',
      transferId: transfer.id,
      action: 'view_request',
    };

    const success = await sendPushToPhone(fromEmployee.phone, title, body, data);
    if (success) sentCount++;
  }

  // 2. Уведомление всем админам
  const admins = getAllAdmins();
  if (admins.length > 0) {
    const title = 'Замена смены требует одобрения';
    const dateText = formatDate(transfer.shiftDate);
    const body = `${employeeName} принял смену от ${transfer.fromEmployeeName} на ${dateText}`;
    const data = {
      type: 'shift_transfer_pending_approval',
      transferId: transfer.id,
      action: 'admin_review',
    };

    const adminSentCount = await sendPushToMultiple(admins, title, body, data);
    sentCount += adminSentCount;
  }

  return sentCount;
}

/**
 * 3. Уведомление при отклонении запроса сотрудником (reject)
 * - Уведомить ТОЛЬКО отправителя (fromEmployeeId)
 * @param {Object} transfer - Данные запроса
 * @param {string} rejectedByEmployeeId - ID отклонившего сотрудника
 * @param {string} rejectedByEmployeeName - Имя отклонившего сотрудника
 */
async function notifyTransferRejected(transfer, rejectedByEmployeeId, rejectedByEmployeeName) {
  console.log(`❌ Уведомление об отклонении запроса: ${transfer.id}`);

  const fromEmployee = getEmployeeById(transfer.fromEmployeeId);
  if (!fromEmployee || !fromEmployee.phone) {
    console.log('⚠️  Отправитель не найден или нет телефона');
    return 0;
  }

  // Используем переданное имя, или данные из transfer, или fallback
  const rejecterName = rejectedByEmployeeName ||
                       transfer.rejectedByEmployeeName ||
                       transfer.toEmployeeName ||
                       'Сотрудник';

  const title = 'Запрос отклонен';
  const body = `${rejecterName} отклонил ваш запрос на замену смены`;
  const data = {
    type: 'shift_transfer_rejected',
    transferId: transfer.id,
    action: 'view_request',
  };

  const success = await sendPushToPhone(fromEmployee.phone, title, body, data);
  return success ? 1 : 0;
}

/**
 * 4. Уведомление при одобрении админом (approve)
 * - Уведомить обоих: fromEmployeeId и одобренного сотрудника
 * @param {Object} transfer - Данные запроса
 * @param {Object} approvedEmployee - Данные одобренного сотрудника {employeeId, employeeName}
 */
async function notifyTransferApproved(transfer, approvedEmployee) {
  console.log(`✅ Уведомление об одобрении админом: ${transfer.id}`);

  const title = 'Замена смены одобрена';
  const dateText = formatDate(transfer.shiftDate);
  const data = {
    type: 'shift_transfer_approved',
    transferId: transfer.id,
    action: 'view_schedule',
  };

  let sentCount = 0;

  // Используем переданного сотрудника или данные из transfer
  const approvedEmployeeId = approvedEmployee?.employeeId || transfer.acceptedByEmployeeId;

  // 1. Уведомить отправителя
  const fromEmployee = getEmployeeById(transfer.fromEmployeeId);
  if (fromEmployee && fromEmployee.phone) {
    const body = `Ваша замена смены на ${dateText} одобрена администратором`;
    const success = await sendPushToPhone(fromEmployee.phone, title, body, data);
    if (success) sentCount++;
  }

  // 2. Уведомить одобренного сотрудника
  const acceptedEmployee = getEmployeeById(approvedEmployeeId);
  if (acceptedEmployee && acceptedEmployee.phone) {
    const body = `Вам назначена смена ${formatShiftType(transfer.shiftType)} на ${dateText} в ${transfer.shopName}`;
    const success = await sendPushToPhone(acceptedEmployee.phone, title, body, data);
    if (success) sentCount++;
  }

  return sentCount;
}

/**
 * 5. Уведомление при отклонении админом (decline)
 * - Уведомить ТОЛЬКО участников: fromEmployeeId и acceptedByEmployeeId
 */
async function notifyTransferDeclined(transfer) {
  console.log(`❌ Уведомление об отклонении админом: ${transfer.id}`);

  const title = 'Замена смены отклонена';
  const dateText = formatDate(transfer.shiftDate);
  const body = `Ваша замена смены на ${dateText} была отклонена администратором`;
  const data = {
    type: 'shift_transfer_declined',
    transferId: transfer.id,
    action: 'view_request',
  };

  let sentCount = 0;

  // 1. Уведомить отправителя
  const fromEmployee = getEmployeeById(transfer.fromEmployeeId);
  if (fromEmployee && fromEmployee.phone) {
    const success = await sendPushToPhone(fromEmployee.phone, title, body, data);
    if (success) sentCount++;
  }

  // 2. Уведомить принявшего (если есть)
  if (transfer.acceptedByEmployeeId) {
    const acceptedEmployee = getEmployeeById(transfer.acceptedByEmployeeId);
    if (acceptedEmployee && acceptedEmployee.phone) {
      const success = await sendPushToPhone(acceptedEmployee.phone, title, body, data);
      if (success) sentCount++;
    }
  }

  return sentCount;
}

/**
 * 6. Уведомление другим принявшим когда админ выбрал одного (declined)
 * - Уведомить всех кто принял, но не был выбран
 * @param {Object} transfer - Данные запроса
 * @param {Array} declinedEmployees - Массив сотрудников которые были отклонены [{employeeId, employeeName}]
 */
async function notifyOthersDeclined(transfer, declinedEmployees) {
  console.log(`❌ Уведомление остальным принявшим (${declinedEmployees.length} чел.): ${transfer.id}`);

  if (!declinedEmployees || declinedEmployees.length === 0) {
    return 0;
  }

  const title = 'Заявка на смену отклонена';
  const dateText = formatDate(transfer.shiftDate);
  const body = `Администратор выбрал другого сотрудника для смены ${formatShiftType(transfer.shiftType)} на ${dateText}`;
  const data = {
    type: 'shift_transfer_declined',
    transferId: transfer.id,
    action: 'view_request',
  };

  let sentCount = 0;

  for (const declined of declinedEmployees) {
    const employee = getEmployeeById(declined.employeeId);
    if (employee && employee.phone) {
      const success = await sendPushToPhone(employee.phone, title, body, data);
      if (success) sentCount++;
    }
  }

  console.log(`✅ Отправлено ${sentCount}/${declinedEmployees.length} уведомлений отклонённым`);
  return sentCount;
}

// ==================== ЭКСПОРТ ====================

module.exports = {
  notifyTransferCreated,
  notifyTransferAccepted,
  notifyTransferRejected,
  notifyTransferApproved,
  notifyTransferDeclined,
  notifyOthersDeclined,
};
