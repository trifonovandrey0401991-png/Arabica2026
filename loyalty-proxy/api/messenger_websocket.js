/**
 * WebSocket модуль для мессенджера
 * Отдельный от employee_chat — свой путь, свои соединения, свои maps.
 *
 * Real-time функциональность:
 * - Мгновенная доставка сообщений (targeted — только участникам разговора)
 * - Индикатор набора текста
 * - Статус онлайн
 * - Read receipts
 * - Реакции
 */

const WebSocket = require('ws');
const db = require('../utils/db');
const { maskPhone } = require('../utils/file_helpers');

// Проверка session token
let sessionMiddleware;
try {
  sessionMiddleware = require('../utils/session_middleware');
} catch (e) {
  sessionMiddleware = null;
}

// Хранилище подключений: Map<phone, Set<WebSocket>>
const connections = new Map();

// Хранилище статусов онлайн: Map<phone, { lastSeen: Date, online: boolean }>
const onlineStatus = new Map();

// Typing статусы: Map<conversationId, Map<phone, timeout>>
const typingStatus = new Map();

// Кэш участников: Map<conversationId, { phones: Set<string>, expires: number }>
const participantsCache = new Map();

const CLEANUP_INTERVAL = 30000;
const CONNECTION_TIMEOUT = 60000;
const MAX_CONNECTIONS_PER_PHONE = 3;
const PARTICIPANTS_CACHE_TTL = 60000; // 60 сек

/**
 * Получить телефоны участников разговора (с кэшем)
 */
async function getConversationPhones(conversationId) {
  const cached = participantsCache.get(conversationId);
  if (cached && Date.now() < cached.expires) {
    return cached.phones;
  }

  try {
    const result = await db.query(
      'SELECT phone FROM messenger_participants WHERE conversation_id = $1',
      [conversationId]
    );
    const phones = new Set(result.rows.map(r => r.phone));
    participantsCache.set(conversationId, {
      phones,
      expires: Date.now() + PARTICIPANTS_CACHE_TTL
    });
    return phones;
  } catch (err) {
    console.error('[Messenger WS] Error loading participants:', err.message);
    return new Set();
  }
}

/**
 * Инвалидировать кэш участников (вызывать при добавлении/удалении)
 */
function invalidateParticipantsCache(conversationId) {
  participantsCache.delete(conversationId);
}

/**
 * Инициализация WebSocket сервера для мессенджера
 */
