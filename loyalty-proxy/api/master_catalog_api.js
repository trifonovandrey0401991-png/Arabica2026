/**
 * Master Catalog API Module
 * API для ручного управления единым мастер-каталогом товаров
 *
 * Мастер-каталог создаётся ВРУЧНУЮ - это надёжнее чем автоматическое объединение по именам.
 * Админ создаёт карточку товара и привязывает к ней коды из разных магазинов.
 */

const fs = require('fs');
const path = require('path');

// Директория для мастер-каталога
const MASTER_CATALOG_DIR = '/var/www/master-catalog';
const PRODUCTS_FILE = path.join(MASTER_CATALOG_DIR, 'products.json');
const MAPPINGS_FILE = path.join(MASTER_CATALOG_DIR, 'mappings.json');
const PENDING_CODES_FILE = path.join(MASTER_CATALOG_DIR, 'pending-codes.json');

// Кэш
let productsCache = null;
let mappingsCache = null;
let pendingCodesCache = null;

/**
 * Загрузить продукты мастер-каталога
 */
function loadProducts() {
  try {
    if (productsCache !== null) {
      return productsCache;
    }

    if (!fs.existsSync(PRODUCTS_FILE)) {
      return [];
    }

    const data = fs.readFileSync(PRODUCTS_FILE, 'utf8');
    productsCache = JSON.parse(data);
    return productsCache;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка загрузки продуктов:', error);
    return [];
  }
}

/**
 * Сохранить продукты мастер-каталога
 */
function saveProducts(products) {
  try {
    if (!fs.existsSync(MASTER_CATALOG_DIR)) {
      fs.mkdirSync(MASTER_CATALOG_DIR, { recursive: true });
    }

    fs.writeFileSync(PRODUCTS_FILE, JSON.stringify(products, null, 2));
    productsCache = products;
    return true;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка сохранения продуктов:', error);
    return false;
  }
}

/**
 * Загрузить маппинги (код магазина → master_id)
 */
function loadMappings() {
  try {
    if (mappingsCache !== null) {
      return mappingsCache;
    }

    if (!fs.existsSync(MAPPINGS_FILE)) {
      return {};
    }

    const data = fs.readFileSync(MAPPINGS_FILE, 'utf8');
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
function saveMappings(mappings) {
  try {
    if (!fs.existsSync(MASTER_CATALOG_DIR)) {
      fs.mkdirSync(MASTER_CATALOG_DIR, { recursive: true });
    }

    fs.writeFileSync(MAPPINGS_FILE, JSON.stringify(mappings, null, 2));
    mappingsCache = mappings;
    return true;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка сохранения маппингов:', error);
    return false;
  }
}

/**
 * Загрузить pending-коды (ожидающие подтверждения)
 */
function loadPendingCodes() {
  try {
    if (pendingCodesCache !== null) {
      return pendingCodesCache;
    }

    if (!fs.existsSync(PENDING_CODES_FILE)) {
      return [];
    }

    const data = fs.readFileSync(PENDING_CODES_FILE, 'utf8');
    pendingCodesCache = JSON.parse(data);
    return pendingCodesCache;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка загрузки pending-codes:', error);
    return [];
  }
}

/**
 * Сохранить pending-коды
 */
function savePendingCodes(codes) {
  try {
    if (!fs.existsSync(MASTER_CATALOG_DIR)) {
      fs.mkdirSync(MASTER_CATALOG_DIR, { recursive: true });
    }

    fs.writeFileSync(PENDING_CODES_FILE, JSON.stringify(codes, null, 2));
    pendingCodesCache = codes;
    return true;
  } catch (error) {
    console.error('[Master Catalog API] Ошибка сохранения pending-codes:', error);
    return false;
  }
}

/**
 * Проверить, есть ли код в мастер-каталоге
 */
function isCodeInMasterCatalog(kod) {
  const products = loadProducts();
  return products.some((p) => p.barcode === kod);
}

/**
 * Проверить, есть ли код в pending
 */
function isCodeInPending(kod) {
  const pending = loadPendingCodes();
  return pending.some((p) => p.kod === kod);
}

/**
 * Добавить новый код в pending (вызывается из shop_products_api.js при sync)
 * Возвращает true если код был добавлен (новый), false если уже существует
 */
function addPendingCode({ kod, shopId, shopName, name, group }) {
  // Проверяем, есть ли уже в мастер-каталоге
  if (isCodeInMasterCatalog(kod)) {
    return { added: false, reason: 'in_master_catalog' };
  }

  const pending = loadPendingCodes();
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
        firstSeenAt: new Date().toISOString(),
      });
      savePendingCodes(pending);
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
        firstSeenAt: new Date().toISOString(),
      },
    ],
    createdAt: new Date().toISOString(),
    notificationSent: false,
  };

  pending.push(newPending);
  savePendingCodes(pending);

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
function updateMappingsForProduct(product) {
  const mappings = loadMappings();

  // Удаляем старые маппинги для этого продукта
  Object.keys(mappings).forEach((key) => {
    if (mappings[key] === product.id) {
      delete mappings[key];
    }
  });

  // Добавляем новые маппинги
  if (product.shopCodes) {
    Object.entries(product.shopCodes).forEach(([shopId, kod]) => {
      if (kod) {
        mappings[`${shopId}:${kod}`] = product.id;
      }
    });
  }

  saveMappings(mappings);
}

