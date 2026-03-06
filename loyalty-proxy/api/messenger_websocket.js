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

// Rate limit for WS connections: Map<phone, { count, resetAt }>
const wsRateLimit = new Map();
const WS_RATE_LIMIT_WINDOW = 10000; // 10 seconds
const WS_RATE_LIMIT_MAX = 5; // max 5 connections per window

// Typing статусы: Map<conversationId, Map<phone, timeout>>
const typingStatus = new Map();

// Кэш участников: Map<conversationId, { phones: Set<string>, expires: number }>
const participantsCache = new Map();

// Батч delivery ack: Map<messageId, Set<phone>>
const deliveryAckBatch = new Map();
let deliveryAckTimer = null;
const DELIVERY_ACK_FLUSH_MS = 2000;

const CLEANUP_INTERVAL = 30000;
const CONNECTION_TIMEOUT = 60000;
const MAX_CONNECTIONS_PER_PHONE = 1;
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

    // Rate limit: prevent reconnection storms
    const now = Date.now();
    const rl = wsRateLimit.get(normalizedPhone);
    if (rl && now < rl.resetAt) {
      rl.count++;
      if (rl.count > WS_RATE_LIMIT_MAX) {
        ws.close(4005, 'Too many connections, try later');
        return;
      }
    } else {
      wsRateLimit.set(normalizedPhone, { count: 1, resetAt: now + WS_RATE_LIMIT_WINDOW });
    }

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

  // Debug: log all call-related messages
  if (type && type.startsWith('call_')) {
    console.log(`📞 [DEBUG] WS message from ${maskPhone(phone)}: type=${type}, keys=${Object.keys(message).join(',')}`);
  }

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
    case 'delivery_ack':
      handleDeliveryAck(phone, message);
      break;
    // ===== CALL SIGNALING =====
    case 'call_offer':
      handleCallOffer(phone, message);
      break;
    case 'call_answer':
      handleCallAnswer(phone, message);
      break;
    case 'call_reject':
      handleCallReject(phone, message);
      break;
    case 'call_ice_candidate':
      handleCallIceCandidate(phone, message);
      break;
    case 'call_hangup':
      handleCallHangup(phone, message);
      break;
    default:
      break;
  }
}

// ===== CALL SIGNALING HANDLERS =====

/**
 * Send a WebSocket message to all connections of a specific phone.
 * Returns true if at least one connection received the message.
 */
function sendToPhone(phone, data) {
  const normalized = phone.replace(/[^\d]/g, '');
  if (!connections.has(normalized)) return false;
  let sent = false;
  for (const socket of connections.get(normalized)) {
    sendToSocket(socket, data);
    sent = true;
  }
  return sent;
}

/**
 * Send to only ONE connection for a phone (the most recent one).
 * Used for call signaling to avoid duplicate events triggering auto-reject.
 */
function sendToPhoneOnce(phone, data) {
  const normalized = phone.replace(/[^\d]/g, '');
  if (!connections.has(normalized)) return false;
  const sockets = connections.get(normalized);
  if (!sockets || sockets.size === 0) return false;
  // Pick the last (most recent) socket
  let lastSocket = null;
  for (const s of sockets) lastSocket = s;
  sendToSocket(lastSocket, data);
  return true;
}

// Caller → Server: start a call
function handleCallOffer(callerPhone, message) {
  const { targetPhone, offerSdp, callId, callerName } = message;
  if (!targetPhone || !offerSdp || !callId) return;
  const normalizedTarget = targetPhone.replace(/[^\d]/g, '');
  const hasWs = connections.has(normalizedTarget);
  const connCount = hasWs ? connections.get(normalizedTarget).size : 0;
  console.log(`📞 Call offer: ${maskPhone(callerPhone)} → ${maskPhone(targetPhone)} [${callId}] (target WS: ${hasWs}, connections: ${connCount})`);
  // Send call_incoming to only ONE connection (avoid duplicate → auto-reject)
  const delivered = sendToPhoneOnce(targetPhone, {
    type: 'call_incoming',
    callId,
    callerPhone,
    callerName: callerName || callerPhone,
    offerSdp,
    timestamp: new Date().toISOString(),
  });
  console.log(`📞 Call incoming ${delivered ? 'DELIVERED' : 'NOT DELIVERED'} to ${maskPhone(targetPhone)}`);
}

