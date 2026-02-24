/**
 * Shop Products API Module
 * API для работы с товарами магазинов (синхронизация из DBF)
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const crypto = require('crypto');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_SHOP_PRODUCTS === 'true';

// Импортируем функции мастер-каталога для детекции новых кодов и подстановки названий
const { addPendingCode, loadProducts } = require('./master_catalog_api');
const { notifyAdminsAboutNewCodes } = require('./master_catalog_notifications');

// Директория для хранения товаров магазинов
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const SHOP_PRODUCTS_DIR = `${DATA_DIR}/shop-products`;

// API ключи для авторизации агентов синхронизации
const API_KEYS_FILE = `${DATA_DIR}/dbf-sync-settings/api-keys.json`;

// Кэш товаров магазинов
const shopProductsCache = new Map();

/**
 * Загрузить API ключи (async)
 */
async function loadApiKeys() {
  try {
    if (!(await fileExists(API_KEYS_FILE))) {
      // SECURITY: Генерируем криптографически случайный ключ вместо захардкоженного
      const randomKey = crypto.randomBytes(32).toString('hex');
      const defaultKeys = {
        keys: [
          {
            key: randomKey,
            shopId: '*', // Доступ ко всем магазинам
            description: 'Auto-generated sync key',
            createdAt: new Date().toISOString(),
          },
        ],
      };
      console.log(`[Shop Products API] ⚠️ Сгенерирован новый API ключ: ${randomKey.substring(0, 8)}...`);
      const dir = path.dirname(API_KEYS_FILE);
      await fsp.mkdir(dir, { recursive: true });
      await writeJsonFile(API_KEYS_FILE, defaultKeys);
      return defaultKeys.keys;
    }

    const data = await fsp.readFile(API_KEYS_FILE, 'utf8');
    const parsed = JSON.parse(data);
    return parsed.keys || [];
  } catch (error) {
    console.error('[Shop Products API] Ошибка загрузки API ключей:', error);
    return [];
  }
}

/**
 * Проверить API ключ (async)
 */
async function validateApiKey(apiKey, shopId) {
  const keys = await loadApiKeys();
  const keyEntry = keys.find((k) => k.key === apiKey);

  if (!keyEntry) return false;
  if (keyEntry.shopId === '*') return true; // Доступ ко всем
  if (keyEntry.shopId === shopId) return true;

  return false;
}

/**
 * Загрузить товары магазина из файла (async)
 */
async function loadShopProducts(shopId) {
  try {
    // Проверяем кэш
    if (shopProductsCache.has(shopId)) {
      return shopProductsCache.get(shopId);
    }

    const filePath = path.join(SHOP_PRODUCTS_DIR, `${shopId}.json`);

    if (!(await fileExists(filePath))) {
      return { products: [], lastSync: null, shopId };
    }

    const data = await fsp.readFile(filePath, 'utf8');
    const parsed = JSON.parse(data);

    // Сохраняем в кэш
    shopProductsCache.set(shopId, parsed);

    return parsed;
  } catch (error) {
    console.error(`[Shop Products API] Ошибка загрузки товаров магазина ${shopId}:`, error);
    return { products: [], lastSync: null, shopId };
  }
}

/**
 * Сохранить товары магазина (async)
 */
async function saveShopProducts(shopId, products) {
  try {
    await fsp.mkdir(SHOP_PRODUCTS_DIR, { recursive: true });

    const filePath = path.join(SHOP_PRODUCTS_DIR, `${shopId}.json`);

    const data = {
      shopId,
      products,
      lastSync: new Date().toISOString(),
      productCount: products.length,
    };

    await writeJsonFile(filePath, data);

    // Обновляем кэш
    shopProductsCache.set(shopId, data);

    if (USE_DB) {
      try { await db.upsert('shop_products', { id: shopId, data: data, updated_at: data.lastSync }); }
      catch (dbErr) { console.error('DB save shop_products error:', dbErr.message); }
    }

    console.log(`[Shop Products API] Сохранено ${products.length} товаров для магазина ${shopId}`);
    return true;
  } catch (error) {
    console.error(`[Shop Products API] Ошибка сохранения товаров магазина ${shopId}:`, error);
    return false;
  }
}

/**
 * Подставить названия из мастер-каталога для массива товаров
 * Если товар найден в мастер-каталоге - используется название оттуда
 * Сохраняет оригинальное название в поле originalName
 */
async function enrichProductsWithMasterNames(products) {
  // Загружаем мастер-каталог один раз и строим Map для быстрого поиска
  const masterProducts = await loadProducts();
  const nameMap = new Map();
  for (const mp of masterProducts) {
    if (mp.barcode && mp.name) {
      nameMap.set(mp.barcode, mp.name);
    }
  }

  return products.map((p) => {
    const masterName = nameMap.get(p.kod);
    if (masterName && masterName !== p.name) {
      return {
        ...p,
        originalName: p.name, // Сохраняем оригинальное название из DBF
        name: masterName, // Используем название из мастер-каталога
        fromMasterCatalog: true, // Флаг что название из мастер-каталога
      };
    }
    return p;
  });
}

