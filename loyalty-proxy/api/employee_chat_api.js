const fs = require('fs');
const fsPromises = fs.promises;
const path = require('path');
const { isAdminPhoneAsync } = require('../utils/admin_cache');
const { maskPhone } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_EMPLOYEE_CHATS === 'true';

// WebSocket уведомления (опционально, если модуль загружен)
let wsNotify = null;
try {
  wsNotify = require('./employee_chat_websocket');
} catch (e) {
  console.log('⚠️ WebSocket модуль не загружен, real-time уведомления отключены');
}

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const EMPLOYEE_CHATS_DIR = `${DATA_DIR}/employee-chats`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const CLIENTS_DIR = `${DATA_DIR}/clients`;
const MESSAGE_RETENTION_DAYS = 90;
const MAX_GROUP_PARTICIPANTS = 100;

// Initialize directory on module load (async)
(async () => {
  try {
    await fsPromises.mkdir(EMPLOYEE_CHATS_DIR, { recursive: true });
  } catch (e) {
    if (e.code !== 'EEXIST') {
      console.error('Failed to create employee chats directory:', e);
    }
  }
})();

// Push notifications — через общий push_service.js
const pushService = require('../utils/push_service');

// ===== DB Converters =====

function chatToDb(chat) {
  return {
    id: chat.id,
    type: chat.type || null,
    name: chat.name || null,
    participants: chat.participants || null,
    participant_names: chat.participantNames || null,
    shop_address: chat.shopAddress || null,
    shop_members: chat.shopMembers || null,
    creator_phone: chat.creatorPhone || null,
    creator_name: chat.creatorName || null,
    image_url: chat.imageUrl || null,
    created_at: chat.createdAt || new Date().toISOString(),
    updated_at: chat.updatedAt || new Date().toISOString()
  };
}

function dbChatToObject(row, messageRows) {
  return {
    id: row.id,
    type: row.type,
    name: row.name,
    participants: row.participants,
    participantNames: row.participant_names,
    shopAddress: row.shop_address,
    shopMembers: row.shop_members,
    creatorPhone: row.creator_phone,
    creatorName: row.creator_name,
    imageUrl: row.image_url,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null,
    updatedAt: row.updated_at ? new Date(row.updated_at).toISOString() : null,
    messages: (messageRows || []).map(dbMsgToCamel)
  };
}

function msgToDb(msg, chatId) {
  return {
    id: msg.id,
    chat_id: chatId || msg.chatId,
    sender_phone: msg.senderPhone || null,
    sender_name: msg.senderName || null,
    text: msg.text || null,
    image_url: msg.imageUrl || null,
    read_by: msg.readBy || [],
    reactions: msg.reactions || null,
    forwarded_from: msg.forwardedFrom || null,
    timestamp: msg.timestamp || new Date().toISOString()
  };
}

function dbMsgToCamel(row) {
  const msg = {
    id: row.id,
    chatId: row.chat_id,
    senderPhone: row.sender_phone,
    senderName: row.sender_name,
    text: row.text,
    imageUrl: row.image_url,
    readBy: row.read_by || [],
    timestamp: row.timestamp ? new Date(row.timestamp).toISOString() : null
  };
  if (row.reactions) msg.reactions = row.reactions;
  if (row.forwarded_from) msg.forwardedFrom = row.forwarded_from;
  return msg;
}

// Helper: Load chat file (async)
async function loadChat(chatId) {
  // DB read branch
  if (USE_DB) {
    try {
      const chatRow = await db.findById('employee_chats', chatId);
      if (!chatRow) return null;
      const msgsResult = await db.query(
        'SELECT * FROM chat_messages WHERE chat_id = $1 ORDER BY timestamp ASC',
        [chatId]
      );
      return dbChatToObject(chatRow, msgsResult.rows);
    } catch (dbErr) {
      console.error('DB loadChat error:', dbErr.message);
      // fallback to file
    }
  }

  const sanitizedId = chatId.replace(/[^a-zA-Z0-9_\-]/g, '_');
  const filePath = path.join(EMPLOYEE_CHATS_DIR, `${sanitizedId}.json`);

  try {
    await fsPromises.access(filePath);
    const content = await fsPromises.readFile(filePath, 'utf8');
    try {
      return JSON.parse(content);
    } catch (parseError) {
      console.error(`JSON parse error for chat ${chatId}:`, parseError.message);
      return null;
    }
  } catch (e) {
    if (e.code !== 'ENOENT') {
      console.error(`Error loading chat ${chatId}:`, e.message);
    }
    return null;
  }
}

// Helper: Save chat file (async)
async function saveChat(chat) {
  const sanitizedId = chat.id.replace(/[^a-zA-Z0-9_\-]/g, '_');
  const filePath = path.join(EMPLOYEE_CHATS_DIR, `${sanitizedId}.json`);
  chat.updatedAt = new Date().toISOString();
  try {
    // Boy Scout: writeJsonFile with file locking instead of raw fsPromises.writeFile
    await writeJsonFile(filePath, chat);
  } catch (e) {
    console.error(`Error saving chat ${chat.id}:`, e.message);
    throw e;
  }
  // DB dual-write: chat metadata only (messages handled per-endpoint)
  if (USE_DB) {
    try {
      await db.upsert('employee_chats', chatToDb(chat));
    } catch (dbErr) {
      console.error('DB saveChat error:', dbErr.message);
    }
  }
}

// Helper: Clean old messages (older than retention days) - async
async function cleanOldMessages(chat) {
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - MESSAGE_RETENTION_DAYS);

  if (chat.messages && chat.messages.length > 0) {
    const originalLength = chat.messages.length;
    chat.messages = chat.messages.filter(m => new Date(m.timestamp) > cutoffDate);
    if (chat.messages.length !== originalLength) {
      await saveChat(chat);
      // DB: delete old messages
      if (USE_DB) {
        try {
          await db.query(
            'DELETE FROM chat_messages WHERE chat_id = $1 AND timestamp < $2',
            [chat.id, cutoffDate.toISOString()]
          );
        } catch (dbErr) {
          console.error('DB cleanOldMessages error:', dbErr.message);
        }
      }
    }
  }
  return chat;
}

// In-memory cache for employees (TTL: 30 seconds)
let _employeesCache = null;
let _employeesCacheTime = 0;
const EMPLOYEES_CACHE_TTL = 30000; // 30 seconds

