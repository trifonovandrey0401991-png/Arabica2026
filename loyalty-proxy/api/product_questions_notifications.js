/**
 * PRODUCT QUESTIONS NOTIFICATIONS API
 * Система push-уведомлений для вопросов о товаре
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 *
 * Типы уведомлений:
 * - product_question_created - Новый вопрос от клиента
 * - product_question_answered - Сотрудник ответил на вопрос
 */

const fsp = require('fs').promises;
const path = require('path');

// Константы
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const FCM_TOKENS_DIR = `${DATA_DIR}/fcm-tokens`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// ==================== УТИЛИТЫ ====================

/**
 * Получить Firebase Admin SDK
 * @returns {Object|null} Firebase Admin или null
 */
function getFirebaseAdmin() {
  try {
    const { admin, firebaseInitialized } = require('../firebase-admin-config');
    if (!firebaseInitialized) {
      console.log('Firebase not initialized');
      return null;
    }
    return admin;
  } catch (e) {
    console.error('Firebase load error:', e.message);
    return null;
  }
}

/**
 * Получить список всех сотрудников (для broadcast)
 * @returns {Promise<Array>} Массив сотрудников
 */
async function getAllEmployees() {
  const employees = [];
  try {
    if (!(await fileExists(EMPLOYEES_DIR))) {
      console.log('Employees directory does not exist');
      return employees;
    }

    const files = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const filePath = path.join(EMPLOYEES_DIR, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const employee = JSON.parse(content);
        employees.push(employee);
      } catch (e) {
        console.error(`Error reading file ${file}:`, e.message);
      }
    }
  } catch (e) {
    console.error('Error getting employees list:', e.message);
  }

  return employees;
}

/**
 * Получить FCM токен по телефону
 * @param {string} phone - Номер телефона
 * @returns {Promise<string|null>} FCM токен или null
 */
async function getFcmTokenByPhone(phone) {
  try {
    const normalizedPhone = phone.replace(/[\s+]/g, '');
    const tokenFile = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);

    if (!(await fileExists(tokenFile))) {
      return null;
    }

    const content = await fsp.readFile(tokenFile, 'utf8');
    const tokenData = JSON.parse(content);
    return tokenData.token || null;
  } catch (e) {
    console.error(`Error getting token for ${phone}:`, e.message);
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
    console.log('Firebase not available, notification not sent');
    return false;
  }

  const token = await getFcmTokenByPhone(phone);
  if (!token) {
    console.log(`FCM token not found for ${phone}`);
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
          channelId: 'product_questions_channel',
        },
      },
    });

    console.log(`Push sent: ${phone.substring(0, 5)}***`);
    return true;
  } catch (e) {
    console.error(`Push error for ${phone}:`, e.message);
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
      console.log(`Employee ${employee.name || employee.id} has no phone`);
      continue;
    }

    const success = await sendPushToPhone(employee.phone, title, body, data);
    if (success) successCount++;
  }

  console.log(`Sent ${successCount}/${employees.length} notifications`);
  return successCount;
}

// ==================== ФУНКЦИИ УВЕДОМЛЕНИЙ ====================

/**
 * Уведомить сотрудников о новом вопросе клиента
 * Broadcast всем сотрудникам (без фильтра по магазину)
 *
 * @param {Object} question - Объект вопроса или сообщения
 * @returns {Promise<void>}
 */
async function notifyQuestionCreated(question) {
  console.log('Sending notifications about new question...');

  const employees = await getAllEmployees();
  if (employees.length === 0) {
    console.log('No recipients for notification');
    return;
  }

  // Определить данные из вопроса или сообщения
  const clientName = question.clientName || question.senderName || 'Client';
  const questionText = question.questionText || question.text || '';
  const questionId = question.id || '';
  const shopAddress = question.shopAddress || question.originalShopAddress || '';

  // Обрезать текст вопроса если он длинный
  const shortText = questionText.length > 50
    ? questionText.substring(0, 50) + '...'
    : questionText;

  const title = 'New product question';
  const body = `${clientName} asks: "${shortText}"`;

  const data = {
    type: 'product_question_created',
    questionId: questionId,
    shopAddress: shopAddress,
    action: 'view_question',
  };

  console.log(`Broadcast: sending to ${employees.length} employees`);
  await sendPushToMultiple(employees, title, body, data);
}