// Callee → Server: accept the call
function handleCallAnswer(calleePhone, message) {
  const { callId, answerSdp, callerPhone } = message;
  if (!callId || !answerSdp || !callerPhone) return;
  console.log(`📞 Call answered: ${maskPhone(calleePhone)} → ${maskPhone(callerPhone)} [${callId}]`);
  sendToPhone(callerPhone, {
    type: 'call_answered',
    callId,
    answerSdp,
    calleePhone,
    timestamp: new Date().toISOString(),
  });
}

// Callee → Server: decline the call
function handleCallReject(calleePhone, message) {
  const { callId, callerPhone } = message;
  if (!callId || !callerPhone) return;
  console.log(`📞 Call rejected: ${maskPhone(calleePhone)} → ${maskPhone(callerPhone)} [${callId}]`);
  sendToPhone(callerPhone, {
    type: 'call_rejected',
    callId,
    calleePhone,
    timestamp: new Date().toISOString(),
  });
}

// Either party → Server: ICE candidate exchange
function handleCallIceCandidate(fromPhone, message) {
  const { callId, targetPhone, candidate } = message;
  if (!targetPhone || !candidate) return;
  sendToPhone(targetPhone, {
    type: 'call_ice_candidate',
    callId,
    candidate,
    fromPhone,
    timestamp: new Date().toISOString(),
  });
}

