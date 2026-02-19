/**
 * Push Service — единый модуль отправки push-уведомлений
 *
 * Заменяет дублирующийся код из:
 * - report_notifications_api.js (sendPushNotification, sendPushToPhone)
 * - shift_transfers_notifications.js (getFirebaseAdmin, getFcmTokenByPhone, sendPushToPhone, sendPushToMultiple)
 * - product_questions_notifications.js (то же)
 * - master_catalog_notifications.js (то же)
 * - employee_chat_api.js (getFcmTokens, sendPushNotification)
 * - modules/orders.js (sendOrderNotification, sendNewOrderNotificationToEmployees)
 *
 * Включает:
 * - Удаление невалидных токенов (BUG-05)
 * - apns payload для iOS (BUG-07)
 * - Конверсия data в строки (требование Firebase)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, loadJsonFile, maskPhone } = require('./file_helpers');
const db = require('./db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const FCM_TOKENS_DIR = `${DATA_DIR}/fcm-tokens`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// Firebase Admin — инициализация на уровне модуля
let admin = null;
let firebaseInitialized = false;
try {
  const firebaseConfig = require('../firebase-admin-config');
  admin = firebaseConfig.admin;
  firebaseInitialized = firebaseConfig.firebaseInitialized;
} catch (e) {
  console.warn('[PushService] Firebase not available:', e.message);
}

/**
 * Паттерны ошибок невалидного FCM-токена
 */
const INVALID_TOKEN_PATTERNS = [
  'Requested entity was not found',
  'NotRegistered',
  'InvalidRegistration',
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
];

function isInvalidTokenError(errorMessage) {
  return INVALID_TOKEN_PATTERNS.some(pattern => errorMessage.includes(pattern));
}

/**
 * Удалить невалидный FCM-токен по телефону
 */
async function removeInvalidToken(phone) {
  try {
    const normalizedPhone = phone.replace(/[^\d]/g, '');
    // Удаляем из JSON
    const tokenFile = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);
    if (await fileExists(tokenFile)) {
      await fsp.unlink(tokenFile);
      console.log(`[PushService] Невалидный FCM токен удалён: ${maskPhone(phone)}`);
    }
    // Удаляем из PostgreSQL (BUG-02)
    try {
      await db.deleteById('fcm_tokens', normalizedPhone, 'phone');
    } catch (dbErr) {
      // Ignore — DB may not have this token yet
    }
  } catch (e) {
    console.error(`[PushService] Ошибка удаления токена:`, e.message);
  }
}

/**
 * Удалить невалидный FCM-токен по значению токена (когда phone неизвестен)
 */
async function removeInvalidTokenByValue(tokenValue) {
  try {
    if (!(await fileExists(FCM_TOKENS_DIR))) return;
    const files = await fsp.readdir(FCM_TOKENS_DIR);
    for (const file of files) {
      if (!file.endsWith('.json')) continue;
      const filePath = path.join(FCM_TOKENS_DIR, file);
      const tokenData = await loadJsonFile(filePath, null);
      if (tokenData && tokenData.token === tokenValue) {
        await fsp.unlink(filePath);
        console.log(`[PushService] Невалидный FCM токен удалён: ${file}`);
        break;
      }
    }
  } catch (e) {
    console.error(`[PushService] Ошибка удаления токена по значению:`, e.message);
  }
}

/**
 * Конвертировать все значения data в строки (требование Firebase)
 */
function stringifyData(data) {
  if (!data || typeof data !== 'object') return {};
  return Object.fromEntries(
    Object.entries(data).map(([k, v]) => [k, String(v)])
  );
}

/**
 * Построить FCM-сообщение
 * @param {string} token - FCM device token
 * @param {string} title - Заголовок уведомления
 * @param {string} body - Тело уведомления
 * @param {Object} data - Данные для навигации
 * @param {string} channelId - Android notification channel
 */
function buildMessage(token, title, body, data, channelId) {
  const message = {
    token,
    notification: { title, body },
    data: {
      ...stringifyData(data),
      click_action: 'FLUTTER_NOTIFICATION_CLICK',
    },
    android: {
      priority: 'high',
      notification: {
        sound: 'default',
        channelId: channelId || 'default_channel',
      },
    },
    apns: {
      payload: {
        aps: { sound: 'default', badge: 1 },
      },
    },
  };
  return message;
}

/**
 * Получить FCM-токен по номеру телефона
 * @param {string} phone - Номер телефона
 * @returns {string|null} FCM token или null
 */
async function getFcmTokenByPhone(phone) {
  try {
    const normalizedPhone = phone.replace(/[^\d]/g, '');
    const tokenFile = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);
    if (!(await fileExists(tokenFile))) return null;
    const tokenData = await loadJsonFile(tokenFile, null);
    return (tokenData && tokenData.token) || null;
  } catch (e) {
    console.error(`[PushService] Ошибка чтения токена ${maskPhone(phone)}:`, e.message);
    return null;
  }
}

/**
 * Получить FCM-токены для списка телефонов (параллельно)
 * @param {string[]} phones - Массив телефонов
 * @returns {Array<{phone: string, token: string}>}
 */
async function getFcmTokens(phones) {
  const results = await Promise.all(phones.map(async (phone) => {
    const token = await getFcmTokenByPhone(phone);
    return token ? { phone, token } : null;
  }));
  return results.filter(Boolean);
}

/**
 * Получить телефоны всех администраторов
 * @returns {string[]} Массив нормализованных телефонов
 */