// Helper: Get all employees (async, with cache + parallel reads)
async function getAllEmployees() {
  // Return cached if fresh
  if (_employeesCache && (Date.now() - _employeesCacheTime) < EMPLOYEES_CACHE_TTL) {
    return _employeesCache;
  }

  const employees = [];
  try {
    await fsPromises.access(EMPLOYEES_DIR);
    const files = await fsPromises.readdir(EMPLOYEES_DIR);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    // Parallel reads instead of sequential
    const results = await Promise.all(jsonFiles.map(async (file) => {
      try {
        const content = await fsPromises.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
        return JSON.parse(content);
      } catch (e) {
        console.error(`Error reading employee file ${file}:`, e.message);
        return null;
      }
    }));

    employees.push(...results.filter(Boolean));

    // Update cache
    _employeesCache = employees;
    _employeesCacheTime = Date.now();
  } catch (e) {
    if (e.code !== 'ENOENT') {
      console.error('Error reading employees directory:', e.message);
    }
  }
  return employees;
}

// Helper: Get employee by phone (async, uses cached getAllEmployees)
async function getEmployeeByPhone(phone) {
  const employees = await getAllEmployees();
  return employees.find(e => e.phone === phone);
}

// Helper: Check if phone belongs to admin - using cached version from admin_cache
// isAdminPhoneAsync is imported from ../utils/admin_cache

// Helper: Create private chat ID (sorted phones)
function createPrivateChatId(phone1, phone2) {
  const sorted = [phone1, phone2].sort();
  return `private_${sorted[0]}_${sorted[1]}`;
}

// Push-функции делегируются в push_service.js (BUG-06: единый модуль)
const CHAT_CHANNEL = 'employee_chat_channel';

async function getFcmTokens(phones) {
  return pushService.getFcmTokens(phones);
}

async function sendPushNotification(tokens, title, body, data) {
  if (tokens.length === 0) return;
  for (const { phone, token } of tokens) {
    await pushService.sendPushByToken(token, title, body, data || {}, CHAT_CHANNEL, phone);
  }
}

// Helper: Get chat participants for notifications (async)
async function getChatParticipants(chat, excludePhone) {
  if (chat.type === 'general') {
    // All employees except sender
    const employees = await getAllEmployees();
    return employees
      .filter(e => e.phone && e.phone !== excludePhone)
      .map(e => e.phone);
  } else if (chat.type === 'shop') {
    // Only shop members except sender
    return (chat.shopMembers || []).filter(p => p !== excludePhone);
  } else if (chat.type === 'private') {
    // Other participant
    return (chat.participants || []).filter(p => p !== excludePhone);
  } else if (chat.type === 'group') {
    // All group participants except sender
    return (chat.participants || []).filter(p => p !== excludePhone);
  }
  return [];
}

// Helper: Delete chat file (async)
async function deleteChat(chatId) {
  const sanitizedId = chatId.replace(/[^a-zA-Z0-9_\-]/g, '_');
  const filePath = path.join(EMPLOYEE_CHATS_DIR, `${sanitizedId}.json`);
  try {
    await fsPromises.unlink(filePath);
    console.log(`🗑️ Удалён чат: ${chatId}`);
  } catch (e) {
    if (e.code !== 'ENOENT') {
      console.error(`Error deleting chat ${chatId}:`, e.message);
    }
  }
  // DB: delete messages first (FK), then chat
  if (USE_DB) {
    try {
      await db.query('DELETE FROM chat_messages WHERE chat_id = $1', [chatId]);
      await db.deleteById('employee_chats', chatId);
    } catch (dbErr) {
      console.error('DB deleteChat error:', dbErr.message);
    }
  }
  return true;
}

// Helper: Get participant name (employee or client) (async)
async function getParticipantName(phone) {
  const normalizedPhone = phone.replace(/[^\d]/g, '');

  // Сначала ищем в сотрудниках
  const employees = await getAllEmployees();
  const employee = employees.find(e => {
    const empPhone = (e.phone || '').replace(/[^\d]/g, '');
    return empPhone === normalizedPhone;
  });
  if (employee && employee.name) {
    return employee.name;
  }

  // Затем в клиентах
  const clientFile = path.join(CLIENTS_DIR, `${normalizedPhone}.json`);
  try {
    await fsPromises.access(clientFile);
    const content = await fsPromises.readFile(clientFile, 'utf8');
    const client = JSON.parse(content);
    if (client.name) {
      return client.name;
    }
  } catch (e) {
    // Файл не существует или ошибка парсинга - возвращаем телефон
  }

  return phone; // Если не найден, возвращаем телефон
}

// Helper: Get all clients for group selection (async)
async function getClientsForGroupSelection() {
  const clients = [];
  try {
    await fsPromises.access(CLIENTS_DIR);
    const files = await fsPromises.readdir(CLIENTS_DIR);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    for (const file of jsonFiles) {
      try {
        const content = await fsPromises.readFile(path.join(CLIENTS_DIR, file), 'utf8');
        const data = JSON.parse(content);
        clients.push({
          phone: file.replace('.json', ''),
          name: data.name || null,
          points: data.points || 0
        });
      } catch (e) {
        // Skip invalid files
      }
    }
  } catch (e) {
    if (e.code !== 'ENOENT') {
      console.error('Error reading clients directory:', e.message);
    }
  }
  return clients;
}

// Helper: Generate random string for group ID
function randomString(length) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

