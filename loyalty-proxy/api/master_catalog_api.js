/**
 * Master Catalog API Module
 * API для ручного управления единым мастер-каталогом товаров
 *
 * Мастер-каталог создаётся ВРУЧНУЮ - это надёжнее чем автоматическое объединение по именам.
 * Админ создаёт карточку товара и привязывает к ней коды из разных магазинов.
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth, requireAdmin } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_MASTER_CATALOG === 'true';

// Модуль машинного зрения для подсчёта counting photos
const cigaretteVision = require('../modules/cigarette-vision');

// Директория для мастер-каталога
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const MASTER_CATALOG_DIR = `${DATA_DIR}/master-catalog`;
const PRODUCTS_FILE = path.join(MASTER_CATALOG_DIR, 'products.json');
const MAPPINGS_FILE = path.join(MASTER_CATALOG_DIR, 'mappings.json');
const PENDING_CODES_FILE = path.join(MASTER_CATALOG_DIR, 'pending-codes.json');

// Кэш
let productsCache = null;
let mappingsCache = null;
let pendingCodesCache = null;

// Кэш для training данных (тяжёлые вычисления)
// Структура: { key: { data, timestamp } }
const trainingDataCache = new Map();
const TRAINING_CACHE_TTL = 30000; // 30 секунд

/**
 * Получить данные из кэша training
 */
function getTrainingCache(key) {
  const cached = trainingDataCache.get(key);
  if (!cached) return null;
  if (Date.now() - cached.timestamp > TRAINING_CACHE_TTL) {
    trainingDataCache.delete(key);
    return null;
  }
  return cached.data;
}

/**
 * Сохранить данные в кэш training
 */
function setTrainingCache(key, data) {
  trainingDataCache.set(key, { data, timestamp: Date.now() });
}

/**
 * Очистить кэш training (вызывать при изменении данных)
 */
function clearTrainingCache() {
  trainingDataCache.clear();
}

/**
 * Загрузить продукты мастер-каталога
 */
async function loadProducts() {
  try {
    if (productsCache !== null) {
      return productsCache;
    }

    if (USE_DB) {
      const row = await db.findById('app_settings', 'master_catalog_products', 'key');
      const rawData = row && row.data;
      if (Array.isArray(rawData)) {
        productsCache = rawData;
      } else if (typeof rawData === 'string') {
        try { productsCache = JSON.parse(rawData); } catch { productsCache = []; }
        if (!Array.isArray(productsCache)) productsCache = [];
      } else {
        productsCache = [];
      }
      return productsCache;
    }

    if (!(await fileExists(PRODUCTS_FILE))) {
      return [];
    }

    const data = await fsp.readFile(PRODUCTS_FILE, 'utf8');
    const parsed = JSON.parse(data);
    productsCache = Array.isArray(parsed) ? parsed : [];
    return productsCache;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка загрузки продуктов:', error);
    return [];
  }
}

/**
 * Сохранить продукты мастер-каталога
 */
async function saveProducts(products) {
  try {
    if (!(await fileExists(MASTER_CATALOG_DIR))) {
      await fsp.mkdir(MASTER_CATALOG_DIR, { recursive: true });
    }

    await writeJsonFile(PRODUCTS_FILE, products);
    productsCache = products;
    clearTrainingCache();

    if (USE_DB) {
      try { await db.upsert('app_settings', { key: 'master_catalog_products', data: products, updated_at: new Date().toISOString() }, 'key'); }
      catch (dbErr) { console.error('DB save master_catalog_products error:', dbErr.message); }
    }

    return true;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка сохранения продуктов:', error);
    return false;
  }
}

/**
 * Загрузить маппинги (код магазина → master_id)
 */
async function loadMappings() {
  try {
    if (mappingsCache !== null) {
      return mappingsCache;
    }

    if (USE_DB) {
      const row = await db.findById('app_settings', 'master_catalog_mappings', 'key');
      mappingsCache = (row && row.data) || {};
      return mappingsCache;
    }

    if (!(await fileExists(MAPPINGS_FILE))) {
      return {};
    }

    const data = await fsp.readFile(MAPPINGS_FILE, 'utf8');
    mappingsCache = JSON.parse(data);
    return mappingsCache;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка загрузки маппингов:', error);
    return {};
  }
}

/**
 * Сохранить маппинги
 */
async function saveMappings(mappings) {
  try {
    if (!(await fileExists(MASTER_CATALOG_DIR))) {
      await fsp.mkdir(MASTER_CATALOG_DIR, { recursive: true });
    }

    await writeJsonFile(MAPPINGS_FILE, mappings);
    mappingsCache = mappings;

    if (USE_DB) {
      try { await db.upsert('app_settings', { key: 'master_catalog_mappings', data: mappings, updated_at: new Date().toISOString() }, 'key'); }
      catch (dbErr) { console.error('DB save master_catalog_mappings error:', dbErr.message); }
    }

    return true;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка сохранения маппингов:', error);
    return false;
  }
}

/**
 * Загрузить pending-коды (ожидающие подтверждения)
 */
async function loadPendingCodes() {
  try {
    if (pendingCodesCache !== null) {
      return pendingCodesCache;
    }

    if (USE_DB) {
      const row = await db.findById('app_settings', 'master_catalog_pending_codes', 'key');
      const rawData = row && row.data;
      // Защита: data может прийти как строка или объект вместо массива
      if (Array.isArray(rawData)) {
        pendingCodesCache = rawData;
      } else if (typeof rawData === 'string') {
        try { pendingCodesCache = JSON.parse(rawData); } catch { pendingCodesCache = []; }
        if (!Array.isArray(pendingCodesCache)) pendingCodesCache = [];
      } else {
        pendingCodesCache = [];
      }
      return pendingCodesCache;
    }

    if (!(await fileExists(PENDING_CODES_FILE))) {
      return [];
    }

    const data = await fsp.readFile(PENDING_CODES_FILE, 'utf8');
    const parsed = JSON.parse(data);
    pendingCodesCache = Array.isArray(parsed) ? parsed : [];
    return pendingCodesCache;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка загрузки pending-codes:', error);
    return [];
  }
}

/**
 * Сохранить pending-коды
 */