// Either party → Server: hang up
function handleCallHangup(fromPhone, message) {
  const { callId, targetPhone } = message;
  if (!targetPhone) return;
  console.log(`📞 Call hangup: ${maskPhone(fromPhone)} → ${maskPhone(targetPhone)} [${callId}]`);
  sendToPhone(targetPhone, {
    type: 'call_hangup',
    callId,
    fromPhone,
    timestamp: new Date().toISOString(),
  });
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

// ===== DELIVERY ACK BATCHING =====

function handleDeliveryAck(phone, message) {
  const { messageIds, conversationId } = message;
  if (!messageIds || !Array.isArray(messageIds) || messageIds.length === 0) return;

  for (const msgId of messageIds) {
    if (!deliveryAckBatch.has(msgId)) {
      deliveryAckBatch.set(msgId, { phones: new Set(), conversationId });
    }
    deliveryAckBatch.get(msgId).phones.add(phone);
  }

  // Start flush timer if not running
  if (!deliveryAckTimer) {
    deliveryAckTimer = setTimeout(flushDeliveryAcks, DELIVERY_ACK_FLUSH_MS);
  }
}

async function flushDeliveryAcks() {
  deliveryAckTimer = null;
  if (deliveryAckBatch.size === 0) return;

  // Take a snapshot and clear
  const batch = new Map(deliveryAckBatch);
  deliveryAckBatch.clear();

  try {
    for (const [msgId, { phones, conversationId }] of batch.entries()) {
      const phonesArray = [...phones];

      // Update DB: merge delivered_to arrays (add phones that aren't already there)
      await db.query(
        `UPDATE messenger_messages
         SET delivered_to = (
           SELECT jsonb_agg(DISTINCT val)
           FROM jsonb_array_elements_text(COALESCE(delivered_to, '[]'::jsonb) || $2::jsonb) AS val
         )
         WHERE id = $1`,
        [msgId, JSON.stringify(phonesArray)]
      );

      // Notify the sender that their message was delivered
      // We need sender_phone to send notification back
      const result = await db.query(
        'SELECT sender_phone, delivered_to FROM messenger_messages WHERE id = $1',
        [msgId]
      );
      if (result.rows.length > 0) {
        const senderPhone = result.rows[0].sender_phone;
        const deliveredTo = result.rows[0].delivered_to || [];
        sendToPhone(senderPhone, {
          type: 'message_delivered',
          conversationId,
          messageId: msgId,
          deliveredTo,
          timestamp: new Date().toISOString(),
        });
      }
    }
  } catch (err) {
    console.error('[Messenger WS] Error flushing delivery acks:', err.message);
  }
}

// ===== TARGETED BROADCASTING (только участникам разговора) =====

async function broadcastToConversation(conversationId, data, excludePhone = null, senderPhone = null) {
  const members = await getConversationPhones(conversationId);

  // If senderPhone provided, check who blocked them — skip those recipients
  let blockedByRecipients = new Set();
  if (senderPhone) {
    try {
      const result = await db.query(
        'SELECT blocker_phone FROM messenger_blocks WHERE blocked_phone = $1',
        [senderPhone]
      );
      blockedByRecipients = new Set(result.rows.map(r => r.blocker_phone));
    } catch (_) { /* non-critical */ }
  }

  for (const [phone, sockets] of connections.entries()) {
    if (phone !== excludePhone && members.has(phone) && !blockedByRecipients.has(phone)) {
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

async function broadcastOnlineStatus(phone, isOnline) {
  const message = {
    type: 'online_status',
    phone,
    isOnline,
    timestamp: new Date().toISOString()
  };

  // Отправляем только участникам разговоров с этим пользователем (не всем подряд)
  try {
    const result = await db.query(
      `SELECT DISTINCT mp.phone FROM messenger_participants mp
       WHERE mp.conversation_id IN (
         SELECT conversation_id FROM messenger_participants WHERE phone = $1
       ) AND mp.phone != $1`,
      [phone]
    );
    const targetPhones = new Set(result.rows.map(r => r.phone));
    for (const targetPhone of targetPhones) {
      if (!connections.has(targetPhone)) continue;
      for (const socket of connections.get(targetPhone)) {
        sendToSocket(socket, message);
      }
    }
  } catch (err) {
    console.error('[Messenger WS] Error broadcasting online status:', err.message);
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

  // Очищаем пустые записи typingStatus (разговоры без активных таймеров набора)
  for (const [convId, chatTyping] of typingStatus.entries()) {
    if (chatTyping.size === 0) {
      typingStatus.delete(convId);
    }
  }

  // Очищаем устаревшие записи wsRateLimit (окно 10 сек давно прошло)
  const now = Date.now();
  for (const [phone, rl] of wsRateLimit.entries()) {
    if (now >= rl.resetAt) {
      wsRateLimit.delete(phone);
    }
  }
}

// ===== ПУБЛИЧНЫЕ ФУНКЦИИ ДЛЯ REST API =====

async function notifyNewMessage(conversationId, message, excludePhone = null) {
  const senderPhone = message.sender_phone || message.senderPhone || null;
  await broadcastToConversation(conversationId, {
    type: 'new_message',
    conversationId,
    message,
    timestamp: new Date().toISOString()
  }, excludePhone, senderPhone);
}

async function notifyMessageDeleted(conversationId, messageId) {
  await broadcastToConversation(conversationId, {
    type: 'message_deleted',
    conversationId,
    messageId,
    timestamp: new Date().toISOString()
  });
}

async function notifyMessageEdited(conversationId, messageId, newContent, editedAt) {
  await broadcastToConversation(conversationId, {
    type: 'message_edited',
    conversationId,
    messageId,
    newContent,
    editedAt,
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
  notifyMessageEdited,
  notifyReactionAdded,
  notifyReactionRemoved,
  notifyReadReceipt,
  isUserOnline,
  getOnlineUsers,
  getConnectionsCount,
  sendToPhone,
  broadcastToConversation,
};
