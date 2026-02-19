/**
 * Clients API
 * Управление клиентами и диалогами
 *
 * Feature flag: USE_DB_CLIENTS=true → PostgreSQL (clients CRUD), false → JSON files
 * Диалоги/сообщения остаются на JSON (Wave 6)
 */

const fsp = require('fs').promises;
const path = require('path');
const { sendPushNotification, sendPushToPhone } = require('./report_notifications_api');
const { isAdminPhone } = require('../utils/admin_cache');
const { createPaginatedResponse, isPaginationRequested } = require('../utils/pagination');
const { fileExists, maskPhone, sanitizePhone } = require('../utils/file_helpers');
const { writeJsonFile, withLock } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const CLIENTS_DIR = path.join(DATA_DIR, 'clients');
const USE_DB = process.env.USE_DB_CLIENTS === 'true';
const USE_DB_MSGS = process.env.USE_DB_CLIENT_MESSAGES === 'true';
const CLIENT_DIALOGS_DIR = path.join(DATA_DIR, 'client-dialogs');
const CLIENT_MESSAGES_DIR = path.join(DATA_DIR, 'client-messages');
const CLIENT_MESSAGES_NETWORK_DIR = path.join(DATA_DIR, 'client-messages-network');
const CLIENT_MESSAGES_MANAGEMENT_DIR = path.join(DATA_DIR, 'client-messages-management');

// ===== Client Messages DB Converters =====

function clientMsgToDb(msg, phone, channel, shopAddress) {
  return {
    id: msg.id,
    client_phone: phone,
    channel: channel,
    shop_address: shopAddress || null,
    text: msg.text || null,
    image_url: msg.imageUrl || null,
    sender_type: msg.senderType || null,
    sender_name: msg.senderName || null,
    sender_phone: msg.senderPhone || null,
    is_read_by_client: msg.isReadByClient === true,
    is_read_by_admin: msg.isReadByAdmin === true,
    is_read_by_manager: msg.isReadByManager === true,
    is_broadcast: msg.isBroadcast === true,
    data: msg.data || null,
    timestamp: msg.timestamp || new Date().toISOString()
  };
}

function dbClientMsgToCamel(row) {
  const msg = {
    id: row.id,
    text: row.text,
    imageUrl: row.image_url,
    timestamp: row.timestamp ? new Date(row.timestamp).toISOString() : null,
    senderType: row.sender_type,
    senderName: row.sender_name,
    senderPhone: row.sender_phone,
    isReadByClient: row.is_read_by_client,
    isReadByAdmin: row.is_read_by_admin,
    isReadByManager: row.is_read_by_manager,
    isBroadcast: row.is_broadcast
  };
  if (row.data) msg.data = row.data;
  return msg;
}

// Initialize directories on module load
(async () => {
  try {
    const dirs = [CLIENTS_DIR, CLIENT_DIALOGS_DIR, CLIENT_MESSAGES_DIR, CLIENT_MESSAGES_NETWORK_DIR, CLIENT_MESSAGES_MANAGEMENT_DIR];
    for (const dir of dirs) {
      await fsp.mkdir(dir, { recursive: true });
    }
  } catch (e) {
    console.error('Failed to create clients directories:', e);
  }
})();

// SECURITY: Проверка что запрос идёт от реального владельца телефона
function verifyClientPhone(req, urlPhone) {
  // Клиент должен передать свой телефон в header X-Client-Phone или в query/body
  const headerPhone = req.headers['x-client-phone'];
  const queryPhone = req.query.clientPhone;
  const bodyPhone = req.body?.clientPhone || req.body?.senderPhone;

  const clientPhone = sanitizePhone(headerPhone || queryPhone || bodyPhone);
  const normalizedUrlPhone = sanitizePhone(urlPhone);

  return clientPhone === normalizedUrlPhone;
}

