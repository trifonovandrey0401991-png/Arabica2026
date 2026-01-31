const fs = require('fs');
const fsPromises = fs.promises;
const path = require('path');
const { isAdminPhoneAsync } = require('../utils/admin_cache');

// WebSocket уведомления (опционально, если модуль загружен)
let wsNotify = null;
try {
  wsNotify = require('./employee_chat_websocket');
} catch (e) {
  console.log('⚠️ WebSocket модуль не загружен, real-time уведомления отключены');
}

const EMPLOYEE_CHATS_DIR = '/var/www/employee-chats';
const EMPLOYEES_DIR = '/var/www/employees';
const CLIENTS_DIR = '/var/www/clients';
const FCM_TOKENS_DIR = '/var/www/fcm-tokens';
const MESSAGE_RETENTION_DAYS = 90;
const MAX_GROUP_PARTICIPANTS = 100;

// Ensure directory exists
if (!fs.existsSync(EMPLOYEE_CHATS_DIR)) {
  fs.mkdirSync(EMPLOYEE_CHATS_DIR, { recursive: true });
}

// Firebase Admin for push notifications - use shared config
let admin = null;
let firebaseInitialized = false;
try {
  const firebaseConfig = require('../firebase-admin-config.js');
  admin = firebaseConfig.admin;
  firebaseInitialized = firebaseConfig.firebaseInitialized;
  if (firebaseInitialized) {
    console.log('✅ Employee Chat API: Firebase Admin подключен');
  }
} catch (e) {
  console.warn('⚠️ Firebase Admin not available for employee chat notifications:', e.message);
}

// Helper: Load chat file (async)
async function loadChat(chatId) {
  const sanitizedId = chatId.replace(/[^a-zA-Z0-9_\-]/g, '_');
  const filePath = path.join(EMPLOYEE_CHATS_DIR, `${sanitizedId}.json`);

  try {
    await fsPromises.access(filePath);
    const content = await fsPromises.readFile(filePath, 'utf8');
    try {
      return JSON.parse(content);
    } catch (parseError) {
      console.error(`JSON parse error for chat ${chatId}:`, parseError.message);
      // Попробуем восстановить - вернём пустой чат
      return null;
    }
  } catch (e) {
    // Файл не существует - это нормально
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
    await fsPromises.writeFile(filePath, JSON.stringify(chat, null, 2), 'utf8');
  } catch (e) {
    console.error(`Error saving chat ${chat.id}:`, e.message);
    throw e;
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
    }
  }
  return chat;
}

// Helper: Get all employees (async)
async function getAllEmployees() {
  const employees = [];
  try {
    await fsPromises.access(EMPLOYEES_DIR);
    const files = await fsPromises.readdir(EMPLOYEES_DIR);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    for (const file of jsonFiles) {
      try {
        const content = await fsPromises.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
        try {
          employees.push(JSON.parse(content));
        } catch (parseError) {
          console.error(`JSON parse error for employee file ${file}:`, parseError.message);
        }
      } catch (readError) {
        console.error(`Error reading employee file ${file}:`, readError.message);
      }
    }
  } catch (e) {
    if (e.code !== 'ENOENT') {
      console.error('Error reading employees directory:', e.message);
    }
  }
  return employees;
}

// Helper: Get employee by phone (async)
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

// Helper: Get FCM tokens for phones (async)
async function getFcmTokens(phones) {
  const tokens = [];
  for (const phone of phones) {
    const tokenFile = path.join(FCM_TOKENS_DIR, `${phone}.json`);
    try {
      await fsPromises.access(tokenFile);
      const content = await fsPromises.readFile(tokenFile, 'utf8');
      try {
        const data = JSON.parse(content);
        if (data.token) {
          tokens.push({ phone, token: data.token });
        }
      } catch (parseError) {
        console.error(`JSON parse error for FCM token ${phone}:`, parseError.message);
      }
    } catch (e) {
      // Файл не существует - это нормально, у пользователя может не быть токена
      if (e.code !== 'ENOENT') {
        console.error(`Error reading FCM token for ${phone}:`, e.message);
      }
    }
  }
  return tokens;
}

