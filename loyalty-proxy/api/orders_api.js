/**
 * Orders API
 * Заказы клиентов
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 * REFACTORED: Added PostgreSQL support with USE_DB_ORDERS flag (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const { sanitizeId, fileExists } = require('../utils/file_helpers');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const ordersModule = require('../modules/orders');
const db = require('../utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const ORDERS_DIR = `${DATA_DIR}/orders`;
const USE_DB = process.env.USE_DB_ORDERS === 'true';

(async () => {
  if (!await fileExists(ORDERS_DIR)) {
    await fsp.mkdir(ORDERS_DIR, { recursive: true });
  }
})();

function setupOrdersAPI(app) {
  // POST /api/orders - создать заказ
  app.post('/api/orders', async (req, res) => {
    try {
      const { clientPhone, clientName, shopAddress, items, totalPrice, comment } = req.body;
      console.log('POST /api/orders clientPhone:', clientPhone, 'shop:', shopAddress);
      const normalizedPhone = clientPhone.replace(/[^\d]/g, '');

      const order = await ordersModule.createOrder({
        clientPhone: normalizedPhone,
        clientName,
        shopAddress,
        items,
        totalPrice,
        comment
      });

      console.log(`✅ Создан заказ #${order.orderNumber} от ${clientName}`);
      res.json({ success: true, order });
    } catch (err) {
      console.error('❌ Ошибка создания заказа:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  });

  // GET /api/orders - получить заказы (с фильтрацией по clientPhone)
  app.get('/api/orders', async (req, res) => {
    try {
      console.log('GET /api/orders', req.query);
      const filters = {};
      if (req.query.clientPhone) {
        filters.clientPhone = req.query.clientPhone.replace(/[^\d]/g, '');
      }
      if (req.query.status) filters.status = req.query.status;
      if (req.query.shopAddress) filters.shopAddress = req.query.shopAddress;

      const orders = await ordersModule.getOrders(filters);
      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(orders, req.query, 'orders'));
      }
      res.json({ success: true, orders });
    } catch (err) {
      console.error('❌ Ошибка получения заказов:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  });

  // GET /api/orders/unviewed-count - получить количество непросмотренных заказов
  // ВАЖНО: этот route должен быть ПЕРЕД /api/orders/:id
  app.get('/api/orders/unviewed-count', async (req, res) => {
    try {
      console.log('GET /api/orders/unviewed-count');
      const counts = await ordersModule.getUnviewedOrdersCounts();
      res.json({
        success: true,
        rejected: counts.rejected,
        unconfirmed: counts.unconfirmed,
        total: counts.total
      });
    } catch (error) {
      console.error('Ошибка получения непросмотренных заказов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/orders/mark-viewed/:type - отметить заказы как просмотренные
  // ВАЖНО: этот route должен быть ПЕРЕД /api/orders/:id
  app.post('/api/orders/mark-viewed/:type', async (req, res) => {
    try {
      const { type } = req.params;
      console.log('POST /api/orders/mark-viewed/' + type);

      if (type !== 'rejected' && type !== 'unconfirmed') {
        return res.status(400).json({
          success: false,
          error: 'Incorrect type: should be rejected or unconfirmed'
        });
      }

      const success = await ordersModule.saveLastViewedAt(type, new Date());
      res.json({ success });
    } catch (error) {
      console.error('Ошибка отметки заказов как просмотренных:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/orders/:id - получить заказ по ID
  app.get('/api/orders/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('GET /api/orders/:id', id);

      let order;

      if (USE_DB) {
        const row = await db.findById('orders', id);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Заказ не найден' });
        }
        order = ordersModule.dbOrderToCamel(row);
      } else {
        const orderFile = path.join(ORDERS_DIR, `${id}.json`);

        if (!await fileExists(orderFile)) {
          return res.status(404).json({ success: false, error: 'Заказ не найден' });
        }

        const content = await fsp.readFile(orderFile, 'utf8');
        order = JSON.parse(content);
      }

      res.json({ success: true, order });
    } catch (error) {
      console.error('Ошибка получения заказа:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PATCH /api/orders/:id - обновить статус заказа
  app.patch('/api/orders/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const updates = {};

      if (req.body.status) updates.status = req.body.status;
      if (req.body.acceptedBy) updates.acceptedBy = req.body.acceptedBy;
      if (req.body.rejectedBy) updates.rejectedBy = req.body.rejectedBy;
      if (req.body.rejectionReason) updates.rejectionReason = req.body.rejectionReason;

      const order = await ordersModule.updateOrderStatus(id, updates);
      console.log(`✅ Заказ #${order.orderNumber} обновлен: ${updates.status}`);
      res.json({ success: true, order });
    } catch (err) {
      console.error('❌ Ошибка обновления заказа:', err);
      res.status(500).json({ success: false, error: err.message });
    }
  });

  // DELETE /api/orders/:id - удалить заказ
  app.delete('/api/orders/:id', async (req, res) => {
    try {
      // Boy Scout: добавлена проверка авторизации
      if (!req.user) return res.status(401).json({ error: 'Unauthorized' });

      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/orders/:id', id);

      if (USE_DB) {
        const deleted = await db.deleteById('orders', id);
        if (!deleted) {
          return res.status(404).json({ success: false, error: 'Заказ не найден' });
        }
      } else {
        const orderFile = path.join(ORDERS_DIR, `${id}.json`);

        if (!await fileExists(orderFile)) {
          return res.status(404).json({ success: false, error: 'Заказ не найден' });
        }

        await fsp.unlink(orderFile);
      }

      res.json({ success: true, message: 'Заказ удален' });
    } catch (error) {
      console.error('Ошибка удаления заказа:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Orders API initialized (storage: ${USE_DB ? 'PostgreSQL' : 'JSON files'})`);
}

module.exports = { setupOrdersAPI };