/**
 * Получить список всех магазинов с товарами (async)
 */
async function getShopsWithProducts() {
  try {
    if (!(await fileExists(SHOP_PRODUCTS_DIR))) {
      return [];
    }

    const files = await fsp.readdir(SHOP_PRODUCTS_DIR);
    const shops = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        const shopId = file.replace('.json', '');
        const shopData = await loadShopProducts(shopId);
        shops.push({
          shopId,
          productCount: shopData.products?.length || 0,
          lastSync: shopData.lastSync,
        });
      }
    }

    return shops;
  } catch (error) {
    console.error('[Shop Products API] Ошибка получения списка магазинов:', error);
    return [];
  }
}

/**
 * Настройка API для товаров магазинов
 */
function setupShopProductsAPI(app) {
  console.log('[Shop Products API] Инициализация...');

  // Создаём директорию асинхронно
  fsp.mkdir(SHOP_PRODUCTS_DIR, { recursive: true }).catch(e => {
    console.error('[Shop Products API] Ошибка создания директории:', e);
  });

  // ============ СИНХРОНИЗАЦИЯ (для DBF Agent) ============

  /**
   * POST /api/shop-products/:shopId/sync
   * Синхронизация товаров магазина (вызывается DBF агентом)
   */
  app.post('/api/shop-products/:shopId/sync', async (req, res) => {
    try {
      const { shopId } = req.params;
      const apiKey = req.headers['x-api-key'];

      // Проверка API ключа
      if (!apiKey || !(await validateApiKey(apiKey, shopId))) {
        return res.status(401).json({ success: false, error: 'Неверный API ключ' });
      }

      const { products } = req.body;

      if (!Array.isArray(products)) {
        return res.status(400).json({ success: false, error: 'products должен быть массивом' });
      }

      // Нормализуем данные
      const normalizedProducts = products.map((p) => ({
        kod: String(p.kod || '').trim(),
        name: String(p.name || '').trim(),
        group: String(p.group || p['ГРУППА'] || '').trim(),
        stock: parseInt(p.stock || p['ОСТ'] || 0, 10),
        sales: parseInt(p.sales || p['ПРОДАЖА'] || 0, 10),
        updatedAt: new Date().toISOString(),
      }));

      // ============ ДЕТЕКЦИЯ НОВЫХ КОДОВ ============
      const shopName = req.body.shopName || shopId;
      const newCodes = [];

      for (const product of normalizedProducts) {
        if (!product.kod) continue;

        const result = await addPendingCode({
          kod: product.kod,
          shopId,
          shopName,
          name: product.name,
          group: product.group,
        });

        if (result.added) {
          newCodes.push({
            kod: product.kod,
            name: product.name,
            group: product.group,
          });
        }
      }

      if (newCodes.length > 0) {
        console.log(`[Shop Products API] Обнаружено ${newCodes.length} новых кодов от магазина ${shopName}`);

        notifyAdminsAboutNewCodes(newCodes, shopName).catch((err) => {
          console.error('[Shop Products API] Ошибка отправки push:', err.message);
        });
      }

      // Сохраняем
      const saved = await saveShopProducts(shopId, normalizedProducts);

      if (saved) {
        res.json({
          success: true,
          message: `Синхронизировано ${normalizedProducts.length} товаров`,
          productCount: normalizedProducts.length,
          newCodesCount: newCodes.length,
          newCodes: newCodes.slice(0, 10),
        });
      } else {
        res.status(500).json({ success: false, error: 'Ошибка сохранения' });
      }
    } catch (error) {
      console.error('[Shop Products API] Ошибка синхронизации:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ПОЛУЧЕНИЕ ТОВАРОВ ============

  /**
   * GET /api/shop-products/:shopId
   */
  app.get('/api/shop-products/:shopId', requireAuth, async (req, res) => {
    try {
      const { shopId } = req.params;
      const { group, hasStock, useMasterNames } = req.query;

      const shopData = await loadShopProducts(shopId);
      let products = shopData.products || [];

      if (group) {
        products = products.filter((p) => p.group === group);
      }

      if (hasStock === 'true') {
        products = products.filter((p) => p.stock > 0);
      } else if (hasStock === 'false') {
        products = products.filter((p) => p.stock === 0);
      }

      if (useMasterNames !== 'false') {
        products = await enrichProductsWithMasterNames(products);
      }

      res.json({
        success: true,
        shopId,
        products,
        total: products.length,
        lastSync: shopData.lastSync,
      });
    } catch (error) {
      console.error('[Shop Products API] Ошибка получения товаров:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/shop-products/:shopId/for-recount
   */
  app.get('/api/shop-products/:shopId/for-recount', requireAuth, async (req, res) => {
    try {
      const { shopId } = req.params;
      const { group } = req.query;

      const shopData = await loadShopProducts(shopId);
      let products = (shopData.products || []).filter((p) => p.stock > 0);

      if (group) {
        products = products.filter((p) => p.group === group);
      }

      products = await enrichProductsWithMasterNames(products);
      products.sort((a, b) => a.name.localeCompare(b.name, 'ru'));

      res.json({
        success: true,
        shopId,
        products,
        total: products.length,
        lastSync: shopData.lastSync,
      });
    } catch (error) {
      console.error('[Shop Products API] Ошибка получения товаров для пересчёта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/shop-products/:shopId/groups
   */
  app.get('/api/shop-products/:shopId/groups', requireAuth, async (req, res) => {
    try {
      const { shopId } = req.params;
      const shopData = await loadShopProducts(shopId);
      const products = shopData.products || [];

      const groupsSet = new Set();
      products.forEach((p) => {
        if (p.group) groupsSet.add(p.group);
      });

      const groups = Array.from(groupsSet).sort((a, b) => a.localeCompare(b, 'ru'));

      res.json({
        success: true,
        groups,
        total: groups.length,
      });
    } catch (error) {
      console.error('[Shop Products API] Ошибка получения групп:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ИНФОРМАЦИЯ О МАГАЗИНАХ ============

  /**
   * GET /api/shop-products/shops/list
   */
  app.get('/api/shop-products/shops/list', requireAuth, async (req, res) => {
    try {
      const shops = await getShopsWithProducts();

      res.json({
        success: true,
        shops,
        total: shops.length,
      });
    } catch (error) {
      console.error('[Shop Products API] Ошибка получения списка магазинов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * GET /api/shop-products/stats
   */
  app.get('/api/shop-products/stats', requireAuth, async (req, res) => {
    try {
      const shops = await getShopsWithProducts();

      let totalProducts = 0;
      let totalWithStock = 0;

      for (const shop of shops) {
        const shopData = await loadShopProducts(shop.shopId);
        const products = shopData.products || [];
        totalProducts += products.length;
        totalWithStock += products.filter((p) => p.stock > 0).length;
      }

      res.json({
        success: true,
        stats: {
          shopsCount: shops.length,
          totalProducts,
          totalWithStock,
          lastUpdated: new Date().toISOString(),
        },
      });
    } catch (error) {
      console.error('[Shop Products API] Ошибка получения статистики:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ПОИСК ============

  /**
   * GET /api/shop-products-search
   */
  app.get('/api/shop-products-search', requireAuth, async (req, res) => {
    try {
      const { q, shopId, group } = req.query;

      if (!q || q.length < 2) {
        return res.status(400).json({
          success: false,
          error: 'Поисковый запрос должен содержать минимум 2 символа',
        });
      }

      const searchLower = q.toLowerCase();
      const searchWords = searchLower.split(/\s+/).filter(w => w.length >= 2);
      const results = [];
      const shops = shopId ? [{ shopId }] : await getShopsWithProducts();

      for (const shop of shops) {
        const shopData = await loadShopProducts(shop.shopId);
        const products = shopData.products || [];

        products.forEach((product) => {
          const nameLower = (product.name || '').toLowerCase();
          const kodLower = (product.kod || '').toLowerCase();

          const allWordsMatch = searchWords.every(word =>
            nameLower.includes(word) || kodLower.includes(word)
          );

          if (allWordsMatch) {
            if (group && product.group !== group) return;

            results.push({
              ...product,
              shopId: shop.shopId,
            });
          }
        });
      }

      results.sort((a, b) => {
        const aExact = a.kod?.toLowerCase() === searchLower;
        const bExact = b.kod?.toLowerCase() === searchLower;
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;
        return a.name.localeCompare(b.name, 'ru');
      });

      res.json({
        success: true,
        results: results.slice(0, 100),
        total: results.length,
        query: q,
      });
    } catch (error) {
      console.error('[Shop Products API] Ошибка поиска:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ УПРАВЛЕНИЕ API КЛЮЧАМИ ============

  /**
   * GET /api/shop-products/api-keys
   */
  app.get('/api/shop-products/api-keys', requireAuth, async (req, res) => {
    try {
      const keys = await loadApiKeys();
      const maskedKeys = keys.map((k) => ({
        ...k,
        key: k.key.substring(0, 4) + '****' + k.key.substring(k.key.length - 4),
      }));

      res.json({ success: true, keys: maskedKeys });
    } catch (error) {
      console.error('[Shop Products API] Ошибка получения API ключей:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/shop-products/api-keys
   */
  app.post('/api/shop-products/api-keys', requireAuth, async (req, res) => {
    try {
      const { shopId, description } = req.body;

      if (!shopId) {
        return res.status(400).json({ success: false, error: 'shopId обязателен' });
      }

      const key = 'arabica-' + Math.random().toString(36).substring(2, 15);

      const keys = await loadApiKeys();
      keys.push({
        key,
        shopId,
        description: description || '',
        createdAt: new Date().toISOString(),
      });

      const dir = path.dirname(API_KEYS_FILE);
      await fsp.mkdir(dir, { recursive: true });
      await writeJsonFile(API_KEYS_FILE, { keys });

      res.json({ success: true, key, shopId });
    } catch (error) {
      console.error('[Shop Products API] Ошибка создания API ключа:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`[Shop Products API] Готово ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = {
  setupShopProductsAPI,
  loadShopProducts,
  saveShopProducts,
  getShopsWithProducts,
};
