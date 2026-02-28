/**
 * Orders Module
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 * REFACTORED: Added PostgreSQL support with USE_DB_ORDERS flag (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const pushService = require('../utils/push_service');
const { sendPushNotification } = require('../api/report_notifications_api');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile, withLock } = require('../utils/async_fs');
const db = require('../utils/db');
const { spendPoints, getBalance } = require('../api/loyalty_wallet_api');
const { loadAuthorizedEmployees } = require('../api/shop_catalog_api');
const { loadShopManagers } = require('../api/shop_managers_api');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const USE_DB = process.env.USE_DB_ORDERS === 'true';

const ORDERS_DIR = `${DATA_DIR}/orders`;
const COUNTER_FILE = path.join(ORDERS_DIR, 'order-counter.json');
const DIALOGS_DIR = `${DATA_DIR}/client-dialogs`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// Файлы для отслеживания просмотров заказов
const ORDERS_VIEWED_REJECTED_FILE = `${DATA_DIR}/orders-viewed-rejected.json`;
const ORDERS_VIEWED_UNCONFIRMED_FILE = `${DATA_DIR}/orders-viewed-unconfirmed.json`;

// =====================================================
// DB CONVERSION
// =====================================================

function dbOrderToCamel(row) {
  return {
    id: row.id,
    orderNumber: row.order_number,
    clientPhone: row.client_phone,
    clientName: row.client_name,
    shopAddress: row.shop_address,
    items: typeof row.items === 'string' ? JSON.parse(row.items) : row.items,
    totalPrice: row.total_price != null ? Number(row.total_price) : null,
    comment: row.comment,
    status: row.status,
    acceptedBy: row.accepted_by,
    rejectedBy: row.rejected_by,
    rejectionReason: row.rejection_reason,
    rejectedAt: row.rejected_at,
    expiredAt: row.expired_at,
    isWholesaleOrder: row.is_wholesale_order || false,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

// =====================================================
// ФУНКЦИИ ДЛЯ ОТСЛЕЖИВАНИЯ ПРОСМОТРОВ ЗАКАЗОВ
// =====================================================

// Получить дату последнего просмотра (async)
async function getLastViewedAt(type) {
  try {
    const file = type === 'rejected' ? ORDERS_VIEWED_REJECTED_FILE : ORDERS_VIEWED_UNCONFIRMED_FILE;
    if (await fileExists(file)) {
      const content = await fsp.readFile(file, 'utf8');
      const data = JSON.parse(content);
      return data.lastViewedAt ? new Date(data.lastViewedAt) : null;
    }
    return null;
  } catch (error) {
    console.error('Error reading lastViewedAt for ' + type + ':', error);
    return null;
  }
}

// Сохранить дату последнего просмотра (async)
async function saveLastViewedAt(type, date) {
  try {
    const file = type === 'rejected' ? ORDERS_VIEWED_REJECTED_FILE : ORDERS_VIEWED_UNCONFIRMED_FILE;
    await writeJsonFile(file, { lastViewedAt: date.toISOString() });
    return true;
  } catch (error) {
    console.error('Error writing lastViewedAt for ' + type + ':', error);
    return false;
  }
}

// Подсчёт непросмотренных заказов
async function countUnviewedOrders(status, lastViewedAt) {
  if (USE_DB) {
    try {
      const dateColumn = status === 'rejected' ? 'rejected_at' : 'expired_at';
      let query = `SELECT COUNT(*)::int as count FROM orders WHERE status = $1 AND ${dateColumn} IS NOT NULL`;
      const params = [status];

      if (lastViewedAt) {
        query += ` AND ${dateColumn} > $2`;
        params.push(lastViewedAt.toISOString());
      }

      const result = await db.query(query, params);
      return result.rows[0].count;
    } catch (err) {
      console.error('DB error counting unviewed orders:', err.message);
      return 0;
    }
  }

  let count = 0;

  try {
    const files = await fsp.readdir(ORDERS_DIR);

    for (const file of files) {
      if (!file.endsWith('.json') || file === 'order-counter.json') continue;

      try {
        const content = await fsp.readFile(path.join(ORDERS_DIR, file), 'utf8');
        const order = JSON.parse(content);

        if (order.status !== status) continue;

        // Для rejected проверяем rejectedAt, для unconfirmed - expiredAt
        let orderTime = null;
        if (status === 'rejected' && order.rejectedAt) {
          orderTime = new Date(order.rejectedAt);
        } else if (status === 'unconfirmed' && order.expiredAt) {
          orderTime = new Date(order.expiredAt);
        }

        if (!orderTime) continue;

        // Если lastViewedAt не задано - считаем все новыми
        if (!lastViewedAt || orderTime > lastViewedAt) {
          count++;
        }
      } catch (err) {
        // Пропускаем битые файлы
      }
    }
  } catch (err) {
    console.error('Ошибка подсчёта непросмотренных заказов:', err);
  }

  return count;
}

// Получить количество непросмотренных заказов
async function getUnviewedOrdersCounts() {
  const rejectedLastViewed = await getLastViewedAt('rejected');
  const unconfirmedLastViewed = await getLastViewedAt('unconfirmed');

  const rejectedCount = await countUnviewedOrders('rejected', rejectedLastViewed);
  const unconfirmedCount = await countUnviewedOrders('unconfirmed', unconfirmedLastViewed);

  return {
    rejected: rejectedCount,
    unconfirmed: unconfirmedCount,
    total: rejectedCount + unconfirmedCount
  };
}

async function getNextOrderNumber() {
  if (USE_DB) {
    const result = await db.query('SELECT COALESCE(MAX(order_number), 0) + 1 as next_num FROM orders');
    return result.rows[0].next_num;
  }

  const lockFile = COUNTER_FILE + '.lock';
  let attempts = 0;
  const maxAttempts = 10;

  while (attempts < maxAttempts) {
    try {
      await fsp.writeFile(lockFile, '', { flag: 'wx' });
      break;
    } catch {
      await new Promise(r => setTimeout(r, 100));
      attempts++;
    }
  }

  if (attempts >= maxAttempts) {
    throw new Error('Не удалось получить блокировку счетчика заказов');
  }

  try {
    const data = await fsp.readFile(COUNTER_FILE, 'utf8');
    const { counter } = JSON.parse(data);
    const nextCounter = counter + 1;
    // Boy Scout: fsp.writeFile → writeJsonFile
    await writeJsonFile(COUNTER_FILE, { counter: nextCounter });
    return nextCounter;
  } finally {
    await fsp.unlink(lockFile).catch(() => {});
  }
}

async function createOrder(orderData) {
  const orderNumber = await getNextOrderNumber();
  const orderId = uuidv4();
  const now = new Date().toISOString();

  // Check if client is wholesale
  let isWholesaleOrder = false;
  if (orderData.clientPhone) {
    try {
      const balance = await getBalance(orderData.clientPhone);
      isWholesaleOrder = balance.isWholesale || false;
    } catch (e) {
      console.error('⚠️ Could not check wholesale status:', e.message);
    }
  }

  let order;

  if (USE_DB) {
    const row = await db.insert('orders', {
      id: orderId,
      order_number: orderNumber,
      client_phone: orderData.clientPhone,
      client_name: orderData.clientName,
      shop_address: orderData.shopAddress,
      items: JSON.stringify(orderData.items || []),
      total_price: orderData.totalPrice,
      comment: orderData.comment || null,
      status: 'pending',
      is_wholesale_order: isWholesaleOrder,
      created_at: now,
      updated_at: now
    });
    order = dbOrderToCamel(row);
  } else {
    order = {
      id: orderId,
      orderNumber,
      clientPhone: orderData.clientPhone,
      clientName: orderData.clientName,
      shopAddress: orderData.shopAddress,
      items: orderData.items,
      totalPrice: orderData.totalPrice,
      comment: orderData.comment || null,
      status: 'pending',
      isWholesaleOrder,
      createdAt: now,
      updatedAt: now,
      acceptedBy: null,
      rejectedBy: null,
      rejectionReason: null
    };

    const orderFile = path.join(ORDERS_DIR, orderId + '.json');
    await writeJsonFile(orderFile, order);
  }

  await addOrderToDialog(order);

  // Списание баллов за товары, оплаченные баллами
  if (orderData.totalPointsPrice > 0 && orderData.clientPhone) {
    try {
      await spendPoints(orderData.clientPhone, orderData.totalPointsPrice, {
        sourceType: 'shop_purchase',
        sourceId: orderId,
        description: `Заказ #${orderNumber} — оплата баллами`,
      });
      console.log(`💰 Списано ${orderData.totalPointsPrice} баллов с ${orderData.clientPhone} за заказ #${orderNumber}`);
    } catch (e) {
      console.error(`⚠️ Ошибка списания баллов за заказ #${orderNumber}:`, e.message);
    }
  }

  // Отправляем push уведомления всем сотрудникам о новом заказе
  await sendNewOrderNotificationToEmployees(order);

  console.log('✅ Создан заказ #' + orderNumber + ' от ' + orderData.clientName + ' (ID: ' + orderId + ')');
  return order;
}

async function getOrders(filters = {}) {
  if (USE_DB) {
    let query = 'SELECT * FROM orders WHERE 1=1';
    const params = [];
    let paramIdx = 1;

    if (filters.clientPhone) {
      query += ` AND client_phone = $${paramIdx++}`;
      params.push(filters.clientPhone);
    }
    if (filters.status) {
      query += ` AND status = $${paramIdx++}`;
      params.push(filters.status);
    }
    if (filters.shopAddress) {
      query += ` AND shop_address = $${paramIdx++}`;
      params.push(filters.shopAddress);
    }

    query += ' ORDER BY order_number DESC NULLS LAST';

    const result = await db.query(query, params);
    return result.rows.map(dbOrderToCamel);
  }

  const files = await fsp.readdir(ORDERS_DIR);
  const orders = [];

  for (const file of files) {
    if (file.endsWith('.json') && file !== 'order-counter.json') {
      try {
        const content = await fsp.readFile(path.join(ORDERS_DIR, file), 'utf8');
        const order = JSON.parse(content);

        if (filters.clientPhone && order.clientPhone !== filters.clientPhone) continue;
        if (filters.status && order.status !== filters.status) continue;
        if (filters.shopAddress && order.shopAddress !== filters.shopAddress) continue;

        orders.push(order);
      } catch (err) {
        console.error('❌ Ошибка чтения файла ' + file + ':', err.message);
      }
    }
  }

  orders.sort((a, b) => b.orderNumber - a.orderNumber);
  return orders;
}

async function updateOrderStatus(orderId, updates) {
  let order;

  if (USE_DB) {
    const dbUpdates = { updated_at: new Date().toISOString() };
    if (updates.status) dbUpdates.status = updates.status;
    if (updates.acceptedBy) dbUpdates.accepted_by = updates.acceptedBy;
    if (updates.rejectedBy) dbUpdates.rejected_by = updates.rejectedBy;
    if (updates.rejectionReason) dbUpdates.rejection_reason = updates.rejectionReason;
    if (updates.status === 'rejected') dbUpdates.rejected_at = new Date().toISOString();

    const row = await db.updateById('orders', orderId, dbUpdates);
    if (!row) throw new Error('Заказ ' + orderId + ' не найден');
    order = dbOrderToCamel(row);
  } else {
    const orderFile = path.join(ORDERS_DIR, orderId + '.json');

    if (!(await fileExists(orderFile))) {
      throw new Error('Заказ ' + orderId + ' не найден');
    }

    order = await withLock(orderFile, async () => {
      const content = await fsp.readFile(orderFile, 'utf8');
      const data = JSON.parse(content);

      Object.assign(data, updates);
      data.updatedAt = new Date().toISOString();

      // Добавляем rejectedAt при отказе
      if (updates.status === 'rejected') {
        data.rejectedAt = new Date().toISOString();
      }

      // Boy Scout: fsp.writeFile → writeJsonFile
      await writeJsonFile(orderFile, data, { useLock: false }); // already inside withLock
      return data;
    });
  }

  if (updates.status === 'accepted') {
    await sendOrderNotification(order, 'accepted');
    await addResponseToDialog(order, 'accepted');
    console.log('✅ Заказ #' + order.orderNumber + ' принят сотрудником ' + order.acceptedBy);
  } else if (updates.status === 'rejected') {
    await sendOrderNotification(order, 'rejected');
    await addResponseToDialog(order, 'rejected');
    console.log('✅ Заказ #' + order.orderNumber + ' отклонен сотрудником ' + order.rejectedBy + ': ' + order.rejectionReason);

    // Push-уведомление админам об отказанном заказе
    try {
      const clientName = order.clientName || order.clientPhone || 'Клиент';
      const reason = order.rejectionReason || 'Не указана';
      await sendPushNotification(
        'Отказанный заказ',
        clientName + ': ' + reason,
        { type: 'order_rejected', orderId: order.id }
      );
      console.log('✅ Push об отказанном заказе #' + order.orderNumber + ' отправлен админам');
    } catch (pushErr) {
      console.error('❌ Ошибка отправки push об отказанном заказе:', pushErr.message);
    }
  }

  return order;
}

async function sendOrderNotification(order, type) {
  let title, body;
  if (type === 'accepted') {
    title = 'Заказ ' + order.orderNumber + ' принят';
    body = 'Ваш заказ принят в работу сотрудником ' + order.acceptedBy;
  } else {
    title = 'Заказ ' + order.orderNumber + ' не принят';
    body = 'Причина: ' + order.rejectionReason;
  }

  await pushService.sendPushToPhone(order.clientPhone, title, body, {
    type: 'order_status',
    orderId: order.id,
    orderNumber: String(order.orderNumber),
    shopAddress: order.shopAddress,
    status: order.status
  }, 'orders_channel');
}

// Отправка push уведомления о новом заказе
// Обычные заказы → всем верифицированным сотрудникам
// Оптовые заказы → только уполномоченным сотрудникам + разработчикам
async function sendNewOrderNotificationToEmployees(order) {
  try {
    const isWholesale = order.isWholesaleOrder || false;

    // Получаем верифицированных из employee_registrations
    const registrations = await db.findAll('employee_registrations');
    let targetPhones = new Set();

    if (isWholesale) {
      // Оптовый заказ: push только уполномоченным + разработчикам
      const authorizedEmployees = await loadAuthorizedEmployees();
      const authorizedPhones = new Set(authorizedEmployees.map(e => e.phone));

      // Добавить разработчиков из shop-managers напрямую (на случай если не в registrations)
      try {
        const smData = await loadShopManagers();
        for (const devPhone of (smData.developers || [])) {
          const cleaned = (devPhone || '').replace(/[^\d]/g, '');
          if (cleaned) targetPhones.add(cleaned);
        }
      } catch (e) {
        console.error('Ошибка загрузки разработчиков для push:', e.message);
      }

      for (const reg of registrations) {
        const data = reg.data || {};
        if (data.isVerified !== true) continue;
        const phone = (data.phone || '').replace(/[^\d]/g, '');
        if (!phone) continue;

        // Уполномоченный или разработчик
        if (authorizedPhones.has(phone) || data.role === 'developer') {
          targetPhones.add(phone);
        }
      }
    } else {
      // Обычный заказ: push всем верифицированным
      for (const reg of registrations) {
        const data = reg.data || {};
        if (data.isVerified === true) {
          const phone = (data.phone || '').replace(/[^\d]/g, '');
          if (phone) targetPhones.add(phone);
        }
      }
    }

    const wholesaleLabel = isWholesale ? ' (ОПТ)' : '';
    const title = 'Новый заказ ' + order.orderNumber + wholesaleLabel;
    const body = order.clientName + ' - ' + order.shopAddress;
    const pushData = {
      type: 'new_order',
      orderId: order.id,
      orderNumber: String(order.orderNumber),
      shopAddress: order.shopAddress,
      clientName: order.clientName,
      totalPrice: String(order.totalPrice),
      isWholesaleOrder: String(isWholesale)
    };

    let sentCount = 0;
    for (const phone of targetPhones) {
      const success = await pushService.sendPushToPhone(phone, title, body, pushData, 'orders_channel');
      if (success) sentCount++;
    }

    if (sentCount > 0) {
      const scope = isWholesale ? 'уполномоченным' : 'сотрудникам';
      console.log(`Push о новом заказе #${order.orderNumber}${wholesaleLabel} отправлен ${sentCount} ${scope}`);
    }
  } catch (err) {
    console.error('Ошибка отправки push сотрудникам:', err.message);
  }
}

async function addOrderToDialog(order) {
  if (!order.clientPhone) return; // Prevent creating 'null/' directory when order has no client
  const dialogDir = path.join(DIALOGS_DIR, order.clientPhone);
  const dialogFile = path.join(dialogDir, encodeURIComponent(order.shopAddress) + '.json');

  await fsp.mkdir(dialogDir, { recursive: true });

  await withLock(dialogFile, async () => {
    let dialog = { shopAddress: order.shopAddress, messages: [], unreadCount: 0 };

    if (await fileExists(dialogFile)) {
      const content = await fsp.readFile(dialogFile, 'utf8');
      dialog = JSON.parse(content);
    }

    const message = {
      id: uuidv4(),
      type: 'order',
      timestamp: order.createdAt,
      senderType: 'client',
      senderName: order.clientName,
      shopAddress: order.shopAddress,
      data: {
        orderId: order.id,
        orderNumber: order.orderNumber,
        items: order.items,
        totalPrice: order.totalPrice,
        comment: order.comment,
        status: order.status
      },
      isRead: false
    };

    dialog.messages.push(message);
    dialog.lastMessageTime = message.timestamp;

    // useLock: false — уже внутри withLock, двойной лок → deadlock
    await writeJsonFile(dialogFile, dialog, { useLock: false });
  });
  console.log('✅ Заказ #' + order.orderNumber + ' добавлен в диалог с магазином ' + order.shopAddress);
}

async function addResponseToDialog(order, responseType) {
  if (!order.clientPhone) return; // Guard against null clientPhone
  const dialogDir = path.join(DIALOGS_DIR, order.clientPhone);
  const dialogFile = path.join(dialogDir, encodeURIComponent(order.shopAddress) + '.json');

  if (!(await fileExists(dialogFile))) {
    console.warn('⚠️  Диалог для ' + order.clientPhone + ' с магазином ' + order.shopAddress + ' не найден');
    return;
  }

  let text, employeeName;
  if (responseType === 'accepted') {
    text = 'Ваш заказ ' + order.orderNumber + ' принят в работу';
    employeeName = order.acceptedBy || 'Сотрудник';
  } else {
    text = 'Отказ по заказу ' + order.orderNumber + ': ' + order.rejectionReason;
    employeeName = order.rejectedBy || 'Сотрудник';
  }

  await withLock(dialogFile, async () => {
    const content = await fsp.readFile(dialogFile, 'utf8');
    const dialog = JSON.parse(content);

    const message = {
      id: uuidv4(),
      type: 'employee_response',
      timestamp: new Date().toISOString(),
      senderType: 'employee',
      senderName: employeeName,
      shopAddress: order.shopAddress,
      data: {
        text,
        orderId: order.id,
        orderNumber: order.orderNumber,
        responseType: responseType === 'accepted' ? 'order_accepted' : 'order_rejected',
        ...(responseType === 'rejected' && { rejectionReason: order.rejectionReason })
      },
      isRead: false
    };

    dialog.messages.push(message);
    dialog.lastMessageTime = message.timestamp;
    dialog.unreadCount += 1;

    // useLock: false — уже внутри withLock, двойной лок → deadlock
    await writeJsonFile(dialogFile, dialog, { useLock: false });
  });
  console.log('✅ Ответ сотрудника добавлен в диалог (заказ #' + order.orderNumber + ')');
}

module.exports = {
  createOrder,
  getOrders,
  updateOrderStatus,
  getUnviewedOrdersCounts,
  saveLastViewedAt,
  dbOrderToCamel
};