function setupClientsAPI(app) {
  // ===== CLIENTS =====

  app.get('/api/clients', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/clients');
      let clients;

      if (USE_DB) {
        const rows = await db.findAll('clients', { orderBy: 'updated_at', orderDir: 'DESC' });
        clients = rows.map(dbClientToCamel);
      } else {
        clients = [];

        if (await fileExists(CLIENTS_DIR)) {
          const allFiles = await fsp.readdir(CLIENTS_DIR);
          const files = allFiles.filter(f => f.endsWith('.json'));

          for (const file of files) {
            try {
              const content = await fsp.readFile(path.join(CLIENTS_DIR, file), 'utf8');
              clients.push(JSON.parse(content));
            } catch (e) {
              console.error(`Error reading ${file}:`, e);
            }
          }
        }

        // Сортировка по дате обновления (новые сверху)
        clients.sort((a, b) => {
          const dateA = new Date(a.updatedAt || a.createdAt || 0);
          const dateB = new Date(b.updatedAt || b.createdAt || 0);
          return dateB - dateA;
        });
      }

      // Поддержка поиска по имени/телефону
      const { search } = req.query;
      if (search) {
        const searchLower = search.toLowerCase();
        clients = clients.filter(c =>
          (c.name && c.name.toLowerCase().includes(searchLower)) ||
          (c.phone && c.phone.includes(search))
        );
      }

      // Пагинация если запрошена
      if (isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(clients, req.query, 'clients'));
      } else {
        res.json({ success: true, clients });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/clients', async (req, res) => {
    try {
      const client = req.body;
      const phone = sanitizePhone(client.phone);

      if (!phone) {
        return res.status(400).json({ success: false, error: 'Phone required' });
      }

      let updated;

      if (USE_DB) {
        const now = new Date().toISOString();
        const data = {
          phone,
          name: client.name !== undefined ? client.name : null,
          client_name: client.clientName !== undefined ? client.clientName : null,
          fcm_token: client.fcmToken !== undefined ? client.fcmToken : null,
          referred_by: client.referredBy !== undefined ? client.referredBy : null,
          referred_at: client.referredAt !== undefined ? client.referredAt : null,
          is_admin: false, // SECURITY: isAdmin нельзя устанавливать через API
          employee_name: client.employeeName !== undefined ? client.employeeName : null,
          updated_at: now
        };
        // Upsert — если клиент существует, обновляем только переданные поля
        const existing = await db.findById('clients', phone, 'phone');
        if (existing) {
          const updateData = { updated_at: now };
          if (client.name !== undefined) updateData.name = client.name;
          if (client.clientName !== undefined) updateData.client_name = client.clientName;
          if (client.fcmToken !== undefined) updateData.fcm_token = client.fcmToken;
          if (client.referredBy !== undefined) updateData.referred_by = client.referredBy;
          if (client.referredAt !== undefined) updateData.referred_at = client.referredAt;
          // SECURITY: isAdmin игнорируется — нельзя менять через API
          if (client.employeeName !== undefined) updateData.employee_name = client.employeeName;
          const row = await db.updateById('clients', phone, updateData, 'phone');
          updated = dbClientToCamel(row);
        } else {
          data.created_at = now;
          const row = await db.insert('clients', data);
          updated = dbClientToCamel(row);
        }
      } else {
        const filePath = path.join(CLIENTS_DIR, `${phone}.json`);

        updated = await withLock(filePath, async () => {
          let existing = {};
          if (await fileExists(filePath)) {
            const content = await fsp.readFile(filePath, 'utf8');
            existing = JSON.parse(content);
          }
          const merged = { ...existing, ...client, phone };
          merged.isAdmin = existing.isAdmin || false; // SECURITY: isAdmin нельзя устанавливать через API
          merged.updatedAt = new Date().toISOString();
          await fsp.writeFile(filePath, JSON.stringify(merged, null, 2), 'utf8');
          return merged;
        });
      }

      res.json({ success: true, client: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CLIENT DIALOGS =====

  app.get('/api/client-dialogs/:phone', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const dialogDir = path.join(CLIENT_DIALOGS_DIR, phone);

      if (!(await fileExists(dialogDir))) {
        return res.json({ success: true, dialogs: [] });
      }

      const allFiles = await fsp.readdir(dialogDir);
      const files = allFiles.filter(f => f.endsWith('.json'));
      const dialogs = [];

      for (const f of files) {
        const content = await fsp.readFile(path.join(dialogDir, f), 'utf8');
        dialogs.push(JSON.parse(content));
      }

      res.json({ success: true, dialogs });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/client-dialogs/:phone/shop/:shopAddress', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { shopAddress } = req.params;

      const sanitizedShop = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ]/g, '_');
      const filePath = path.join(CLIENT_MESSAGES_DIR, phone, `${sanitizedShop}.json`);

      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        const dialog = JSON.parse(content);
        res.json({ success: true, dialog });
      } else {
        res.json({ success: true, dialog: { phone, shopAddress, messages: [] } });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/shop/:shopAddress/messages', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { shopAddress } = req.params;
      const message = req.body;

      const clientDir = path.join(CLIENT_MESSAGES_DIR, phone);
      await fsp.mkdir(clientDir, { recursive: true });

      const sanitizedShop = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ]/g, '_');
      const filePath = path.join(clientDir, `${sanitizedShop}.json`);

      await withLock(filePath, async () => {
        let dialog = { phone, shopAddress, messages: [] };
        if (await fileExists(filePath)) {
          const content = await fsp.readFile(filePath, 'utf8');
          dialog = JSON.parse(content);
        }
        message.timestamp = message.timestamp || new Date().toISOString();
        dialog.messages.push(message);
        await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      });

      // DB dual-write
      if (USE_DB_MSGS && message.id) {
        try {
          await db.upsert('client_messages', clientMsgToDb(message, phone, 'dialog', shopAddress));
        } catch (dbErr) {
          console.error('DB dialog message error:', dbErr.message);
        }
      }

      res.json({ success: true, message });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== NETWORK MESSAGES =====

  app.get('/api/client-dialogs/:phone/network', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);

      const requesterPhone = sanitizePhone(req.query.clientPhone || req.headers['x-client-phone']);
      const isAdmin = isAdminPhone(requesterPhone);

      if (!isAdmin && requesterPhone !== phone) {
        console.warn(`SECURITY: Попытка доступа к чужому диалогу network: ${maskPhone(requesterPhone)} -> ${maskPhone(phone)}`);
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      let messages = [];
      if (USE_DB_MSGS) {
        try {
          const result = await db.query(
            'SELECT * FROM client_messages WHERE client_phone = $1 AND channel = $2 ORDER BY timestamp ASC',
            [phone, 'network']
          );
          messages = result.rows.map(dbClientMsgToCamel);
        } catch (dbErr) {
          console.error('DB network GET error:', dbErr.message);
          messages = [];
        }
      } else {
        const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);
        if (await fileExists(filePath)) {
          const content = await fsp.readFile(filePath, 'utf8');
          const dialog = JSON.parse(content);
          messages = dialog.messages || [];
        }
      }

      const unreadCount = messages.filter(m => m.senderType === 'admin' && !m.isReadByClient).length;
      res.json({ success: true, messages, unreadCount });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/network/reply', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { text, imageUrl, clientName, senderPhone } = req.body;

      // SECURITY: Проверка что клиент отправляет сообщение от своего имени
      const normalizedSenderPhone = sanitizePhone(senderPhone);
      if (normalizedSenderPhone && normalizedSenderPhone !== phone) {
        console.warn(`SECURITY: Попытка отправки сообщения от чужого имени: ${maskPhone(normalizedSenderPhone)} -> ${maskPhone(phone)}`);
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      // Создаём полный объект сообщения
      const message = {
        id: `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        text: text || '',
        imageUrl: imageUrl || null,
        timestamp: new Date().toISOString(),
        senderType: 'client',
        senderName: clientName || 'Клиент',
        senderPhone: phone,
        isReadByClient: true,
        isReadByAdmin: false,
        isBroadcast: false
      };

      await withLock(filePath, async () => {
        let dialog = { phone, messages: [] };
        if (await fileExists(filePath)) {
          const content = await fsp.readFile(filePath, 'utf8');
          dialog = JSON.parse(content);
        }
        dialog.messages.push(message);
        await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      });

      // DB dual-write
      if (USE_DB_MSGS) {
        try {
          await db.upsert('client_messages', clientMsgToDb(message, phone, 'network'));
        } catch (dbErr) {
          console.error('DB network reply error:', dbErr.message);
        }
      }

      console.log(`Сообщение от клиента ${maskPhone(phone)} в общий чат сохранено`);
      res.json({ success: true, message });
    } catch (error) {
      console.error('Ошибка сохранения network reply:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/network/read-by-client', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      if (await fileExists(filePath)) {
        await withLock(filePath, async () => {
          const content = await fsp.readFile(filePath, 'utf8');
          const dialog = JSON.parse(content);
          dialog.messages.forEach(m => { if (m.from === 'admin') m.readByClient = true; });
          await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
        });
      }

      // DB: mark as read by client
      if (USE_DB_MSGS) {
        try {
          await db.query(
            `UPDATE client_messages SET is_read_by_client = true
             WHERE client_phone = $1 AND channel = 'network' AND sender_type = 'admin' AND is_read_by_client = false`,
            [phone]
          );
        } catch (dbErr) {
          console.error('DB network read-by-client error:', dbErr.message);
        }
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/network/read-by-admin', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      if (await fileExists(filePath)) {
        await withLock(filePath, async () => {
          const content = await fsp.readFile(filePath, 'utf8');
          const dialog = JSON.parse(content);
          dialog.messages.forEach(m => { if (m.from === 'client') m.readByAdmin = true; });
          await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
        });
      }

      // DB: mark as read by admin
      if (USE_DB_MSGS) {
        try {
          await db.query(
            `UPDATE client_messages SET is_read_by_admin = true
             WHERE client_phone = $1 AND channel = 'network' AND sender_type = 'client' AND is_read_by_admin = false`,
            [phone]
          );
        } catch (dbErr) {
          console.error('DB network read-by-admin error:', dbErr.message);
        }
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== MANAGEMENT MESSAGES =====

  app.get('/api/client-dialogs/:phone/management', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);

      const requesterPhone = sanitizePhone(req.query.clientPhone || req.headers['x-client-phone']);
      const isAdmin = isAdminPhone(requesterPhone);

      if (!isAdmin && requesterPhone !== phone) {
        console.warn(`SECURITY: Попытка доступа к чужому диалогу management: ${maskPhone(requesterPhone)} -> ${maskPhone(phone)}`);
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      let messages = [];
      if (USE_DB_MSGS) {
        try {
          const result = await db.query(
            'SELECT * FROM client_messages WHERE client_phone = $1 AND channel = $2 ORDER BY timestamp ASC',
            [phone, 'management']
          );
          messages = result.rows.map(dbClientMsgToCamel);
        } catch (dbErr) {
          console.error('DB management GET error:', dbErr.message);
          messages = [];
        }
      } else {
        const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);
        if (await fileExists(filePath)) {
          const content = await fsp.readFile(filePath, 'utf8');
          const dialog = JSON.parse(content);
          messages = dialog.messages || [];
        }
      }

      const unreadCount = messages.filter(m => m.senderType === 'manager' && !m.isReadByClient).length;
      res.json({ success: true, messages, unreadCount });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/management/reply', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { text, imageUrl, clientName, senderPhone } = req.body;

      // SECURITY: Проверка что клиент отправляет сообщение от своего имени
      const normalizedSenderPhone = sanitizePhone(senderPhone);
      if (normalizedSenderPhone && normalizedSenderPhone !== phone) {
        console.warn(`SECURITY: Попытка отправки management сообщения от чужого имени: ${maskPhone(normalizedSenderPhone)} -> ${maskPhone(phone)}`);
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      // Создаём полный объект сообщения
      const message = {
        id: `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        text: text || '',
        imageUrl: imageUrl || null,
        timestamp: new Date().toISOString(),
        senderType: 'client',
        senderName: clientName || 'Клиент',
        senderPhone: phone,
        isReadByClient: true,
        isReadByManager: false
      };

      await withLock(filePath, async () => {
        let dialog = { phone, messages: [] };
        if (await fileExists(filePath)) {
          const content = await fsp.readFile(filePath, 'utf8');
          dialog = JSON.parse(content);
        }
        dialog.messages.push(message);
        await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      });

      // DB dual-write
      if (USE_DB_MSGS) {
        try {
          await db.upsert('client_messages', clientMsgToDb(message, phone, 'management'));
        } catch (dbErr) {
          console.error('DB management reply error:', dbErr.message);
        }
      }

      console.log(`Сообщение руководству от клиента ${maskPhone(phone)} сохранено`);

      // Отправить push-уведомление админам
      await sendPushNotification(
        '💼 Связь с руководством',
        `${clientName || 'Клиент'}: ${text.substring(0, 50)}${text.length > 50 ? '...' : ''}`,
        {
          type: 'management_message',
          clientPhone: phone,
          clientName: clientName || 'Клиент',
        }
      );

      res.json({ success: true, message });
    } catch (error) {
      console.error('Ошибка сохранения management reply:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/management/read-by-client', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const msgType = req.query.type; // 'broadcast' | 'personal' | undefined (all)
      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      if (await fileExists(filePath)) {
        await withLock(filePath, async () => {
          const content = await fsp.readFile(filePath, 'utf8');
          const dialog = JSON.parse(content);
          dialog.messages.forEach(m => {
            if (m.senderType === 'manager') {
              if (!msgType) {
                m.isReadByClient = true;
              } else if (msgType === 'broadcast' && m.isBroadcast) {
                m.isReadByClient = true;
              } else if (msgType === 'personal' && !m.isBroadcast) {
                m.isReadByClient = true;
              }
            }
          });
          await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
        });
      }

      // DB: mark as read by client (with type filter)
      if (USE_DB_MSGS) {
        try {
          let sql = `UPDATE client_messages SET is_read_by_client = true
                     WHERE client_phone = $1 AND channel = 'management' AND sender_type = 'manager' AND is_read_by_client = false`;
          const params = [phone];
          if (msgType === 'broadcast') {
            sql += ' AND is_broadcast = true';
          } else if (msgType === 'personal') {
            sql += ' AND is_broadcast = false';
          }
          await db.query(sql, params);
        } catch (dbErr) {
          console.error('DB management read-by-client error:', dbErr.message);
        }
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/management/read-by-manager', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      if (await fileExists(filePath)) {
        await withLock(filePath, async () => {
          const content = await fsp.readFile(filePath, 'utf8');
          const dialog = JSON.parse(content);
          dialog.messages.forEach(m => { if (m.senderType === 'client') m.isReadByManager = true; });
          await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
        });
      }

      // DB: mark as read by manager
      if (USE_DB_MSGS) {
        try {
          await db.query(
            `UPDATE client_messages SET is_read_by_manager = true
             WHERE client_phone = $1 AND channel = 'management' AND sender_type = 'client' AND is_read_by_manager = false`,
            [phone]
          );
        } catch (dbErr) {
          console.error('DB management read-by-manager error:', dbErr.message);
        }
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/management/send', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { text, imageUrl, senderPhone } = req.body;

      // SECURITY: Только админы могут отправлять сообщения от имени руководства
      const normalizedSenderPhone = sanitizePhone(senderPhone);
      if (!isAdminPhone(normalizedSenderPhone)) {
        console.warn(`SECURITY: Неадмин пытается отправить management сообщение: ${normalizedSenderPhone}`);
        return res.status(403).json({ success: false, error: 'Access denied - admin only' });
      }

      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      // Создаём полный объект сообщения от руководства
      const message = {
        id: `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        text: text || '',
        imageUrl: imageUrl || null,
        timestamp: new Date().toISOString(),
        senderType: 'manager',
        senderName: 'Руководство',
        isReadByClient: false,
        isReadByManager: true
      };

      await withLock(filePath, async () => {
        let dialog = { phone, messages: [] };
        if (await fileExists(filePath)) {
          const content = await fsp.readFile(filePath, 'utf8');
          dialog = JSON.parse(content);
        }
        dialog.messages.push(message);
        await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      });

      // DB dual-write
      if (USE_DB_MSGS) {
        try {
          await db.upsert('client_messages', clientMsgToDb(message, phone, 'management'));
        } catch (dbErr) {
          console.error('DB management send error:', dbErr.message);
        }
      }

      console.log(`Сообщение от руководства клиенту ${maskPhone(phone)} сохранено (от админа: ${maskPhone(normalizedSenderPhone)})`);

      // Отправить push-уведомление клиенту
      await sendPushToPhone(
        phone,
        '💼 Ответ от руководства',
        text.substring(0, 50) + (text.length > 50 ? '...' : ''),
        {
          type: 'management_message',
          clientPhone: phone,
        }
      );

      res.json({ success: true, message });
    } catch (error) {
      console.error('Ошибка сохранения management send:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CLIENT MESSAGES (legacy) =====

  app.get('/api/clients/:phone/messages', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const clientDir = path.join(CLIENT_MESSAGES_DIR, phone);

      if (!(await fileExists(clientDir))) {
        return res.json({ success: true, messages: [] });
      }

      const allFiles = await fsp.readdir(clientDir);
      const files = allFiles.filter(f => f.endsWith('.json'));
      let allMessages = [];

      for (const file of files) {
        const content = await fsp.readFile(path.join(clientDir, file), 'utf8');
        const dialog = JSON.parse(content);
        if (dialog.messages) {
          allMessages = allMessages.concat(dialog.messages);
        }
      }

      allMessages.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
      res.json({ success: true, messages: allMessages });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/clients/:phone/messages', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { shopAddress, ...message } = req.body;

      // 1. Сохраняем в legacy-директорию (для admin chat history)
      const clientDir = path.join(CLIENT_MESSAGES_DIR, phone);
      await fsp.mkdir(clientDir, { recursive: true });

      const sanitizedShop = (shopAddress || 'default').replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ]/g, '_');
      const filePath = path.join(clientDir, `${sanitizedShop}.json`);

      message.timestamp = new Date().toISOString();

      // 1. Сохраняем в legacy-директорию с блокировкой
      await withLock(filePath, async () => {
        let dialog = { phone, shopAddress, messages: [] };
        if (await fileExists(filePath)) {
          const content = await fsp.readFile(filePath, 'utf8');
          dialog = JSON.parse(content);
        }
        dialog.messages.push(message);
        await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      });

      // 2. Дублируем в management-директорию (клиент видит в "Связь с руководством")
      const mgmtMessage = {
        id: `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        text: message.text || '',
        imageUrl: message.imageUrl || null,
        timestamp: message.timestamp,
        senderType: 'manager',
        senderName: 'Руководство',
        isReadByClient: false,
        isReadByManager: true
      };

      const mgmtFilePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);
      await withLock(mgmtFilePath, async () => {
        let mgmtDialog = { phone, messages: [] };
        if (await fileExists(mgmtFilePath)) {
          try {
            mgmtDialog = JSON.parse(await fsp.readFile(mgmtFilePath, 'utf8'));
          } catch (e) { /* ignore parse errors */ }
        }
        mgmtDialog.messages.push(mgmtMessage);
        await fsp.writeFile(mgmtFilePath, JSON.stringify(mgmtDialog, null, 2), 'utf8');
      });

      // DB dual-write: both dialog + management
      if (USE_DB_MSGS) {
        try {
          if (message.id) {
            await db.upsert('client_messages', clientMsgToDb(message, phone, 'dialog', shopAddress));
          }
          await db.upsert('client_messages', clientMsgToDb(mgmtMessage, phone, 'management'));
        } catch (dbErr) {
          console.error('DB legacy message error:', dbErr.message);
        }
      }

      // 3. Отправляем push-уведомление клиенту
      try {
        const text = message.text || '';
        await sendPushToPhone(
          phone,
          '💬 Новое сообщение',
          text.substring(0, 50) + (text.length > 50 ? '...' : ''),
          { type: 'management_message', clientPhone: phone }
        );
      } catch (pushErr) {
        console.error('Push notification error:', pushErr.message);
      }

      res.json({ success: true, message });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/clients/messages/broadcast', requireAuth, async (req, res) => {
    try {
      console.log('POST /api/clients/messages/broadcast');

      // Поддержка двух форматов:
      // Формат 1 (legacy): { message: {...}, phones: [...] }
      // Формат 2 (Flutter): { text: "...", imageUrl?: "...", senderPhone?: "..." }
      let messageObj = req.body.message;
      let targetPhones = req.body.phones;

      // Если Flutter-формат (text вместо message)
      if (!messageObj && req.body.text) {
        messageObj = { text: req.body.text };
        if (req.body.imageUrl) messageObj.imageUrl = req.body.imageUrl;
        if (req.body.senderPhone) messageObj.senderPhone = req.body.senderPhone;
      }

      if (!messageObj) {
        return res.status(400).json({ success: false, error: 'Не указан текст сообщения (message или text)' });
      }

      // Если phones не указан — рассылаем всем клиентам
      if (!targetPhones || !Array.isArray(targetPhones) || targetPhones.length === 0) {
        try {
          if (await fileExists(CLIENTS_DIR)) {
            const allFiles = await fsp.readdir(CLIENTS_DIR);
            targetPhones = allFiles
              .filter(f => f.endsWith('.json'))
              .map(f => f.replace('.json', ''));
          } else {
            targetPhones = [];
          }
        } catch {
          targetPhones = [];
        }
      }

      // Параллельная запись (по 20 штук) вместо последовательной
      let sent = 0;
      const BATCH_SIZE = 20;
      const msgText = messageObj.text || '';
      for (let i = 0; i < targetPhones.length; i += BATCH_SIZE) {
        const batch = targetPhones.slice(i, i + BATCH_SIZE);
        const results = await Promise.allSettled(batch.map(async (phone) => {
          const normalizedPhone = sanitizePhone(phone);
          if (!normalizedPhone) return false;
          const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${normalizedPhone}.json`);

          await withLock(filePath, async () => {
            let dialog = { phone: normalizedPhone, messages: [] };
            if (await fileExists(filePath)) {
              const content = await fsp.readFile(filePath, 'utf8');
              dialog = JSON.parse(content);
            }

            dialog.messages.push({
              id: `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
              text: msgText,
              imageUrl: messageObj.imageUrl || null,
              timestamp: new Date().toISOString(),
              senderType: 'manager',
              senderName: 'Руководство',
              isReadByClient: false,
              isReadByManager: true,
              isBroadcast: true
            });

            await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
          });

          // DB dual-write
          if (USE_DB_MSGS) {
            try {
              const broadcastMsgId = `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
              await db.upsert('client_messages', {
                id: broadcastMsgId,
                client_phone: normalizedPhone,
                channel: 'management',
                shop_address: null,
                text: msgText,
                image_url: messageObj.imageUrl || null,
                sender_type: 'manager',
                sender_name: 'Руководство',
                sender_phone: null,
                is_read_by_client: false,
                is_read_by_admin: false,
                is_read_by_manager: true,
                is_broadcast: true,
                data: null,
                timestamp: new Date().toISOString()
              });
            } catch (dbErr) {
              // non-critical
            }
          }

          // Push-уведомление каждому клиенту
          try {
            await sendPushToPhone(
              normalizedPhone,
              '📢 Рассылка',
              msgText.substring(0, 50) + (msgText.length > 50 ? '...' : ''),
              { type: 'management_message', clientPhone: normalizedPhone, isBroadcast: 'true' }
            );
          } catch (pushErr) { /* ignore individual push errors */ }

          return true;
        }));
        sent += results.filter(r => r.status === 'fulfilled' && r.value === true).length;
      }

      console.log(`✅ Broadcast sent to ${sent}/${targetPhones.length} clients`);
      res.json({ success: true, sent, sentCount: sent, totalClients: targetPhones.length });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/management-dialogs - Получить все диалоги "Связь с руководством" для админа
  app.get('/api/management-dialogs', requireAuth, async (req, res) => {
    try {
      console.log('GET /api/management-dialogs');

      // DB read branch: efficient aggregation query
      if (USE_DB_MSGS) {
        try {
          const result = await db.query(`
            SELECT
              client_phone,
              COUNT(*)::int as messages_count,
              COUNT(*) FILTER (WHERE sender_type = 'client' AND is_read_by_manager = false)::int as unread_count,
              MAX(timestamp) as last_timestamp
            FROM client_messages
            WHERE channel = 'management'
            GROUP BY client_phone
            HAVING COUNT(*) > 0
            ORDER BY MAX(timestamp) DESC
          `);

          const dialogs = [];
          for (const row of result.rows) {
            // Get last message and client name
            const lastMsgResult = await db.query(
              `SELECT text, timestamp, sender_type, sender_name FROM client_messages
               WHERE client_phone = $1 AND channel = 'management' ORDER BY timestamp DESC LIMIT 1`,
              [row.client_phone]
            );
            const clientNameResult = await db.query(
              `SELECT sender_name FROM client_messages
               WHERE client_phone = $1 AND channel = 'management' AND sender_name IS NOT NULL AND sender_name != 'Руководство'
               ORDER BY timestamp DESC LIMIT 1`,
              [row.client_phone]
            );

            const lastMsg = lastMsgResult.rows[0];
            dialogs.push({
              phone: row.client_phone,
              clientName: clientNameResult.rows[0]?.sender_name || 'Клиент',
              messagesCount: row.messages_count,
              unreadCount: row.unread_count,
              lastMessage: lastMsg ? {
                text: lastMsg.text,
                timestamp: lastMsg.timestamp ? new Date(lastMsg.timestamp).toISOString() : null,
                senderType: lastMsg.sender_type
              } : null
            });
          }

          const totalUnread = dialogs.reduce((sum, d) => sum + d.unreadCount, 0);
          return res.json({ success: true, dialogs, totalUnread });
        } catch (dbErr) {
          console.error('DB management-dialogs error:', dbErr.message);
          // fallback to file
        }
      }

      const dialogs = [];

      if (!(await fileExists(CLIENT_MESSAGES_MANAGEMENT_DIR))) {
        return res.json({ success: true, dialogs: [], totalUnread: 0 });
      }

      const allFiles = await fsp.readdir(CLIENT_MESSAGES_MANAGEMENT_DIR);
      const files = allFiles.filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, file);
          const content = await fsp.readFile(filePath, 'utf8');
          const dialog = JSON.parse(content);

          if (dialog.messages && dialog.messages.length > 0) {
            const unreadCount = dialog.messages.filter(
              m => m.senderType === 'client' && m.isReadByManager === false
            ).length;

            const lastMessage = dialog.messages[dialog.messages.length - 1];
            const clientName = dialog.messages.find(m => m.senderName && m.senderName !== 'Руководство')?.senderName || 'Клиент';

            dialogs.push({
              phone: dialog.phone,
              clientName: clientName,
              messagesCount: dialog.messages.length,
              unreadCount: unreadCount,
              lastMessage: {
                text: lastMessage.text,
                timestamp: lastMessage.timestamp,
                senderType: lastMessage.senderType
              }
            });
          }
        } catch (e) {
          console.error(`Error reading ${file}:`, e);
        }
      }

      dialogs.sort((a, b) => {
        return new Date(b.lastMessage.timestamp) - new Date(a.lastMessage.timestamp);
      });

      const totalUnread = dialogs.reduce((sum, d) => sum + d.unreadCount, 0);
      res.json({ success: true, dialogs, totalUnread });
    } catch (error) {
      console.error('Error getting management dialogs:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ========== FREE DRINKS COUNTER (Геймификация) ==========

  // POST /api/clients/:phone/free-drink - увеличить счётчик бесплатных напитков
  app.post('/api/clients/:phone/free-drink', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const count = parseInt(req.body.count) || 1;

      if (!phone) {
        return res.status(400).json({ success: false, error: 'Телефон обязателен' });
      }

      const clientFile = path.join(CLIENTS_DIR, `${phone}.json`);

      try {
        await fsp.access(clientFile);
      } catch {
        return res.status(404).json({ success: false, error: 'Клиент не найден' });
      }

      const result = await withLock(clientFile, async () => {
        const client = JSON.parse(await fsp.readFile(clientFile, 'utf8'));
        client.freeDrinksGiven = (client.freeDrinksGiven || 0) + count;
        client.updatedAt = new Date().toISOString();
        await fsp.writeFile(clientFile, JSON.stringify(client, null, 2), 'utf8');
        return { name: client.name, freeDrinksGiven: client.freeDrinksGiven };
      });

      console.log(`🍹 Выдан бесплатный напиток клиенту ${result.name || maskPhone(phone)}. Всего: ${result.freeDrinksGiven}`);
      res.json({ success: true, freeDrinksGiven: result.freeDrinksGiven });
    } catch (error) {
      console.error('Ошибка обновления счётчика напитков:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/clients/:phone/sync-free-drinks - синхронизировать счётчик из внешнего API
  app.post('/api/clients/:phone/sync-free-drinks', requireAuth, async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { freeDrinksGiven } = req.body;

      if (!phone) {
        return res.status(400).json({ success: false, error: 'Телефон обязателен' });
      }

      if (freeDrinksGiven == null || isNaN(freeDrinksGiven)) {
        return res.status(400).json({ success: false, error: 'freeDrinksGiven обязателен' });
      }

      const clientFile = path.join(CLIENTS_DIR, `${phone}.json`);

      try {
        await fsp.access(clientFile);
      } catch {
        return res.status(404).json({ success: false, error: 'Клиент не найден' });
      }

      const result = await withLock(clientFile, async () => {
        const client = JSON.parse(await fsp.readFile(clientFile, 'utf8'));
        const oldValue = client.freeDrinksGiven || 0;
        client.freeDrinksGiven = parseInt(freeDrinksGiven);
        client.updatedAt = new Date().toISOString();
        await fsp.writeFile(clientFile, JSON.stringify(client, null, 2), 'utf8');
        return { oldValue, freeDrinksGiven: client.freeDrinksGiven };
      });

      console.log(`🔄 Синхронизация freeDrinksGiven для ${maskPhone(phone)}: ${result.oldValue} → ${result.freeDrinksGiven}`);
      res.json({ success: true, freeDrinksGiven: result.freeDrinksGiven });
    } catch (error) {
      console.error('Ошибка синхронизации freeDrinksGiven:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Clients API initialized (clients: ${USE_DB ? 'PostgreSQL' : 'JSON'}, messages: ${USE_DB_MSGS ? 'PostgreSQL' : 'JSON'})`);
}

/**
 * Преобразование DB row (snake_case) → camelCase (для совместимости с Flutter)
 */
function dbClientToCamel(row) {
  return {
    phone: row.phone,
    name: row.name,
    clientName: row.client_name,
    fcmToken: row.fcm_token,
    referredBy: row.referred_by,
    referredAt: row.referred_at,
    isAdmin: row.is_admin,
    employeeName: row.employee_name,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

module.exports = { setupClientsAPI };
