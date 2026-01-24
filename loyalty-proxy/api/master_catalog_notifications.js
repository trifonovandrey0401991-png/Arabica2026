/**
 * MASTER CATALOG NOTIFICATIONS
 * Push-уведомления для мастер-каталога товаров
 *
 * Типы уведомлений:
 * - new_pending_code - Обнаружен новый код товара
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
      console.log('[Master Catalog Notifications] Firebase не инициализирован');
      return null;
    }
    return admin;
  } catch (e) {
    console.error('[Master Catalog Notifications] Ошибка загрузки Firebase:', e.message);
    return null;
  }
}

/**
 * Получить список всех администраторов
 * @returns {Array} Массив администраторов
 */
function getAllAdmins() {
  const admins = [];
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) {
      return admins;
    }

    const files = fs.readdirSync(EMPLOYEES_DIR).filter((f) => f.endsWith('.json'));

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
        // Ignore individual file errors
      }
    }
  } catch (e) {
    console.error('[Master Catalog Notifications] Ошибка получения админов:', e.message);
  }

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

  const token = getFcmTokenByPhone(phone);
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
    console.error(`[Master Catalog Notifications] Ошибка push на ${phone}:`, e.message);
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

  console.log(`[Master Catalog Notifications] Отправка уведомлений о ${newCodes.length} новых кодах`);

  const admins = getAllAdmins();
  if (admins.length === 0) {
    console.log('[Master Catalog Notifications] Админы не найдены');
    return 0;
  }

  // Формируем текст уведомления
  const title = 'Новые товары';
  let body;

  if (newCodes.length === 1) {
    body = `Обнаружен новый код: ${newCodes[0].name || newCodes[0].kod}`;
  } else if (newCodes.length <= 3) {
    const names = newCodes.map((c) => c.name || c.kod).join(', ');
    body = `Обнаружены новые товары: ${names}`;
  } else {
    body = `Обнаружено ${newCodes.length} новых товаров от магазина ${shopName}`;
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
      console.log(`[Master Catalog Notifications] Push отправлен админу: ${admin.name}`);
    }
  }

  console.log(`[Master Catalog Notifications] Отправлено ${successCount}/${admins.length} уведомлений`);
  return successCount;
}

// ==================== ЭКСПОРТ ====================

module.exports = {
  notifyAdminsAboutNewCodes,
};
