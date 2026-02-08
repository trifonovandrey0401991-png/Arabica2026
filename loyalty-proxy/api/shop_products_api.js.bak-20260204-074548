/**
 * Shop Products API Module
 * API для работы с товарами магазинов (синхронизация из DBF)
 */

const fs = require('fs');
const path = require('path');

// Импортируем функции мастер-каталога для детекции новых кодов и подстановки названий
const { addPendingCode, isCodeInMasterCatalog, getMasterNameByBarcode } = require('./master_catalog_api');
const { notifyAdminsAboutNewCodes } = require('./master_catalog_notifications');

// Директория для хранения товаров магазинов
const SHOP_PRODUCTS_DIR = '/var/www/shop-products';

// API ключи для авторизации агентов синхронизации
const API_KEYS_FILE = '/var/www/dbf-sync-settings/api-keys.json';

// Кэш товаров магазинов
const shopProductsCache = new Map();

/**
 * Загрузить API ключи
 */
function loadApiKeys() {
  try {
    if (!fs.existsSync(API_KEYS_FILE)) {
      // Создаём файл с дефолтным ключом
      const defaultKeys = {
        keys: [
          {
            key: 'arabica-sync-2025',
            shopId: '*', // Доступ ко всем магазинам
            description: 'Default sync key',
            createdAt: new Date().toISOString(),
          },
        ],
      };
      const dir = path.dirname(API_KEYS_FILE);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      fs.writeFileSync(API_KEYS_FILE, JSON.stringify(defaultKeys, null, 2));
      return defaultKeys.keys;
    }

    const data = fs.readFileSync(API_KEYS_FILE, 'utf8');
    const parsed = JSON.parse(data);
    return parsed.keys || [];
  } catch (error) {
    console.error('[Shop Products API] Ошибка загрузки API ключей:', error);
    return [];
  }
}

/**
 * Проверить API ключ
 */
function validateApiKey(apiKey, shopId) {
  const keys = loadApiKeys();
  const keyEntry = keys.find((k) => k.key === apiKey);

  if (!keyEntry) return false;
  if (keyEntry.shopId === '*') return true; // Доступ ко всем
  if (keyEntry.shopId === shopId) return true;

  return false;
}

/**
 * Загрузить товары магазина из файла
 */