async function savePendingCodes(codes) {
  try {
    if (!(await fileExists(MASTER_CATALOG_DIR))) {
      await fsp.mkdir(MASTER_CATALOG_DIR, { recursive: true });
    }

    await writeJsonFile(PENDING_CODES_FILE, codes);
    pendingCodesCache = codes;

    if (USE_DB) {
      try { await db.upsert('app_settings', { key: 'master_catalog_pending_codes', data: codes, updated_at: new Date().toISOString() }, 'key'); }
      catch (dbErr) { console.error('DB save master_catalog_pending_codes error:', dbErr.message); }
    }

    return true;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка сохранения pending-codes:', error);
    return false;
  }
}

/**
 * Проверить, есть ли код в мастер-каталоге
 */
async function isCodeInMasterCatalog(kod) {
  const products = await loadProducts();
  return products.some((p) =>
    p.barcode === kod ||
    (p.additionalBarcodes && p.additionalBarcodes.includes(kod)) ||
    (p.shopCodes && Object.values(p.shopCodes).includes(kod))
  );
}

/**
 * Получить название товара из мастер-каталога по barcode (kod)
 * Возвращает название из мастер-каталога или null если не найден
 */
async function getMasterNameByBarcode(barcode) {
  if (!barcode) return null;
  const products = await loadProducts();
  const product = products.find((p) => p.barcode === barcode);
  return product ? product.name : null;
}

/**
 * Получить товар из мастер-каталога по barcode (kod)
 * Возвращает весь объект товара или null если не найден
 */
async function getMasterProductByBarcode(barcode) {
  if (!barcode) return null;
  const products = await loadProducts();
  return products.find((p) => p.barcode === barcode) || null;
}

/**
 * Проверить, есть ли код в pending
 */
async function isCodeInPending(kod) {
  const pending = await loadPendingCodes();
  return pending.some((p) => p.kod === kod);
}

/**
 * Добавить новый код в pending (вызывается из shop_products_api.js при sync)
 * Возвращает true если код был добавлен (новый), false если уже существует
 */
async function addPendingCode({ kod, shopId, shopName, name, group }) {
  // Проверяем, есть ли уже в мастер-каталоге
  if (await isCodeInMasterCatalog(kod)) {
    return { added: false, reason: 'in_master_catalog' };
  }

  const pending = await loadPendingCodes();
  const existingIndex = pending.findIndex((p) => p.kod === kod);

  if (existingIndex >= 0) {
    // Код уже в pending - добавляем источник если его нет
    const existing = pending[existingIndex];
    const sourceExists = existing.sources.some((s) => s.shopId === shopId);

    if (!sourceExists) {
      existing.sources.push({
        shopId,
        shopName,
        name,
        group,
        kod,
        firstSeenAt: new Date().toISOString(),
      });
      await savePendingCodes(pending);
      console.log(`[Master Catalog API] Добавлен источник ${shopId} для pending-кода ${kod}`);
    }

    return { added: false, reason: 'already_pending' };
  }

  // Новый код - добавляем в pending
  const newPending = {
    kod,
    sources: [
      {
        shopId,
        shopName,
        name,
        group,
        kod,
        firstSeenAt: new Date().toISOString(),
      },
    ],
    createdAt: new Date().toISOString(),
    notificationSent: false,
  };

  pending.push(newPending);
  await savePendingCodes(pending);

  console.log(`[Master Catalog API] Новый pending-код: ${kod} (${name}) от магазина ${shopName}`);

  return { added: true, pendingCode: newPending };
}

/**
 * Сгенерировать уникальный ID
 */
function generateId() {
  return 'master_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
}

/**
 * Обновить маппинги после изменения продукта
 */
async function updateMappingsForProduct(product) {
  const mappings = await loadMappings();

  // Удаляем старые маппинги для этого продукта
  Object.keys(mappings).forEach((key) => {
    if (mappings[key] === product.id) {
      delete mappings[key];
    }
  });

  // Добавляем новые маппинги для shopCodes
  if (product.shopCodes) {
    Object.entries(product.shopCodes).forEach(([shopId, kod]) => {
      if (kod) {
        mappings[`${shopId}:${kod}`] = product.id;
      }
    });
  }

  // Также маппим additionalBarcodes чтобы они не попадали повторно в pending
  if (product.additionalBarcodes && Array.isArray(product.additionalBarcodes)) {
    product.additionalBarcodes.forEach((barcode) => {
      if (barcode) {
        mappings[`barcode:${barcode}`] = product.id;
      }
    });
  }

  // Маппим основной barcode
  if (product.barcode) {
    mappings[`barcode:${product.barcode}`] = product.id;
  }

  await saveMappings(mappings);
}

/**
 * Настройка API для мастер-каталога
 */