async function getAdminPhones() {
  const adminPhones = [];
  try {
    if (!(await fileExists(EMPLOYEES_DIR))) return adminPhones;
    const files = await fsp.readdir(EMPLOYEES_DIR);
    for (const file of files) {
      if (!file.endsWith('.json')) continue;
      const employee = await loadJsonFile(path.join(EMPLOYEES_DIR, file), null);
      if (employee && employee.isAdmin === true && employee.phone) {
        adminPhones.push(employee.phone.replace(/[^\d]/g, ''));
      }
    }
  } catch (e) {
    console.error('[PushService] Ошибка получения админов:', e.message);
  }
  return adminPhones;
}

/**
 * Получить FCM-токены всех администраторов
 * @returns {Array<{phone: string, token: string}>}
 */
async function getAdminFcmTokens() {
  const adminPhones = await getAdminPhones();
  if (adminPhones.length === 0) return [];
  return await getFcmTokens(adminPhones);
}

/**
 * Отправить push одному пользователю по телефону
 * @param {string} phone - Номер телефона
 * @param {string} title - Заголовок
 * @param {string} body - Текст
 * @param {Object} [data={}] - Данные для навигации
 * @param {string} [channelId='default_channel'] - Android channel
 * @returns {boolean} Успешно ли отправлено
 */
async function sendPushToPhone(phone, title, body, data = {}, channelId = 'default_channel') {
  if (!firebaseInitialized || !admin) {
    console.log('[PushService] Firebase не инициализирован');
    return false;
  }

  const normalizedPhone = phone.replace(/[^\d]/g, '');
  const token = await getFcmTokenByPhone(normalizedPhone);
  if (!token) {
    console.log(`[PushService] Токен не найден: ${maskPhone(phone)}`);
    return false;
  }

  try {
    const message = buildMessage(token, title, body, data, channelId);
    await admin.messaging().send(message);
    console.log(`[PushService] Push отправлен: ${maskPhone(phone)}`);
    return true;
  } catch (e) {
    console.error(`[PushService] Ошибка push ${maskPhone(phone)}:`, e.message);
    if (isInvalidTokenError(e.message || '')) {
      await removeInvalidToken(normalizedPhone);
    }
    return false;
  }
}

/**
 * Отправить push списку сотрудников
 * @param {Array<{phone: string}>} employees - Массив объектов с полем phone
 * @param {string} title
 * @param {string} body
 * @param {Object} [data={}]
 * @param {string} [channelId='default_channel']
 * @returns {number} Количество успешных отправок
 */
async function sendPushToMultiple(employees, title, body, data = {}, channelId = 'default_channel') {
  let successCount = 0;
  for (const employee of employees) {
    if (!employee.phone) continue;
    const success = await sendPushToPhone(employee.phone, title, body, data, channelId);
    if (success) successCount++;
  }
  console.log(`[PushService] Отправлено ${successCount}/${employees.length}`);
  return successCount;
}

/**
 * Отправить push всем администраторам
 * @param {string} title
 * @param {string} body
 * @param {Object} [data={}]
 * @param {string} [channelId='reports_channel']
 */
async function sendPushToAllAdmins(title, body, data = {}, channelId = 'reports_channel') {
  if (!firebaseInitialized || !admin) {
    console.log('[PushService] Firebase не инициализирован');
    return;
  }

  const adminTokens = await getAdminFcmTokens();
  if (adminTokens.length === 0) {
    console.log('[PushService] Нет FCM токенов админов');
    return;
  }

  console.log(`[PushService] Push ${adminTokens.length} админам: ${title}`);

  for (const { phone, token } of adminTokens) {
    try {
      const message = buildMessage(token, title, body, data, channelId);
      await admin.messaging().send(message);
      console.log(`[PushService] Push админу отправлен: ${maskPhone(phone)}`);
    } catch (e) {
      console.error(`[PushService] Ошибка push админу ${maskPhone(phone)}:`, e.message);
      if (isInvalidTokenError(e.message || '')) {
        await removeInvalidToken(phone);
      }
    }
  }
}

/**
 * Отправить push по прямому FCM-токену (для cases когда токен уже известен)
 * @param {string} token - FCM device token
 * @param {string} title
 * @param {string} body
 * @param {Object} [data={}]
 * @param {string} [channelId='default_channel']
 * @param {string} [phone] - Телефон для логирования и удаления невалидного токена
 * @returns {boolean}
 */
async function sendPushByToken(token, title, body, data = {}, channelId = 'default_channel', phone = null) {
  if (!firebaseInitialized || !admin) return false;

  try {
    const message = buildMessage(token, title, body, data, channelId);
    await admin.messaging().send(message);
    if (phone) console.log(`[PushService] Push отправлен: ${maskPhone(phone)}`);
    return true;
  } catch (e) {
    if (phone) console.error(`[PushService] Ошибка push ${maskPhone(phone)}:`, e.message);
    if (isInvalidTokenError(e.message || '')) {
      if (phone) {
        await removeInvalidToken(phone);
      } else {
        await removeInvalidTokenByValue(token);
      }
    }
    return false;
  }
}

module.exports = {
  sendPushToPhone,
  sendPushToMultiple,
  sendPushToAllAdmins,
  sendPushByToken,
  getFcmTokenByPhone,
  getFcmTokens,
  getAdminPhones,
  getAdminFcmTokens,
  isInvalidTokenError,
  removeInvalidToken,
  stringifyData,
  buildMessage,
};
