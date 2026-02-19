/**
 * MASTER CATALOG NOTIFICATIONS
 * Push-уведомления для мастер-каталога товаров
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 *
 * Типы уведомлений:
 * - new_pending_code - Обнаружен новый код товара
 */

const pushService = require('../utils/push_service');

// ==================== ФУНКЦИИ УВЕДОМЛЕНИЙ ====================

const CHANNEL = 'master_catalog_channel';

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

  await pushService.sendPushToAllAdmins(title, body, data, CHANNEL);
}

// ==================== ЭКСПОРТ ====================

module.exports = {
  notifyAdminsAboutNewCodes,
};
