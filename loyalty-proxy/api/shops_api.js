/**
 * Shops API - Управление магазинами
 * Extracted from index.js inline routes
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SHOPS_DIR = `${DATA_DIR}/shops`;

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

// Дефолтные магазины (создаются при первом запуске)
const DEFAULT_SHOPS = [
  { id: 'shop_1', name: 'Арабика Винсады', address: 'с.Винсады,ул Подгорная 156д (На Выезде)', icon: 'store_outlined', latitude: 44.091173, longitude: 42.952451 },
  { id: 'shop_2', name: 'Арабика Лермонтов', address: 'Лермонтов,ул Пятигорская 19', icon: 'store_outlined', latitude: 44.100923, longitude: 42.967543 },
  { id: 'shop_3', name: 'Арабика Лермонтов (Площадь)', address: 'Лермонтов,Комсомольская 1 (На Площади)', icon: 'store_outlined', latitude: 44.104619, longitude: 42.970543 },
  { id: 'shop_4', name: 'Арабика Лермонтов (Остановка)', address: 'Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )', icon: 'store_outlined', latitude: 44.105379, longitude: 42.978421 },
  { id: 'shop_5', name: 'Арабика Ессентуки', address: 'Ессентуки , ул пятигорская 149/1 (Золотушка)', icon: 'store_mall_directory_outlined', latitude: 44.055559, longitude: 42.911012 },
  { id: 'shop_6', name: 'Арабика Иноземцево', address: 'Иноземцево , ул Гагарина 1', icon: 'store_outlined', latitude: 44.080153, longitude: 43.081593 },
  { id: 'shop_7', name: 'Арабика Пятигорск (Ромашка)', address: 'Пятигорск, 295-стрелковой дивизии 2А стр1 (ромашка)', icon: 'store_outlined', latitude: 44.061053, longitude: 43.063672 },
  { id: 'shop_8', name: 'Арабика Пятигорск', address: 'Пятигорск,ул Коллективная 26а', icon: 'store_outlined', latitude: 44.032997, longitude: 43.042525 },
];

// Инициализация директории магазинов
async function initShopsDir() {
  if (!await fileExists(SHOPS_DIR)) {
    await fsp.mkdir(SHOPS_DIR, { recursive: true });
    // Создаем дефолтные магазины
    for (const shop of DEFAULT_SHOPS) {
      const shopFile = path.join(SHOPS_DIR, `${shop.id}.json`);
      await fsp.writeFile(shopFile, JSON.stringify(shop, null, 2));
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

      const shops = [];
      const files = (await fsp.readdir(SHOPS_DIR)).filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const content = await fsp.readFile(path.join(SHOPS_DIR, file), 'utf8');
          shops.push(JSON.parse(content));
        } catch (e) {
          console.error(`Ошибка чтения файла ${file}:`, e.message);
        }
      }

      res.json({ success: true, shops });
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
      const { name, address, latitude, longitude, icon } = req.body;
      console.log('POST /api/shops', req.body);

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
      await fsp.writeFile(shopFile, JSON.stringify(shop, null, 2));

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

      await fsp.writeFile(shopFile, JSON.stringify(shop, null, 2));

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
      const id = sanitizeId(req.params.id);
      console.log('DELETE /api/shops/' + id);

      const shopFile = path.join(SHOPS_DIR, `${id}.json`);
      if (!await fileExists(shopFile)) {
        return res.status(404).json({ success: false, error: 'Магазин не найден' });
      }

      await fsp.unlink(shopFile);

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
