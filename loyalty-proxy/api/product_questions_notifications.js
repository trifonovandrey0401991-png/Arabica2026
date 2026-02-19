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
const { maskPhone, fileExists } = require('../utils/file_helpers');
const pushService = require('../utils/push_service');

// Константы
const DATA_DIR = process.env.DATA_DIR || '/var/www';
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// Push-функции делегируются в push_service.js (BUG-06: единый модуль)
const CHANNEL = 'product_questions_channel';

function sendPushToPhone(phone, title, body, data = {}) {
  return pushService.sendPushToPhone(phone, title, body, data, CHANNEL);
}

function sendPushToMultiple(employees, title, body, data = {}) {
  return pushService.sendPushToMultiple(employees, title, body, data, CHANNEL);
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
  const clientName = question.clientName || question.senderName || 'Клиент';
  const questionText = question.questionText || question.text || '';
  const questionId = question.id || '';
  const shopAddress = question.shopAddress || question.originalShopAddress || '';

  // Обрезать текст вопроса если он длинный
  const shortText = questionText.length > 50
    ? questionText.substring(0, 50) + '...'
    : questionText;

  const title = 'Новый вопрос о товаре';
  const body = `${clientName}: "${shortText}"`;

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
  console.log('Sending notifications to ALL employees about personal dialog message...');

  // Получить всех сотрудников (broadcast - любой может ответить)
  const allEmployees = await getAllEmployees();
  if (allEmployees.length === 0) {
    console.log('No employees for notification');
    return;
  }

  const shopAddress = dialog.shopAddress;
  const clientName = message.senderName || dialog.clientName || 'Клиент';
  const messageText = message.text || '';

  const shortText = messageText.length > 50
    ? messageText.substring(0, 50) + '...'
    : messageText;

  const title = 'Сообщение в поиске товара';
  const body = `${shopAddress}: ${clientName} — "${shortText}"`;

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
