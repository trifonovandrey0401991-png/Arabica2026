/**
 * PRODUCT QUESTIONS NOTIFICATIONS API
 * Система push-уведомлений для вопросов о товаре
 *
 * Типы уведомлений:
 * - product_question_created - Новый вопрос от клиента
 * - product_question_answered - Сотрудник ответил на вопрос
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
 * Получить список всех сотрудников (для broadcast)
 * @returns {Array} Массив сотрудников
 */
function getAllEmployees() {
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
 * Получить FCM токен по телефону
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
          channelId: 'product_questions_channel',
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

// ==================== ФУНКЦИИ УВЕДОМЛЕНИЙ ====================

/**
 * Уведомить сотрудников о новом вопросе клиента
 * Broadcast всем сотрудникам (без фильтра по магазину)
 *
 * @param {Object} question - Объект вопроса или сообщения
 * @returns {Promise<void>}
 */
async function notifyQuestionCreated(question) {
  console.log('📨 Отправка уведомлений о новом вопросе...');

  const employees = getAllEmployees();
  if (employees.length === 0) {
    console.log('⚠️  Нет получателей для уведомления');
    return;
  }

  // Определить данные из вопроса или сообщения
  const clientName = question.clientName || question.senderName || 'Клиент';
  const questionText = question.questionText || question.text || '';
  const questionId = question.id || '';
  const shopAddress = question.shopAddress || question.originalShopAddress || '';

  // Обрезать текст вопроса если он длинный
  const shortText = questionText.length > 50
    ? questionText.substring(0, 50) + '...'
    : questionText;

  const title = 'Новый вопрос о товаре';
  const body = `${clientName} спрашивает: "${shortText}"`;

  const data = {
    type: 'product_question_created',
    questionId: questionId,
    shopAddress: shopAddress,
    action: 'view_question',
  };

  console.log(`📨 Broadcast: отправка ${employees.length} сотрудникам`);
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
  console.log('📨 Отправка уведомления клиенту об ответе...');

  const clientPhone = question.clientPhone;
  if (!clientPhone) {
    console.log('⚠️  Нет телефона клиента для уведомления');
    return;
  }

  // Определить данные из ответа
  const shopName = answer.shopAddress || 'Сотрудник';
  const answerText = answer.text || '';

  // Обрезать текст ответа если он длинный
  const shortText = answerText.length > 50
    ? answerText.substring(0, 50) + '...'
    : answerText;

  const title = 'Ответ на ваш вопрос';
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
  console.log('📨 Отправка уведомлений сотрудникам о сообщении в персональном диалоге...');

  // Получить всех сотрудников
  const allEmployees = getAllEmployees();
  if (allEmployees.length === 0) {
    console.log('⚠️  Нет сотрудников для уведомления');
    return;
  }

  // Фильтровать только сотрудников этого магазина
  const shopAddress = dialog.shopAddress;
  const shopEmployees = allEmployees.filter(emp => {
    if (!emp.assignedShops || !Array.isArray(emp.assignedShops)) {
      return false;
    }
    return emp.assignedShops.includes(shopAddress);
  });

  if (shopEmployees.length === 0) {
    console.log(`⚠️  Нет сотрудников для магазина ${shopAddress}`);
    return;
  }

  const clientName = message.senderName || dialog.clientName || 'Клиент';
  const messageText = message.text || '';

  const shortText = messageText.length > 50
    ? messageText.substring(0, 50) + '...'
    : messageText;

  const title = 'Сообщение в поиске товара';
  const body = `${clientName}: "${shortText}"`;

  const data = {
    type: 'personal_dialog_client_message',
    dialogId: dialog.id,
    shopAddress: shopAddress,
    action: 'view_personal_dialog',
  };

  console.log(`📨 Уведомление ${shopEmployees.length} сотрудникам магазина ${shopAddress}`);
  await sendPushToMultiple(shopEmployees, title, body, data);
}

/**
 * Уведомить клиента об ответе сотрудника в персональном диалоге
 * @param {Object} dialog - Объект персонального диалога
 * @param {Object} message - Объект сообщения от сотрудника
 * @returns {Promise<void>}
 */
async function notifyPersonalDialogEmployeeMessage(dialog, message) {
  console.log('📨 Отправка уведомления клиенту о сообщении в персональном диалоге...');

  const clientPhone = dialog.clientPhone;
  if (!clientPhone) {
    console.log('⚠️  Нет телефона клиента для уведомления');
    return;
  }

  const shopName = message.shopAddress || dialog.shopAddress || 'Магазин';
  const messageText = message.text || '';

  const shortText = messageText.length > 50
    ? messageText.substring(0, 50) + '...'
    : messageText;

  const title = 'Ответ от магазина';
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
