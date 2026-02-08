/**
 * Orders API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const fs = require('fs');
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const ORDERS_DIR = `${DATA_DIR}/orders`;
const FCM_TOKENS_DIR = `${DATA_DIR}/fcm-tokens`;

/**
 * Sanitize ID — защита от path traversal
 */
function sanitizeId(id) {
  if (!id || typeof id !== 'string') return '';
  return id.replace(/[^a-zA-Z0-9_\-\.]/g, '_');
}

/**
 * Sanitize phone — только цифры
 */
function sanitizePhone(phone) {
  if (!phone) return '';
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

// Ensure directories exist (async IIFE)
(async () => {
  for (const dir of [ORDERS_DIR, FCM_TOKENS_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

// Firebase initialization (sync for require, but needs existsSync for file check)
let admin = null;
let firebaseInitialized = false;

try {
  admin = require('firebase-admin');
  const serviceAccountPath = path.join(__dirname, '..', 'firebase-service-account.json');

  // Using sync here because require() needs sync check
  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = require(serviceAccountPath);

    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
    }

    firebaseInitialized = true;
    console.log('✅ Firebase Admin SDK инициализирован');
  } else {
    console.warn('⚠️  firebase-service-account.json не найден');
  }
} catch (error) {
  console.warn('⚠️  Firebase не инициализирован:', error.message);
}

// Helper function to send push notification
async function sendPushNotification(token, title, body, data = {}) {
  if (!firebaseInitialized || !admin) {
    console.log('Firebase не инициализирован, пропуск отправки push');
    return false;
  }

  try {
    const message = {
      token,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'orders'
        }
      }
    };

    const response = await admin.messaging().send(message);
    console.log('✅ Push отправлен:', response);
    return true;
  } catch (error) {
    console.error('❌ Ошибка отправки push:', error.message);
    return false;
  }
}

// Helper to get FCM token by phone
async function getFcmToken(phone) {
  const normalizedPhone = phone.replace(/[\s+]/g, '');
  const filePath = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);

  if (await fileExists(filePath)) {
    try {
      const data = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      return data.token;
    } catch (e) {
      return null;
    }
  }
  return null;
}