/**
 * Настройка API для мастер-каталога
 */
function setupMasterCatalogAPI(app) {
  console.log('[Master Catalog API] Инициализация...');

  // Создаём директорию если не существует
  if (!fs.existsSync(MASTER_CATALOG_DIR)) {
    fs.mkdirSync(MASTER_CATALOG_DIR, { recursive: true });
  }

  // ============ CRUD ПРОДУКТОВ ============

  /**
   * GET /api/master-catalog
   * Получить все продукты мастер-каталога
   */
  app.get('/api/master-catalog', (req, res) => {
    try {
      const { group, search, limit, offset } = req.query;

      let products = loadProducts();

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

  /**
   * GET /api/master-catalog/:id
   * Получить продукт по ID
   */
  app.get('/api/master-catalog/:id', (req, res) => {
    try {
      const products = loadProducts();
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
  app.post('/api/master-catalog', (req, res) => {
    try {
      const { name, group, barcode, shopCodes, createdBy } = req.body;

      if (!name || !name.trim()) {
        return res.status(400).json({ success: false, error: 'Название товара обязательно' });
      }

      const products = loadProducts();

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
        createdAt: new Date().toISOString(),
        createdBy: createdBy || 'admin',
        updatedAt: new Date().toISOString(),
      };

      products.push(newProduct);
      saveProducts(products);

      // Обновляем маппинги
      updateMappingsForProduct(newProduct);

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
  app.put('/api/master-catalog/:id', (req, res) => {
    try {
      const { name, group, barcode, shopCodes } = req.body;
      const products = loadProducts();
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

      saveProducts(products);

      // Обновляем маппинги
      updateMappingsForProduct(products[index]);

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
  app.delete('/api/master-catalog/:id', (req, res) => {
    try {
      const products = loadProducts();
      const index = products.findIndex((p) => p.id === req.params.id);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Продукт не найден' });
      }

      const deleted = products.splice(index, 1)[0];
      saveProducts(products);

      // Удаляем маппинги
      const mappings = loadMappings();
      Object.keys(mappings).forEach((key) => {
        if (mappings[key] === deleted.id) {
          delete mappings[key];
        }
      });
      saveMappings(mappings);

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
  app.post('/api/master-catalog/:id/link-shop-code', (req, res) => {
    try {
      const { shopId, kod } = req.body;

      if (!shopId || !kod) {
        return res.status(400).json({ success: false, error: 'shopId и kod обязательны' });
      }

      const products = loadProducts();
      const product = products.find((p) => p.id === req.params.id);

      if (!product) {
        return res.status(404).json({ success: false, error: 'Продукт не найден' });
      }

      // Проверяем, не привязан ли этот код к другому продукту
      const mappings = loadMappings();
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

      saveProducts(products);
      updateMappingsForProduct(product);

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
  app.delete('/api/master-catalog/:id/unlink-shop-code/:shopId', (req, res) => {
    try {
      const { id, shopId } = req.params;

      const products = loadProducts();
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

      saveProducts(products);
      updateMappingsForProduct(product);

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
  app.get('/api/master-catalog/groups/list', (req, res) => {
    try {
      const products = loadProducts();
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
  app.get('/api/master-catalog/by-shop-code', (req, res) => {
    try {
      const { shopId, kod } = req.query;

      if (!shopId || !kod) {
        return res.status(400).json({ success: false, error: 'shopId и kod обязательны' });
      }

      const mappings = loadMappings();
      const mappingKey = `${shopId}:${kod}`;
      const masterId = mappings[mappingKey];

      if (!masterId) {
        return res.json({ success: true, product: null, message: 'Продукт не найден в мастер-каталоге' });
      }

      const products = loadProducts();
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
  app.get('/api/master-catalog/stats', (req, res) => {
    try {
      const products = loadProducts();
      const mappings = loadMappings();

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
  app.get('/api/master-catalog/pending-codes', (req, res) => {
    try {
      const pending = loadPendingCodes();

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
  app.post('/api/master-catalog/approve-code', (req, res) => {
    try {
      const { kod, name, group } = req.body;

      if (!kod || !name) {
        return res.status(400).json({ success: false, error: 'kod и name обязательны' });
      }

      // Проверяем что код в pending
      const pending = loadPendingCodes();
      const pendingIndex = pending.findIndex((p) => p.kod === kod);

      if (pendingIndex === -1) {
        return res.status(404).json({ success: false, error: 'Код не найден в pending' });
      }

      const pendingCode = pending[pendingIndex];

      // Проверяем что нет в мастер-каталоге
      const products = loadProducts();
      const existing = products.find((p) => p.barcode === kod);

      if (existing) {
        // Удаляем из pending и возвращаем существующий
        pending.splice(pendingIndex, 1);
        savePendingCodes(pending);
        return res.json({
          success: true,
          message: 'Код уже в мастер-каталоге',
          product: existing,
        });
      }

      // Собираем shopCodes из всех источников
      const shopCodes = {};
      pendingCode.sources.forEach((source) => {
        shopCodes[source.shopId] = kod;
      });

      // Создаём новый продукт
      const newProduct = {
        id: generateId(),
        name: name.trim(),
        group: group?.trim() || pendingCode.sources[0]?.group || '',
        barcode: kod,
        shopCodes,
        createdAt: new Date().toISOString(),
        createdBy: 'admin',
        updatedAt: new Date().toISOString(),
      };

      products.push(newProduct);
      saveProducts(products);

      // Обновляем маппинги
      updateMappingsForProduct(newProduct);

      // Удаляем из pending
      pending.splice(pendingIndex, 1);
      savePendingCodes(pending);

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
  app.delete('/api/master-catalog/pending-codes/:kod', (req, res) => {
    try {
      const { kod } = req.params;

      const pending = loadPendingCodes();
      const index = pending.findIndex((p) => p.kod === kod);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Код не найден в pending' });
      }

      const deleted = pending.splice(index, 1)[0];
      savePendingCodes(pending);

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
  app.post('/api/master-catalog/bulk-import', (req, res) => {
    try {
      const { products: inputProducts, skipExisting = true } = req.body;

      if (!inputProducts || !Array.isArray(inputProducts)) {
        return res.status(400).json({ success: false, error: 'products должен быть массивом' });
      }

      const existingProducts = loadProducts();
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
          createdAt: new Date().toISOString(),
          createdBy: 'bulk-import',
          updatedAt: new Date().toISOString(),
        };

        existingProducts.push(newProduct);
        existingBarcodes.add(newProduct.barcode);
        added++;
      });

      saveProducts(existingProducts);

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
  app.post('/api/master-catalog/pending-codes/:kod/mark-notified', (req, res) => {
    try {
      const { kod } = req.params;

      const pending = loadPendingCodes();
      const pendingCode = pending.find((p) => p.kod === kod);

      if (!pendingCode) {
        return res.status(404).json({ success: false, error: 'Код не найден в pending' });
      }

      pendingCode.notificationSent = true;
      savePendingCodes(pending);

      res.json({ success: true });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка mark-notified:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ДЛЯ AI TRAINING ============

  /**
   * GET /api/master-catalog/for-training
   * Получить товары для AI обучения (формат как cigarette-vision/products)
   */
  app.get('/api/master-catalog/for-training', (req, res) => {
    try {
      const { productGroup } = req.query;
      let products = loadProducts();

      // Фильтр по группе
      if (productGroup) {
        products = products.filter((p) => p.group === productGroup);
      }

      // Преобразуем в формат для AI Training
      const trainingProducts = products.map((p) => ({
        id: p.id,
        productName: p.name,
        group: p.group,
        barcode: p.barcode,
        // AI Training ожидает эти поля (будут заполняться из training samples)
        recountPhotosCount: 0,
        displayPhotosCount: 0,
        trainingPhotosCount: 0,
        requiredPhotos: 10,
        completionPercentage: 0,
        shopCodes: p.shopCodes,
      }));

      res.json({ success: true, products: trainingProducts });
    } catch (error) {
      console.error('[Master Catalog API] Ошибка получения товаров для обучения:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('[Master Catalog API] Готово');
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
};