function loadShopProducts(shopId) {
  try {
    // Проверяем кэш
    if (shopProductsCache.has(shopId)) {
      return shopProductsCache.get(shopId);
    }

    const filePath = path.join(SHOP_PRODUCTS_DIR, `${shopId}.json`);

    if (!fs.existsSync(filePath)) {
      return { products: [], lastSync: null, shopId };
    }

    const data = fs.readFileSync(filePath, 'utf8');
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
 * Сохранить товары магазина
 */
function saveShopProducts(shopId, products) {
  try {
    if (!fs.existsSync(SHOP_PRODUCTS_DIR)) {
      fs.mkdirSync(SHOP_PRODUCTS_DIR, { recursive: true });
    }

    const filePath = path.join(SHOP_PRODUCTS_DIR, `${shopId}.json`);

    const data = {
      shopId,
      products,
      lastSync: new Date().toISOString(),
      productCount: products.length,
    };

    fs.writeFileSync(filePath, JSON.stringify(data, null, 2));

    // Обновляем кэш
    shopProductsCache.set(shopId, data);

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
function enrichProductsWithMasterNames(products) {
  return products.map((p) => {
    const masterName = getMasterNameByBarcode(p.kod);
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
 * Получить список всех магазинов с товарами
 */
function getShopsWithProducts() {
  try {
    if (!fs.existsSync(SHOP_PRODUCTS_DIR)) {
      return [];
    }

    const files = fs.readdirSync(SHOP_PRODUCTS_DIR);
    const shops = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        const shopId = file.replace('.json', '');
        const shopData = loadShopProducts(shopId);
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

  // Создаём директорию если не существует
  if (!fs.existsSync(SHOP_PRODUCTS_DIR)) {
    fs.mkdirSync(SHOP_PRODUCTS_DIR, { recursive: true });
  }

  // ============ СИНХРОНИЗАЦИЯ (для DBF Agent) ============

  /**
   * POST /api/shop-products/:shopId/sync
   * Синхронизация товаров магазина (вызывается DBF агентом)
   *
   * Headers:
   *   X-API-Key: ключ авторизации
   *
   * Body:
   *   {
   *     "products": [
   *       { "kod": "12345", "name": "Товар", "group": "Сигареты", "stock": 10 }
   *     ]
   *   }
   */
  app.post('/api/shop-products/:shopId/sync', (req, res) => {
    try {
      const { shopId } = req.params;
      const apiKey = req.headers['x-api-key'];

      // Проверка API ключа
      if (!apiKey || !validateApiKey(apiKey, shopId)) {
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
      // Получаем название магазина для pending-codes
      const shopName = req.body.shopName || shopId;
      const newCodes = [];

      for (const product of normalizedProducts) {
        if (!product.kod) continue;

        // Проверяем через master_catalog_api
        const result = addPendingCode({
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

        // Отправляем push-уведомления админам (асинхронно, не блокируем ответ)
        notifyAdminsAboutNewCodes(newCodes, shopName).catch((err) => {
          console.error('[Shop Products API] Ошибка отправки push:', err.message);
        });
      }
      // ============ КОНЕЦ ДЕТЕКЦИИ ============

      // Сохраняем
      const saved = saveShopProducts(shopId, normalizedProducts);

      if (saved) {
        res.json({
          success: true,
          message: `Синхронизировано ${normalizedProducts.length} товаров`,
          productCount: normalizedProducts.length,
          newCodesCount: newCodes.length,
          newCodes: newCodes.slice(0, 10), // Первые 10 для лога
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
   * Получить все товары магазина
   * Названия подставляются из мастер-каталога если товар там найден
   */
  app.get('/api/shop-products/:shopId', (req, res) => {
    try {
      const { shopId } = req.params;
      const { group, hasStock, useMasterNames } = req.query;

      const shopData = loadShopProducts(shopId);
      let products = shopData.products || [];

      // Фильтр по группе
      if (group) {
        products = products.filter((p) => p.group === group);
      }

      // Фильтр по наличию остатка
      if (hasStock === 'true') {
        products = products.filter((p) => p.stock > 0);
      } else if (hasStock === 'false') {
        products = products.filter((p) => p.stock === 0);
      }

      // Подставляем названия из мастер-каталога (по умолчанию включено)
      if (useMasterNames !== 'false') {
        products = enrichProductsWithMasterNames(products);
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
   * Получить товары для пересчёта (только с остатком > 0)
   * Названия ВСЕГДА подставляются из мастер-каталога если товар там найден
   */
  app.get('/api/shop-products/:shopId/for-recount', (req, res) => {
    try {
      const { shopId } = req.params;
      const { group } = req.query;

      const shopData = loadShopProducts(shopId);
      let products = (shopData.products || []).filter((p) => p.stock > 0);

      // Фильтр по группе
      if (group) {
        products = products.filter((p) => p.group === group);
      }

      // Подставляем названия из мастер-каталога (для пересчёта ОБЯЗАТЕЛЬНО)
      products = enrichProductsWithMasterNames(products);

      // Сортировка по названию (уже с подставленными названиями)
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
   * Получить список групп товаров магазина
   */
  app.get('/api/shop-products/:shopId/groups', (req, res) => {
    try {
      const { shopId } = req.params;
      const shopData = loadShopProducts(shopId);
      const products = shopData.products || [];

      // Собираем уникальные группы
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
   * Получить список всех магазинов с товарами
   */
  app.get('/api/shop-products/shops/list', (req, res) => {
    try {
      const shops = getShopsWithProducts();

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
   * Общая статистика по товарам всех магазинов
   */
  app.get('/api/shop-products/stats', (req, res) => {
    try {
      const shops = getShopsWithProducts();

      let totalProducts = 0;
      let totalWithStock = 0;

      shops.forEach((shop) => {
        const shopData = loadShopProducts(shop.shopId);
        const products = shopData.products || [];
        totalProducts += products.length;
        totalWithStock += products.filter((p) => p.stock > 0).length;
      });

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
   * GET /api/shop-products/search
   * Поиск товара по всем магазинам
   */
  app.get('/api/shop-products/search', (req, res) => {
    try {
      const { q, shopId, group } = req.query;

      if (!q || q.length < 2) {
        return res.status(400).json({
          success: false,
          error: 'Поисковый запрос должен содержать минимум 2 символа',
        });
      }

      const searchLower = q.toLowerCase();
      const results = [];
      const shops = shopId ? [{ shopId }] : getShopsWithProducts();

      shops.forEach((shop) => {
        const shopData = loadShopProducts(shop.shopId);
        const products = shopData.products || [];

        products.forEach((product) => {
          // Поиск по названию или коду
          const nameMatch = product.name?.toLowerCase().includes(searchLower);
          const kodMatch = product.kod?.toLowerCase().includes(searchLower);

          if (nameMatch || kodMatch) {
            // Фильтр по группе
            if (group && product.group !== group) return;

            results.push({
              ...product,
              shopId: shop.shopId,
            });
          }
        });
      });

      // Сортировка по релевантности (точное совпадение кода первее)
      results.sort((a, b) => {
        const aExact = a.kod?.toLowerCase() === searchLower;
        const bExact = b.kod?.toLowerCase() === searchLower;
        if (aExact && !bExact) return -1;
        if (!aExact && bExact) return 1;
        return a.name.localeCompare(b.name, 'ru');
      });

      res.json({
        success: true,
        results: results.slice(0, 100), // Лимит 100 результатов
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
   * Получить список API ключей (только для админа)
   */
  app.get('/api/shop-products/api-keys', (req, res) => {
    try {
      const keys = loadApiKeys();
      // Маскируем ключи
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
   * Создать новый API ключ
   */
  app.post('/api/shop-products/api-keys', (req, res) => {
    try {
      const { shopId, description } = req.body;

      if (!shopId) {
        return res.status(400).json({ success: false, error: 'shopId обязателен' });
      }

      // Генерируем ключ
      const key = 'arabica-' + Math.random().toString(36).substring(2, 15);

      const keys = loadApiKeys();
      keys.push({
        key,
        shopId,
        description: description || '',
        createdAt: new Date().toISOString(),
      });

      const dir = path.dirname(API_KEYS_FILE);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
      fs.writeFileSync(API_KEYS_FILE, JSON.stringify({ keys }, null, 2));

      res.json({ success: true, key, shopId });
    } catch (error) {
      console.error('[Shop Products API] Ошибка создания API ключа:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('[Shop Products API] Готово');
}

module.exports = {
  setupShopProductsAPI,
  loadShopProducts,
  saveShopProducts,
  getShopsWithProducts,
};
