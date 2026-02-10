/**
 * WebSocket модуль для чата сотрудников
 * Обеспечивает real-time функциональность:
 * - Мгновенная доставка сообщений
 * - Индикатор набора текста
 * - Статус онлайн
 */

const WebSocket = require('ws');
const { maskPhone } = require('../utils/file_helpers');

// Проверка session token (обязательная)
let tokenIndex;
try {
  const sessionMiddleware = require('../utils/session_middleware');
  // Используем внутренний tokenIndex для проверки (через экспортированные функции)
  tokenIndex = sessionMiddleware;
} catch (e) {
  tokenIndex = null;
}

// Хранилище подключений: Map<phone, Set<WebSocket>>
const connections = new Map();

// Хранилище статусов онлайн: Map<phone, { lastSeen: Date, chatIds: Set }>
const onlineStatus = new Map();

// Typing статусы: Map<chatId, Map<phone, timeout>>
const typingStatus = new Map();

// Интервал очистки неактивных соединений
const CLEANUP_INTERVAL = 30000; // 30 сек
const CONNECTION_TIMEOUT = 60000; // 60 сек без пинга = отключение

/**
 * Инициализация WebSocket сервера
 * @param {http.Server} server - HTTP сервер Express
 */
function setupChatWebSocket(server) {
  const wss = new WebSocket.Server({
    server,
    path: '/ws/employee-chat'
  });

  console.log('✅ Employee Chat WebSocket initialized on /ws/employee-chat');

  wss.on('connection', (ws, req) => {
    let userPhone = null;
    let pingInterval = null;
    let lastPong = Date.now();

    // Парсим phone и token из query string
    const url = new URL(req.url, `http://${req.headers.host}`);
    userPhone = url.searchParams.get('phone');
    const authToken = url.searchParams.get('token');

    if (!userPhone) {
      console.log('❌ WebSocket: подключение без phone, отклонено');
      ws.close(4001, 'Phone required');
      return;
    }

    // Проверяем session token (обязательно)
    if (!authToken) {
      console.log(`❌ WebSocket: подключение без token для ${userPhone}, отклонено`);
      ws.close(4002, 'Auth token required');
      return;
    }

    if (!tokenIndex) {
      console.log(`❌ WebSocket: session middleware не загружен`);
      ws.close(4003, 'Auth service unavailable');
      return;
    }

    const tokenUser = tokenIndex.verifyToken(authToken);
    if (!tokenUser) {
      console.log(`❌ WebSocket: невалидный token для ${userPhone}`);
      ws.close(4003, 'Invalid session token');
      return;
    }
    // Используем phone из token (более надёжный)
    userPhone = tokenUser.phone || userPhone;

    const normalizedPhone = userPhone.replace(/[^\d]/g, '');
    console.log(`📱 WebSocket: подключился ${normalizedPhone}`);

    // Регистрируем соединение
    if (!connections.has(normalizedPhone)) {
      connections.set(normalizedPhone, new Set());
    }
    connections.get(normalizedPhone).add(ws);

    // Обновляем онлайн статус
    onlineStatus.set(normalizedPhone, {
      lastSeen: new Date(),
      online: true
    });

    // Отправляем подтверждение подключения
    sendToSocket(ws, {
      type: 'connected',
      phone: normalizedPhone,
      timestamp: new Date().toISOString()
    });

    // Оповещаем всех об онлайн статусе
    broadcastOnlineStatus(normalizedPhone, true);

    // Пинг для поддержания соединения
    pingInterval = setInterval(() => {
      if (Date.now() - lastPong > CONNECTION_TIMEOUT) {
        console.log(`⏰ WebSocket: таймаут для ${normalizedPhone}`);
        ws.terminate();
        return;
      }
      if (ws.readyState === WebSocket.OPEN) {
        ws.ping();
      }
    }, 30000);

    ws.on('pong', () => {
      lastPong = Date.now();
      // Обновляем lastSeen
      if (onlineStatus.has(normalizedPhone)) {
        onlineStatus.get(normalizedPhone).lastSeen = new Date();
      }
    });

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString());
        handleMessage(normalizedPhone, message, ws);
      } catch (e) {
        console.error('❌ WebSocket: ошибка парсинга сообщения:', e.message);
      }
    });

    ws.on('close', () => {
      console.log(`📴 WebSocket: отключился ${normalizedPhone}`);
      clearInterval(pingInterval);

      // Удаляем соединение
      if (connections.has(normalizedPhone)) {
        connections.get(normalizedPhone).delete(ws);
        if (connections.get(normalizedPhone).size === 0) {
          connections.delete(normalizedPhone);
          // Обновляем статус на офлайн
          onlineStatus.set(normalizedPhone, {
            lastSeen: new Date(),
            online: false
          });
          broadcastOnlineStatus(normalizedPhone, false);
        }
      }

      // Очищаем typing статус
      clearTypingStatus(normalizedPhone);
    });

    ws.on('error', (error) => {
      console.error(`❌ WebSocket error for ${normalizedPhone}:`, error.message);
    });
  });

  // Периодическая очистка
  setInterval(() => {
    cleanupStaleConnections();
  }, CLEANUP_INTERVAL);

  return wss;
}

