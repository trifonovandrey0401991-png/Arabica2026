/**
 * SHIFT TRANSFERS NOTIFICATIONS API
 * Система push-уведомлений для замен смены
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 *
 * Типы уведомлений:
 * - shift_transfer_created - Новый запрос на замену смены
 * - shift_transfer_accepted - Сотрудник принял запрос
 * - shift_transfer_rejected - Сотрудник отклонил запрос
 * - shift_transfer_pending_approval - Требуется одобрение админа
 * - shift_transfer_approved - Админ одобрил замену
 * - shift_transfer_declined - Админ отклонил замену
 */

const fsp = require('fs').promises;
const path = require('path');
const { maskPhone, fileExists } = require('../utils/file_helpers');
const pushService = require('../utils/push_service');
const db = require('../utils/db');

// Feature flag
const USE_DB_EMPLOYEES = process.env.USE_DB_EMPLOYEES === 'true';

// Константы
const EMPLOYEES_DIR = process.env.DATA_DIR ? `${process.env.DATA_DIR}/employees` : '/var/www/employees';

// ==================== УТИЛИТЫ ====================

/**
 * Получить данные сотрудника по ID
 * @param {string} employeeId - ID сотрудника
 * @returns {Promise<Object|null>} Данные сотрудника или null
 */
async function getEmployeeById(employeeId) {
  // DB first
  if (USE_DB_EMPLOYEES) {
    try {
      const row = await db.findById('employees', employeeId);
      if (row) {
        return {
          id: row.id,
          name: row.name,
          phone: row.phone,
          isAdmin: row.is_admin || false,
          shopAddresses: row.shop_addresses || [],
        };
      }
    } catch (dbErr) {
      console.error(`[ShiftTransferNotif] DB error for employee ${employeeId}:`, dbErr.message);
    }
  }
  // Fallback: JSON
  try {
    const employeeFile = path.join(EMPLOYEES_DIR, `${employeeId}.json`);
    if (await fileExists(employeeFile)) {
      const content = await fsp.readFile(employeeFile, 'utf8');
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
 * @returns {Promise<Array>} Массив сотрудников
 */
async function getAllEmployees(excludeEmployeeId = null) {
  // DB first
  if (USE_DB_EMPLOYEES) {
    try {
      const result = await db.query('SELECT * FROM employees');
      if (result.rows.length > 0) {
        return result.rows
          .filter(row => !excludeEmployeeId || row.id !== excludeEmployeeId)
          .map(row => ({
            id: row.id,
            name: row.name,
            phone: row.phone,
            isAdmin: row.is_admin || false,
            shopAddresses: row.shop_addresses || [],
          }));
      }
    } catch (dbErr) {
      console.error('[ShiftTransferNotif] DB error for getAllEmployees:', dbErr.message);
    }
  }
  // Fallback: JSON
  const employees = [];
  try {
    if (!(await fileExists(EMPLOYEES_DIR))) {
      console.log('⚠️  Папка сотрудников не существует');
      return employees;
    }

    const files = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const filePath = path.join(EMPLOYEES_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
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
 * @returns {Promise<Array>} Массив администраторов
 */
async function getAllAdmins() {
  // DB first
  if (USE_DB_EMPLOYEES) {
    try {
      const result = await db.query("SELECT * FROM employees WHERE is_admin = true");
      if (result.rows.length > 0) {
        console.log(`✅ Найдено ${result.rows.length} администраторов (DB)`);
        return result.rows.map(row => ({
          id: row.id,
          name: row.name,
          phone: row.phone,
          isAdmin: true,
          shopAddresses: row.shop_addresses || [],
        }));
      }
    } catch (dbErr) {
      console.error('[ShiftTransferNotif] DB error for getAllAdmins:', dbErr.message);
    }
  }
  // Fallback: JSON
  const admins = [];
  try {
    if (!(await fileExists(EMPLOYEES_DIR))) {
      console.log('⚠️  Папка сотрудников не существует');
      return admins;
    }

    const files = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const filePath = path.join(EMPLOYEES_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
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

// Push-функции делегируются в push_service.js (BUG-06: единый модуль)
const CHANNEL = 'shift_transfers_channel';

function sendPushToPhone(phone, title, body, data = {}) {
  return pushService.sendPushToPhone(phone, title, body, data, CHANNEL);
}

function sendPushToMultiple(employees, title, body, data = {}) {
  return pushService.sendPushToMultiple(employees, title, body, data, CHANNEL);
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
    const targetEmployee = await getEmployeeById(transfer.toEmployeeId);
    if (targetEmployee) {
      recipients = [targetEmployee];
      console.log(`📨 Отправка конкретному сотруднику: ${targetEmployee.name}`);
    } else {
      console.log(`⚠️  Сотрудник ${transfer.toEmployeeId} не найден`);
    }
  }
  // Broadcast - всем сотрудникам (кроме отправителя)
  else {
    recipients = await getAllEmployees(transfer.fromEmployeeId);
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
  const fromEmployee = await getEmployeeById(transfer.fromEmployeeId);
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
  const admins = await getAllAdmins();
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

  const fromEmployee = await getEmployeeById(transfer.fromEmployeeId);
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
  const fromEmployee = await getEmployeeById(transfer.fromEmployeeId);
  if (fromEmployee && fromEmployee.phone) {
    const body = `Ваша замена смены на ${dateText} одобрена администратором`;
    const success = await sendPushToPhone(fromEmployee.phone, title, body, data);
    if (success) sentCount++;
  }

  // 2. Уведомить одобренного сотрудника
  const acceptedEmployee = await getEmployeeById(approvedEmployeeId);
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
  const fromEmployee = await getEmployeeById(transfer.fromEmployeeId);
  if (fromEmployee && fromEmployee.phone) {
    const success = await sendPushToPhone(fromEmployee.phone, title, body, data);
    if (success) sentCount++;
  }

  // 2. Уведомить принявшего (если есть)
  if (transfer.acceptedByEmployeeId) {
    const acceptedEmployee = await getEmployeeById(transfer.acceptedByEmployeeId);
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
    const employee = await getEmployeeById(declined.employeeId);
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
