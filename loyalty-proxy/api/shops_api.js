/**
 * Shops API - Управление магазинами
 * Extracted from index.js inline routes
 */

const fsp = require('fs').promises;
const path = require('path');
const dataCache = require('../utils/data_cache');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const { fileExists, sanitizeId } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SHOPS_DIR = `${DATA_DIR}/shops`;

// Дефолтные магазины (создаются при первом запуске) — загружаются из config/default_shops.json
const DEFAULT_SHOPS = require('../config/default_shops.json');

// Инициализация директории магазинов
async function initShopsDir() {
  if (!await fileExists(SHOPS_DIR)) {
    await fsp.mkdir(SHOPS_DIR, { recursive: true });
    // Создаем дефолтные магазины
    for (const shop of DEFAULT_SHOPS) {
      const shopFile = path.join(SHOPS_DIR, `${shop.id}.json`);
      await writeJsonFile(shopFile, shop);
    }
    console.log('✅ Директория магазинов создана с дефолтными данными');
  }
}
initShopsDir();

function setupShopsAPI(app) {
  // GET /api/shops - получить все магазины
  app.get('/api/shops', async (req, res) => {
    try {
      console.log('GET /api/shops');

      // SCALABILITY: Используем кэш если доступен
      let shops = dataCache.getShops();

      if (!shops) {
        shops = [];
        const files = (await fsp.readdir(SHOPS_DIR)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(SHOPS_DIR, file), 'utf8');
            shops.push(JSON.parse(content));
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e.message);
          }
        }
      }

      // SCALABILITY: Пагинация если запрошена
      if (isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(shops, req.query, 'shops'));
      } else {
        res.json({ success: true, shops });
      }
    } catch (error) {
      console.error('Ошибка получения магазинов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/shops/:id - получить магазин по ID
  app.get('/api/shops/:id', async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('GET /api/shops/' + id);

      const shopFile = path.join(SHOPS_DIR, `${id}.json`);
      if (!await fileExists(shopFile)) {
        return res.status(404).json({ success: false, error: 'Магазин не найден' });
      }

      const shop = JSON.parse(await fsp.readFile(shopFile, 'utf8'));
      res.json({ success: true, shop });
    } catch (error) {
      console.error('Ошибка получения магазина:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/shops - создать магазин
  app.post('/api/shops', async (req, res) => {
    try {
      if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
      const { name, address, latitude, longitude, icon } = req.body;
      console.log('POST /api/shops', name, address);

      const id = 'shop_' + Date.now();
      const shop = {
        id,
        name: name || '',
        address: address || '',
        icon: icon || 'store_outlined',
        latitude: latitude || null,
        longitude: longitude || null,
        createdAt: new Date().toISOString(),
      };

      const shopFile = path.join(SHOPS_DIR, `${id}.json`);
      await writeJsonFile(shopFile, shop);
      dataCache.invalidateShops();

      console.log('✅ Магазин создан:', id);
      res.json({ success: true, shop });
    } catch (error) {
      console.error('Ошибка создания магазина:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/shops/:id - обновить магазин
  app.put('/api/shops/:id', async (req, res) => {
    try {
      if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
      const id = sanitizeId(req.params.id);
      const updates = req.body;
      console.log('PUT /api/shops/' + id, updates);

      const shopFile = path.join(SHOPS_DIR, `${id}.json`);
      if (!await fileExists(shopFile)) {
        return res.status(404).json({ success: false, error: 'Магазин не найден' });
      }

      const shop = JSON.parse(await fsp.readFile(shopFile, 'utf8'));

      // Обновляем только переданные поля
      if (updates.name !== undefined) shop.name = updates.name;
      if (updates.address !== undefined) shop.address = updates.address;
      if (updates.latitude !== undefined) shop.latitude = updates.latitude;
      if (updates.longitude !== undefined) shop.longitude = updates.longitude;
      if (updates.icon !== undefined) shop.icon = updates.icon;
      shop.updatedAt = new Date().toISOString();

      await writeJsonFile(shopFile, shop);
      dataCache.invalidateShops();

      console.log('✅ Магазин обновлен:', id);
      res.json({ success: true, shop });
    } catch (error) {
      console.error('Ошибка обновления магазина:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/shops/:id - удалить магазин
  app.delete('/api/shops/:id', async (req, res) => {
    try {
      if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/shops/' + id);

      const shopFile = path.join(SHOPS_DIR, `${id}.json`);
      if (!await fileExists(shopFile)) {
        return res.status(404).json({ success: false, error: 'Магазин не найден' });
      }

      await fsp.unlink(shopFile);
      dataCache.invalidateShops();

      console.log('✅ Магазин удален:', id);
      res.json({ success: true });
    } catch (error) {
      console.error('Ошибка удаления магазина:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Shops API initialized');
}

module.exports = { setupShopsAPI };
