/**
 * Reviews API
 * Отзывы клиентов о магазинах (с чатом)
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 * REFACTORED: Added PostgreSQL support with USE_DB_REVIEWS flag (2026-02-17)
 */

const fsp = require('fs').promises;
const path = require('path');
const { sanitizeId, isPathSafe, fileExists } = require('../utils/file_helpers');
const { isPaginationRequested, createPaginatedResponse, createDbPaginatedResponse } = require('../utils/pagination');
const { writeJsonFile } = require('../utils/async_fs');
const { notifyCounterUpdate } = require('./counters_websocket');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const REVIEWS_DIR = `${DATA_DIR}/reviews`;
const USE_DB = process.env.USE_DB_REVIEWS === 'true';

// Ensure directory exists at startup
(async () => {
  try {
    if (!(await fileExists(REVIEWS_DIR))) {
      await fsp.mkdir(REVIEWS_DIR, { recursive: true });
    }
  } catch (e) {
    console.error('Failed to create reviews directory:', e);
  }
})();

// ==================== DB CONVERSION ====================

function dbReviewToCamel(row) {
  return {
    id: row.id,
    clientPhone: row.client_phone,
    clientName: row.client_name,
    shopAddress: row.shop_address,
    reviewType: row.review_type,
    reviewText: row.review_text,
    messages: typeof row.messages === 'string' ? JSON.parse(row.messages) : (row.messages || []),
    hasUnreadFromClient: row.has_unread_from_client,
    hasUnreadFromAdmin: row.has_unread_from_admin,
    createdAt: row.created_at
  };
}

// ==================== API ====================

