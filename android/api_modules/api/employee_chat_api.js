const fs = require('fs');
const path = require('path');

const EMPLOYEE_CHATS_DIR = '/var/www/employee-chats';
const EMPLOYEES_DIR = '/var/www/employees';
const FCM_TOKENS_DIR = '/var/www/fcm-tokens';
const MESSAGE_RETENTION_DAYS = 90;

// Ensure directory exists
if (!fs.existsSync(EMPLOYEE_CHATS_DIR)) {
  fs.mkdirSync(EMPLOYEE_CHATS_DIR, { recursive: true });
}

// Firebase Admin for push notifications
let admin = null;
try {
  admin = require('firebase-admin');
} catch (e) {
  console.warn('Firebase Admin not available for employee chat notifications');
}

// Helper: Load chat file
function loadChat(chatId) {
  const sanitizedId = chatId.replace(/[^a-zA-Z0-9_\-]/g, '_');
  const filePath = path.join(EMPLOYEE_CHATS_DIR, `${sanitizedId}.json`);

  if (fs.existsSync(filePath)) {
    try {
      return JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch (e) {
      console.error(`Error loading chat ${chatId}:`, e);
    }
  }
  return null;
}

// Helper: Save chat file
function saveChat(chat) {
  const sanitizedId = chat.id.replace(/[^a-zA-Z0-9_\-]/g, '_');
  const filePath = path.join(EMPLOYEE_CHATS_DIR, `${sanitizedId}.json`);
  chat.updatedAt = new Date().toISOString();
  fs.writeFileSync(filePath, JSON.stringify(chat, null, 2), 'utf8');
}

// Helper: Clean old messages (older than retention days)
function cleanOldMessages(chat) {
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - MESSAGE_RETENTION_DAYS);

  if (chat.messages && chat.messages.length > 0) {
    const originalLength = chat.messages.length;
    chat.messages = chat.messages.filter(m => new Date(m.timestamp) > cutoffDate);
    if (chat.messages.length !== originalLength) {
      saveChat(chat);
    }
  }
  return chat;
}

// Helper: Get all employees
function getAllEmployees() {
  const employees = [];
  if (fs.existsSync(EMPLOYEES_DIR)) {
    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8');
        employees.push(JSON.parse(content));
      } catch (e) {
        console.error(`Error reading employee file ${file}:`, e);
      }
    }
  }
  return employees;
}

// Helper: Get employee by phone
function getEmployeeByPhone(phone) {
  const employees = getAllEmployees();
  return employees.find(e => e.phone === phone);
}

// Helper: Create private chat ID (sorted phones)
function createPrivateChatId(phone1, phone2) {
  const sorted = [phone1, phone2].sort();
  return `private_${sorted[0]}_${sorted[1]}`;
}

// Helper: Get FCM tokens for phones
function getFcmTokens(phones) {
  const tokens = [];
  for (const phone of phones) {
    const tokenFile = path.join(FCM_TOKENS_DIR, `${phone}.json`);
    if (fs.existsSync(tokenFile)) {
      try {
        const data = JSON.parse(fs.readFileSync(tokenFile, 'utf8'));
        if (data.token) {
          tokens.push({ phone, token: data.token });
        }
      } catch (e) {
        console.error(`Error reading FCM token for ${phone}:`, e);
      }
    }
  }
  return tokens;
}

// Helper: Send push notification
async function sendPushNotification(tokens, title, body, data) {
  if (!admin || !admin.apps.length || tokens.length === 0) return;

  for (const { token } of tokens) {
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
    } catch (e) {
      console.error(`Push notification error:`, e.message);
    }
  }
}

// Helper: Get chat participants for notifications
function getChatParticipants(chat, excludePhone) {
  if (chat.type === 'general') {
    // All employees except sender
    return getAllEmployees()
      .filter(e => e.phone && e.phone !== excludePhone)
      .map(e => e.phone);
  } else if (chat.type === 'shop') {
    // All employees (could filter by shop assignment in future)
    return getAllEmployees()
      .filter(e => e.phone && e.phone !== excludePhone)
      .map(e => e.phone);
  } else if (chat.type === 'private') {
    // Other participant
    return (chat.participants || []).filter(p => p !== excludePhone);
  }
  return [];
}

