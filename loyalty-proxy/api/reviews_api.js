/**
 * Reviews API
 * Отзывы клиентов о магазинах (с чатом)
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { sanitizeId, isPathSafe, fileExists } = require('../utils/file_helpers');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const REVIEWS_DIR = `${DATA_DIR}/reviews`;

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

function setupReviewsAPI(app, { sendPushNotification, sendPushToPhone } = {}) {
  // GET /api/reviews - получить отзывы (фильтр по phone)
  app.get('/api/reviews', async (req, res) => {
    try {
      const { phone } = req.query;
      let reviews = [];
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
  app.post('/api/reviews', async (req, res) => {
    try {
      const review = {
        id: `review_${Date.now()}`,
        clientPhone: req.body.clientPhone,
        clientName: req.body.clientName,
        shopAddress: req.body.shopAddress,
        reviewType: req.body.reviewType,
        reviewText: req.body.reviewText,
        messages: [],
        createdAt: new Date().toISOString(),
        hasUnreadFromClient: true,
        hasUnreadFromAdmin: false,
      };
      const reviewFile = path.join(REVIEWS_DIR, `${review.id}.json`);
      await fsp.writeFile(reviewFile, JSON.stringify(review, null, 2), 'utf8');

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

      res.json({ success: true, review });
    } catch (error) {
      console.error('Ошибка создания отзыва:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/reviews/:id - получить отзыв по ID
  app.get('/api/reviews/:id', async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);
      const reviewFile = path.join(REVIEWS_DIR, `${safeId}.json`);
      if (!isPathSafe(REVIEWS_DIR, reviewFile)) {
        return res.status(400).json({ success: false, error: 'Invalid review ID' });
      }
      if (!await fileExists(reviewFile)) {
        return res.status(404).json({ success: false, error: 'Отзыв не найден' });
      }
      const review = JSON.parse(await fsp.readFile(reviewFile, 'utf8'));
      res.json({ success: true, review });
    } catch (error) {
      console.error('Ошибка получения отзыва:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/reviews/:id/messages - добавить сообщение в отзыв
  app.post('/api/reviews/:id/messages', async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);
      const reviewFile = path.join(REVIEWS_DIR, `${safeId}.json`);
      if (!isPathSafe(REVIEWS_DIR, reviewFile)) {
        return res.status(400).json({ success: false, error: 'Invalid review ID' });
      }
      if (!await fileExists(reviewFile)) {
        return res.status(404).json({ success: false, error: 'Отзыв не найден' });
      }
      const review = JSON.parse(await fsp.readFile(reviewFile, 'utf8'));
      const message = {
        id: `message_${Date.now()}`,
        sender: req.body.sender,
        senderName: req.body.senderName,
        text: req.body.text,
        timestamp: new Date().toISOString(),
        createdAt: new Date().toISOString(),
        isRead: false,
      };
      review.messages = review.messages || [];
      review.messages.push(message);

      // Установить флаги непрочитанности и отправить push в зависимости от отправителя
      if (message.sender === 'client') {
        review.hasUnreadFromClient = true;

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
        review.hasUnreadFromAdmin = true;

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

      await fsp.writeFile(reviewFile, JSON.stringify(review, null, 2), 'utf8');
      res.json({ success: true, message });
    } catch (error) {
      console.error('Ошибка добавления сообщения:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/reviews/:id/mark-read - Отметить диалог как прочитанный
  app.post('/api/reviews/:id/mark-read', async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);
      const reviewFile = path.join(REVIEWS_DIR, `${safeId}.json`);
      if (!isPathSafe(REVIEWS_DIR, reviewFile)) {
        return res.status(400).json({ success: false, error: 'Invalid review ID' });
      }
      if (!await fileExists(reviewFile)) {
        return res.status(404).json({ success: false, error: 'Отзыв не найден' });
      }

      const review = JSON.parse(await fsp.readFile(reviewFile, 'utf8'));
      const { readerType } = req.body;

      if (!readerType) {
        return res.status(400).json({ success: false, error: 'readerType обязателен' });
      }

      if (readerType === 'admin') {
        review.hasUnreadFromClient = false;
        if (review.messages) {
          review.messages.forEach(msg => {
            if (msg.sender === 'client') {
              msg.isRead = true;
            }
          });
        }
      } else if (readerType === 'client') {
        review.hasUnreadFromAdmin = false;
        if (review.messages) {
          review.messages.forEach(msg => {
            if (msg.sender === 'admin') {
              msg.isRead = true;
            }
          });
        }
      }

      await fsp.writeFile(reviewFile, JSON.stringify(review, null, 2), 'utf8');
      res.json({ success: true });
    } catch (error) {
      console.error('Ошибка отметки диалога как прочитанного:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Reviews API initialized');
}

module.exports = { setupReviewsAPI };