function setupEmployeeChatAPI(app) {
  // ===== GET ALL CHATS FOR USER =====
  app.get('/api/employee-chats', requireAuth, async (req, res) => {
    try {
      const { phone } = req.query;
      const isAdminUser = await isAdminPhoneAsync(phone);
      console.log('GET /api/employee-chats for phone:', maskPhone(phone), 'isAdmin:', isAdminUser, '(verified from DB)');

      if (!phone) {
        return res.status(400).json({ success: false, error: 'phone is required' });
      }

      // DB read branch: efficient single query
      if (USE_DB) {
        try {
          // Ensure general chat exists
          const generalExists = await db.findById('employee_chats', 'general');
          if (!generalExists) {
            await db.upsert('employee_chats', {
              id: 'general', type: 'general', name: 'Общий чат',
              participants: [], created_at: new Date().toISOString(), updated_at: new Date().toISOString()
            });
          }

          // Single query: all chats with last message + unread count
          const result = await db.query(`
            SELECT c.*,
              lm.id as last_msg_id, lm.sender_phone as last_msg_sender_phone,
              lm.sender_name as last_msg_sender_name, lm.text as last_msg_text,
              lm.image_url as last_msg_image_url, lm.timestamp as last_msg_timestamp,
              lm.read_by as last_msg_read_by,
              COALESCE(uc.cnt, 0)::int as unread_count
            FROM employee_chats c
            LEFT JOIN LATERAL (
              SELECT * FROM chat_messages WHERE chat_id = c.id ORDER BY timestamp DESC LIMIT 1
            ) lm ON true
            LEFT JOIN LATERAL (
              SELECT COUNT(*) as cnt FROM chat_messages
              WHERE chat_id = c.id AND sender_phone != $1
              AND NOT ($1 = ANY(COALESCE(read_by, ARRAY[]::TEXT[])))
            ) uc ON true
            WHERE c.type = 'general'
              OR (c.type = 'private' AND $1 = ANY(COALESCE(c.participants, ARRAY[]::TEXT[])))
              OR (c.type = 'shop' AND ($2::boolean = true OR $1 = ANY(COALESCE(c.shop_members, ARRAY[]::TEXT[]))))
              OR (c.type = 'group' AND ($2::boolean = true OR $1 = ANY(COALESCE(c.participants, ARRAY[]::TEXT[]))))
            ORDER BY lm.timestamp DESC NULLS LAST
          `, [phone, isAdminUser]);

          // Resolve private chat names
          let employeesCache = null;
          const chats = [];
          for (const row of result.rows) {
            let chatName = row.name;
            if (row.type === 'private') {
              const participants = row.participants || [];
              const otherPhone = participants.find(p => p !== phone);
              if (otherPhone) {
                if (!employeesCache) employeesCache = await getAllEmployees();
                const otherEmp = employeesCache.find(e => e.phone === otherPhone);
                chatName = otherEmp?.name || otherPhone;
              }
            }
            const lastMessage = row.last_msg_id ? {
              id: row.last_msg_id,
              senderPhone: row.last_msg_sender_phone,
              senderName: row.last_msg_sender_name,
              text: row.last_msg_text,
              imageUrl: row.last_msg_image_url,
              readBy: row.last_msg_read_by || [],
              timestamp: row.last_msg_timestamp ? new Date(row.last_msg_timestamp).toISOString() : null
            } : null;

            chats.push({
              id: row.id,
              type: row.type,
              name: chatName,
              shopAddress: row.shop_address,
              participants: row.participants,
              participantNames: row.participant_names,
              imageUrl: row.image_url,
              creatorPhone: row.creator_phone,
              creatorName: row.creator_name,
              unreadCount: row.unread_count,
              lastMessage
            });
          }
          return res.json({ success: true, chats });
        } catch (dbErr) {
          console.error('DB list chats error:', dbErr.message);
          // fallback to file
        }
      }

      const chats = [];

      // 1. General chat (always exists)
      let generalChat = await loadChat('general');
      if (!generalChat) {
        generalChat = {
          id: 'general',
          type: 'general',
          name: 'Общий чат',
          messages: [],
          participants: [],
          createdAt: new Date().toISOString()
        };
        await saveChat(generalChat);
      }
      generalChat = await cleanOldMessages(generalChat);

      const generalUnread = (generalChat.messages || []).filter(m =>
        m.senderPhone !== phone && !(m.readBy || []).includes(phone)
      ).length;

      chats.push({
        id: generalChat.id,
        type: 'general',
        name: 'Общий чат',
        unreadCount: generalUnread,
        lastMessage: generalChat.messages?.length > 0
          ? generalChat.messages[generalChat.messages.length - 1]
          : null
      });

      // 2. Shop chats and private chats
      try {
        await fsPromises.access(EMPLOYEE_CHATS_DIR);
        const allFiles = await fsPromises.readdir(EMPLOYEE_CHATS_DIR);
        const files = allFiles.filter(f => f.endsWith('.json') && f !== 'general.json');

        const chatResults = await Promise.all(files.map(async (file) => {
          try {
            const content = await fsPromises.readFile(path.join(EMPLOYEE_CHATS_DIR, file), 'utf8');
            return JSON.parse(content);
          } catch (e) {
            console.error(`Error reading/parsing chat file ${file}:`, e.message);
            return null;
          }
        }));
        const allChats = chatResults.filter(Boolean);

        let employeesCache = null;
        const getEmployeeCached = async (empPhone) => {
          if (!employeesCache) {
            employeesCache = await getAllEmployees();
          }
          return employeesCache.find(e => e.phone === empPhone);
        };

        const normalizedPhone = phone.replace(/[^\d]/g, '');

        for (const chat of allChats) {
          if (chat.type === 'private') {
            if (!(chat.participants || []).includes(phone)) continue;
            const otherPhone = chat.participants.find(p => p !== phone);
            const otherEmployee = await getEmployeeCached(otherPhone);
            chat.name = otherEmployee?.name || otherPhone;
          }

          if (chat.type === 'shop') {
            if (!isAdminUser && (!chat.shopMembers || !chat.shopMembers.includes(phone))) continue;
          }

          if (chat.type === 'group') {
            const normalizedParticipants = (chat.participants || []).map(p => p.replace(/[^\d]/g, ''));
            if (!isAdminUser && !normalizedParticipants.includes(normalizedPhone)) continue;
          }

          const messages = chat.messages || [];
          const unread = messages.filter(m =>
            m.senderPhone !== phone && !(m.readBy || []).includes(phone)
          ).length;

          chats.push({
            id: chat.id,
            type: chat.type,
            name: chat.name,
            shopAddress: chat.shopAddress,
            participants: chat.participants,
            participantNames: chat.participantNames,
            imageUrl: chat.imageUrl,
            creatorPhone: chat.creatorPhone,
            creatorName: chat.creatorName,
            unreadCount: unread,
            lastMessage: messages.length > 0
              ? messages[messages.length - 1]
              : null
          });
        }
      } catch (e) {
        if (e.code !== 'ENOENT') {
          console.error('Error reading chats directory:', e.message);
        }
      }

      // Sort by last message time
      chats.sort((a, b) => {
        const aTime = a.lastMessage?.timestamp || '1970-01-01';
        const bTime = b.lastMessage?.timestamp || '1970-01-01';
        return new Date(bTime) - new Date(aTime);
      });

      res.json({ success: true, chats });
    } catch (error) {
      console.error('Error getting chats:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET MESSAGES FOR CHAT =====
  app.get('/api/employee-chats/:chatId/messages', requireAuth, async (req, res) => {
    try {
      const { chatId } = req.params;
      const { phone, limit = 50, before } = req.query;
      const parsedLimit = Math.min(parseInt(limit) || 50, 200);
      console.log('GET /api/employee-chats/:chatId/messages:', chatId, 'limit:', parsedLimit, 'before:', before ? 'yes' : 'no');

      // DB path: SQL-level pagination (не загружает ВСЕ сообщения)
      if (USE_DB) {
        try {
          const chatExists = await db.findById('employee_chats', chatId);
          if (!chatExists) {
            return res.json({ success: true, messages: [], hasMore: false });
          }

          let query, params;
          if (before) {
            // Загрузить сообщения старше указанного timestamp
            query = `SELECT * FROM chat_messages WHERE chat_id = $1 AND timestamp < $2
                     ORDER BY timestamp DESC LIMIT $3`;
            params = [chatId, before, parsedLimit + 1];
          } else {
            // Загрузить последние сообщения
            query = `SELECT * FROM chat_messages WHERE chat_id = $1
                     ORDER BY timestamp DESC LIMIT $2`;
            params = [chatId, parsedLimit + 1];
          }

          const result = await db.query(query, params);
          const hasMore = result.rows.length > parsedLimit;
          const rows = hasMore ? result.rows.slice(0, parsedLimit) : result.rows;

          // Reverse: DB возвращает DESC, клиенту нужен ASC (хронологический)
          const messages = rows.reverse().map(dbMsgToCamel);

          return res.json({ success: true, messages, hasMore });
        } catch (dbErr) {
          console.error('DB getMessages error:', dbErr.message);
          // fallback to file
        }
      }

      // JSON fallback (загружает всё, потом slice)
      let chat = await loadChat(chatId);
      if (!chat) {
        return res.json({ success: true, messages: [], hasMore: false });
      }

      chat = await cleanOldMessages(chat);
      let messages = chat.messages || [];

      // Pagination by timestamp
      if (before) {
        messages = messages.filter(m => new Date(m.timestamp) < new Date(before));
      }

      const hasMore = messages.length > parsedLimit;
      messages = messages.slice(-parsedLimit);

      res.json({ success: true, messages, hasMore });
    } catch (error) {
      console.error('Error getting messages:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SEND MESSAGE =====
  app.post('/api/employee-chats/:chatId/messages', requireAuth, async (req, res) => {
    try {
      const { chatId } = req.params;
      const { senderPhone, senderName, text, imageUrl } = req.body;
      console.log('POST /api/employee-chats/:chatId/messages:', chatId, senderName, 'text length:', text?.length || 0);

      if (!senderPhone || (!text && !imageUrl)) {
        return res.status(400).json({
          success: false,
          error: 'senderPhone and (text or imageUrl) are required'
        });
      }

      let chat = await loadChat(chatId);
      if (!chat) {
        // Create chat if doesn't exist (for general)
        if (chatId === 'general') {
          chat = {
            id: 'general',
            type: 'general',
            name: 'Общий чат',
            messages: [],
            participants: [],
            createdAt: new Date().toISOString()
          };
        } else {
          return res.status(404).json({ success: false, error: 'Chat not found' });
        }
      }

      const message = {
        id: `msg_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`,
        chatId,
        senderPhone,
        senderName: senderName || senderPhone,
        text: text || '',
        imageUrl: imageUrl || null,
        timestamp: new Date().toISOString(),
        readBy: [senderPhone]
      };

      if (!chat.messages) chat.messages = [];
      chat.messages.push(message);
      await saveChat(chat);

      // DB: insert message
      if (USE_DB) {
        try {
          await db.upsert('chat_messages', msgToDb(message, chatId));
        } catch (dbErr) {
          console.error('DB send message error:', dbErr.message);
        }
      }

      // Send push notifications
      const recipients = await getChatParticipants(chat, senderPhone);
      const tokens = await getFcmTokens(recipients);

      if (tokens.length > 0) {
        const title = chat.type === 'private' ? senderName : chat.name;
        const body = imageUrl ? `${senderName}: [Фото]` : `${senderName}: ${text.substring(0, 100)}`;

        // Push отправляется асинхронно, не ждём результата
        sendPushNotification(tokens, title, body, {
          type: 'employee_chat',
          chatId: chatId,
          messageId: message.id
        }).catch(e => console.error('Push error:', e.message));
      }

      // WebSocket: мгновенное уведомление о новом сообщении
      if (wsNotify) {
        wsNotify.notifyNewMessage(chatId, message, senderPhone);
      }

      res.json({ success: true, message });
    } catch (error) {
      console.error('Error sending message:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== MARK CHAT AS READ =====
  app.post('/api/employee-chats/:chatId/read', requireAuth, async (req, res) => {
    try {
      const { chatId } = req.params;
      const { phone } = req.body;
      console.log('POST /api/employee-chats/:chatId/read:', chatId, maskPhone(phone));

      if (!phone) {
        return res.status(400).json({ success: false, error: 'phone is required' });
      }

      const chat = await loadChat(chatId);
      if (!chat) {
        return res.status(404).json({ success: false, error: 'Chat not found' });
      }

      let updated = false;
      for (const msg of (chat.messages || [])) {
        if (msg.senderPhone !== phone && !(msg.readBy || []).includes(phone)) {
          if (!msg.readBy) msg.readBy = [];
          msg.readBy.push(phone);
          updated = true;
        }
      }

      if (updated) {
        await saveChat(chat);
        // DB: bulk update read_by
        if (USE_DB) {
          try {
            await db.query(
              `UPDATE chat_messages SET read_by = array_append(read_by, $1)
               WHERE chat_id = $2 AND sender_phone != $1
               AND NOT ($1 = ANY(COALESCE(read_by, ARRAY[]::TEXT[])))`,
              [phone, chatId]
            );
          } catch (dbErr) {
            console.error('DB mark-read error:', dbErr.message);
          }
        }
      }

      res.json({ success: true });
    } catch (error) {
      console.error('Error marking as read:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CREATE/GET PRIVATE CHAT =====
  app.post('/api/employee-chats/private', requireAuth, async (req, res) => {
    try {
      const { phone1, phone2 } = req.body;
      console.log('POST /api/employee-chats/private:', maskPhone(phone1), maskPhone(phone2));

      if (!phone1 || !phone2) {
        return res.status(400).json({ success: false, error: 'phone1 and phone2 are required' });
      }

      const chatId = createPrivateChatId(phone1, phone2);
      let chat = await loadChat(chatId);

      if (!chat) {
        // One read instead of two separate getEmployeeByPhone calls
        const allEmployees = await getAllEmployees();
        const employee1 = allEmployees.find(e => e.phone === phone1);
        const employee2 = allEmployees.find(e => e.phone === phone2);

        chat = {
          id: chatId,
          type: 'private',
          name: '', // Will be set dynamically based on viewer
          participants: [phone1, phone2].sort(),
          participantNames: {
            [phone1]: employee1?.name || phone1,
            [phone2]: employee2?.name || phone2
          },
          messages: [],
          createdAt: new Date().toISOString()
        };
        await saveChat(chat);
      }

      res.json({ success: true, chat });
    } catch (error) {
      console.error('Error creating private chat:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CREATE/GET SHOP CHAT =====
  app.post('/api/employee-chats/shop', requireAuth, async (req, res) => {
    try {
      const { shopAddress, phone } = req.body;
      console.log('POST /api/employee-chats/shop:', shopAddress, 'phone:', maskPhone(phone));

      if (!shopAddress) {
        return res.status(400).json({ success: false, error: 'shopAddress is required' });
      }

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const chatId = `shop_${sanitizedAddress}`;
      let chat = await loadChat(chatId);
      let needSave = false;

      if (!chat) {
        chat = {
          id: chatId,
          type: 'shop',
          name: shopAddress,
          shopAddress: shopAddress,
          shopMembers: phone ? [phone] : [],
          messages: [],
          createdAt: new Date().toISOString()
        };
        needSave = true;
      } else if (phone && !(chat.shopMembers || []).includes(phone)) {
        // Автоматически добавляем пользователя в участники при открытии
        if (!chat.shopMembers) chat.shopMembers = [];
        chat.shopMembers.push(phone);
        needSave = true;
      }

      if (needSave) {
        await saveChat(chat);
      }

      res.json({ success: true, chat });
    } catch (error) {
      console.error('Error creating shop chat:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET SHOP CHAT MEMBERS =====
  app.get('/api/employee-chats/shop/:shopAddress/members', requireAuth, async (req, res) => {
    try {
      const { shopAddress } = req.params;
      console.log('GET /api/employee-chats/shop/:shopAddress/members:', shopAddress);

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const chatId = `shop_${sanitizedAddress}`;
      const chat = await loadChat(chatId);

      if (!chat) {
        return res.status(404).json({ success: false, error: 'Shop chat not found' });
      }

      // Получаем информацию о всех участниках (один запрос вместо N)
      const allEmployees = await getAllEmployees();
      const members = (chat.shopMembers || []).map(phone => {
        const employee = allEmployees.find(e => e.phone === phone);
        return {
          phone,
          name: employee?.name || phone,
          position: employee?.position || ''
        };
      });

      res.json({ success: true, members, shopAddress: chat.shopAddress });
    } catch (error) {
      console.error('Error getting shop chat members:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ADD MEMBERS TO SHOP CHAT =====
  app.post('/api/employee-chats/shop/:shopAddress/members', requireAuth, async (req, res) => {
    try {
      const { shopAddress } = req.params;
      const { phones } = req.body;
      console.log('POST /api/employee-chats/shop/:shopAddress/members:', shopAddress, 'phones:', phones?.length);

      if (!phones || !Array.isArray(phones) || phones.length === 0) {
        return res.status(400).json({ success: false, error: 'phones array is required' });
      }

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const chatId = `shop_${sanitizedAddress}`;
      let chat = await loadChat(chatId);

      if (!chat) {
        // Создаём чат если не существует
        chat = {
          id: chatId,
          type: 'shop',
          name: shopAddress,
          shopAddress: shopAddress,
          shopMembers: [],
          messages: [],
          createdAt: new Date().toISOString()
        };
      }

      // Добавляем новых участников (без дубликатов)
      if (!chat.shopMembers) chat.shopMembers = [];
      for (const phone of phones) {
        if (!chat.shopMembers.includes(phone)) {
          chat.shopMembers.push(phone);
        }
      }

      await saveChat(chat);

      res.json({ success: true, shopMembers: chat.shopMembers });
    } catch (error) {
      console.error('Error adding shop chat members:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== REMOVE MEMBER FROM SHOP CHAT (admin only) =====
  app.delete('/api/employee-chats/shop/:shopAddress/members/:phone', requireAuth, async (req, res) => {
    try {
      const { shopAddress, phone } = req.params;
      const { requesterPhone } = req.query;
      console.log('DELETE /api/employee-chats/shop/:shopAddress/members/:phone:', shopAddress, maskPhone(phone), 'requester:', maskPhone(requesterPhone));

      // Проверка авторизации: только админ может удалять участников
      if (!requesterPhone || !(await isAdminPhoneAsync(requesterPhone))) {
        console.log('❌ Отказ: удаление участника чата без прав админа');
        return res.status(403).json({ success: false, error: 'Доступ только для администраторов' });
      }

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const chatId = `shop_${sanitizedAddress}`;
      const chat = await loadChat(chatId);

      if (!chat) {
        return res.status(404).json({ success: false, error: 'Shop chat not found' });
      }

      if (!chat.shopMembers) chat.shopMembers = [];
      const idx = chat.shopMembers.indexOf(phone);
      if (idx === -1) {
        return res.status(404).json({ success: false, error: 'Member not found in chat' });
      }

      chat.shopMembers.splice(idx, 1);
      await saveChat(chat);

      res.json({ success: true, shopMembers: chat.shopMembers });
    } catch (error) {
      console.error('Error removing shop chat member:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CLEAR CHAT MESSAGES (admin only) =====
  app.post('/api/employee-chats/:chatId/clear', requireAuth, async (req, res) => {
    try {
      const { chatId } = req.params;
      const { mode, requesterPhone } = req.body; // "previous_month" | "all"
      console.log('POST /api/employee-chats/:chatId/clear:', chatId, 'mode:', mode, 'requester:', requesterPhone);

      // Проверка авторизации: только админ может очищать чат
      if (!requesterPhone || !(await isAdminPhoneAsync(requesterPhone))) {
        console.log('❌ Отказ: очистка чата без прав админа');
        return res.status(403).json({ success: false, error: 'Доступ только для администраторов' });
      }

      const chat = await loadChat(chatId);
      if (!chat) {
        return res.status(404).json({ success: false, error: 'Chat not found' });
      }

      const originalCount = (chat.messages || []).length;
      let deletedCount = 0;

      if (mode === 'all') {
        // Удаляем все сообщения
        deletedCount = originalCount;
        chat.messages = [];
      } else if (mode === 'previous_month') {
        // Удаляем сообщения старше текущего месяца
        const now = new Date();
        const firstDayOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

        chat.messages = (chat.messages || []).filter(m => {
          const msgDate = new Date(m.timestamp);
          return msgDate >= firstDayOfMonth;
        });
        deletedCount = originalCount - chat.messages.length;
      } else {
        return res.status(400).json({ success: false, error: 'Invalid mode. Use "previous_month" or "all"' });
      }

      await saveChat(chat);

      // DB: delete messages
      if (USE_DB && deletedCount > 0) {
        try {
          if (mode === 'all') {
            await db.query('DELETE FROM chat_messages WHERE chat_id = $1', [chatId]);
          } else {
            await db.query(
              'DELETE FROM chat_messages WHERE chat_id = $1 AND timestamp < $2',
              [chatId, firstDayOfMonth.toISOString()]
            );
          }
        } catch (dbErr) {
          console.error('DB clear messages error:', dbErr.message);
        }
      }

      // WebSocket: уведомление об очистке чата
      if (wsNotify && deletedCount > 0) {
        wsNotify.notifyChatCleared(chatId, deletedCount);
      }

      res.json({ success: true, deletedCount });
    } catch (error) {
      console.error('Error clearing chat messages:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== DELETE MESSAGE (admin only) =====
  app.delete('/api/employee-chats/:chatId/messages/:messageId', requireAuth, async (req, res) => {
    try {
      const { chatId, messageId } = req.params;
      const { requesterPhone } = req.query;
      console.log('DELETE /api/employee-chats/:chatId/messages/:messageId:', chatId, messageId, 'requester:', requesterPhone);

      // Проверка авторизации: только админ может удалять сообщения
      if (!requesterPhone || !(await isAdminPhoneAsync(requesterPhone))) {
        console.log('❌ Отказ: удаление сообщения без прав админа');
        return res.status(403).json({ success: false, error: 'Доступ только для администраторов' });
      }

      const chat = await loadChat(chatId);
      if (!chat) {
        return res.status(404).json({ success: false, error: 'Chat not found' });
      }

      const idx = (chat.messages || []).findIndex(m => m.id === messageId);
      if (idx === -1) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      chat.messages.splice(idx, 1);
      await saveChat(chat);

      // DB: delete message
      if (USE_DB) {
        try {
          await db.query('DELETE FROM chat_messages WHERE id = $1 AND chat_id = $2', [messageId, chatId]);
        } catch (dbErr) {
          console.error('DB delete message error:', dbErr.message);
        }
      }

      // WebSocket: уведомление об удалении сообщения
      if (wsNotify) {
        wsNotify.notifyMessageDeleted(chatId, messageId);
      }

      res.json({ success: true });
    } catch (error) {
      console.error('Error deleting message:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SEARCH MESSAGES IN CHAT =====
  app.get('/api/employee-chats/:chatId/messages/search', requireAuth, async (req, res) => {
    try {
      const { chatId } = req.params;
      const { query, limit = 50 } = req.query;
      console.log('GET /api/employee-chats/:chatId/messages/search:', chatId, 'query:', query);

      if (!query || query.trim().length < 2) {
        return res.status(400).json({ success: false, error: 'Query must be at least 2 characters' });
      }

      const chat = await loadChat(chatId);
      if (!chat) {
        return res.json({ success: true, messages: [] });
      }

      const searchQuery = query.toLowerCase().trim();
      const messages = (chat.messages || [])
        .filter(m =>
          (m.text && m.text.toLowerCase().includes(searchQuery)) ||
          (m.senderName && m.senderName.toLowerCase().includes(searchQuery))
        )
        .slice(-parseInt(limit));

      res.json({ success: true, messages, total: messages.length });
    } catch (error) {
      console.error('Error searching messages:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ADD REACTION TO MESSAGE =====
  app.post('/api/employee-chats/:chatId/messages/:messageId/reactions', requireAuth, async (req, res) => {
    try {
      const { chatId, messageId } = req.params;
      const { phone, reaction } = req.body; // reaction: emoji string like "👍", "❤️", etc.
      console.log('POST /api/employee-chats/:chatId/messages/:messageId/reactions:', chatId, messageId, maskPhone(phone), reaction);

      if (!phone || !reaction) {
        return res.status(400).json({ success: false, error: 'phone and reaction are required' });
      }

      const chat = await loadChat(chatId);
      if (!chat) {
        return res.status(404).json({ success: false, error: 'Chat not found' });
      }

      const message = (chat.messages || []).find(m => m.id === messageId);
      if (!message) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      // Инициализируем reactions если нет
      if (!message.reactions) {
        message.reactions = {};
      }

      // Добавляем реакцию: reactions = { "👍": ["phone1", "phone2"], "❤️": ["phone3"] }
      if (!message.reactions[reaction]) {
        message.reactions[reaction] = [];
      }

      // Проверяем, не ставил ли уже этот пользователь эту реакцию
      if (!message.reactions[reaction].includes(phone)) {
        message.reactions[reaction].push(phone);
      }

      await saveChat(chat);

      // DB: update reactions on message
      if (USE_DB) {
        try {
          await db.query(
            'UPDATE chat_messages SET reactions = $1 WHERE id = $2 AND chat_id = $3',
            [JSON.stringify(message.reactions), messageId, chatId]
          );
        } catch (dbErr) {
          console.error('DB add reaction error:', dbErr.message);
        }
      }

      // WebSocket: уведомление о реакции
      if (wsNotify) {
        wsNotify.notifyReactionAdded(chatId, messageId, reaction, phone);
      }

      res.json({ success: true, reactions: message.reactions });
    } catch (error) {
      console.error('Error adding reaction:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== REMOVE REACTION FROM MESSAGE =====
  app.delete('/api/employee-chats/:chatId/messages/:messageId/reactions', requireAuth, async (req, res) => {
    try {
      const { chatId, messageId } = req.params;
      const { phone, reaction } = req.query;
      console.log('DELETE /api/employee-chats/:chatId/messages/:messageId/reactions:', chatId, messageId, maskPhone(phone), reaction);

      if (!phone || !reaction) {
        return res.status(400).json({ success: false, error: 'phone and reaction are required' });
      }

      const chat = await loadChat(chatId);
      if (!chat) {
        return res.status(404).json({ success: false, error: 'Chat not found' });
      }

      const message = (chat.messages || []).find(m => m.id === messageId);
      if (!message) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      if (message.reactions && message.reactions[reaction]) {
        const idx = message.reactions[reaction].indexOf(phone);
        if (idx !== -1) {
          message.reactions[reaction].splice(idx, 1);
          // Удаляем пустые реакции
          if (message.reactions[reaction].length === 0) {
            delete message.reactions[reaction];
          }
        }
      }

      await saveChat(chat);

      // DB: update reactions on message
      if (USE_DB) {
        try {
          await db.query(
            'UPDATE chat_messages SET reactions = $1 WHERE id = $2 AND chat_id = $3',
            [JSON.stringify(message.reactions || {}), messageId, chatId]
          );
        } catch (dbErr) {
          console.error('DB remove reaction error:', dbErr.message);
        }
      }

      // WebSocket: уведомление об удалении реакции
      if (wsNotify) {
        wsNotify.notifyReactionRemoved(chatId, messageId, reaction, phone);
      }

      res.json({ success: true, reactions: message.reactions || {} });
    } catch (error) {
      console.error('Error removing reaction:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== FORWARD MESSAGE =====
  app.post('/api/employee-chats/:targetChatId/messages/forward', requireAuth, async (req, res) => {
    try {
      const { targetChatId } = req.params;
      const { sourceChatId, sourceMessageId, senderPhone, senderName } = req.body;
      console.log('POST /api/employee-chats/:targetChatId/messages/forward:', targetChatId, 'from:', sourceChatId, sourceMessageId);

      if (!sourceChatId || !sourceMessageId || !senderPhone) {
        return res.status(400).json({ success: false, error: 'sourceChatId, sourceMessageId and senderPhone are required' });
      }

      // Загружаем исходный чат и сообщение
      const sourceChat = await loadChat(sourceChatId);
      if (!sourceChat) {
        return res.status(404).json({ success: false, error: 'Source chat not found' });
      }

      const sourceMessage = (sourceChat.messages || []).find(m => m.id === sourceMessageId);
      if (!sourceMessage) {
        return res.status(404).json({ success: false, error: 'Source message not found' });
      }

      // Загружаем целевой чат
      let targetChat = await loadChat(targetChatId);
      if (!targetChat) {
        return res.status(404).json({ success: false, error: 'Target chat not found' });
      }

      // Создаём пересланное сообщение
      const forwardedMessage = {
        id: `msg_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`,
        chatId: targetChatId,
        senderPhone,
        senderName: senderName || senderPhone,
        text: sourceMessage.text || '',
        imageUrl: sourceMessage.imageUrl || null,
        timestamp: new Date().toISOString(),
        readBy: [senderPhone],
        // Информация о пересылке
        forwardedFrom: {
          chatId: sourceChatId,
          messageId: sourceMessageId,
          originalSenderName: sourceMessage.senderName,
          originalTimestamp: sourceMessage.timestamp
        }
      };

      if (!targetChat.messages) targetChat.messages = [];
      targetChat.messages.push(forwardedMessage);
      await saveChat(targetChat);

      // DB: insert forwarded message
      if (USE_DB) {
        try {
          await db.upsert('chat_messages', msgToDb(forwardedMessage, targetChatId));
        } catch (dbErr) {
          console.error('DB forward message error:', dbErr.message);
        }
      }

      // Push уведомления
      const recipients = await getChatParticipants(targetChat, senderPhone);
      const tokens = await getFcmTokens(recipients);

      if (tokens.length > 0) {
        const title = targetChat.type === 'private' ? senderName : targetChat.name;
        const body = `${senderName}: [Пересланное сообщение]`;
        sendPushNotification(tokens, title, body, {
          type: 'employee_chat',
          chatId: targetChatId,
          messageId: forwardedMessage.id
        });
      }

      // WebSocket: уведомление о новом сообщении
      if (wsNotify) {
        wsNotify.notifyNewMessage(targetChatId, forwardedMessage, senderPhone);
      }

      res.json({ success: true, message: forwardedMessage });
    } catch (error) {
      console.error('Error forwarding message:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET CLIENTS LIST FOR GROUP SELECTION =====
  app.get('/api/clients/list', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/clients/list');
      const clients = await getClientsForGroupSelection();
      res.json({ success: true, clients });
    } catch (error) {
      console.error('Error getting clients list:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CREATE GROUP CHAT (admin only) =====
  app.post('/api/employee-chats/group', requireAuth, async (req, res) => {
    try {
      const { creatorPhone, creatorName, name, imageUrl, participants } = req.body;
      console.log('POST /api/employee-chats/group:', name, 'creator:', creatorPhone, 'participants:', participants?.length);

      // Валидация
      if (!creatorPhone || !name || !participants || !Array.isArray(participants) || participants.length === 0) {
        return res.status(400).json({ success: false, error: 'creatorPhone, name and participants are required' });
      }

      // Проверка что создатель - админ
      if (!(await isAdminPhoneAsync(creatorPhone))) {
        console.log('❌ Отказ: создание группы без прав админа');
        return res.status(403).json({ success: false, error: 'Только администраторы могут создавать группы' });
      }

      // Проверка лимита участников
      if (participants.length > MAX_GROUP_PARTICIPANTS) {
        return res.status(400).json({ success: false, error: `Максимум ${MAX_GROUP_PARTICIPANTS} участников в группе` });
      }

      const groupId = `group_${Date.now()}_${randomString(8)}`;
      const normalizedCreatorPhone = creatorPhone.replace(/[^\d]/g, '');

      // Собрать имена участников
      const participantNames = {};
      participantNames[normalizedCreatorPhone] = creatorName || await getParticipantName(creatorPhone);

      // Нормализуем телефоны участников и получаем их имена
      const normalizedParticipants = [normalizedCreatorPhone];
      for (const phone of participants) {
        const normalizedPhone = phone.replace(/[^\d]/g, '');
        if (normalizedPhone !== normalizedCreatorPhone && !normalizedParticipants.includes(normalizedPhone)) {
          normalizedParticipants.push(normalizedPhone);
          participantNames[normalizedPhone] = await getParticipantName(phone);
        }
      }

      const chat = {
        id: groupId,
        type: 'group',
        name: name.trim(),
        imageUrl: imageUrl || null,
        creatorPhone: normalizedCreatorPhone,
        creatorName: creatorName || await getParticipantName(creatorPhone),
        participants: normalizedParticipants,
        participantNames,
        messages: [],
        createdAt: new Date().toISOString()
      };

      await saveChat(chat);
      console.log(`✅ Создана группа "${name}" с ${normalizedParticipants.length} участниками`);

      res.json({ success: true, chat });
    } catch (error) {
      console.error('Error creating group:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== UPDATE GROUP CHAT (creator only) =====
  app.put('/api/employee-chats/group/:groupId', requireAuth, async (req, res) => {
    try {
      const { groupId } = req.params;
      const { requesterPhone, name, imageUrl } = req.body;
      console.log('PUT /api/employee-chats/group/:groupId:', groupId, 'requester:', requesterPhone);

      if (!requesterPhone) {
        return res.status(400).json({ success: false, error: 'requesterPhone is required' });
      }

      const chat = await loadChat(groupId);
      if (!chat || chat.type !== 'group') {
        return res.status(404).json({ success: false, error: 'Группа не найдена' });
      }

      // Только создатель может редактировать
      const normalizedRequester = requesterPhone.replace(/[^\d]/g, '');
      if (chat.creatorPhone !== normalizedRequester) {
        console.log('❌ Отказ: редактирование группы не создателем');
        return res.status(403).json({ success: false, error: 'Только создатель может редактировать группу' });
      }

      if (name !== undefined && name.trim()) {
        chat.name = name.trim();
      }
      if (imageUrl !== undefined) {
        chat.imageUrl = imageUrl || null;
      }

      await saveChat(chat);
      console.log(`✅ Группа "${chat.name}" обновлена`);

      res.json({ success: true, chat });
    } catch (error) {
      console.error('Error updating group:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ADD MEMBERS TO GROUP (creator only) =====
  app.post('/api/employee-chats/group/:groupId/members', requireAuth, async (req, res) => {
    try {
      const { groupId } = req.params;
      const { requesterPhone, phones } = req.body;
      console.log('POST /api/employee-chats/group/:groupId/members:', groupId, 'phones:', phones?.length);

      if (!requesterPhone || !phones || !Array.isArray(phones) || phones.length === 0) {
        return res.status(400).json({ success: false, error: 'requesterPhone and phones array are required' });
      }

      const chat = await loadChat(groupId);
      if (!chat || chat.type !== 'group') {
        return res.status(404).json({ success: false, error: 'Группа не найдена' });
      }

      // Только создатель может добавлять участников
      const normalizedRequester = requesterPhone.replace(/[^\d]/g, '');
      if (chat.creatorPhone !== normalizedRequester) {
        console.log('❌ Отказ: добавление участников не создателем');
        return res.status(403).json({ success: false, error: 'Только создатель может добавлять участников' });
      }

      // Проверка лимита
      if ((chat.participants || []).length + phones.length > MAX_GROUP_PARTICIPANTS) {
        return res.status(400).json({ success: false, error: `Максимум ${MAX_GROUP_PARTICIPANTS} участников в группе` });
      }

      // Добавляем новых участников
      for (const phone of phones) {
        const normalizedPhone = phone.replace(/[^\d]/g, '');
        if (!chat.participants.includes(normalizedPhone)) {
          chat.participants.push(normalizedPhone);
          chat.participantNames[normalizedPhone] = await getParticipantName(phone);
        }
      }

      await saveChat(chat);
      console.log(`✅ Добавлено ${phones.length} участников в группу "${chat.name}"`);

      res.json({ success: true, participants: chat.participants, participantNames: chat.participantNames });
    } catch (error) {
      console.error('Error adding group members:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== REMOVE MEMBER FROM GROUP (creator only) =====
  app.delete('/api/employee-chats/group/:groupId/members/:phone', requireAuth, async (req, res) => {
    try {
      const { groupId, phone } = req.params;
      const { requesterPhone } = req.query;
      console.log('DELETE /api/employee-chats/group/:groupId/members/:phone:', groupId, maskPhone(phone), 'requester:', maskPhone(requesterPhone));

      if (!requesterPhone) {
        return res.status(400).json({ success: false, error: 'requesterPhone is required' });
      }

      const chat = await loadChat(groupId);
      if (!chat || chat.type !== 'group') {
        return res.status(404).json({ success: false, error: 'Группа не найдена' });
      }

      // Только создатель может удалять участников
      const normalizedRequester = requesterPhone.replace(/[^\d]/g, '');
      if (chat.creatorPhone !== normalizedRequester) {
        console.log('❌ Отказ: удаление участника не создателем');
        return res.status(403).json({ success: false, error: 'Только создатель может удалять участников' });
      }

      const normalizedPhone = phone.replace(/[^\d]/g, '');

      // Нельзя удалить создателя
      if (normalizedPhone === chat.creatorPhone) {
        return res.status(400).json({ success: false, error: 'Нельзя удалить создателя группы' });
      }

      const idx = chat.participants.indexOf(normalizedPhone);
      if (idx === -1) {
        return res.status(404).json({ success: false, error: 'Участник не найден в группе' });
      }

      chat.participants.splice(idx, 1);
      delete chat.participantNames[normalizedPhone];

      await saveChat(chat);
      console.log(`✅ Участник ${maskPhone(phone)} удалён из группы "${chat.name}"`);

      res.json({ success: true, participants: chat.participants });
    } catch (error) {
      console.error('Error removing group member:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== LEAVE GROUP (participant) =====
  app.post('/api/employee-chats/group/:groupId/leave', requireAuth, async (req, res) => {
    try {
      const { groupId } = req.params;
      const { phone } = req.body;
      console.log('POST /api/employee-chats/group/:groupId/leave:', groupId, 'phone:', maskPhone(phone));

      if (!phone) {
        return res.status(400).json({ success: false, error: 'phone is required' });
      }

      const chat = await loadChat(groupId);
      if (!chat || chat.type !== 'group') {
        return res.status(404).json({ success: false, error: 'Группа не найдена' });
      }

      const normalizedPhone = phone.replace(/[^\d]/g, '');

      // Создатель не может выйти - должен удалить группу
      if (normalizedPhone === chat.creatorPhone) {
        return res.status(400).json({ success: false, error: 'Создатель не может выйти из группы. Удалите группу вместо этого.' });
      }

      const idx = chat.participants.indexOf(normalizedPhone);
      if (idx === -1) {
        return res.status(404).json({ success: false, error: 'Вы не являетесь участником этой группы' });
      }

      chat.participants.splice(idx, 1);
      delete chat.participantNames[normalizedPhone];

      await saveChat(chat);
      console.log(`✅ Участник ${maskPhone(phone)} вышел из группы "${chat.name}"`);

      res.json({ success: true });
    } catch (error) {
      console.error('Error leaving group:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== DELETE GROUP (creator only) =====
  app.delete('/api/employee-chats/group/:groupId', requireAuth, async (req, res) => {
    try {
      const { groupId } = req.params;
      const { requesterPhone } = req.query;
      console.log('DELETE /api/employee-chats/group/:groupId:', groupId, 'requester:', requesterPhone);

      if (!requesterPhone) {
        return res.status(400).json({ success: false, error: 'requesterPhone is required' });
      }

      const chat = await loadChat(groupId);
      if (!chat || chat.type !== 'group') {
        return res.status(404).json({ success: false, error: 'Группа не найдена' });
      }

      // Только создатель может удалить группу
      const normalizedRequester = requesterPhone.replace(/[^\d]/g, '');
      if (chat.creatorPhone !== normalizedRequester) {
        console.log('❌ Отказ: удаление группы не создателем');
        return res.status(403).json({ success: false, error: 'Только создатель может удалить группу' });
      }

      await deleteChat(groupId);
      console.log(`✅ Группа "${chat.name}" удалена`);

      res.json({ success: true });
    } catch (error) {
      console.error('Error deleting group:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET GROUP INFO =====
  app.get('/api/employee-chats/group/:groupId', requireAuth, async (req, res) => {
    try {
      const { groupId } = req.params;
      console.log('GET /api/employee-chats/group/:groupId:', groupId);

      const chat = await loadChat(groupId);
      if (!chat || chat.type !== 'group') {
        return res.status(404).json({ success: false, error: 'Группа не найдена' });
      }

      res.json({
        success: true,
        group: {
          id: chat.id,
          name: chat.name,
          imageUrl: chat.imageUrl,
          creatorPhone: chat.creatorPhone,
          creatorName: chat.creatorName,
          participants: chat.participants,
          participantNames: chat.participantNames,
          createdAt: chat.createdAt,
          updatedAt: chat.updatedAt
        }
      });
    } catch (error) {
      console.error('Error getting group info:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Employee Chat API initialized (storage: ${USE_DB ? 'PostgreSQL' : 'JSON files'})`);
}

module.exports = { setupEmployeeChatAPI };