function setupReviewsAPI(app, { sendPushNotification, sendPushToPhone } = {}) {
  // GET /api/reviews - получить отзывы (фильтр по phone)
  app.get('/api/reviews', requireAuth, async (req, res) => {
    try {
      const { phone } = req.query;
      let reviews;

      if (USE_DB) {
        // SQL-level pagination
        if (isPaginationRequested(req.query)) {
          const where = phone ? 'client_phone = $1' : undefined;
          const whereParams = phone ? [phone] : undefined;
          const result = await db.findAllPaginated('reviews', {
            where,
            whereParams,
            orderBy: 'created_at',
            orderDir: 'DESC',
            page: parseInt(req.query.page) || 1,
            pageSize: Math.min(parseInt(req.query.limit) || 50, 200),
          });
          return res.json(createDbPaginatedResponse(result, 'reviews', dbReviewToCamel));
        }

        let query = 'SELECT * FROM reviews';
        const params = [];

        if (phone) {
          query += ' WHERE client_phone = $1';
          params.push(phone);
        }

        query += ' ORDER BY created_at DESC';

        const result = await db.query(query, params);
        reviews = result.rows.map(dbReviewToCamel);
      } else {
        reviews = [];
        if (await fileExists(REVIEWS_DIR)) {
          const files = (await fsp.readdir(REVIEWS_DIR)).filter(f => f.endsWith('.json'));
          // Параллельное чтение файлов (вместо последовательного for...of)
          const results = await Promise.all(files.map(async (file) => {
            try {
              const content = await fsp.readFile(path.join(REVIEWS_DIR, file), 'utf8');
              return JSON.parse(content);
            } catch (e) {
              console.error(`Ошибка чтения ${file}:`, e);
              return null;
            }
          }));
          reviews = results.filter(r => r && (!phone || r.clientPhone === phone));
        }
      }

      if (isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(reviews, req.query, 'reviews'));
      } else {
        res.json({ success: true, reviews });
      }
    } catch (error) {
      console.error('Ошибка получения отзывов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/reviews - создать отзыв
  app.post('/api/reviews', requireAuth, async (req, res) => {
    try {
      const now = new Date().toISOString();
      const id = `review_${Date.now()}`;

      let review;

      if (USE_DB) {
        const row = await db.insert('reviews', {
          id,
          client_phone: req.body.clientPhone,
          client_name: req.body.clientName,
          shop_address: req.body.shopAddress,
          review_type: req.body.reviewType,
          review_text: req.body.reviewText,
          messages: '[]',
          has_unread_from_client: true,
          has_unread_from_admin: false,
          created_at: now
        });
        review = dbReviewToCamel(row);
      } else {
        review = {
          id,
          clientPhone: req.body.clientPhone,
          clientName: req.body.clientName,
          shopAddress: req.body.shopAddress,
          reviewType: req.body.reviewType,
          reviewText: req.body.reviewText,
          messages: [],
          createdAt: now,
          hasUnreadFromClient: true,
          hasUnreadFromAdmin: false,
        };
        const reviewFile = path.join(REVIEWS_DIR, `${review.id}.json`);
        // Boy Scout: fsp.writeFile → writeJsonFile
        await writeJsonFile(reviewFile, review);
      }

      // Отправить push-уведомление админам
      if (sendPushNotification) {
        const reviewEmoji = review.reviewType === 'positive' ? '👍' : '👎';
        await sendPushNotification(
          `Новый ${reviewEmoji} отзыв`,
          `${review.clientName} - ${review.shopAddress}`,
          {
            type: 'review_created',
            reviewId: review.id,
            reviewType: review.reviewType,
            shopAddress: review.shopAddress,
          }
        );
      }

      notifyCounterUpdate('unreadReviews', { delta: 1 });
      res.json({ success: true, review });
    } catch (error) {
      console.error('Ошибка создания отзыва:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/reviews/:id - получить отзыв по ID
  app.get('/api/reviews/:id', requireAuth, async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);

      let review;

      if (USE_DB) {
        const row = await db.findById('reviews', safeId);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отзыв не найден' });
        }
        review = dbReviewToCamel(row);
      } else {
        const reviewFile = path.join(REVIEWS_DIR, `${safeId}.json`);
        if (!isPathSafe(REVIEWS_DIR, reviewFile)) {
          return res.status(400).json({ success: false, error: 'Invalid review ID' });
        }
        if (!await fileExists(reviewFile)) {
          return res.status(404).json({ success: false, error: 'Отзыв не найден' });
        }
        review = JSON.parse(await fsp.readFile(reviewFile, 'utf8'));
      }

      res.json({ success: true, review });
    } catch (error) {
      console.error('Ошибка получения отзыва:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/reviews/:id/messages - добавить сообщение в отзыв
  app.post('/api/reviews/:id/messages', requireAuth, async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);

      const message = {
        id: `message_${Date.now()}`,
        sender: req.body.sender,
        senderName: req.body.senderName,
        text: req.body.text,
        timestamp: new Date().toISOString(),
        createdAt: new Date().toISOString(),
        isRead: false,
      };

      let review;

      if (USE_DB) {
        const row = await db.findById('reviews', safeId);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отзыв не найден' });
        }
        review = dbReviewToCamel(row);

        review.messages = review.messages || [];
        review.messages.push(message);

        const dbUpdates = {
          messages: JSON.stringify(review.messages)
        };

        if (message.sender === 'client') {
          dbUpdates.has_unread_from_client = true;
          review.hasUnreadFromClient = true;
        } else if (message.sender === 'admin') {
          dbUpdates.has_unread_from_admin = true;
          review.hasUnreadFromAdmin = true;
        }

        await db.updateById('reviews', safeId, dbUpdates);
      } else {
        const reviewFile = path.join(REVIEWS_DIR, `${safeId}.json`);
        if (!isPathSafe(REVIEWS_DIR, reviewFile)) {
          return res.status(400).json({ success: false, error: 'Invalid review ID' });
        }
        if (!await fileExists(reviewFile)) {
          return res.status(404).json({ success: false, error: 'Отзыв не найден' });
        }
        review = JSON.parse(await fsp.readFile(reviewFile, 'utf8'));

        review.messages = review.messages || [];
        review.messages.push(message);

        // Установить флаги непрочитанности
        if (message.sender === 'client') {
          review.hasUnreadFromClient = true;
        } else if (message.sender === 'admin') {
          review.hasUnreadFromAdmin = true;
        }

        // Boy Scout: fsp.writeFile → writeJsonFile
        await writeJsonFile(reviewFile, review);
      }

      // Push-уведомления в зависимости от отправителя
      if (message.sender === 'client') {
        if (sendPushNotification) {
          await sendPushNotification(
            'Новое сообщение в отзыве',
            `${review.clientName}: ${message.text.substring(0, 50)}${message.text.length > 50 ? '...' : ''}`,
            {
              type: 'review_message',
              reviewId: review.id,
              shopAddress: review.shopAddress,
            }
          );
        }
      } else if (message.sender === 'admin') {
        if (sendPushToPhone) {
          await sendPushToPhone(
            review.clientPhone,
            'Ответ на ваш отзыв',
            message.text.substring(0, 50) + (message.text.length > 50 ? '...' : ''),
            {
              type: 'review_message',
              reviewId: review.id,
            }
          );
        }
      }

      res.json({ success: true, message });
    } catch (error) {
      console.error('Ошибка добавления сообщения:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/reviews/:id/mark-read - Отметить диалог как прочитанный
  app.post('/api/reviews/:id/mark-read', requireAuth, async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);
      const { readerType } = req.body;

      if (!readerType) {
        return res.status(400).json({ success: false, error: 'readerType обязателен' });
      }

      if (USE_DB) {
        const row = await db.findById('reviews', safeId);
        if (!row) {
          return res.status(404).json({ success: false, error: 'Отзыв не найден' });
        }

        const review = dbReviewToCamel(row);
        const dbUpdates = {};

        if (readerType === 'admin') {
          dbUpdates.has_unread_from_client = false;
          if (review.messages) {
            review.messages.forEach(msg => {
              if (msg.sender === 'client') msg.isRead = true;
            });
            dbUpdates.messages = JSON.stringify(review.messages);
          }
        } else if (readerType === 'client') {
          dbUpdates.has_unread_from_admin = false;
          if (review.messages) {
            review.messages.forEach(msg => {
              if (msg.sender === 'admin') msg.isRead = true;
            });
            dbUpdates.messages = JSON.stringify(review.messages);
          }
        }

        await db.updateById('reviews', safeId, dbUpdates);
      } else {
        const reviewFile = path.join(REVIEWS_DIR, `${safeId}.json`);
        if (!isPathSafe(REVIEWS_DIR, reviewFile)) {
          return res.status(400).json({ success: false, error: 'Invalid review ID' });
        }
        if (!await fileExists(reviewFile)) {
          return res.status(404).json({ success: false, error: 'Отзыв не найден' });
        }

        const review = JSON.parse(await fsp.readFile(reviewFile, 'utf8'));

        if (readerType === 'admin') {
          review.hasUnreadFromClient = false;
          if (review.messages) {
            review.messages.forEach(msg => {
              if (msg.sender === 'client') msg.isRead = true;
            });
          }
        } else if (readerType === 'client') {
          review.hasUnreadFromAdmin = false;
          if (review.messages) {
            review.messages.forEach(msg => {
              if (msg.sender === 'admin') msg.isRead = true;
            });
          }
        }

        // Boy Scout: fsp.writeFile → writeJsonFile
        await writeJsonFile(reviewFile, review);
      }

      notifyCounterUpdate('unreadReviews', { delta: -1 });
      res.json({ success: true });
    } catch (error) {
      console.error('Ошибка отметки диалога как прочитанного:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Reviews API initialized (storage: ${USE_DB ? 'PostgreSQL' : 'JSON files'})`);
}

module.exports = { setupReviewsAPI };
