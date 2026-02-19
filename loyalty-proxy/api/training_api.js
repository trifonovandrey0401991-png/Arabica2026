/**
 * Training API
 * Статьи обучения для сотрудников (с загрузкой изображений)
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const multer = require('multer');
const express = require('express');
const { sanitizeId, isPathSafe, fileExists } = require('../utils/file_helpers');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_TRAINING === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const TRAINING_ARTICLES_DIR = `${DATA_DIR}/training-articles`;
const TRAINING_ARTICLES_MEDIA_DIR = `${DATA_DIR}/training-articles-media`;

// Ensure directories exist at startup
(async () => {
  try {
    for (const dir of [TRAINING_ARTICLES_DIR, TRAINING_ARTICLES_MEDIA_DIR]) {
      if (!(await fileExists(dir))) {
        await fsp.mkdir(dir, { recursive: true });
      }
    }
  } catch (e) {
    console.error('Error creating training directories:', e.message);
  }
})();

// Настройка multer для загрузки изображений статей обучения
const trainingArticleMediaStorage = multer.diskStorage({
  destination: async function (req, file, cb) {
    if (!await fileExists(TRAINING_ARTICLES_MEDIA_DIR)) {
      await fsp.mkdir(TRAINING_ARTICLES_MEDIA_DIR, { recursive: true });
    }
    cb(null, TRAINING_ARTICLES_MEDIA_DIR);
  },
  filename: function (req, file, cb) {
    // SECURITY: Безопасное извлечение расширения
    const safeBasename = path.basename(file.originalname);
    const ext = path.extname(safeBasename).replace(/[^a-zA-Z0-9\.]/g, '') || '.jpg';
    const uniqueName = `training_img_${Date.now()}_${Math.random().toString(36).substr(2, 9)}${ext}`;
    cb(null, uniqueName);
  }
});

const uploadTrainingArticleMedia = multer({
  storage: trainingArticleMediaStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: function (req, file, cb) {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (allowedTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Разрешены только изображения (JPEG, PNG, GIF, WebP)'));
    }
  }
});

function setupTrainingAPI(app) {
  // GET /api/training-articles
  app.get('/api/training-articles', requireAuth, async (req, res) => {
    try {
      if (USE_DB) {
        const rows = await db.findAll('training_articles', { orderBy: 'created_at', orderDir: 'DESC' });
        const articles = rows.map(r => r.data);
        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(articles, req.query, 'articles'));
        }
        return res.json({ success: true, articles });
      }

      const articles = [];
      if (await fileExists(TRAINING_ARTICLES_DIR)) {
        const files = (await fsp.readdir(TRAINING_ARTICLES_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(TRAINING_ARTICLES_DIR, file), 'utf8');
            articles.push(JSON.parse(content));
          } catch (e) {
            console.error(`Ошибка чтения ${file}:`, e);
          }
        }
      }
      if (isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(articles, req.query, 'articles'));
      } else {
        res.json({ success: true, articles });
      }
    } catch (error) {
      console.error('Ошибка получения статей обучения:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/training-articles
  app.post('/api/training-articles', requireAuth, async (req, res) => {
    try {
      const article = {
        id: `training_article_${Date.now()}`,
        group: req.body.group,
        title: req.body.title,
        content: req.body.content || '',
        visibility: req.body.visibility || 'all',
        createdAt: new Date().toISOString(),
      };
      // URL опционален (для обратной совместимости)
      if (req.body.url) {
        article.url = req.body.url;
      }
      // Блоки контента (текст + изображения)
      if (req.body.contentBlocks && Array.isArray(req.body.contentBlocks)) {
        article.contentBlocks = req.body.contentBlocks;
      }
      const articleFile = path.join(TRAINING_ARTICLES_DIR, `${article.id}.json`);
      await writeJsonFile(articleFile, article);

      if (USE_DB) {
        try { await db.upsert('training_articles', { id: article.id, data: article, created_at: article.createdAt, updated_at: article.createdAt }); }
        catch (dbErr) { console.error('DB save training_article error:', dbErr.message); }
      }

      res.json({ success: true, article });
    } catch (error) {
      console.error('Ошибка создания статьи обучения:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/training-articles/:id
  app.put('/api/training-articles/:id', requireAuth, async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);
      const articleFile = path.join(TRAINING_ARTICLES_DIR, `${safeId}.json`);
      if (!isPathSafe(TRAINING_ARTICLES_DIR, articleFile)) {
        return res.status(400).json({ success: false, error: 'Invalid article ID' });
      }
      if (!await fileExists(articleFile)) {
        return res.status(404).json({ success: false, error: 'Статья не найдена' });
      }
      const article = JSON.parse(await fsp.readFile(articleFile, 'utf8'));
      if (req.body.group !== undefined) article.group = req.body.group;
      if (req.body.title !== undefined) article.title = req.body.title;
      if (req.body.content !== undefined) article.content = req.body.content;
      if (req.body.url !== undefined) article.url = req.body.url;
      if (req.body.visibility !== undefined) article.visibility = req.body.visibility;
      // Блоки контента (текст + изображения)
      if (req.body.contentBlocks !== undefined) {
        article.contentBlocks = req.body.contentBlocks;
      }
      article.updatedAt = new Date().toISOString();
      await writeJsonFile(articleFile, article);

      if (USE_DB) {
        try { await db.upsert('training_articles', { id: safeId, data: article, updated_at: article.updatedAt }); }
        catch (dbErr) { console.error('DB update training_article error:', dbErr.message); }
      }

      res.json({ success: true, article });
    } catch (error) {
      console.error('Ошибка обновления статьи обучения:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/training-articles/:id
  app.delete('/api/training-articles/:id', requireAuth, async (req, res) => {
    try {
      const safeId = sanitizeId(req.params.id);
      const articleFile = path.join(TRAINING_ARTICLES_DIR, `${safeId}.json`);
      if (!isPathSafe(TRAINING_ARTICLES_DIR, articleFile)) {
        return res.status(400).json({ success: false, error: 'Invalid article ID' });
      }
      if (!await fileExists(articleFile)) {
        return res.status(404).json({ success: false, error: 'Статья не найдена' });
      }
      await fsp.unlink(articleFile);

      if (USE_DB) {
        try { await db.deleteById('training_articles', safeId); }
        catch (dbErr) { console.error('DB delete training_article error:', dbErr.message); }
      }

      res.json({ success: true });
    } catch (error) {
      console.error('Ошибка удаления статьи обучения:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Загрузка изображения для статьи обучения
  app.post('/api/training-articles/upload-image', requireAuth, uploadTrainingArticleMedia.single('image'), (req, res) => {
    try {
      if (!req.file) {
        return res.status(400).json({ success: false, error: 'Файл не загружен' });
      }

      const imageUrl = `https://arabica26.ru/training-articles-media/${req.file.filename}`;
      console.log(`📷 Загружено изображение статьи обучения: ${req.file.filename}`);

      res.json({
        success: true,
        imageUrl: imageUrl,
        filename: req.file.filename,
      });
    } catch (error) {
      console.error('Ошибка загрузки изображения статьи:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Удаление изображения статьи обучения
  app.delete('/api/training-articles/delete-image/:filename', requireAuth, async (req, res) => {
    try {
      const filename = path.basename(req.params.filename);
      const filePath = path.join(TRAINING_ARTICLES_MEDIA_DIR, filename);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Изображение не найдено' });
      }

      await fsp.unlink(filePath);
      console.log(`🗑️ Удалено изображение статьи обучения: ${filename}`);

      res.json({ success: true });
    } catch (error) {
      console.error('Ошибка удаления изображения статьи:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Статические файлы для изображений статей обучения
  app.use('/training-articles-media', express.static(TRAINING_ARTICLES_MEDIA_DIR));

  console.log(`✅ Training API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = { setupTrainingAPI };
