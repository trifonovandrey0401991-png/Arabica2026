/**
 * Clients API
 * Управление клиентами и диалогами
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { sendPushNotification, sendPushToPhone } = require('./report_notifications_api');
const { isAdminPhone } = require('../utils/admin_cache');
const { createPaginatedResponse, isPaginationRequested } = require('../utils/pagination');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const CLIENTS_DIR = path.join(DATA_DIR, 'clients');
const CLIENT_DIALOGS_DIR = path.join(DATA_DIR, 'client-dialogs');
const CLIENT_MESSAGES_DIR = path.join(DATA_DIR, 'client-messages');
const CLIENT_MESSAGES_NETWORK_DIR = path.join(DATA_DIR, 'client-messages-network');
const CLIENT_MESSAGES_MANAGEMENT_DIR = path.join(DATA_DIR, 'client-messages-management');

/**
 * Sanitize phone — нормализация + защита от path traversal
 */
function sanitizePhone(phone) {
  if (!phone) return '';
  // Убираем пробелы и +, затем оставляем только цифры
  return phone.replace(/[^\d]/g, '');
}

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
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

  app.get('/api/clients', async (req, res) => {
    try {
      console.log('GET /api/clients');
      let clients = [];

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

      // SCALABILITY: Поддержка поиска по имени/телефону
      const { search } = req.query;
      if (search) {
        const searchLower = search.toLowerCase();
        clients = clients.filter(c =>
          (c.name && c.name.toLowerCase().includes(searchLower)) ||
          (c.phone && c.phone.includes(search))
        );
      }

      // SCALABILITY: Сортировка по дате обновления (новые сверху)
      clients.sort((a, b) => {
        const dateA = new Date(a.updatedAt || a.createdAt || 0);
        const dateB = new Date(b.updatedAt || b.createdAt || 0);
        return dateB - dateA;
      });

      // SCALABILITY: Пагинация если запрошена
      if (isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(clients, req.query, 'clients'));
      } else {
        // Backwards compatibility - возвращаем все без пагинации
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

      const filePath = path.join(CLIENTS_DIR, `${phone}.json`);

      let existing = {};
      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        existing = JSON.parse(content);
      }

      const updated = { ...existing, ...client, phone };
      updated.updatedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, client: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CLIENT DIALOGS =====

  app.get('/api/client-dialogs/:phone', async (req, res) => {
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

  app.get('/api/client-dialogs/:phone/shop/:shopAddress', async (req, res) => {
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

  app.post('/api/client-dialogs/:phone/shop/:shopAddress/messages', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { shopAddress } = req.params;
      const message = req.body;

      const clientDir = path.join(CLIENT_MESSAGES_DIR, phone);
      await fsp.mkdir(clientDir, { recursive: true });

      const sanitizedShop = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ]/g, '_');
      const filePath = path.join(clientDir, `${sanitizedShop}.json`);

      let dialog = { phone, shopAddress, messages: [] };
      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        dialog = JSON.parse(content);
      }

      message.timestamp = message.timestamp || new Date().toISOString();
      dialog.messages.push(message);

      await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      res.json({ success: true, message });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== NETWORK MESSAGES =====

  app.get('/api/client-dialogs/:phone/network', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);

      // SECURITY: Проверка авторизации - клиент может читать только свои диалоги
      // Админ может читать любые диалоги
      const requesterPhone = sanitizePhone(req.query.clientPhone || req.headers['x-client-phone']);
      const isAdmin = isAdminPhone(requesterPhone);

      if (!isAdmin && requesterPhone !== phone) {
        console.warn(`SECURITY: Попытка доступа к чужому диалогу network: ${requesterPhone} -> ${phone}`);
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      let messages = [];
      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        const dialog = JSON.parse(content);
        messages = dialog.messages || [];
      }

      // Считаем непрочитанные сообщения от админа (для клиента)
      const unreadCount = messages.filter(m => m.senderType === 'admin' && !m.isReadByClient).length;

      res.json({ success: true, messages, unreadCount });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/network/reply', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { text, imageUrl, clientName, senderPhone } = req.body;

      // SECURITY: Проверка что клиент отправляет сообщение от своего имени
      const normalizedSenderPhone = sanitizePhone(senderPhone);
      if (normalizedSenderPhone && normalizedSenderPhone !== phone) {
        console.warn(`SECURITY: Попытка отправки сообщения от чужого имени: ${normalizedSenderPhone} -> ${phone}`);
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      let dialog = { phone, messages: [] };
      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        dialog = JSON.parse(content);
      }

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

      dialog.messages.push(message);

      await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      console.log(`Сообщение от клиента ${phone} в общий чат сохранено`);
      res.json({ success: true, message });
    } catch (error) {
      console.error('Ошибка сохранения network reply:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/network/read-by-client', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        const dialog = JSON.parse(content);
        dialog.messages.forEach(m => { if (m.from === 'admin') m.readByClient = true; });
        await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/network/read-by-admin', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        const dialog = JSON.parse(content);
        dialog.messages.forEach(m => { if (m.from === 'client') m.readByAdmin = true; });
        await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== MANAGEMENT MESSAGES =====

  app.get('/api/client-dialogs/:phone/management', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);

      // SECURITY: Проверка авторизации - клиент может читать только свои диалоги
      // Админ может читать любые диалоги
      const requesterPhone = sanitizePhone(req.query.clientPhone || req.headers['x-client-phone']);
      const isAdmin = isAdminPhone(requesterPhone);

      if (!isAdmin && requesterPhone !== phone) {
        console.warn(`SECURITY: Попытка доступа к чужому диалогу management: ${requesterPhone} -> ${phone}`);
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      let messages = [];
      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        const dialog = JSON.parse(content);
        messages = dialog.messages || [];
      }

      // Считаем непрочитанные сообщения от руководства (для клиента)
      const unreadCount = messages.filter(m => m.senderType === 'manager' && !m.isReadByClient).length;

      res.json({ success: true, messages, unreadCount });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/management/reply', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { text, imageUrl, clientName, senderPhone } = req.body;

      // SECURITY: Проверка что клиент отправляет сообщение от своего имени
      const normalizedSenderPhone = sanitizePhone(senderPhone);
      if (normalizedSenderPhone && normalizedSenderPhone !== phone) {
        console.warn(`SECURITY: Попытка отправки management сообщения от чужого имени: ${normalizedSenderPhone} -> ${phone}`);
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      let dialog = { phone, messages: [] };
      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        dialog = JSON.parse(content);
      }

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

      dialog.messages.push(message);

      await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      console.log(`Сообщение руководству от клиента ${phone} сохранено`);

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

  app.post('/api/client-dialogs/:phone/management/read-by-client', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        const dialog = JSON.parse(content);
        dialog.messages.forEach(m => { if (m.senderType === 'manager') m.isReadByClient = true; });
        await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/management/read-by-manager', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        const dialog = JSON.parse(content);
        dialog.messages.forEach(m => { if (m.senderType === 'client') m.isReadByManager = true; });
        await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/management/send', async (req, res) => {
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

      let dialog = { phone, messages: [] };
      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        dialog = JSON.parse(content);
      }

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

      dialog.messages.push(message);

      await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      console.log(`Сообщение от руководства клиенту ${phone} сохранено (от админа: ${normalizedSenderPhone})`);

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

  app.get('/api/clients/:phone/messages', async (req, res) => {
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

  app.post('/api/clients/:phone/messages', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      const { shopAddress, ...message } = req.body;

      const clientDir = path.join(CLIENT_MESSAGES_DIR, phone);
      await fsp.mkdir(clientDir, { recursive: true });

      const sanitizedShop = (shopAddress || 'default').replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ]/g, '_');
      const filePath = path.join(clientDir, `${sanitizedShop}.json`);

      let dialog = { phone, shopAddress, messages: [] };
      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        dialog = JSON.parse(content);
      }

      message.timestamp = new Date().toISOString();
      dialog.messages.push(message);

      await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      res.json({ success: true, message });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/clients/messages/broadcast', async (req, res) => {
    try {
      const { message, phones } = req.body;
      console.log('POST /api/clients/messages/broadcast');

      let sent = 0;
      for (const phone of phones) {
        const normalizedPhone = sanitizePhone(phone);
        const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${normalizedPhone}.json`);

        let dialog = { phone: normalizedPhone, messages: [] };
        if (await fileExists(filePath)) {
          const content = await fsp.readFile(filePath, 'utf8');
          dialog = JSON.parse(content);
        }

        dialog.messages.push({
          ...message,
          timestamp: new Date().toISOString(),
          from: 'manager',
          isBroadcast: true
        });

        await fsp.writeFile(filePath, JSON.stringify(dialog, null, 2), 'utf8');
        sent++;
      }

      res.json({ success: true, sent });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/management-dialogs - Получить все диалоги "Связь с руководством" для админа
  app.get('/api/management-dialogs', async (req, res) => {
    try {
      console.log('GET /api/management-dialogs');
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
            // Подсчитываем непрочитанные сообщения от клиентов
            const unreadCount = dialog.messages.filter(
              m => m.senderType === 'client' && m.isReadByManager === false
            ).length;

            // Находим последнее сообщение
            const lastMessage = dialog.messages[dialog.messages.length - 1];

            // Получаем имя клиента из последнего сообщения
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

      // Сортируем по последнему сообщению (новые первыми)
      dialogs.sort((a, b) => {
        return new Date(b.lastMessage.timestamp) - new Date(a.lastMessage.timestamp);
      });

      // Подсчитываем общее количество непрочитанных
      const totalUnread = dialogs.reduce((sum, d) => sum + d.unreadCount, 0);

      res.json({ success: true, dialogs, totalUnread });
    } catch (error) {
      console.error('Error getting management dialogs:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Clients API initialized');
}

module.exports = { setupClientsAPI };