function setupMessengerWebSocket(server) {
  const wss = new WebSocket.Server({ noServer: true });

  console.log('✅ Messenger WebSocket initialized (noServer mode, path: /ws/messenger)');

  wss.on('connection', (ws, req) => {
    let userPhone = null;
    let pingInterval = null;
    let lastPong = Date.now();

    const url = new URL(req.url, `http://${req.headers.host}`);
    userPhone = url.searchParams.get('phone');
    const authToken = url.searchParams.get('token');

    if (!userPhone) {
      ws.close(4001, 'Phone required');
      return;
    }

    if (!authToken) {
      ws.close(4002, 'Auth token required');
      return;
    }

    if (!sessionMiddleware) {
      ws.close(4003, 'Auth service unavailable');
      return;
    }

    const tokenUser = sessionMiddleware.verifyToken(authToken);
    if (!tokenUser) {
      ws.close(4003, 'Invalid session token');
      return;
    }

    userPhone = tokenUser.phone || userPhone;
    const normalizedPhone = userPhone.replace(/[^\d]/g, '');
    console.log(`💬 Messenger WS: подключился ${maskPhone(normalizedPhone)}`);

    // Регистрируем соединение
    if (!connections.has(normalizedPhone)) {
      connections.set(normalizedPhone, new Set());
    }
    const phoneSockets = connections.get(normalizedPhone);

    // Лимит соединений — закрываем самое старое
    if (phoneSockets.size >= MAX_CONNECTIONS_PER_PHONE) {
      const oldest = phoneSockets.values().next().value;
      oldest.close(4004, 'Too many connections');
      phoneSockets.delete(oldest);
    }

    phoneSockets.add(ws);

    // Обновляем онлайн статус
    onlineStatus.set(normalizedPhone, { lastSeen: new Date(), online: true });

    // Подтверждение подключения
    sendToSocket(ws, {
      type: 'connected',
      phone: normalizedPhone,
      timestamp: new Date().toISOString()
    });

    // Оповещаем всех об онлайн статусе
    broadcastOnlineStatus(normalizedPhone, true);

    // Пинг
    pingInterval = setInterval(() => {
      if (Date.now() - lastPong > CONNECTION_TIMEOUT) {
        ws.terminate();
        return;
      }
      if (ws.readyState === WebSocket.OPEN) {
        ws.ping();
      }
    }, 30000);

    ws.on('pong', () => {
      lastPong = Date.now();
      const status = onlineStatus.get(normalizedPhone);
      if (status) status.lastSeen = new Date();
    });

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString());
        handleMessage(normalizedPhone, message, ws);
      } catch (e) {
        console.error('[Messenger WS] parse error:', e.message);
      }
    });

    ws.on('close', () => {
      clearInterval(pingInterval);

      if (connections.has(normalizedPhone)) {
        connections.get(normalizedPhone).delete(ws);
        if (connections.get(normalizedPhone).size === 0) {
          connections.delete(normalizedPhone);
          onlineStatus.set(normalizedPhone, { lastSeen: new Date(), online: false });
          broadcastOnlineStatus(normalizedPhone, false);
        }
      }

      clearTypingStatus(normalizedPhone);
    });

    ws.on('error', (error) => {
      console.error(`[Messenger WS] error for ${maskPhone(normalizedPhone)}:`, error.message);
    });
  });

  // Периодическая очистка
  setInterval(() => cleanupStaleConnections(), CLEANUP_INTERVAL);

  return wss;
}

// ===== ОБРАБОТКА СООБЩЕНИЙ =====

function handleMessage(phone, message, ws) {
  const { type, conversationId } = message;

  switch (type) {
    case 'typing_start':
      handleTypingStart(phone, conversationId);
      break;
    case 'typing_stop':
      handleTypingStop(phone, conversationId);
      break;
    case 'get_online_users':
      sendOnlineUsersList(ws);
      break;
    case 'ping':
      sendToSocket(ws, { type: 'pong', timestamp: new Date().toISOString() });
      break;
    default:
      break;
  }
}

function handleTypingStart(phone, conversationId) {
  if (!conversationId) return;

  if (!typingStatus.has(conversationId)) {
    typingStatus.set(conversationId, new Map());
  }

  const chatTyping = typingStatus.get(conversationId);
  if (chatTyping.has(phone)) {
    clearTimeout(chatTyping.get(phone));
  }

  const timeout = setTimeout(() => handleTypingStop(phone, conversationId), 5000);
  chatTyping.set(phone, timeout);

  broadcastTypingStatus(conversationId, phone, true);
}

function handleTypingStop(phone, conversationId) {
  if (!conversationId || !typingStatus.has(conversationId)) return;

  const chatTyping = typingStatus.get(conversationId);
  if (chatTyping.has(phone)) {
    clearTimeout(chatTyping.get(phone));
    chatTyping.delete(phone);
  }

  broadcastTypingStatus(conversationId, phone, false);
}

function clearTypingStatus(phone) {
  for (const [convId, chatTyping] of typingStatus.entries()) {
    if (chatTyping.has(phone)) {
      clearTimeout(chatTyping.get(phone));
      chatTyping.delete(phone);
      broadcastTypingStatus(convId, phone, false);
    }
  }
}

// ===== TARGETED BROADCASTING (только участникам разговора) =====

