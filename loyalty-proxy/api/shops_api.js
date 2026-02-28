/**
 * Shops API - Управление магазинами
 * Extracted from index.js inline routes
 *
 * Feature flag: USE_DB_SHOPS=true → PostgreSQL, false → JSON files
 */

const fsp = require('fs').promises;
const path = require('path');
const dataCache = require('../utils/data_cache');
const { isPaginationRequested, createPaginatedResponse, createDbPaginatedResponse } = require('../utils/pagination');
const { fileExists, sanitizeId } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAdmin } = require('../utils/session_middleware');
const { generateId } = require('../utils/id_generator');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SHOPS_DIR = `${DATA_DIR}/shops`;
const USE_DB = process.env.USE_DB_SHOPS === 'true';

// Дефолтные магазины (создаются при первом запуске) — загружаются из config/default_shops.json
const DEFAULT_SHOPS = require('../config/default_shops.json');

// Инициализация директории магазинов (только для JSON-режима)
async function initShopsDir() {
  if (USE_DB) return; // В DB-режиме не нужно
  if (!await fileExists(SHOPS_DIR)) {
    await fsp.mkdir(SHOPS_DIR, { recursive: true });
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
      let shops;

      if (USE_DB) {
        if (isPaginationRequested(req.query)) {
          const result = await db.findAllPaginated('shops', {
            orderBy: 'created_at', orderDir: 'ASC',
            page: parseInt(req.query.page) || 1,
            pageSize: Math.min(parseInt(req.query.limit) || 50, 200),
          });
          return res.json(createDbPaginatedResponse(result, 'shops', dbShopToCamel));
        }
        shops = await db.findAll('shops', { orderBy: 'created_at', orderDir: 'ASC' });
        shops = shops.map(dbShopToCamel);
      } else {
        // SCALABILITY: Используем кэш если доступен
        shops = dataCache.getShops();

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

      let shop;

      if (USE_DB) {
        const row = await db.findById('shops', id);
        if (!row) return res.status(404).json({ success: false, error: 'Магазин не найден' });
        shop = dbShopToCamel(row);
      } else {
        const shopFile = path.join(SHOPS_DIR, `${id}.json`);
        if (!await fileExists(shopFile)) {
          return res.status(404).json({ success: false, error: 'Магазин не найден' });
        }
        shop = JSON.parse(await fsp.readFile(shopFile, 'utf8'));
      }

      res.json({ success: true, shop });
    } catch (error) {
      console.error('Ошибка получения магазина:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/shops - создать магазин
  app.post('/api/shops', requireAdmin, async (req, res) => {
    try {
      const { name, address, latitude, longitude, icon } = req.body;
      console.log('POST /api/shops', name, address);

      const id = generateId('shop');
      const now = new Date().toISOString();

      let shop;

      shop = {
        id,
        name: name || '',
        address: address || '',
        icon: icon || 'store_outlined',
        latitude: latitude || null,
        longitude: longitude || null,
        createdAt: now,
        updatedAt: now,
      };

      if (USE_DB) {
        const row = await db.insert('shops', {
          id,
          name: name || '',
          address: address || '',
          latitude: latitude || null,
          longitude: longitude || null,
          created_at: now,
          updated_at: now
        });
        shop = dbShopToCamel(row);
      }

      // Dual-write: always keep JSON file in sync (schedulers read from files)
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
  app.put('/api/shops/:id', requireAdmin, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const updates = req.body;
      console.log('PUT /api/shops/' + id, updates);

      let shop;

      if (USE_DB) {
        const existing = await db.findById('shops', id);
        if (!existing) return res.status(404).json({ success: false, error: 'Магазин не найден' });

        const updateData = { updated_at: new Date().toISOString() };
        if (updates.name !== undefined) updateData.name = updates.name;
        if (updates.address !== undefined) updateData.address = updates.address;
        if (updates.latitude !== undefined) updateData.latitude = updates.latitude;
        if (updates.longitude !== undefined) updateData.longitude = updates.longitude;

        const row = await db.updateById('shops', id, updateData);
        shop = dbShopToCamel(row);
      } else {
        const shopFile = path.join(SHOPS_DIR, `${id}.json`);
        if (!await fileExists(shopFile)) {
          return res.status(404).json({ success: false, error: 'Магазин не найден' });
        }

        shop = JSON.parse(await fsp.readFile(shopFile, 'utf8'));
        if (updates.name !== undefined) shop.name = updates.name;
        if (updates.address !== undefined) shop.address = updates.address;
        if (updates.latitude !== undefined) shop.latitude = updates.latitude;
        if (updates.longitude !== undefined) shop.longitude = updates.longitude;
        if (updates.icon !== undefined) shop.icon = updates.icon;
        shop.updatedAt = new Date().toISOString();
      }

      // Dual-write: always keep JSON file in sync (schedulers read from files)
      const shopFile = path.join(SHOPS_DIR, `${id}.json`);
      shop.updatedAt = shop.updatedAt || new Date().toISOString();
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
  app.delete('/api/shops/:id', requireAdmin, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/shops/' + id);

      if (USE_DB) {
        const deleted = await db.deleteById('shops', id);
        if (!deleted) return res.status(404).json({ success: false, error: 'Магазин не найден' });
      } else {
        const shopFile = path.join(SHOPS_DIR, `${id}.json`);
        if (!await fileExists(shopFile)) {
          return res.status(404).json({ success: false, error: 'Магазин не найден' });
        }
      }

      // Dual-write: always remove JSON file in sync (schedulers read from files)
      const shopFile = path.join(SHOPS_DIR, `${id}.json`);
      if (await fileExists(shopFile)) {
        await fsp.unlink(shopFile);
      }

      dataCache.invalidateShops();
      console.log('✅ Магазин удален:', id);
      res.json({ success: true });
    } catch (error) {
      console.error('Ошибка удаления магазина:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Shops API initialized (storage: ${USE_DB ? 'PostgreSQL' : 'JSON files'})`);
}

/**
 * Преобразование DB row (snake_case) → camelCase (для совместимости с Flutter)
 * Flutter ожидает: { id, name, address, latitude, longitude, createdAt, updatedAt }
 */
function dbShopToCamel(row) {
  return {
    id: row.id,
    name: row.name,
    address: row.address,
    latitude: row.latitude,
    longitude: row.longitude,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

module.exports = { setupShopsAPI };
