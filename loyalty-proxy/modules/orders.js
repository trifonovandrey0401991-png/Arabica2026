const fs = require('fs').promises;
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const { admin, firebaseInitialized } = require('../firebase-admin-config');

const ORDERS_DIR = '/var/www/orders';
const COUNTER_FILE = path.join(ORDERS_DIR, 'order-counter.json');
const FCM_TOKENS_DIR = '/var/www/fcm-tokens';
const DIALOGS_DIR = '/var/www/client-dialogs';
const EMPLOYEES_DIR = '/var/www/employees';

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function getNextOrderNumber() {
  const lockFile = COUNTER_FILE + '.lock';
  let attempts = 0;
  const maxAttempts = 10;

  while (attempts < maxAttempts) {
    try {
      await fs.writeFile(lockFile, '', { flag: 'wx' });
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
    const data = await fs.readFile(COUNTER_FILE, 'utf8');
    const { counter } = JSON.parse(data);
    const nextCounter = counter + 1;
    await fs.writeFile(COUNTER_FILE, JSON.stringify({ counter: nextCounter }, null, 2));
    return nextCounter;
  } finally {
    await fs.unlink(lockFile).catch(() => {});
  }
}

async function createOrder(orderData) {
  const orderNumber = await getNextOrderNumber();
  const orderId = uuidv4();

  const order = {
    id: orderId,
    orderNumber,
    clientPhone: orderData.clientPhone,
    clientName: orderData.clientName,
    shopAddress: orderData.shopAddress,
    items: orderData.items,
    totalPrice: orderData.totalPrice,
    comment: orderData.comment || null,
    status: 'pending',
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    acceptedBy: null,
    rejectedBy: null,
    rejectionReason: null
  };

  const orderFile = path.join(ORDERS_DIR, orderId + '.json');
  await fs.writeFile(orderFile, JSON.stringify(order, null, 2));

  await addOrderToDialog(order);

  // Отправляем push уведомления всем админам о новом заказе
  await sendNewOrderNotificationToAdmins(order);

  console.log('✅ Создан заказ #' + orderNumber + ' от ' + orderData.clientName + ' (ID: ' + orderId + ')');
  return order;
}

async function getOrders(filters = {}) {
  const files = await fs.readdir(ORDERS_DIR);
  const orders = [];

  for (const file of files) {
    if (file.endsWith('.json') && file !== 'order-counter.json') {
      try {
        const content = await fs.readFile(path.join(ORDERS_DIR, file), 'utf8');
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
  const orderFile = path.join(ORDERS_DIR, orderId + '.json');

  if (!(await fileExists(orderFile))) {
    throw new Error('Заказ ' + orderId + ' не найден');
  }

  const content = await fs.readFile(orderFile, 'utf8');
  const order = JSON.parse(content);

  Object.assign(order, updates);
  order.updatedAt = new Date().toISOString();

  await fs.writeFile(orderFile, JSON.stringify(order, null, 2));

  if (updates.status === 'accepted') {
    await sendOrderNotification(order, 'accepted');
    await addResponseToDialog(order, 'accepted');
    console.log('✅ Заказ #' + order.orderNumber + ' принят сотрудником ' + order.acceptedBy);
  } else if (updates.status === 'rejected') {
    await sendOrderNotification(order, 'rejected');
    await addResponseToDialog(order, 'rejected');
    console.log('✅ Заказ #' + order.orderNumber + ' отклонен сотрудником ' + order.rejectedBy + ': ' + order.rejectionReason);
  }

  return order;
}

async function sendOrderNotification(order, type) {
  if (!firebaseInitialized) {
    console.warn('⚠️  Push-уведомление не отправлено: Firebase не инициализирован');
    return;
  }

  const tokenFile = path.join(FCM_TOKENS_DIR, order.clientPhone + '.json');

  if (!(await fileExists(tokenFile))) {
    console.warn('⚠️  FCM токен для ' + order.clientPhone + ' не найден');
    return;
  }

  try {
    const content = await fs.readFile(tokenFile, 'utf8');
    const { token } = JSON.parse(content);

    let title, body;
    if (type === 'accepted') {
      title = 'Заказ #' + order.orderNumber + ' принят';
      body = 'Ваш заказ принят в работу сотрудником ' + order.acceptedBy;
    } else {
      title = 'Заказ #' + order.orderNumber + ' не принят';
      body = 'Причина: ' + order.rejectionReason;
    }

    await admin.messaging().send({
      token,
      notification: { title, body },
      data: {
        type: 'order',
        orderId: order.id,
        orderNumber: String(order.orderNumber),
        shopAddress: order.shopAddress,
        status: order.status
      },
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } }
    });

    console.log('✅ Push-уведомление отправлено клиенту ' + order.clientPhone);
  } catch (err) {
    console.error('❌ Ошибка отправки push-уведомления:', err.message);
  }
}

// Отправка push уведомления всем админам о новом заказе
async function sendNewOrderNotificationToAdmins(order) {
  if (!firebaseInitialized) {
    console.warn('⚠️  Push админам не отправлен: Firebase не инициализирован');
    return;
  }

  try {
    // Получаем список всех сотрудников
    const files = await fs.readdir(EMPLOYEES_DIR);
    let adminCount = 0;

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      try {
        const content = await fs.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
        const employee = JSON.parse(content);

        // Проверяем, является ли сотрудник админом
        if (!employee.isAdmin) continue;

        // Получаем телефон сотрудника (нормализуем)
        const phone = (employee.phone || '').replace(/[\s+]/g, '');
        if (!phone) continue;

        // Проверяем наличие FCM токена
        const tokenFile = path.join(FCM_TOKENS_DIR, phone + '.json');
        if (!(await fileExists(tokenFile))) continue;

        const tokenContent = await fs.readFile(tokenFile, 'utf8');
        const { token } = JSON.parse(tokenContent);

        // Формируем уведомление
        const title = 'Новый заказ #' + order.orderNumber;
        const body = order.clientName + ' - ' + order.shopAddress;

        await admin.messaging().send({
          token,
          notification: { title, body },
          data: {
            type: 'new_order',
            orderId: order.id,
            orderNumber: String(order.orderNumber),
            shopAddress: order.shopAddress,
            clientName: order.clientName,
            totalPrice: String(order.totalPrice)
          },
          android: { priority: 'high' },
          apns: { payload: { aps: { sound: 'default' } } }
        });

        adminCount++;
        console.log('✅ Push о новом заказе отправлен админу: ' + employee.name);
      } catch (err) {
        // Продолжаем для других админов
      }
    }

    if (adminCount > 0) {
      console.log('✅ Push о новом заказе #' + order.orderNumber + ' отправлен ' + adminCount + ' админам');
    }
  } catch (err) {
    console.error('❌ Ошибка отправки push админам:', err.message);
  }
}

async function addOrderToDialog(order) {
  const dialogDir = path.join(DIALOGS_DIR, order.clientPhone);
  const dialogFile = path.join(dialogDir, encodeURIComponent(order.shopAddress) + '.json');

  await fs.mkdir(dialogDir, { recursive: true });

  let dialog = { shopAddress: order.shopAddress, messages: [], unreadCount: 0 };

  if (await fileExists(dialogFile)) {
    const content = await fs.readFile(dialogFile, 'utf8');
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

  await fs.writeFile(dialogFile, JSON.stringify(dialog, null, 2));
  console.log('✅ Заказ #' + order.orderNumber + ' добавлен в диалог с магазином ' + order.shopAddress);
}

async function addResponseToDialog(order, responseType) {
  const dialogDir = path.join(DIALOGS_DIR, order.clientPhone);
  const dialogFile = path.join(dialogDir, encodeURIComponent(order.shopAddress) + '.json');

  if (!(await fileExists(dialogFile))) {
    console.warn('⚠️  Диалог для ' + order.clientPhone + ' с магазином ' + order.shopAddress + ' не найден');
    return;
  }

  const content = await fs.readFile(dialogFile, 'utf8');
  const dialog = JSON.parse(content);

  let text, employeeName;
  if (responseType === 'accepted') {
    text = 'Ваш заказ #' + order.orderNumber + ' принят в работу';
    employeeName = order.acceptedBy || 'Сотрудник';
  } else {
    text = 'Отказ по заказу #' + order.orderNumber + ': ' + order.rejectionReason;
    employeeName = order.rejectedBy || 'Сотрудник';
  }

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

  await fs.writeFile(dialogFile, JSON.stringify(dialog, null, 2));
  console.log('✅ Ответ сотрудника добавлен в диалог (заказ #' + order.orderNumber + ')');
}

module.exports = { createOrder, getOrders, updateOrderStatus };