/**
 * Обработка входящих сообщений
 */
function handleMessage(phone, message, ws) {
  const { type, chatId, data } = message;

  switch (type) {
    case 'typing_start':
      handleTypingStart(phone, chatId);
      break;

    case 'typing_stop':
      handleTypingStop(phone, chatId);
      break;

    case 'subscribe_chat':
      // Подписка на чат (для получения сообщений)
      console.log(`📝 ${maskPhone(phone)} подписался на чат ${chatId}`);
      break;

    case 'get_online_users':
      // Запрос списка онлайн пользователей
      sendOnlineUsersList(ws);
      break;

    case 'ping':
      sendToSocket(ws, { type: 'pong', timestamp: new Date().toISOString() });
      break;

    default:
      console.log(`⚠️ WebSocket: неизвестный тип сообщения: ${type}`);
  }
}

/**
 * Обработка начала набора текста
 */
function handleTypingStart(phone, chatId) {
  if (!chatId) return;

  if (!typingStatus.has(chatId)) {
    typingStatus.set(chatId, new Map());
  }

  const chatTyping = typingStatus.get(chatId);

  // Очищаем предыдущий таймаут
  if (chatTyping.has(phone)) {
    clearTimeout(chatTyping.get(phone));
  }

  // Устанавливаем новый таймаут (автоочистка через 5 сек)
  const timeout = setTimeout(() => {
    handleTypingStop(phone, chatId);
  }, 5000);

  chatTyping.set(phone, timeout);

  // Оповещаем участников чата
  broadcastTypingStatus(chatId, phone, true);
}

/**
 * Обработка окончания набора текста
 */
function handleTypingStop(phone, chatId) {
  if (!chatId || !typingStatus.has(chatId)) return;

  const chatTyping = typingStatus.get(chatId);

  if (chatTyping.has(phone)) {
    clearTimeout(chatTyping.get(phone));
    chatTyping.delete(phone);
  }

  broadcastTypingStatus(chatId, phone, false);
}

/**
 * Очистка typing статуса для пользователя
 */
function clearTypingStatus(phone) {
  for (const [chatId, chatTyping] of typingStatus.entries()) {
    if (chatTyping.has(phone)) {
      clearTimeout(chatTyping.get(phone));
      chatTyping.delete(phone);
      broadcastTypingStatus(chatId, phone, false);
    }
  }
}

/**
 * Рассылка статуса набора текста
 */
function broadcastTypingStatus(chatId, phone, isTyping) {
  const message = {
    type: 'typing',
    chatId,
    phone,
    isTyping,
    timestamp: new Date().toISOString()
  };

  // Отправляем всем подключённым (кроме автора)
  for (const [userPhone, sockets] of connections.entries()) {
    if (userPhone !== phone) {
      for (const socket of sockets) {
        sendToSocket(socket, message);
      }
    }
  }
}

/**
 * Рассылка онлайн статуса
 */
function broadcastOnlineStatus(phone, isOnline) {
  const message = {
    type: 'online_status',
    phone,
    isOnline,
    timestamp: new Date().toISOString()
  };

  for (const [userPhone, sockets] of connections.entries()) {
    if (userPhone !== phone) {
      for (const socket of sockets) {
        sendToSocket(socket, message);
      }
    }
  }
}

/**
 * Отправка списка онлайн пользователей
 */
function sendOnlineUsersList(ws) {
  const onlineUsers = [];
  for (const [phone, status] of onlineStatus.entries()) {
    if (status.online) {
      onlineUsers.push({
        phone,
        lastSeen: status.lastSeen.toISOString()
      });
    }
  }

  sendToSocket(ws, {
    type: 'online_users_list',
    users: onlineUsers,
    timestamp: new Date().toISOString()
  });
}

