/**
 * Menu API
 * Extracted from index.js inline routes
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, sanitizeId } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const db = require('../utils/db');
const { requireAuth, requireAdmin } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_MENU === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const MENU_DIR = `${DATA_DIR}/menu`;

// Ensure directory exists at startup
(async () => {
  try {
    if (!(await fileExists(MENU_DIR))) {
      await fsp.mkdir(MENU_DIR, { recursive: true });
    }
  } catch (e) {
    console.error('Error creating menu directory:', e.message);
  }
})();

function setupMenuAPI(app) {
  // GET /api/menu - получить все позиции меню
  app.get('/api/menu', async (req, res) => {
    try {
      console.log('GET /api/menu');

      if (USE_DB) {
        const rows = await db.findAll('menu_items', { orderBy: 'created_at', orderDir: 'ASC' });
        const items = rows.map(r => r.data);
        // Сортируем по категории и названию
        items.sort((a, b) => {
          const catCompare = (a.category || '').localeCompare(b.category || '');
          if (catCompare !== 0) return catCompare;
          return (a.name || '').localeCompare(b.name || '');
        });
        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(items, req.query, 'items'));
        }
        return res.json({ success: true, items });
      }

      const items = [];

      if (!await fileExists(MENU_DIR)) {
        return res.json({ success: true, items: [] });
      }

      const files = (await fsp.readdir(MENU_DIR)).filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const filePath = path.join(MENU_DIR, file);
          const content = await fsp.readFile(filePath, 'utf8');
          const item = JSON.parse(content);
          items.push(item);
        } catch (e) {
          console.error(`Ошибка чтения файла ${file}:`, e);
        }
      }

      // Сортируем по категории и названию
      items.sort((a, b) => {
        const catCompare = (a.category || '').localeCompare(b.category || '');
        if (catCompare !== 0) return catCompare;
        return (a.name || '').localeCompare(b.name || '');
      });

      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(items, req.query, 'items'));
      }
      res.json({ success: true, items });
    } catch (error) {
      console.error('Ошибка получения меню:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/menu/:id - получить позицию меню по ID
  app.get('/api/menu/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('GET /api/menu/:id', id);

      if (USE_DB) {
        const row = await db.findById('menu_items', id);
        if (!row) return res.status(404).json({ success: false, error: 'Позиция меню не найдена' });
        return res.json({ success: true, item: row.data });
      }

      const itemFile = path.join(MENU_DIR, `${id}.json`);

      if (!await fileExists(itemFile)) {
        return res.status(404).json({
          success: false,
          error: 'Позиция меню не найдена'
        });
      }

      const content = await fsp.readFile(itemFile, 'utf8');
      const item = JSON.parse(content);

      res.json({ success: true, item });
    } catch (error) {
      console.error('Ошибка получения позиции меню:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/menu - создать позицию меню
  app.post('/api/menu', requireAdmin, async (req, res) => {
    try {
      const item = req.body;
      console.log('POST /api/menu:', item.name);

      // Генерируем ID если его нет
      if (!item.id) {
        item.id = `menu_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      const itemFile = path.join(MENU_DIR, `${item.id}.json`);
      await writeJsonFile(itemFile, item);

      if (USE_DB) {
        try { await db.upsert('menu_items', { id: item.id, data: item, created_at: new Date().toISOString(), updated_at: new Date().toISOString() }); }
        catch (dbErr) { console.error('DB save menu_item error:', dbErr.message); }
      }

      res.json({ success: true, item });
    } catch (error) {
      console.error('Ошибка создания позиции меню:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/menu/:id - обновить позицию меню
  app.put('/api/menu/:id', requireAdmin, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const updates = req.body;
      console.log('PUT /api/menu/:id', id);

      const itemFile = path.join(MENU_DIR, `${id}.json`);

      if (!await fileExists(itemFile)) {
        return res.status(404).json({
          success: false,
          error: 'Позиция меню не найдена'
        });
      }

      const content = await fsp.readFile(itemFile, 'utf8');
      const item = JSON.parse(content);

      // Обновляем поля
      Object.assign(item, updates);
      item.id = id; // Сохраняем оригинальный ID

      await writeJsonFile(itemFile, item);

      if (USE_DB) {
        try { await db.upsert('menu_items', { id, data: item, updated_at: new Date().toISOString() }); }
        catch (dbErr) { console.error('DB update menu_item error:', dbErr.message); }
      }

      res.json({ success: true, item });
    } catch (error) {
      console.error('Ошибка обновления позиции меню:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/menu/:id - удалить позицию меню
  app.delete('/api/menu/:id', requireAdmin, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/menu/:id', id);

      const itemFile = path.join(MENU_DIR, `${id}.json`);

      if (!await fileExists(itemFile)) {
        return res.status(404).json({
          success: false,
          error: 'Позиция меню не найдена'
        });
      }

      await fsp.unlink(itemFile);

      if (USE_DB) {
        try { await db.deleteById('menu_items', id); }
        catch (dbErr) { console.error('DB delete menu_item error:', dbErr.message); }
      }

      res.json({ success: true, message: 'Позиция меню удалена' });
    } catch (error) {
      console.error('Ошибка удаления позиции меню:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Menu API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = { setupMenuAPI };
