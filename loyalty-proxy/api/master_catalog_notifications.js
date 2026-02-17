/**
 * MASTER CATALOG NOTIFICATIONS
 * Push-уведомления для мастер-каталога товаров
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 *
 * Типы уведомлений:
 * - new_pending_code - Обнаружен новый код товара
 */

const fsp = require('fs').promises;
const path = require('path');
const { maskPhone, fileExists } = require('../utils/file_helpers');

// Константы
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const FCM_TOKENS_DIR = `${DATA_DIR}/fcm-tokens`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// ==================== УТИЛИТЫ ====================

/**
 * Получить Firebase Admin SDK
 * @returns {Object|null} Firebase Admin или null
 */
function getFirebaseAdmin() {
  try {
    const { admin, firebaseInitialized } = require('../firebase-admin-config');
    if (!firebaseInitialized) {
      console.log('[Master Catalog Notifications] Firebase not initialized');
      return null;
    }
    return admin;
  } catch (e) {
    console.error('[Master Catalog Notifications] Firebase load error:', e.message);
    return null;
  }
}

/**
 * Получить список всех администраторов
 * @returns {Promise<Array>} Массив администраторов
 */
async function getAllAdmins() {
  const admins = [];
  try {
    if (!(await fileExists(EMPLOYEES_DIR))) {
      return admins;
    }

    const files = (await fsp.readdir(EMPLOYEES_DIR)).filter((f) => f.endsWith('.json'));

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
        // Ignore individual file errors
      }
    }
  } catch (e) {
    console.error('[Master Catalog Notifications] Error getting admins:', e.message);
  }

  return admins;
}

/**
 * Получить FCM токен сотрудника по телефону
 * @param {string} phone - Номер телефона
 * @returns {Promise<string|null>} FCM токен или null
 */
async function getFcmTokenByPhone(phone) {
  try {
    const normalizedPhone = phone.replace(/[^\d]/g, '');
    const tokenFile = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);

    if (!(await fileExists(tokenFile))) {
      return null;
    }

    const content = await fsp.readFile(tokenFile, 'utf8');
    const tokenData = JSON.parse(content);
    return tokenData.token || null;
  } catch (e) {
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
    return false;
  }

  const token = await getFcmTokenByPhone(phone);
  if (!token) {
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
          channelId: 'master_catalog_channel',
        },
      },
    });

    return true;
  } catch (e) {
    console.error(`[Master Catalog Notifications] Push error for ${maskPhone(phone)}:`, e.message);
    return false;
  }
}

// ==================== ФУНКЦИИ УВЕДОМЛЕНИЙ ====================

/**
 * Уведомить админов о новых кодах товаров
 * @param {Array} newCodes - Массив новых кодов [{kod, name, group}]
 * @param {string} shopName - Название магазина откуда пришли коды
 * @returns {Promise<number>} Количество успешно отправленных уведомлений
 */
async function notifyAdminsAboutNewCodes(newCodes, shopName) {
  if (!newCodes || newCodes.length === 0) {
    return 0;
  }

  console.log(`[Master Catalog Notifications] Sending notifications for ${newCodes.length} new codes`);

  const admins = await getAllAdmins();
  if (admins.length === 0) {
    console.log('[Master Catalog Notifications] No admins found');
    return 0;
  }

  // Формируем текст уведомления
  const title = 'New Products';
  let body;

  if (newCodes.length === 1) {
    body = `New code detected: ${newCodes[0].name || newCodes[0].kod}`;
  } else if (newCodes.length <= 3) {
    const names = newCodes.map((c) => c.name || c.kod).join(', ');
    body = `New products detected: ${names}`;
  } else {
    body = `${newCodes.length} new products from shop ${shopName}`;
  }

  const data = {
    type: 'new_pending_codes',
    codesCount: String(newCodes.length),
    shopName: shopName,
    action: 'view_pending_codes',
  };

  let successCount = 0;

  for (const admin of admins) {
    if (!admin.phone) continue;

    const success = await sendPushToPhone(admin.phone, title, body, data);
    if (success) {
      successCount++;
      console.log(`[Master Catalog Notifications] Push sent to admin: ${admin.name}`);
    }
  }

  console.log(`[Master Catalog Notifications] Sent ${successCount}/${admins.length} notifications`);
  return successCount;
}

// ==================== ЭКСПОРТ ====================

module.exports = {
  notifyAdminsAboutNewCodes,
};