/**
 * Отправка сообщения в сокет
 */
function sendToSocket(ws, data) {
  if (ws.readyState === WebSocket.OPEN) {
    try {
      ws.send(JSON.stringify(data));
    } catch (e) {
      console.error('❌ WebSocket send error:', e.message);
    }
  }
}

/**
 * Очистка неактивных соединений и onlineStatus
 */
function cleanupStaleConnections() {
  const now = Date.now();

  for (const [phone, sockets] of connections.entries()) {
    for (const socket of sockets) {
      if (socket.readyState !== WebSocket.OPEN) {
        sockets.delete(socket);
      }
    }
    if (sockets.size === 0) {
      connections.delete(phone);
      // MEMORY LEAK FIX: Удаляем onlineStatus для отключённых пользователей
      onlineStatus.delete(phone);
    }
  }

  // Дополнительно: очищаем onlineStatus для телефонов без активных соединений
  for (const [phone] of onlineStatus.entries()) {
    if (!connections.has(phone) || connections.get(phone).size === 0) {
      onlineStatus.delete(phone);
    }
  }
}

// ===== ПУБЛИЧНЫЕ ФУНКЦИИ ДЛЯ ИНТЕГРАЦИИ С REST API =====

/**
 * Оповестить о новом сообщении в чате
 * Вызывается из REST API при отправке сообщения
 */
function notifyNewMessage(chatId, message, excludePhone = null) {
  const notification = {
    type: 'new_message',
    chatId,
    message,
    timestamp: new Date().toISOString()
  };

  for (const [phone, sockets] of connections.entries()) {
    if (phone !== excludePhone) {
      for (const socket of sockets) {
        sendToSocket(socket, notification);
      }
    }
  }

  console.log(`📤 WebSocket: new_message в ${chatId} (${connections.size} получателей)`);
}

/**
 * Оповестить об удалении сообщения
 */
function notifyMessageDeleted(chatId, messageId) {
  const notification = {
    type: 'message_deleted',
    chatId,
    messageId,
    timestamp: new Date().toISOString()
  };

  for (const sockets of connections.values()) {
    for (const socket of sockets) {
      sendToSocket(socket, notification);
    }
  }
}

/**
 * Оповестить об очистке чата
 */
function notifyChatCleared(chatId, deletedCount) {
  const notification = {
    type: 'chat_cleared',
    chatId,
    deletedCount,
    timestamp: new Date().toISOString()
  };

  for (const sockets of connections.values()) {
    for (const socket of sockets) {
      sendToSocket(socket, notification);
    }
  }
}

/**
 * Оповестить о добавлении реакции
 */
function notifyReactionAdded(chatId, messageId, reaction, phone) {
  const notification = {
    type: 'reaction_added',
    chatId,
    messageId,
    reaction,
    phone,
    timestamp: new Date().toISOString()
  };

  for (const sockets of connections.values()) {
    for (const socket of sockets) {
      sendToSocket(socket, notification);
    }
  }
}

/**
 * Оповестить об удалении реакции
 */
function notifyReactionRemoved(chatId, messageId, reaction, phone) {
  const notification = {
    type: 'reaction_removed',
    chatId,
    messageId,
    reaction,
    phone,
    timestamp: new Date().toISOString()
  };

  for (const sockets of connections.values()) {
    for (const socket of sockets) {
      sendToSocket(socket, notification);
    }
  }
}

/**
 * Проверить онлайн ли пользователь
 */
function isUserOnline(phone) {
  const normalizedPhone = phone.replace(/[^\d]/g, '');
  const status = onlineStatus.get(normalizedPhone);
  return status?.online === true;
}

/**
 * Получить список онлайн пользователей
 */
function getOnlineUsers() {
  const users = [];
  for (const [phone, status] of onlineStatus.entries()) {
    if (status.online) {
      users.push(phone);
    }
  }
  return users;
}

/**
 * Получить количество подключений
 */
function getConnectionsCount() {
  let count = 0;
  for (const sockets of connections.values()) {
    count += sockets.size;
  }
  return count;
}

module.exports = {
  setupChatWebSocket,
  notifyNewMessage,
  notifyMessageDeleted,
  notifyChatCleared,
  notifyReactionAdded,
  notifyReactionRemoved,
  isUserOnline,
  getOnlineUsers,
  getConnectionsCount
};