async function broadcastToConversation(conversationId, data, excludePhone = null) {
  const members = await getConversationPhones(conversationId);
  for (const [phone, sockets] of connections.entries()) {
    if (phone !== excludePhone && members.has(phone)) {
      for (const socket of sockets) {
        sendToSocket(socket, data);
      }
    }
  }
}

async function broadcastTypingStatus(conversationId, phone, isTyping) {
  const message = {
    type: 'typing',
    conversationId,
    phone,
    isTyping,
    timestamp: new Date().toISOString()
  };
  await broadcastToConversation(conversationId, message, phone);
}

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

function sendOnlineUsersList(ws) {
  const onlineUsers = [];
  for (const [phone, status] of onlineStatus.entries()) {
    if (status.online) {
      onlineUsers.push({ phone, lastSeen: status.lastSeen.toISOString() });
    }
  }
  sendToSocket(ws, {
    type: 'online_users_list',
    users: onlineUsers,
    timestamp: new Date().toISOString()
  });
}

function sendToSocket(ws, data) {
  if (ws.readyState === WebSocket.OPEN) {
    try {
      ws.send(JSON.stringify(data));
    } catch (e) {
      console.error('[Messenger WS] send error:', e.message);
    }
  }
}

function cleanupStaleConnections() {
  for (const [phone, sockets] of connections.entries()) {
    for (const socket of sockets) {
      if (socket.readyState !== WebSocket.OPEN) {
        sockets.delete(socket);
      }
    }
    if (sockets.size === 0) {
      connections.delete(phone);
      onlineStatus.delete(phone);
    }
  }

  for (const [phone] of onlineStatus.entries()) {
    if (!connections.has(phone) || connections.get(phone).size === 0) {
      onlineStatus.delete(phone);
    }
  }
}

// ===== ПУБЛИЧНЫЕ ФУНКЦИИ ДЛЯ REST API =====

async function notifyNewMessage(conversationId, message, excludePhone = null) {
  await broadcastToConversation(conversationId, {
    type: 'new_message',
    conversationId,
    message,
    timestamp: new Date().toISOString()
  }, excludePhone);
}

async function notifyMessageDeleted(conversationId, messageId) {
  await broadcastToConversation(conversationId, {
    type: 'message_deleted',
    conversationId,
    messageId,
    timestamp: new Date().toISOString()
  });
}

async function notifyReactionAdded(conversationId, messageId, reaction, phone) {
  await broadcastToConversation(conversationId, {
    type: 'reaction_added',
    conversationId,
    messageId,
    reaction,
    phone,
    timestamp: new Date().toISOString()
  });
}

async function notifyReactionRemoved(conversationId, messageId, reaction, phone) {
  await broadcastToConversation(conversationId, {
    type: 'reaction_removed',
    conversationId,
    messageId,
    reaction,
    phone,
    timestamp: new Date().toISOString()
  });
}

async function notifyReadReceipt(conversationId, phone, timestamp) {
  await broadcastToConversation(conversationId, {
    type: 'read_receipt',
    conversationId,
    phone,
    readAt: timestamp,
    timestamp: new Date().toISOString()
  }, phone);
}

function isUserOnline(phone) {
  const normalizedPhone = phone.replace(/[^\d]/g, '');
  const status = onlineStatus.get(normalizedPhone);
  return status?.online === true;
}

function getOnlineUsers() {
  const users = [];
  for (const [phone, status] of onlineStatus.entries()) {
    if (status.online) users.push(phone);
  }
  return users;
}

function getConnectionsCount() {
  let count = 0;
  for (const sockets of connections.values()) {
    count += sockets.size;
  }
  return count;
}

module.exports = {
  setupMessengerWebSocket,
  invalidateParticipantsCache,
  notifyNewMessage,
  notifyMessageDeleted,
  notifyReactionAdded,
  notifyReactionRemoved,
  notifyReadReceipt,
  isUserOnline,
  getOnlineUsers,
  getConnectionsCount
};