// Helper: Send push notification
async function sendPushNotification(tokens, title, body, data) {
  if (!firebaseInitialized || !admin || tokens.length === 0) {
    console.log(`📵 Push не отправлен: firebase=${firebaseInitialized}, tokens=${tokens.length}`);
    return;
  }

  console.log(`📤 Отправка push: "${title}" -> ${tokens.length} получателей`);

  for (const { phone, token } of tokens) {
    try {
      await admin.messaging().send({
        token,
        notification: { title, body },
        data: data || {},
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'employee_chat_channel'
          }
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1
            }
          }
        }
      });
      console.log(`✅ Push отправлен: ${phone}`);
    } catch (e) {
      console.error(`❌ Push ошибка для ${phone}:`, e.message);
    }
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
    return true;
  } catch (e) {
    if (e.code !== 'ENOENT') {
      console.error(`Error deleting chat ${chatId}:`, e.message);
    }
    return false;
  }
}

// Helper: Get participant name (employee or client) (async)
async function getParticipantName(phone) {
  const normalizedPhone = phone.replace(/[\s+]/g, '');

  // Сначала ищем в сотрудниках
  const employees = await getAllEmployees();
  const employee = employees.find(e => {
    const empPhone = (e.phone || '').replace(/[\s+]/g, '');
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
  app.get('/api/employee-chats', async (req, res) => {
    try {
      const { phone } = req.query;
      // SECURITY FIX: Проверяем isAdmin по базе данных сотрудников, а не по query параметру
      // Это предотвращает подделку прав доступа клиентом
      const isAdminUser = await isAdminPhoneAsync(phone);
      console.log('GET /api/employee-chats for phone:', phone, 'isAdmin:', isAdminUser, '(verified from DB)');

      if (!phone) {
        return res.status(400).json({ success: false, error: 'phone is required' });
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
        const files = allFiles.filter(f => f.endsWith('.json'));

        for (const file of files) {
          if (file === 'general.json') continue;

          try {
            const content = await fsPromises.readFile(path.join(EMPLOYEE_CHATS_DIR, file), 'utf8');
            let chat;
            try {
              chat = JSON.parse(content);
            } catch (parseError) {
              console.error(`JSON parse error for chat file ${file}:`, parseError.message);
              continue;
            }
            chat = await cleanOldMessages(chat);

            // For private chats, only show if user is participant
            if (chat.type === 'private') {
              if (!(chat.participants || []).includes(phone)) continue;

              // Get other participant's name
              const otherPhone = chat.participants.find(p => p !== phone);
              const otherEmployee = await getEmployeeByPhone(otherPhone);
              chat.name = otherEmployee?.name || otherPhone;
            }

            // For shop chats, only show if user is a member (or if admin - show all)
            if (chat.type === 'shop') {
              if (!isAdminUser && (!chat.shopMembers || !chat.shopMembers.includes(phone))) continue;
            }

            // For group chats, only show if user is a participant (or if admin - show all)
            if (chat.type === 'group') {
              const normalizedPhone = phone.replace(/[\s+]/g, '');
              const normalizedParticipants = (chat.participants || []).map(p => p.replace(/[\s+]/g, ''));
              if (!isAdminUser && !normalizedParticipants.includes(normalizedPhone)) continue;
            }

            const unread = (chat.messages || []).filter(m =>
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
              lastMessage: chat.messages?.length > 0
                ? chat.messages[chat.messages.length - 1]
                : null
            });
          } catch (e) {
            console.error(`Error processing chat file ${file}:`, e.message);
          }
        }
      } catch (e) {
        // Directory doesn't exist - это нормально при первом запуске
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
  app.get('/api/employee-chats/:chatId/messages', async (req, res) => {
    try {
      const { chatId } = req.params;
      const { phone, limit = 50, before } = req.query;
      console.log('GET /api/employee-chats/:chatId/messages:', chatId);

      let chat = await loadChat(chatId);
      if (!chat) {
        return res.json({ success: true, messages: [] });
      }

      chat = await cleanOldMessages(chat);
      let messages = chat.messages || [];

      // Pagination
      if (before) {
        const idx = messages.findIndex(m => m.id === before);
        if (idx > 0) {
          messages = messages.slice(0, idx);
        }
      }

      // Limit
      messages = messages.slice(-parseInt(limit));

      res.json({ success: true, messages });
    } catch (error) {
      console.error('Error getting messages:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SEND MESSAGE =====
  app.post('/api/employee-chats/:chatId/messages', async (req, res) => {
    try {
      const { chatId } = req.params;
      const { senderPhone, senderName, text, imageUrl } = req.body;
      console.log('POST /api/employee-chats/:chatId/messages:', chatId, senderName, 'text:', text, 'body:', JSON.stringify(req.body));

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
        });
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
  app.post('/api/employee-chats/:chatId/read', async (req, res) => {
    try {
      const { chatId } = req.params;
      const { phone } = req.body;
      console.log('POST /api/employee-chats/:chatId/read:', chatId, phone);

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
      }

      res.json({ success: true });
    } catch (error) {
      console.error('Error marking as read:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CREATE/GET PRIVATE CHAT =====
  app.post('/api/employee-chats/private', async (req, res) => {
    try {
      const { phone1, phone2 } = req.body;
      console.log('POST /api/employee-chats/private:', phone1, phone2);

      if (!phone1 || !phone2) {
        return res.status(400).json({ success: false, error: 'phone1 and phone2 are required' });
      }

      const chatId = createPrivateChatId(phone1, phone2);
      let chat = await loadChat(chatId);

      if (!chat) {
        const employee1 = await getEmployeeByPhone(phone1);
        const employee2 = await getEmployeeByPhone(phone2);

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
  app.post('/api/employee-chats/shop', async (req, res) => {
    try {
      const { shopAddress } = req.body;
      console.log('POST /api/employee-chats/shop:', shopAddress);

      if (!shopAddress) {
        return res.status(400).json({ success: false, error: 'shopAddress is required' });
      }

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const chatId = `shop_${sanitizedAddress}`;
      let chat = await loadChat(chatId);

      if (!chat) {
        chat = {
          id: chatId,
          type: 'shop',
          name: shopAddress,
          shopAddress: shopAddress,
          shopMembers: [], // Участники чата магазина
          messages: [],
          createdAt: new Date().toISOString()
        };
        await saveChat(chat);
      }

      res.json({ success: true, chat });
    } catch (error) {
      console.error('Error creating shop chat:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET SHOP CHAT MEMBERS =====
  app.get('/api/employee-chats/shop/:shopAddress/members', async (req, res) => {
    try {
      const { shopAddress } = req.params;
      console.log('GET /api/employee-chats/shop/:shopAddress/members:', shopAddress);

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const chatId = `shop_${sanitizedAddress}`;
      const chat = await loadChat(chatId);

      if (!chat) {
        return res.status(404).json({ success: false, error: 'Shop chat not found' });
      }

      // Получаем информацию о каждом участнике
      const members = [];
      for (const phone of (chat.shopMembers || [])) {
        const employee = await getEmployeeByPhone(phone);
        members.push({
          phone,
          name: employee?.name || phone,
          position: employee?.position || ''
        });
      }

      res.json({ success: true, members, shopAddress: chat.shopAddress });
    } catch (error) {
      console.error('Error getting shop chat members:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ADD MEMBERS TO SHOP CHAT =====
  app.post('/api/employee-chats/shop/:shopAddress/members', async (req, res) => {
    try {
      const { shopAddress } = req.params;
      const { phones } = req.body;
      console.log('POST /api/employee-chats/shop/:shopAddress/members:', shopAddress, phones);

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
  app.delete('/api/employee-chats/shop/:shopAddress/members/:phone', async (req, res) => {
    try {
      const { shopAddress, phone } = req.params;
      const { requesterPhone } = req.query;
      console.log('DELETE /api/employee-chats/shop/:shopAddress/members/:phone:', shopAddress, phone, 'requester:', requesterPhone);

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
  app.post('/api/employee-chats/:chatId/clear', async (req, res) => {
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
  app.delete('/api/employee-chats/:chatId/messages/:messageId', async (req, res) => {
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
  app.get('/api/employee-chats/:chatId/messages/search', async (req, res) => {
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
  app.post('/api/employee-chats/:chatId/messages/:messageId/reactions', async (req, res) => {
    try {
      const { chatId, messageId } = req.params;
      const { phone, reaction } = req.body; // reaction: emoji string like "👍", "❤️", etc.
      console.log('POST /api/employee-chats/:chatId/messages/:messageId/reactions:', chatId, messageId, phone, reaction);

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
  app.delete('/api/employee-chats/:chatId/messages/:messageId/reactions', async (req, res) => {
    try {
      const { chatId, messageId } = req.params;
      const { phone, reaction } = req.query;
      console.log('DELETE /api/employee-chats/:chatId/messages/:messageId/reactions:', chatId, messageId, phone, reaction);

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
  app.post('/api/employee-chats/:targetChatId/messages/forward', async (req, res) => {
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
  app.get('/api/clients/list', async (req, res) => {
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
  app.post('/api/employee-chats/group', async (req, res) => {
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
      const normalizedCreatorPhone = creatorPhone.replace(/[\s+]/g, '');

      // Собрать имена участников
      const participantNames = {};
      participantNames[normalizedCreatorPhone] = creatorName || await getParticipantName(creatorPhone);

      // Нормализуем телефоны участников и получаем их имена
      const normalizedParticipants = [normalizedCreatorPhone];
      for (const phone of participants) {
        const normalizedPhone = phone.replace(/[\s+]/g, '');
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
  app.put('/api/employee-chats/group/:groupId', async (req, res) => {
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
      const normalizedRequester = requesterPhone.replace(/[\s+]/g, '');
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
  app.post('/api/employee-chats/group/:groupId/members', async (req, res) => {
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
      const normalizedRequester = requesterPhone.replace(/[\s+]/g, '');
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
        const normalizedPhone = phone.replace(/[\s+]/g, '');
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
  app.delete('/api/employee-chats/group/:groupId/members/:phone', async (req, res) => {
    try {
      const { groupId, phone } = req.params;
      const { requesterPhone } = req.query;
      console.log('DELETE /api/employee-chats/group/:groupId/members/:phone:', groupId, phone, 'requester:', requesterPhone);

      if (!requesterPhone) {
        return res.status(400).json({ success: false, error: 'requesterPhone is required' });
      }

      const chat = await loadChat(groupId);
      if (!chat || chat.type !== 'group') {
        return res.status(404).json({ success: false, error: 'Группа не найдена' });
      }

      // Только создатель может удалять участников
      const normalizedRequester = requesterPhone.replace(/[\s+]/g, '');
      if (chat.creatorPhone !== normalizedRequester) {
        console.log('❌ Отказ: удаление участника не создателем');
        return res.status(403).json({ success: false, error: 'Только создатель может удалять участников' });
      }

      const normalizedPhone = phone.replace(/[\s+]/g, '');

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
      console.log(`✅ Участник ${phone} удалён из группы "${chat.name}"`);

      res.json({ success: true, participants: chat.participants });
    } catch (error) {
      console.error('Error removing group member:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== LEAVE GROUP (participant) =====
  app.post('/api/employee-chats/group/:groupId/leave', async (req, res) => {
    try {
      const { groupId } = req.params;
      const { phone } = req.body;
      console.log('POST /api/employee-chats/group/:groupId/leave:', groupId, 'phone:', phone);

      if (!phone) {
        return res.status(400).json({ success: false, error: 'phone is required' });
      }

      const chat = await loadChat(groupId);
      if (!chat || chat.type !== 'group') {
        return res.status(404).json({ success: false, error: 'Группа не найдена' });
      }

      const normalizedPhone = phone.replace(/[\s+]/g, '');

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
      console.log(`✅ Участник ${phone} вышел из группы "${chat.name}"`);

      res.json({ success: true });
    } catch (error) {
      console.error('Error leaving group:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== DELETE GROUP (creator only) =====
  app.delete('/api/employee-chats/group/:groupId', async (req, res) => {
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
      const normalizedRequester = requesterPhone.replace(/[\s+]/g, '');
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
  app.get('/api/employee-chats/group/:groupId', async (req, res) => {
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

  console.log('Employee Chat API initialized');
}

module.exports = { setupEmployeeChatAPI };