function setupOrdersAPI(app) {
  // ===== ORDERS =====

  app.get('/api/orders', async (req, res) => {
    try {
      console.log('GET /api/orders');
      const { shopAddress, status, date } = req.query;
      const orders = [];

      if (await fileExists(ORDERS_DIR)) {
        const files = (await fsp.readdir(ORDERS_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(ORDERS_DIR, file), 'utf8');
            const order = JSON.parse(content);

            if (shopAddress && order.shopAddress !== shopAddress) continue;
            if (status && order.status !== status) continue;
            if (date && !order.createdAt?.startsWith(date)) continue;

            orders.push(order);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      orders.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, orders });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/orders', async (req, res) => {
    try {
      const order = req.body;
      console.log('POST /api/orders:', order.shopAddress);

      if (!order.id) {
        order.id = `order_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      order.createdAt = order.createdAt || new Date().toISOString();
      order.status = order.status || 'pending';

      const filePath = path.join(ORDERS_DIR, `${order.id}.json`);
      await fsp.writeFile(filePath, JSON.stringify(order, null, 2), 'utf8');

      res.json({ success: true, order });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/orders/:orderId', async (req, res) => {
    try {
      const orderId = sanitizeId(req.params.orderId);
      console.log('GET /api/orders/:orderId', orderId);

      const filePath = path.join(ORDERS_DIR, `${orderId}.json`);

      if (await fileExists(filePath)) {
        const data = await fsp.readFile(filePath, 'utf8');
        const order = JSON.parse(data);
        res.json({ success: true, order });
      } else {
        res.status(404).json({ success: false, error: 'Order not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/orders/:orderId', async (req, res) => {
    try {
      const orderId = sanitizeId(req.params.orderId);
      const updates = req.body;
      console.log('PUT /api/orders/:orderId', orderId);

      const filePath = path.join(ORDERS_DIR, `${orderId}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Order not found' });
      }

      const data = await fsp.readFile(filePath, 'utf8');
      const order = JSON.parse(data);
      const updated = { ...order, ...updates, updatedAt: new Date().toISOString() };

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, order: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/orders/:orderId', async (req, res) => {
    try {
      const orderId = sanitizeId(req.params.orderId);
      console.log('DELETE /api/orders/:orderId', orderId);

      const filePath = path.join(ORDERS_DIR, `${orderId}.json`);

      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Order not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== FCM TOKENS =====

  app.get('/api/fcm-tokens', async (req, res) => {
    try {
      console.log('GET /api/fcm-tokens');
      const tokens = [];

      if (await fileExists(FCM_TOKENS_DIR)) {
        const files = (await fsp.readdir(FCM_TOKENS_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(FCM_TOKENS_DIR, file), 'utf8');
            tokens.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      res.json({ success: true, tokens });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/fcm-tokens', async (req, res) => {
    try {
      const tokenData = req.body;
      console.log('POST /api/fcm-tokens:', tokenData.phone);

      if (!tokenData.phone || !tokenData.token) {
        return res.status(400).json({ success: false, error: 'Phone and token required' });
      }

      const normalizedPhone = tokenData.phone.replace(/[\s+]/g, '');
      const filePath = path.join(FCM_TOKENS_DIR, `${normalizedPhone}.json`);

      tokenData.phone = normalizedPhone;
      tokenData.updatedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(tokenData, null, 2), 'utf8');
      res.json({ success: true, tokenData });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/fcm-tokens/:phone', async (req, res) => {
    try {
      const phone = sanitizePhone(req.params.phone);
      console.log('DELETE /api/fcm-tokens:', phone);

      const filePath = path.join(FCM_TOKENS_DIR, `${phone}.json`);

      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Token not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SEND PUSH NOTIFICATION =====

  app.post('/api/send-push', async (req, res) => {
    try {
      const { phone, title, body, data } = req.body;
      console.log('POST /api/send-push:', phone, title);

      if (!phone || !title) {
        return res.status(400).json({ success: false, error: 'Phone and title required' });
      }

      const token = await getFcmToken(phone);
      if (!token) {
        return res.status(404).json({ success: false, error: 'FCM token not found for phone' });
      }

      const sent = await sendPushNotification(token, title, body || '', data || {});
      res.json({ success: sent });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== BROADCAST PUSH =====

  app.post('/api/send-push/broadcast', async (req, res) => {
    try {
      const { title, body, data, phones } = req.body;
      console.log('POST /api/send-push/broadcast:', title);

      if (!title) {
        return res.status(400).json({ success: false, error: 'Title required' });
      }

      let sent = 0;
      let failed = 0;

      // Get all tokens or filter by phones
      const tokensToSend = [];

      if (phones && phones.length > 0) {
        for (const phone of phones) {
          const token = await getFcmToken(phone);
          if (token) tokensToSend.push(token);
        }
      } else {
        // Send to all
        if (await fileExists(FCM_TOKENS_DIR)) {
          const files = (await fsp.readdir(FCM_TOKENS_DIR)).filter(f => f.endsWith('.json'));
          for (const file of files) {
            try {
              const content = await fsp.readFile(path.join(FCM_TOKENS_DIR, file), 'utf8');
              const tokenData = JSON.parse(content);
              if (tokenData.token) tokensToSend.push(tokenData.token);
            } catch (e) {}
          }
        }
      }

      for (const token of tokensToSend) {
        const success = await sendPushNotification(token, title, body || '', data || {});
        if (success) sent++;
        else failed++;
      }

      res.json({ success: true, sent, failed, total: tokensToSend.length });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Orders & FCM API initialized');
}

module.exports = { setupOrdersAPI, sendPushNotification, getFcmToken };