/**
 * Уведомить клиента об ответе сотрудника
 * Прямое уведомление конкретному клиенту
 *
 * @param {Object} question - Объект вопроса с данными клиента
 * @param {Object} answer - Объект ответа от сотрудника
 * @returns {Promise<void>}
 */
async function notifyQuestionAnswered(question, answer) {
  console.log('Sending notification to client about answer...');

  const clientPhone = question.clientPhone;
  if (!clientPhone) {
    console.log('No client phone for notification');
    return;
  }

  // Определить данные из ответа
  const shopName = answer.shopAddress || 'Employee';
  const answerText = answer.text || '';

  // Обрезать текст ответа если он длинный
  const shortText = answerText.length > 50
    ? answerText.substring(0, 50) + '...'
    : answerText;

  const title = 'Answer to your question';
  const body = `${shopName}: ${shortText}`;

  const data = {
    type: 'product_question_answered',
    questionId: question.id || '',
    shopAddress: answer.shopAddress || '',
    action: 'view_answer',
  };

  await sendPushToPhone(clientPhone, title, body, data);
}

/**
 * Уведомить сотрудников магазина о новом сообщении клиента в персональном диалоге
 * @param {Object} dialog - Объект персонального диалога
 * @param {Object} message - Объект сообщения от клиента
 * @returns {Promise<void>}
 */
async function notifyPersonalDialogClientMessage(dialog, message) {
  console.log('Sending notifications to ALL employees about personal dialog message...');

  // Получить всех сотрудников (broadcast - любой может ответить)
  const allEmployees = await getAllEmployees();
  if (allEmployees.length === 0) {
    console.log('No employees for notification');
    return;
  }

  const shopAddress = dialog.shopAddress;
  const clientName = message.senderName || dialog.clientName || 'Client';
  const messageText = message.text || '';

  const shortText = messageText.length > 50
    ? messageText.substring(0, 50) + '...'
    : messageText;

  const title = 'Message in product search';
  const body = `${shopAddress}: ${clientName} - "${shortText}"`;

  const data = {
    type: 'personal_dialog_client_message',
    dialogId: dialog.id,
    shopAddress: shopAddress,
    action: 'view_personal_dialog',
  };

  console.log(`Broadcast: sending to ${allEmployees.length} employees`);
  await sendPushToMultiple(allEmployees, title, body, data);
}

/**
 * Уведомить клиента об ответе сотрудника в персональном диалоге
 * @param {Object} dialog - Объект персонального диалога
 * @param {Object} message - Объект сообщения от сотрудника
 * @returns {Promise<void>}
 */
async function notifyPersonalDialogEmployeeMessage(dialog, message) {
  console.log('Sending notification to client about personal dialog message...');

  const clientPhone = dialog.clientPhone;
  if (!clientPhone) {
    console.log('No client phone for notification');
    return;
  }

  const shopName = message.shopAddress || dialog.shopAddress || 'Shop';
  const messageText = message.text || '';

  const shortText = messageText.length > 50
    ? messageText.substring(0, 50) + '...'
    : messageText;

  const title = 'Response from shop';
  const body = `${shopName}: ${shortText}`;

  const data = {
    type: 'personal_dialog_employee_message',
    dialogId: dialog.id,
    shopAddress: dialog.shopAddress,
    action: 'view_personal_dialog',
  };

  await sendPushToPhone(clientPhone, title, body, data);
}

// ==================== ЭКСПОРТ ====================

module.exports = {
  notifyQuestionCreated,
  notifyQuestionAnswered,
  notifyPersonalDialogClientMessage,
  notifyPersonalDialogEmployeeMessage,
};
