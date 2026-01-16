const fs = require('fs');
const path = require('path');
const { sendPushNotification, sendPushToPhone } = require('../report_notifications_api');

const CLIENTS_DIR = '/var/www/clients';
const CLIENT_DIALOGS_DIR = '/var/www/client-dialogs';
const CLIENT_MESSAGES_DIR = '/var/www/client-messages';
const CLIENT_MESSAGES_NETWORK_DIR = '/var/www/client-messages-network';
const CLIENT_MESSAGES_MANAGEMENT_DIR = '/var/www/client-messages-management';

[CLIENTS_DIR, CLIENT_DIALOGS_DIR, CLIENT_MESSAGES_DIR, CLIENT_MESSAGES_NETWORK_DIR, CLIENT_MESSAGES_MANAGEMENT_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

function setupClientsAPI(app) {
  // ===== CLIENTS =====

  app.get('/api/clients', async (req, res) => {
    try {
      console.log('GET /api/clients');
      const clients = [];

      if (fs.existsSync(CLIENTS_DIR)) {
        const files = fs.readdirSync(CLIENTS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(CLIENTS_DIR, file), 'utf8');
            clients.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      res.json({ success: true, clients });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/clients', async (req, res) => {
    try {
      const client = req.body;
      const phone = (client.phone || '').replace(/[\s+]/g, '');

      if (!phone) {
        return res.status(400).json({ success: false, error: 'Phone required' });
      }

      const filePath = path.join(CLIENTS_DIR, `${phone}.json`);

      let existing = {};
      if (fs.existsSync(filePath)) {
        existing = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      }

      const updated = { ...existing, ...client, phone };
      updated.updatedAt = new Date().toISOString();

      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, client: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CLIENT DIALOGS =====

  app.get('/api/client-dialogs/:phone', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const dialogDir = path.join(CLIENT_DIALOGS_DIR, phone);

      if (!fs.existsSync(dialogDir)) {
        return res.json({ success: true, dialogs: [] });
      }

      const files = fs.readdirSync(dialogDir).filter(f => f.endsWith('.json'));
      const dialogs = files.map(f => JSON.parse(fs.readFileSync(path.join(dialogDir, f), 'utf8')));

      res.json({ success: true, dialogs });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/client-dialogs/:phone/shop/:shopAddress', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const { shopAddress } = req.params;

      const sanitizedShop = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ]/g, '_');
      const filePath = path.join(CLIENT_MESSAGES_DIR, phone, `${sanitizedShop}.json`);

      if (fs.existsSync(filePath)) {
        const dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
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
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const { shopAddress } = req.params;
      const message = req.body;

      const clientDir = path.join(CLIENT_MESSAGES_DIR, phone);
      if (!fs.existsSync(clientDir)) {
        fs.mkdirSync(clientDir, { recursive: true });
      }

      const sanitizedShop = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ]/g, '_');
      const filePath = path.join(clientDir, `${sanitizedShop}.json`);

      let dialog = { phone, shopAddress, messages: [] };
      if (fs.existsSync(filePath)) {
        dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      }

      message.timestamp = message.timestamp || new Date().toISOString();
      dialog.messages.push(message);

      fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      res.json({ success: true, message });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== NETWORK MESSAGES =====

  app.get('/api/client-dialogs/:phone/network', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      let messages = [];
      if (fs.existsSync(filePath)) {
        const dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
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
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const { text, imageUrl, clientName } = req.body;
      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      let dialog = { phone, messages: [] };
      if (fs.existsSync(filePath)) {
        dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
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

      fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      console.log(`Сообщение от клиента ${phone} в общий чат сохранено`);
      res.json({ success: true, message });
    } catch (error) {
      console.error('Ошибка сохранения network reply:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/network/read-by-client', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      if (fs.existsSync(filePath)) {
        const dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        dialog.messages.forEach(m => { if (m.from === 'admin') m.readByClient = true; });
        fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/network/read-by-admin', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const filePath = path.join(CLIENT_MESSAGES_NETWORK_DIR, `${phone}.json`);

      if (fs.existsSync(filePath)) {
        const dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        dialog.messages.forEach(m => { if (m.from === 'client') m.readByAdmin = true; });
        fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== MANAGEMENT MESSAGES =====

  app.get('/api/client-dialogs/:phone/management', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      let messages = [];
      if (fs.existsSync(filePath)) {
        const dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
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
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const { text, imageUrl, clientName } = req.body;
      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      let dialog = { phone, messages: [] };
      if (fs.existsSync(filePath)) {
        dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
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

      fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
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
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      if (fs.existsSync(filePath)) {
        const dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        dialog.messages.forEach(m => { if (m.senderType === 'manager') m.isReadByClient = true; });
        fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/management/read-by-manager', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      if (fs.existsSync(filePath)) {
        const dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        dialog.messages.forEach(m => { if (m.senderType === 'client') m.isReadByManager = true; });
        fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      }

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/client-dialogs/:phone/management/send', async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const { text, imageUrl } = req.body;
      const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${phone}.json`);

      let dialog = { phone, messages: [] };
      if (fs.existsSync(filePath)) {
        dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
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

      fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
      console.log(`Сообщение от руководства клиенту ${phone} сохранено`);

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
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const clientDir = path.join(CLIENT_MESSAGES_DIR, phone);

      if (!fs.existsSync(clientDir)) {
        return res.json({ success: true, messages: [] });
      }

      const files = fs.readdirSync(clientDir).filter(f => f.endsWith('.json'));
      let allMessages = [];

      for (const file of files) {
        const dialog = JSON.parse(fs.readFileSync(path.join(clientDir, file), 'utf8'));
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
      const phone = req.params.phone.replace(/[\s+]/g, '');
      const { shopAddress, ...message } = req.body;

      const clientDir = path.join(CLIENT_MESSAGES_DIR, phone);
      if (!fs.existsSync(clientDir)) {
        fs.mkdirSync(clientDir, { recursive: true });
      }

      const sanitizedShop = (shopAddress || 'default').replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ]/g, '_');
      const filePath = path.join(clientDir, `${sanitizedShop}.json`);

      let dialog = { phone, shopAddress, messages: [] };
      if (fs.existsSync(filePath)) {
        dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      }

      message.timestamp = new Date().toISOString();
      dialog.messages.push(message);

      fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
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
        const normalizedPhone = phone.replace(/[\s+]/g, '');
        const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, `${normalizedPhone}.json`);

        let dialog = { phone: normalizedPhone, messages: [] };
        if (fs.existsSync(filePath)) {
          dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        }

        dialog.messages.push({
          ...message,
          timestamp: new Date().toISOString(),
          from: 'manager',
          isBroadcast: true
        });

        fs.writeFileSync(filePath, JSON.stringify(dialog, null, 2), 'utf8');
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

      if (!fs.existsSync(CLIENT_MESSAGES_MANAGEMENT_DIR)) {
        return res.json({ success: true, dialogs: [], totalUnread: 0 });
      }

      const files = fs.readdirSync(CLIENT_MESSAGES_MANAGEMENT_DIR).filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const filePath = path.join(CLIENT_MESSAGES_MANAGEMENT_DIR, file);
          const dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));

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