function setupEmployeeChatAPI(app) {
  // ===== GET ALL CHATS FOR USER =====
  app.get('/api/employee-chats', async (req, res) => {
    try {
      const { phone } = req.query;
      console.log('GET /api/employee-chats for phone:', phone);

      if (!phone) {
        return res.status(400).json({ success: false, error: 'phone is required' });
      }

      const chats = [];

      // 1. General chat (always exists)
      let generalChat = loadChat('general');
      if (!generalChat) {
        generalChat = {
          id: 'general',
          type: 'general',
          name: 'Общий чат',
          messages: [],
          participants: [],
          createdAt: new Date().toISOString()
        };
        saveChat(generalChat);
      }
      generalChat = cleanOldMessages(generalChat);

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
      if (fs.existsSync(EMPLOYEE_CHATS_DIR)) {
        const files = fs.readdirSync(EMPLOYEE_CHATS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          if (file === 'general.json') continue;

          try {
            let chat = JSON.parse(fs.readFileSync(path.join(EMPLOYEE_CHATS_DIR, file), 'utf8'));
            chat = cleanOldMessages(chat);

            // For private chats, only show if user is participant
            if (chat.type === 'private') {
              if (!(chat.participants || []).includes(phone)) continue;

              // Get other participant's name
              const otherPhone = chat.participants.find(p => p !== phone);
              const otherEmployee = getEmployeeByPhone(otherPhone);
              chat.name = otherEmployee?.name || otherPhone;
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
              unreadCount: unread,
              lastMessage: chat.messages?.length > 0
                ? chat.messages[chat.messages.length - 1]
                : null
            });
          } catch (e) {
            console.error(`Error processing chat file ${file}:`, e);
          }
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

      let chat = loadChat(chatId);
      if (!chat) {
        return res.json({ success: true, messages: [] });
      }

      chat = cleanOldMessages(chat);
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

      let chat = loadChat(chatId);
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
      saveChat(chat);

      // Send push notifications
      const recipients = getChatParticipants(chat, senderPhone);
      const tokens = getFcmTokens(recipients);

      if (tokens.length > 0) {
        const title = chat.type === 'private' ? senderName : chat.name;
        const body = imageUrl ? `${senderName}: [Фото]` : `${senderName}: ${text.substring(0, 100)}`;

        sendPushNotification(tokens, title, body, {
          type: 'employee_chat',
          chatId: chatId,
          messageId: message.id
        });
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

      const chat = loadChat(chatId);
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
        saveChat(chat);
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
      let chat = loadChat(chatId);

      if (!chat) {
        const employee1 = getEmployeeByPhone(phone1);
        const employee2 = getEmployeeByPhone(phone2);

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
        saveChat(chat);
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
      let chat = loadChat(chatId);

      if (!chat) {
        chat = {
          id: chatId,
          type: 'shop',
          name: shopAddress,
          shopAddress: shopAddress,
          messages: [],
          createdAt: new Date().toISOString()
        };
        saveChat(chat);
      }

      res.json({ success: true, chat });
    } catch (error) {
      console.error('Error creating shop chat:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== DELETE MESSAGE (admin only) =====
  app.delete('/api/employee-chats/:chatId/messages/:messageId', async (req, res) => {
    try {
      const { chatId, messageId } = req.params;
      console.log('DELETE /api/employee-chats/:chatId/messages/:messageId:', chatId, messageId);

      const chat = loadChat(chatId);
      if (!chat) {
        return res.status(404).json({ success: false, error: 'Chat not found' });
      }

      const idx = (chat.messages || []).findIndex(m => m.id === messageId);
      if (idx === -1) {
        return res.status(404).json({ success: false, error: 'Message not found' });
      }

      chat.messages.splice(idx, 1);
      saveChat(chat);

      res.json({ success: true });
    } catch (error) {
      console.error('Error deleting message:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('Employee Chat API initialized');
}

module.exports = { setupEmployeeChatAPI };