function setupMasterCatalogAPI(app) {
  console.log('[Master Catalog API] Инициализация...');

  // Создаём директорию если не существует (async IIFE)
  (async () => {
    if (!(await fileExists(MASTER_CATALOG_DIR))) {
      await fsp.mkdir(MASTER_CATALOG_DIR, { recursive: true });
    }
  })();

  // ============ CRUD ПРОДУКТОВ ============

  /**
   * GET /api/master-catalog
   * Получить все продукты мастер-каталога
   */
  app.get('/api/master-catalog', requireAuth, async (req, res) => {
    try {
      const { group, search, limit, offset } = req.query;

      let products = await loadProducts();

      // Фильтр по группе
      if (group) {
        products = products.filter((p) => p.group === group);
      }

      // Поиск
      if (search && search.length >= 2) {
        const searchLower = search.toLowerCase();
        products = products.filter((p) =>
          p.name?.toLowerCase().includes(searchLower) ||
          p.barcode?.toLowerCase().includes(searchLower)
        );
      }

      // Сортировка по названию
      products.sort((a, b) => (a.name || '').localeCompare(b.name || '', 'ru'));

      const total = products.length;

      // Пагинация
      if (limit || offset) {
        const offsetNum = parseInt(offset) || 0;
        const limitNum = parseInt(limit) || 50;
        products = products.slice(offsetNum, offsetNum + limitNum);
      }

      res.json({
        success: true,
        products,
        total,
      });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка получения продуктов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ВАЖНО: Маршрут /:id перенесён в конец файла, чтобы не перехватывать конкретные пути

  /**
   * POST /api/master-catalog
   * Создать новый продукт в мастер-каталоге
   *
   * Body:
   *   {
   *     "name": "Название товара",
   *     "group": "Сигареты",
   *     "barcode": "4600000000001",
   *     "shopCodes": {
   *       "shop_1": "46210586",
   *       "shop_2": "11223344"
   *     }
   *   }
   */
  app.post('/api/master-catalog', requireAdmin, async (req, res) => {
    try {
      const { name, group, barcode, shopCodes, createdBy } = req.body;

      if (!name || !name.trim()) {
        return res.status(400).json({ success: false, error: 'Название товара обязательно' });
      }

      const products = await loadProducts();

      // Проверяем уникальность barcode
      if (barcode) {
        const existing = products.find((p) => p.barcode === barcode);
        if (existing) {
          return res.status(400).json({
            success: false,
            error: `Товар с штрих-кодом ${barcode} уже существует: ${existing.name}`,
          });
        }
      }

      const newProduct = {
        id: generateId(),
        name: name.trim(),
        group: group?.trim() || '',
        barcode: barcode?.trim() || null,
        shopCodes: shopCodes || {},
        isAiActive: false, // ИИ проверка отключена по умолчанию
        createdAt: new Date().toISOString(),
        createdBy: createdBy || 'admin',
        updatedAt: new Date().toISOString(),
      };

      products.push(newProduct);
      await saveProducts(products);

      // Обновляем маппинги
      await updateMappingsForProduct(newProduct);

      console.log(`[Master Catalog API] Создан продукт: ${newProduct.name}`);

      res.status(201).json({ success: true, product: newProduct });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка создания продукта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * PUT /api/master-catalog/:id
   * Обновить продукт
   */
  app.put('/api/master-catalog/:id', requireAdmin, async (req, res) => {
    try {
      const { name, group, barcode, shopCodes } = req.body;
      const products = await loadProducts();
      const index = products.findIndex((p) => p.id === req.params.id);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Продукт не найден' });
      }

      // Проверяем уникальность barcode (если изменился)
      if (barcode && barcode !== products[index].barcode) {
        const existing = products.find((p) => p.barcode === barcode && p.id !== req.params.id);
        if (existing) {
          return res.status(400).json({
            success: false,
            error: `Товар с штрих-кодом ${barcode} уже существует: ${existing.name}`,
          });
        }
      }

      // Обновляем поля
      if (name !== undefined) products[index].name = name.trim();
      if (group !== undefined) products[index].group = group.trim();
      if (barcode !== undefined) products[index].barcode = barcode?.trim() || null;
      if (shopCodes !== undefined) products[index].shopCodes = shopCodes;

      products[index].updatedAt = new Date().toISOString();

      await saveProducts(products);

      // Обновляем маппинги
      await updateMappingsForProduct(products[index]);

      console.log(`[Master Catalog API] Обновлён продукт: ${products[index].name}`);

      res.json({ success: true, product: products[index] });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка обновления продукта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/master-catalog/:id
   * Удалить продукт
   */
  app.delete('/api/master-catalog/:id', requireAdmin, async (req, res) => {
    try {
      const products = await loadProducts();
      const index = products.findIndex((p) => p.id === req.params.id);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Продукт не найден' });
      }

      const deleted = products.splice(index, 1)[0];
      await saveProducts(products);

      // Удаляем маппинги
      const mappings = await loadMappings();
      Object.keys(mappings).forEach((key) => {
        if (mappings[key] === deleted.id) {
          delete mappings[key];
        }
      });
      await saveMappings(mappings);

      // D2: Удаляем orphan вопросы пересчёта для этого товара
      if (deleted.barcode) {
        const { deleteQuestionsByBarcode } = require('./recount_questions_api');
        await deleteQuestionsByBarcode(deleted.barcode);
      }

      console.log(`[Master Catalog API] Удалён продукт: ${deleted.name}`);

      res.json({ success: true, deleted });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка удаления продукта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ПРИВЯЗКА КОДОВ МАГАЗИНОВ ============

  /**
   * POST /api/master-catalog/:id/link-shop-code
   * Привязать код магазина к продукту
   *
   * Body:
   *   {
   *     "shopId": "shop_1",
   *     "kod": "46210586"
   *   }
   */
  app.post('/api/master-catalog/:id/link-shop-code', requireAdmin, async (req, res) => {
    try {
      const { shopId, kod } = req.body;

      if (!shopId || !kod) {
        return res.status(400).json({ success: false, error: 'shopId и kod обязательны' });
      }

      const products = await loadProducts();
      const product = products.find((p) => p.id === req.params.id);

      if (!product) {
        return res.status(404).json({ success: false, error: 'Продукт не найден' });
      }

      // Проверяем, не привязан ли этот код к другому продукту
      const mappings = await loadMappings();
      const mappingKey = `${shopId}:${kod}`;

      if (mappings[mappingKey] && mappings[mappingKey] !== product.id) {
        const linkedProduct = products.find((p) => p.id === mappings[mappingKey]);
        return res.status(400).json({
          success: false,
          error: `Код ${kod} уже привязан к товару: ${linkedProduct?.name || 'Unknown'}`,
        });
      }

      // Привязываем код
      if (!product.shopCodes) product.shopCodes = {};
      product.shopCodes[shopId] = kod;
      product.updatedAt = new Date().toISOString();

      await saveProducts(products);
      await updateMappingsForProduct(product);

      console.log(`[Master Catalog API] Привязан код ${shopId}:${kod} к продукту ${product.name}`);

      res.json({ success: true, product });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка привязки кода:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/master-catalog/:id/unlink-shop-code/:shopId
   * Отвязать код магазина от продукта
   */
  app.delete('/api/master-catalog/:id/unlink-shop-code/:shopId', requireAdmin, async (req, res) => {
    try {
      const { id, shopId } = req.params;

      const products = await loadProducts();
      const product = products.find((p) => p.id === id);

      if (!product) {
        return res.status(404).json({ success: false, error: 'Продукт не найден' });
      }

      if (!product.shopCodes || !product.shopCodes[shopId]) {
        return res.status(404).json({ success: false, error: 'Код магазина не найден' });
      }

      // Отвязываем код
      delete product.shopCodes[shopId];
      product.updatedAt = new Date().toISOString();

      await saveProducts(products);
      await updateMappingsForProduct(product);

      console.log(`[Master Catalog API] Отвязан код ${shopId} от продукта ${product.name}`);

      res.json({ success: true, product });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка отвязки кода:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ГРУППЫ ============

  /**
   * GET /api/master-catalog/groups/list
   * Получить список групп товаров
   */
  app.get('/api/master-catalog/groups/list', requireAuth, async (req, res) => {
    try {
      const products = await loadProducts();
      const groupsSet = new Set();

      products.forEach((p) => {
        if (p.group) groupsSet.add(p.group);
      });

      const groups = Array.from(groupsSet).sort((a, b) => a.localeCompare(b, 'ru'));

      res.json({ success: true, groups, total: groups.length });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка получения групп:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ПОИСК ПО КОДУ МАГАЗИНА ============

  /**
   * GET /api/master-catalog/by-shop-code
   * Найти продукт по коду магазина
   *
   * Query:
   *   shopId: ID магазина
   *   kod: код товара в магазине
   */
  app.get('/api/master-catalog/by-shop-code', requireAuth, async (req, res) => {
    try {
      const { shopId, kod } = req.query;

      if (!shopId || !kod) {
        return res.status(400).json({ success: false, error: 'shopId и kod обязательны' });
      }

      const mappings = await loadMappings();
      const mappingKey = `${shopId}:${kod}`;
      const masterId = mappings[mappingKey];

      if (!masterId) {
        return res.json({ success: true, product: null, message: 'Продукт не найден в мастер-каталоге' });
      }

      const products = await loadProducts();
      const product = products.find((p) => p.id === masterId);

      res.json({ success: true, product: product || null });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка поиска по коду:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ СТАТИСТИКА ============

  /**
   * GET /api/master-catalog/stats
   * Статистика мастер-каталога
   */
  app.get('/api/master-catalog/stats', requireAuth, async (req, res) => {
    try {
      const products = await loadProducts();
      const mappings = await loadMappings();

      // Группы
      const groupsSet = new Set();
      products.forEach((p) => {
        if (p.group) groupsSet.add(p.group);
      });

      // Количество товаров с привязками
      const withMappings = products.filter(
        (p) => p.shopCodes && Object.keys(p.shopCodes).length > 0
      ).length;

      // Уникальные магазины
      const shopsSet = new Set();
      Object.keys(mappings).forEach((key) => {
        const shopId = key.split(':')[0];
        shopsSet.add(shopId);
      });

      res.json({
        success: true,
        stats: {
          totalProducts: products.length,
          productsWithMappings: withMappings,
          productsWithoutMappings: products.length - withMappings,
          totalGroups: groupsSet.size,
          totalMappings: Object.keys(mappings).length,
          linkedShops: shopsSet.size,
        },
      });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка получения статистики:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ PENDING CODES (новые коды из магазинов) ============

  /**
   * GET /api/master-catalog/pending-codes
   * Получить список кодов ожидающих подтверждения
   */
  app.get('/api/master-catalog/pending-codes', requireAuth, async (req, res) => {
    try {
      const pending = await loadPendingCodes();

      // Сортируем по дате (новые первыми)
      pending.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      res.json({
        success: true,
        codes: pending,
        total: pending.length,
      });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка получения pending-codes:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/master-catalog/approve-code
   * Подтвердить код и добавить в мастер-каталог
   *
   * Body:
   *   {
   *     "kod": "4620011111111",
   *     "name": "CAMEL (KS) BLUE",
   *     "group": "Сигареты"
   *   }
   */
  app.post('/api/master-catalog/approve-code', requireAdmin, async (req, res) => {
    try {
      const { kod, name, group } = req.body;

      if (!kod || !name) {
        return res.status(400).json({ success: false, error: 'kod и name обязательны' });
      }

      // Проверяем что код в pending
      const pending = await loadPendingCodes();
      const pendingIndex = pending.findIndex((p) => p.kod === kod);

      if (pendingIndex === -1) {
        return res.status(404).json({ success: false, error: 'Код не найден в pending' });
      }

      const pendingCode = pending[pendingIndex];

      // Проверяем что нет в мастер-каталоге
      const products = await loadProducts();
      const existing = products.find((p) => p.barcode === kod);

      if (existing) {
        // Удаляем из pending и возвращаем существующий
        pending.splice(pendingIndex, 1);
        await savePendingCodes(pending);
        return res.json({
          success: true,
          message: 'Код уже в мастер-каталоге',
          product: existing,
        });
      }

      // Собираем shopCodes из всех источников (используем kod каждого магазина)
      const shopCodes = {};
      pendingCode.sources.forEach((source) => {
        shopCodes[source.shopId] = source.kod || kod;
      });

      // Создаём новый продукт
      const newProduct = {
        id: generateId(),
        name: name.trim(),
        group: group?.trim() || pendingCode.sources[0]?.group || '',
        barcode: kod,
        shopCodes,
        isAiActive: false, // ИИ проверка отключена по умолчанию
        createdAt: new Date().toISOString(),
        createdBy: 'admin',
        updatedAt: new Date().toISOString(),
      };

      products.push(newProduct);
      await saveProducts(products);

      // Обновляем маппинги
      await updateMappingsForProduct(newProduct);

      // Удаляем из pending
      pending.splice(pendingIndex, 1);
      await savePendingCodes(pending);

      console.log(`[Master Catalog API] Код ${kod} подтверждён как: ${name}`);

      res.json({ success: true, product: newProduct });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка подтверждения кода:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * DELETE /api/master-catalog/pending-codes/:kod
   * Отклонить код (удалить из pending)
   */
  app.delete('/api/master-catalog/pending-codes/:kod', requireAdmin, async (req, res) => {
    try {
      const { kod } = req.params;

      const pending = await loadPendingCodes();
      const index = pending.findIndex((p) => p.kod === kod);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Код не найден в pending' });
      }

      const deleted = pending.splice(index, 1)[0];
      await savePendingCodes(pending);

      console.log(`[Master Catalog API] Код ${kod} отклонён`);

      res.json({ success: true, deleted });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка удаления pending-кода:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/master-catalog/bulk-import
   * Массовый импорт товаров в мастер-каталог
   *
   * Body:
   *   {
   *     "products": [
   *       { "name": "...", "barcode": "...", "group": "..." },
   *       ...
   *     ],
   *     "skipExisting": true  // пропускать существующие (по barcode)
   *   }
   */
  app.post('/api/master-catalog/bulk-import', requireAdmin, async (req, res) => {
    try {
      const { products: inputProducts, skipExisting = true } = req.body;

      if (!inputProducts || !Array.isArray(inputProducts)) {
        return res.status(400).json({ success: false, error: 'products должен быть массивом' });
      }

      const existingProducts = await loadProducts();
      const existingBarcodes = new Set(existingProducts.filter((p) => p.barcode).map((p) => p.barcode));

      let added = 0;
      let skipped = 0;
      let errors = 0;

      inputProducts.forEach((input) => {
        if (!input.name || !input.barcode) {
          errors++;
          return;
        }

        if (existingBarcodes.has(input.barcode)) {
          if (skipExisting) {
            skipped++;
            return;
          } else {
            // Обновляем существующий
            const existing = existingProducts.find((p) => p.barcode === input.barcode);
            if (existing) {
              existing.name = input.name.trim();
              if (input.group) existing.group = input.group.trim();
              existing.updatedAt = new Date().toISOString();
            }
            return;
          }
        }

        // Создаём новый
        const newProduct = {
          id: generateId(),
          name: input.name.trim(),
          group: input.group?.trim() || '',
          barcode: input.barcode.trim(),
          shopCodes: {},
          isAiActive: false, // ИИ проверка отключена по умолчанию
          createdAt: new Date().toISOString(),
          createdBy: 'bulk-import',
          updatedAt: new Date().toISOString(),
        };

        existingProducts.push(newProduct);
        existingBarcodes.add(newProduct.barcode);
        added++;
      });

      await saveProducts(existingProducts);

      console.log(`[Master Catalog API] Bulk import: добавлено ${added}, пропущено ${skipped}, ошибок ${errors}`);

      res.json({
        success: true,
        added,
        skipped,
        errors,
        total: existingProducts.length,
      });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка bulk import:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/master-catalog/pending-codes/:kod/mark-notified
   * Пометить pending-код как отправивший уведомление
   */
  app.post('/api/master-catalog/pending-codes/:kod/mark-notified', requireAdmin, async (req, res) => {
    try {
      const { kod } = req.params;

      const pending = await loadPendingCodes();
      const pendingCode = pending.find((p) => p.kod === kod);

      if (!pendingCode) {
        return res.status(404).json({ success: false, error: 'Код не найден в pending' });
      }

      pendingCode.notificationSent = true;
      await savePendingCodes(pending);

      res.json({ success: true });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка mark-notified:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ AI STATUS ============

  /**
   * PATCH /api/master-catalog/:id/ai-status
   * Изменить статус ИИ проверки для товара
   *
   * Body:
   *   { "isAiActive": true/false }
   */
  app.patch('/api/master-catalog/:id/ai-status', requireAdmin, async (req, res) => {
    try {
      const { isAiActive } = req.body;

      if (typeof isAiActive !== 'boolean') {
        return res.status(400).json({ success: false, error: 'isAiActive должен быть boolean' });
      }

      const products = await loadProducts();
      const product = products.find((p) => p.id === req.params.id);

      if (!product) {
        return res.status(404).json({ success: false, error: 'Продукт не найден' });
      }

      product.isAiActive = isAiActive;
      product.updatedAt = new Date().toISOString();

      await saveProducts(products);

      console.log(`[Master Catalog API] AI статус для ${product.name}: ${isAiActive ? 'активна' : 'неактивна'}`);

      res.json({ success: true, product });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка изменения AI статуса:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ДЛЯ AI TRAINING ============

  /**
   * GET /api/master-catalog/for-training
   * Получить товары для AI обучения с per-shop статистикой
   * Поддерживает пагинацию: limit, offset
   * Поддерживает кэширование (TTL 30 сек) для ускорения повторных запросов
   */
  app.get('/api/master-catalog/for-training', requireAuth, async (req, res) => {
    try {
      const { productGroup, shopAddress, limit, offset, grouped } = req.query;
      // shopAddress - если передан, возвращаем perShopDisplayStats только для этого магазина
      // Это критически важно для производительности при 100+ магазинах
      const filterShopAddress = shopAddress ? decodeURIComponent(shopAddress) : null;

      // Пагинация
      const pageLimit = limit ? parseInt(limit, 10) : null;
      const pageOffset = offset ? parseInt(offset, 10) : 0;

      // Кэш-ключ на основе параметров (без пагинации - кэшируем полный список)
      const isGrouped = grouped !== 'false';
      const cacheKey = `training_${productGroup || 'all'}_${filterShopAddress || 'all'}_${isGrouped ? 'grouped' : 'flat'}`;

      // Пробуем получить из кэша
      let trainingProducts = getTrainingCache(cacheKey);

      if (!trainingProducts) {
        // Кэш пуст - вычисляем данные
        const startTime = Date.now();

        let products = await loadProducts();

        // Фильтр по группе
        if (productGroup) {
          products = products.filter((p) => p.group === productGroup);
        }

        // Загружаем данные для статистики из cigarette-vision
        const samples = await cigaretteVision.loadSamples();
      const settings = await cigaretteVision.getSettings();
      const shops = await cigaretteVision.loadAllShops();

      // Загружаем статистику распознаваний (accuracy)
      const allRecognitionStats = await cigaretteVision.getAllRecognitionStats();

      const requiredRecount = settings.requiredRecountPhotos || 10;
      const requiredDisplayPerShop = settings.requiredDisplayPhotosPerShop || 3;
      const requiredCounting = settings.requiredCountingPhotos || 10;

      // Загружаем counting samples (фото с пересчёта - подтверждённые)
      const countingSamples = await cigaretteVision.loadTypedSamples(cigaretteVision.TRAINING_TYPES.COUNTING);
      // Загружаем pending counting samples (ожидающие подтверждения админа)
      const pendingCountingSamples = await cigaretteVision.getAllPendingCountingSamples();

      // Подсчёт фото по товарам
      const recountPhotosByProduct = {};
      const completedTemplatesByProduct = {};
      const displayPhotosByProductAndShop = {};
      const countingPhotosByProduct = {};
      const pendingCountingPhotosByProduct = {};

      // Lookup фото товара: первое фото крупного плана (templateId === 1) = фото лицевой стороны
      const productPhotoUrlMap = {};
      samples.forEach(sample => {
        if (sample.templateId === 1 && (!sample.type || sample.type === 'recount')) {
          const productId = sample.productId;
          const barcode = sample.barcode;
          if (productId && !productPhotoUrlMap[productId]) {
            productPhotoUrlMap[productId] = sample.imageUrl;
          }
          if (barcode && barcode !== productId && !productPhotoUrlMap[barcode]) {
            productPhotoUrlMap[barcode] = sample.imageUrl;
          }
        }
      });

      // Подсчёт counting photos (подтверждённые)
      countingSamples.forEach(sample => {
        const productId = sample.productId;
        const barcode = sample.barcode;
        if (productId) {
          countingPhotosByProduct[productId] = (countingPhotosByProduct[productId] || 0) + 1;
        }
        if (barcode && barcode !== productId) {
          countingPhotosByProduct[barcode] = (countingPhotosByProduct[barcode] || 0) + 1;
        }
      });

      // Подсчёт pending counting photos (ожидающие подтверждения)
      pendingCountingSamples.forEach(sample => {
        const productId = sample.productId;
        const barcode = sample.barcode;
        if (productId) {
          pendingCountingPhotosByProduct[productId] = (pendingCountingPhotosByProduct[productId] || 0) + 1;
        }
        if (barcode && barcode !== productId) {
          pendingCountingPhotosByProduct[barcode] = (pendingCountingPhotosByProduct[barcode] || 0) + 1;
        }
      });

      samples.forEach(sample => {
        const productId = sample.productId;
        const barcode = sample.barcode;

        if (sample.type === 'display') {
          if (sample.shopAddress) {
            if (productId) {
              const keyById = `${productId}|${sample.shopAddress}`;
              displayPhotosByProductAndShop[keyById] = (displayPhotosByProductAndShop[keyById] || 0) + 1;
            }
            if (barcode && barcode !== productId) {
              const keyByBarcode = `${barcode}|${sample.shopAddress}`;
              displayPhotosByProductAndShop[keyByBarcode] = (displayPhotosByProductAndShop[keyByBarcode] || 0) + 1;
            }
          }
        } else {
          if (productId) {
            recountPhotosByProduct[productId] = (recountPhotosByProduct[productId] || 0) + 1;
          }
          if (barcode && barcode !== productId) {
            recountPhotosByProduct[barcode] = (recountPhotosByProduct[barcode] || 0) + 1;
          }

          if (sample.templateId) {
            const key = productId || barcode;
            if (!completedTemplatesByProduct[key]) {
              completedTemplatesByProduct[key] = new Set();
            }
            completedTemplatesByProduct[key].add(sample.templateId);
            if (barcode && barcode !== key) {
              if (!completedTemplatesByProduct[barcode]) {
                completedTemplatesByProduct[barcode] = new Set();
              }
              completedTemplatesByProduct[barcode].add(sample.templateId);
            }
          }
        }
      });

      // Преобразуем в формат для AI Training с per-shop статистикой
      trainingProducts = products.map((p) => {
        const recountPhotos = recountPhotosByProduct[p.id] || recountPhotosByProduct[p.barcode] || 0;
        const countingPhotos = countingPhotosByProduct[p.id] || countingPhotosByProduct[p.barcode] || 0;
        const pendingCountingPhotos = pendingCountingPhotosByProduct[p.id] || pendingCountingPhotosByProduct[p.barcode] || 0;

        // Получаем статистику распознаваний (accuracy)
        const recognitionStats = allRecognitionStats[p.id] || allRecognitionStats[p.barcode] || {
          display: { accuracy: null, attempts: 0, successes: 0 },
          counting: { accuracy: null, attempts: 0, successes: 0 },
        };
        const completedTemplatesSet = completedTemplatesByProduct[p.id] || completedTemplatesByProduct[p.barcode] || new Set();
        const completedTemplates = Array.from(completedTemplatesSet).sort((a, b) => a - b);
        const isRecountComplete = completedTemplates.length >= requiredRecount;
        const isCountingComplete = countingPhotos >= requiredCounting;

        // Per-shop статистика для выкладки
        // ОПТИМИЗАЦИЯ: Если передан filterShopAddress, возвращаем только статистику для этого магазина
        // Это уменьшает размер ответа с 7MB до ~100KB при 100 магазинах
        const shopsToProcess = filterShopAddress
          ? shops.filter(s => s.address === filterShopAddress)
          : shops;

        const perShopDisplayStats = shopsToProcess.map(shop => {
          const keyById = `${p.id}|${shop.address}`;
          const keyByBarcode = `${p.barcode}|${shop.address}`;
          const count = displayPhotosByProductAndShop[keyById] || displayPhotosByProductAndShop[keyByBarcode] || 0;
          return {
            shopAddress: shop.address,
            shopName: shop.name,
            shopId: shop.id,
            displayPhotosCount: count,
            requiredDisplayPhotos: requiredDisplayPerShop,
            isDisplayComplete: count >= requiredDisplayPerShop,
          };
        });

        // Для totalDisplayPhotos и shopsWithAiReady нужны данные по ВСЕМ магазинам
        // даже если фильтруем perShopDisplayStats
        let totalDisplayPhotos = 0;
        let shopsWithAiReady = 0;
        shops.forEach(shop => {
          const keyById = `${p.id}|${shop.address}`;
          const keyByBarcode = `${p.barcode}|${shop.address}`;
          const count = displayPhotosByProductAndShop[keyById] || displayPhotosByProductAndShop[keyByBarcode] || 0;
          totalDisplayPhotos += count;
          if (count >= requiredDisplayPerShop) {
            shopsWithAiReady++;
          }
        });
        const isDisplayComplete = shopsWithAiReady > 0;

        return {
          id: p.id,
          productName: p.name,
          productGroup: p.group,
          group: p.group,
          barcode: p.barcode,
          grade: 1,
          isAiActive: p.isAiActive ?? false,
          // Общая статистика
          trainingPhotosCount: recountPhotos + totalDisplayPhotos,
          requiredPhotosCount: requiredRecount + requiredDisplayPerShop,
          isTrainingComplete: isRecountComplete && isDisplayComplete,
          // Крупный план (общий для всех магазинов)
          recountPhotosCount: recountPhotos,
          requiredRecountPhotos: requiredRecount,
          isRecountComplete: isRecountComplete,
          completedTemplates: completedTemplates,
          // Выкладка - общая статистика
          displayPhotosCount: totalDisplayPhotos,
          requiredDisplayPhotos: requiredDisplayPerShop,
          isDisplayComplete: isDisplayComplete,
          // Пересчёт (counting) - фото с пересчёта для обучения
          countingPhotosCount: countingPhotos,
          pendingCountingPhotosCount: pendingCountingPhotos,  // Ожидающие подтверждения админа
          requiredCountingPhotos: requiredCounting,
          isCountingComplete: isCountingComplete,
          // Per-shop статистика выкладки
          perShopDisplayStats: perShopDisplayStats,
          totalDisplayPhotos: totalDisplayPhotos,
          requiredDisplayPhotosPerShop: requiredDisplayPerShop,
          shopsWithAiReady: shopsWithAiReady,
          totalShops: shops.length,
          shopCodes: p.shopCodes,
          // Статистика точности распознавания ИИ
          displayAccuracy: recognitionStats.display.accuracy,
          displayAttempts: recognitionStats.display.attempts,
          displaySuccesses: recognitionStats.display.successes,
          countingAccuracy: recognitionStats.counting.accuracy,
          countingAttempts: recognitionStats.counting.attempts,
          countingSuccesses: recognitionStats.counting.successes,
          // Фото товара (первое фото крупного плана, templateId=1)
          productPhotoUrl: productPhotoUrlMap[p.id] || productPhotoUrlMap[p.barcode] || null,
        };
      });

      // Группировка товаров по имени (exact match, case-sensitive)
      // grouped=false отключает группировку (по умолчанию true)
      if (grouped !== 'false') {
        const groupedMap = new Map();
        trainingProducts.forEach(p => {
          const key = p.productName;
          if (groupedMap.has(key)) {
            const g = groupedMap.get(key);
            g.barcodes.push(p.barcode);
            g.ids.push(p.id);
            // Суммируем статистику
            g.recountPhotosCount += p.recountPhotosCount;
            g.displayPhotosCount += p.displayPhotosCount;
            g.countingPhotosCount += p.countingPhotosCount;
            g.pendingCountingPhotosCount += p.pendingCountingPhotosCount;
            g.totalDisplayPhotos += p.totalDisplayPhotos;
            g.trainingPhotosCount += p.trainingPhotosCount;
            // Объединяем completedTemplates (union)
            p.completedTemplates.forEach(t => g._completedSet.add(t));
            // Объединяем perShopDisplayStats (берём максимальные значения)
            p.perShopDisplayStats.forEach(shopStat => {
              const existing = g.perShopDisplayStats.find(s => s.shopAddress === shopStat.shopAddress);
              if (existing) {
                existing.displayPhotosCount += shopStat.displayPhotosCount;
                existing.isDisplayComplete = existing.displayPhotosCount >= existing.requiredDisplayPhotos;
              } else {
                g.perShopDisplayStats.push({ ...shopStat });
              }
            });
            g.shopsWithAiReady = g.perShopDisplayStats.filter(s => s.isDisplayComplete).length;
            // Берём первый доступный productPhotoUrl
            if (!g.productPhotoUrl && p.productPhotoUrl) {
              g.productPhotoUrl = p.productPhotoUrl;
            }
            // Объединяем accuracy (суммируем attempts/successes)
            g.displayAttempts += p.displayAttempts;
            g.displaySuccesses += p.displaySuccesses;
            g.countingAttempts += p.countingAttempts;
            g.countingSuccesses += p.countingSuccesses;
          } else {
            groupedMap.set(key, {
              ...p,
              barcodes: [p.barcode],
              ids: [p.id],
              _completedSet: new Set(p.completedTemplates),
            });
          }
        });
        // Финализация: completedTemplates из Set, пересчёт accuracy и флагов
        trainingProducts = Array.from(groupedMap.values()).map(g => {
          g.completedTemplates = Array.from(g._completedSet).sort((a, b) => a - b);
          delete g._completedSet;
          g.isRecountComplete = g.completedTemplates.length >= requiredRecount;
          g.isCountingComplete = g.countingPhotosCount >= requiredCounting;
          g.isDisplayComplete = g.shopsWithAiReady > 0;
          g.isTrainingComplete = g.isRecountComplete && g.isDisplayComplete;
          g.displayAccuracy = g.displayAttempts > 0 ? Math.round(g.displaySuccesses / g.displayAttempts * 100) : null;
          g.countingAccuracy = g.countingAttempts > 0 ? Math.round(g.countingSuccesses / g.countingAttempts * 100) : null;
          return g;
        });
      } else {
        // Без группировки — оборачиваем barcode в массив для единообразия
        trainingProducts = trainingProducts.map(p => ({
          ...p,
          barcodes: [p.barcode],
          ids: [p.id],
        }));
      }

        // Сохраняем в кэш
        setTrainingCache(cacheKey, trainingProducts);
        console.log(`[Master Catalog API] for-training: вычислено за ${Date.now() - startTime}ms, закэшировано`);
      } // конец блока if (!trainingProducts)

      // Общее количество товаров (до пагинации)
      const total = trainingProducts.length;

      // Применяем пагинацию
      let paginatedProducts = trainingProducts;
      if (pageLimit) {
        paginatedProducts = trainingProducts.slice(pageOffset, pageOffset + pageLimit);
      }

      res.json({
        success: true,
        products: paginatedProducts,
        total: total,
        offset: pageOffset,
        limit: pageLimit,
        cached: !!getTrainingCache(cacheKey),
      });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка получения товаров для обучения:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ПОИСК ДЛЯ ПРИВЯЗКИ КОДА К СУЩЕСТВУЮЩЕМУ ТОВАРУ ============

  /**
   * GET /api/master-catalog/search-for-assign
   * Лёгкий поиск товаров для привязки pending-кода к существующей карточке
   * Возвращает: id, name, group, barcode, additionalBarcodes, barcodesCount, productPhotoUrl
   */
  app.get('/api/master-catalog/search-for-assign', requireAuth, async (req, res) => {
    try {
      const { search } = req.query;
      if (!search || search.length < 2) {
        return res.json({ success: true, products: [] });
      }

      let products = await loadProducts();
      const searchLower = search.toLowerCase();
      products = products.filter(p =>
        p.name?.toLowerCase().includes(searchLower) ||
        p.barcode?.toLowerCase().includes(searchLower) ||
        (p.additionalBarcodes || []).some(b => b.toLowerCase().includes(searchLower))
      );

      // Группируем по имени (exact match) для показа объединённых карточек
      const groupedMap = new Map();
      products.forEach(p => {
        const key = p.name;
        if (groupedMap.has(key)) {
          const g = groupedMap.get(key);
          g.barcodes.push(p.barcode);
          if (p.additionalBarcodes) g.barcodes.push(...p.additionalBarcodes);
          g.ids.push(p.id);
        } else {
          groupedMap.set(key, {
            id: p.id,
            name: p.name,
            group: p.group,
            barcode: p.barcode,
            barcodes: [p.barcode, ...(p.additionalBarcodes || [])],
            ids: [p.id],
            productPhotoUrl: null, // Заполним ниже
          });
        }
      });

      // Добавляем productPhotoUrl из samples
      const samples = await cigaretteVision.loadSamples();
      const photoMap = {};
      (samples || []).forEach(s => {
        if (s.templateId === 1 && (!s.type || s.type === 'recount')) {
          const key = s.productId || s.barcode;
          if (!photoMap[key]) photoMap[key] = s.imageUrl;
        }
      });

      const result = Array.from(groupedMap.values()).slice(0, 20).map(g => ({
        id: g.id,
        name: g.name,
        group: g.group,
        barcode: g.barcode,
        barcodes: g.barcodes,
        ids: g.ids,
        barcodesCount: g.barcodes.length,
        productPhotoUrl: photoMap[g.id] || photoMap[g.barcode] || null,
      }));

      res.json({ success: true, products: result });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка поиска для привязки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  /**
   * POST /api/master-catalog/assign-code-to-product
   * Привязать pending-код к существующему товару
   *
   * Body: { kod: "4620011111111", targetProductId: "master_..." }
   */
  app.post('/api/master-catalog/assign-code-to-product', requireAdmin, async (req, res) => {
    try {
      const { kod, targetProductId } = req.body;

      if (!kod || !targetProductId) {
        return res.status(400).json({ success: false, error: 'kod и targetProductId обязательны' });
      }

      // Найти pending code
      const pending = await loadPendingCodes();
      const pendingIndex = pending.findIndex(p => p.kod === kod);
      if (pendingIndex === -1) {
        return res.status(404).json({ success: false, error: 'Код не найден в pending' });
      }
      const pendingCode = pending[pendingIndex];

      // Найти target product
      const products = await loadProducts();
      const product = products.find(p => p.id === targetProductId);
      if (!product) {
        return res.status(404).json({ success: false, error: 'Целевой продукт не найден' });
      }

      // Добавить штрихкод в additionalBarcodes
      if (!product.additionalBarcodes) product.additionalBarcodes = [];
      if (!product.additionalBarcodes.includes(kod) && product.barcode !== kod) {
        product.additionalBarcodes.push(kod);
      }

      // Перенести shopCodes из sources pending code (используем kod каждого магазина)
      if (!product.shopCodes) product.shopCodes = {};
      pendingCode.sources.forEach(source => {
        product.shopCodes[source.shopId] = source.kod || kod;
      });

      product.updatedAt = new Date().toISOString();
      await saveProducts(products);
      await updateMappingsForProduct(product);

      // Удалить из pending
      pending.splice(pendingIndex, 1);
      await savePendingCodes(pending);

      // Очистить кэш training данных
      clearTrainingCache();

      console.log(`[Master Catalog API] Код ${kod} привязан к продукту "${product.name}"`);
      res.json({ success: true, product });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка привязки кода:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ФОТО ТОВАРОВ ИЗ ОБУЧЕНИЯ ИИ ============

  /**
   * GET /api/master-catalog/product-photos
   * Лёгкий эндпоинт: возвращает Map barcode → productPhotoUrl
   * Фото = первый sample с templateId=5 (очень крупно, 70% кадра)
   */
  app.get('/api/master-catalog/product-photos', requireAuth, async (req, res) => {
    try {
      const samples = await cigaretteVision.loadSamples();
      const photos = {};
      (samples || []).forEach(s => {
        if (s.templateId === 5 && (!s.type || s.type === 'recount')) {
          const productId = s.productId;
          const barcode = s.barcode;
          if (productId && !photos[productId]) photos[productId] = s.imageUrl;
          if (barcode && barcode !== productId && !photos[barcode]) photos[barcode] = s.imageUrl;
        }
      });
      res.json({ success: true, photos });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка загрузки фото товаров:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ПАРАМЕТРИЗОВАННЫЕ МАРШРУТЫ (ДОЛЖНЫ БЫТЬ В КОНЦЕ!) ============

  /**
   * GET /api/master-catalog/:id
   * Получить продукт по ID
   * ВАЖНО: Этот маршрут должен быть ПОСЛЕ всех конкретных путей!
   */
  app.get('/api/master-catalog/:id', requireAuth, async (req, res) => {
    try {
      const products = await loadProducts();
      const product = products.find((p) => p.id === req.params.id);

      if (!product) {
        return res.status(404).json({ success: false, error: 'Продукт не найден' });
      }

      res.json({ success: true, product });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка получения продукта:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ОЧИСТКА КЭША ============

  /**
   * POST /api/master-catalog/clear-cache
   * Очистить кэш training данных (для принудительного обновления)
   */
  app.post('/api/master-catalog/clear-cache', requireAdmin, (req, res) => {
    try {
      clearTrainingCache();
      res.json({ success: true, message: 'Кэш очищен' });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`[Master Catalog API] Готово ${USE_DB ? '(DB mode)' : '(file mode)'} (с кэшированием TTL 30s)`);
}

module.exports = {
  setupMasterCatalogAPI,
  loadProducts,
  saveProducts,
  loadMappings,
  saveMappings,
  loadPendingCodes,
  savePendingCodes,
  addPendingCode,
  isCodeInMasterCatalog,
  isCodeInPending,
  getMasterNameByBarcode,
  getMasterProductByBarcode,
  clearTrainingCache,
};
