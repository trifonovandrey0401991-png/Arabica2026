/**
 * Menu API
 * Extracted from index.js inline routes
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const MENU_DIR = `${DATA_DIR}/menu`;

async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

function sanitizeId(id) {
  if (!id || typeof id !== 'string') return '';
  return id.replace(/[^a-zA-Z0-9_\-\.]/g, '_');
}

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
  app.post('/api/menu', async (req, res) => {
    try {
      const item = req.body;
      console.log('POST /api/menu:', item.name);

      // Генерируем ID если его нет
      if (!item.id) {
        item.id = `menu_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      const itemFile = path.join(MENU_DIR, `${item.id}.json`);
      await fsp.writeFile(itemFile, JSON.stringify(item, null, 2), 'utf8');

      res.json({ success: true, item });
    } catch (error) {
      console.error('Ошибка создания позиции меню:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/menu/:id - обновить позицию меню
  app.put('/api/menu/:id', async (req, res) => {
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

      await fsp.writeFile(itemFile, JSON.stringify(item, null, 2), 'utf8');

      res.json({ success: true, item });
    } catch (error) {
      console.error('Ошибка обновления позиции меню:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/menu/:id - удалить позицию меню
  app.delete('/api/menu/:id', async (req, res) => {
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

      res.json({ success: true, message: 'Позиция меню удалена' });
    } catch (error) {
      console.error('Ошибка удаления позиции меню:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Menu API initialized');
}

module.exports = { setupMenuAPI };
