/**
 * Shop Catalog API — каталог товаров магазина
 * CRUD товаров, групп, загрузка фото, уполномоченные сотрудники
 */

const path = require('path');
const fsp = require('fs').promises;
const multer = require('multer');
const { sanitizeId, fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { compressUpload } = require('../utils/image_compress');

const USE_DB = process.env.USE_DB_SHOP_CATALOG === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const PRODUCTS_DIR = `${DATA_DIR}/shop-products`;
const GROUPS_DIR = `${DATA_DIR}/shop-product-groups`;
const PRODUCT_PHOTOS_DIR = `${DATA_DIR}/shop-product-photos`;

let db;
try { db = require('../utils/db'); } catch (e) { /* db optional */ }

// Multer for product photos
const productPhotoStorage = multer.diskStorage({
  destination: async function (req, file, cb) {
    if (!await fileExists(PRODUCT_PHOTOS_DIR)) {
      await fsp.mkdir(PRODUCT_PHOTOS_DIR, { recursive: true });
    }
    cb(null, PRODUCT_PHOTOS_DIR);
  },
  filename: function (req, file, cb) {
    const productId = sanitizeId(req.params.id || `product_${Date.now()}`);
    const ext = path.extname(file.originalname) || '.jpg';
    cb(null, `${productId}_${Date.now()}${ext}`);
  }
});

const uploadProductPhoto = multer({
  storage: productPhotoStorage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: function (req, file, cb) {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (allowedTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Разрешены только изображения (JPEG, PNG, GIF, WebP)'));
    }
  }
});

// ==================== AUTHORIZED EMPLOYEES (module-level for cross-module use) ====================

const AUTH_KEY = 'wholesale_authorized_employees';

async function loadAuthorizedEmployees() {
  if (USE_DB && db) {
    try {
      const row = await db.findById('app_settings', AUTH_KEY, 'key');
      return row && row.data ? (Array.isArray(row.data) ? row.data : JSON.parse(row.data)) : [];
    } catch (e) { /* fallback to file */ }
  }
  const filePath = path.join(DATA_DIR, `${AUTH_KEY}.json`);
  if (await fileExists(filePath)) {
    return JSON.parse(await fsp.readFile(filePath, 'utf8'));
  }
  return [];
}

async function saveAuthorizedEmployees(list) {
  const filePath = path.join(DATA_DIR, `${AUTH_KEY}.json`);
  await writeJsonFile(filePath, list);
  if (USE_DB && db) {
    try { await db.upsert('app_settings', { key: AUTH_KEY, data: JSON.stringify(list) }, 'key'); }
    catch (dbErr) { console.error('DB save authorized employees error:', dbErr.message); }
  }
}

function setupShopCatalogAPI(app) {
  const requireAuth = app._requireAuth || require('../utils/session_middleware').requireAuth;
  const requireAdmin = require('../utils/session_middleware').requireAdmin;

  // ==================== PRODUCT GROUPS ====================

  // GET /api/shop-catalog/groups
  app.get('/api/shop-catalog/groups', requireAuth, async (req, res) => {
    try {
      let groups = [];
      if (USE_DB && db) {
        const rows = await db.findAll('shop_product_groups', { orderBy: 'sort_order', orderDir: 'ASC' });
        groups = rows.map(r => ({
          id: r.id,
          name: r.name,
          visibility: r.visibility || 'all',
          sortOrder: r.sort_order || 0,
          isActive: r.is_active !== false,
          createdAt: r.created_at,
        }));
      } else {
        if (await fileExists(GROUPS_DIR)) {
          const files = await fsp.readdir(GROUPS_DIR);
          for (const f of files) {
            if (!f.endsWith('.json')) continue;
            const data = JSON.parse(await fsp.readFile(path.join(GROUPS_DIR, f), 'utf8'));
            groups.push(data);
          }
          groups.sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));
        }
      }
      res.json({ success: true, groups });
    } catch (e) {
      console.error('GET /api/shop-catalog/groups error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/shop-catalog/groups
  app.post('/api/shop-catalog/groups', requireAuth, async (req, res) => {
    try {
      const { name, visibility, sortOrder } = req.body;
      if (!name) return res.status(400).json({ success: false, error: 'Название обязательно' });

      const id = `grp_${Date.now()}_${Math.random().toString(36).substr(2, 4)}`;
      const group = {
        id,
        name,
        visibility: visibility || 'all',
        sortOrder: sortOrder || 0,
        isActive: true,
        createdAt: new Date().toISOString(),
      };

      await fsp.mkdir(GROUPS_DIR, { recursive: true });
      await writeJsonFile(path.join(GROUPS_DIR, `${id}.json`), group);

      if (USE_DB && db) {
        try {
          await db.upsert('shop_product_groups', {
            id, name: group.name, visibility: group.visibility,
            sort_order: group.sortOrder, is_active: true, created_at: group.createdAt,
          });
        } catch (dbErr) { console.error('DB save group error:', dbErr.message); }
      }

      res.json({ success: true, group });
    } catch (e) {
      console.error('POST /api/shop-catalog/groups error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // PUT /api/shop-catalog/groups/:id
  app.put('/api/shop-catalog/groups/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const groupFile = path.join(GROUPS_DIR, `${id}.json`);

      let group;
      if (await fileExists(groupFile)) {
        group = JSON.parse(await fsp.readFile(groupFile, 'utf8'));
      } else if (USE_DB && db) {
        group = await db.findById('shop_product_groups', id);
        if (group) group = { id: group.id, name: group.name, visibility: group.visibility, sortOrder: group.sort_order, isActive: group.is_active };
      }
      if (!group) return res.status(404).json({ success: false, error: 'Группа не найдена' });

      const updates = req.body;
      if (updates.name !== undefined) group.name = updates.name;
      if (updates.visibility !== undefined) group.visibility = updates.visibility;
      if (updates.sortOrder !== undefined) group.sortOrder = updates.sortOrder;
      if (updates.isActive !== undefined) group.isActive = updates.isActive;

      await writeJsonFile(groupFile, group);

      if (USE_DB && db) {
        try {
          await db.upsert('shop_product_groups', {
            id, name: group.name, visibility: group.visibility,
            sort_order: group.sortOrder, is_active: group.isActive,
          });
        } catch (dbErr) { console.error('DB update group error:', dbErr.message); }
      }

      res.json({ success: true, group });
    } catch (e) {
      console.error('PUT /api/shop-catalog/groups error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // DELETE /api/shop-catalog/groups/:id
  app.delete('/api/shop-catalog/groups/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const groupFile = path.join(GROUPS_DIR, `${id}.json`);
      if (await fileExists(groupFile)) await fsp.unlink(groupFile);

      if (USE_DB && db) {
        try { await db.deleteById('shop_product_groups', id); }
        catch (dbErr) { console.error('DB delete group error:', dbErr.message); }
      }

      res.json({ success: true });
    } catch (e) {
      console.error('DELETE /api/shop-catalog/groups error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // ==================== PRODUCTS ====================

  // GET /api/shop-catalog/products
  app.get('/api/shop-catalog/products', requireAuth, async (req, res) => {
    try {
      const { groupId, active } = req.query;
      let products = [];

      if (USE_DB && db) {
        const filters = {};
        if (groupId) filters.group_id = groupId;
        if (active !== undefined) filters.is_active = active === 'true';
        const rows = await db.findAll('shop_products', { filters, orderBy: 'sort_order', orderDir: 'ASC' });
        products = rows.map(dbProductToApi);
      } else {
        if (await fileExists(PRODUCTS_DIR)) {
          const files = await fsp.readdir(PRODUCTS_DIR);
          for (const f of files) {
            if (!f.endsWith('.json')) continue;
            const data = JSON.parse(await fsp.readFile(path.join(PRODUCTS_DIR, f), 'utf8'));
            if (groupId && data.groupId !== groupId) continue;
            if (active !== undefined && data.isActive !== (active === 'true')) continue;
            products.push(data);
          }
          products.sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));
        }
      }

      res.json({ success: true, products });
    } catch (e) {
      console.error('GET /api/shop-catalog/products error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // GET /api/shop-catalog/products/:id
  app.get('/api/shop-catalog/products/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      let product = await loadProduct(id);
      if (!product) return res.status(404).json({ success: false, error: 'Товар не найден' });
      res.json({ success: true, product });
    } catch (e) {
      console.error('GET /api/shop-catalog/products/:id error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/shop-catalog/products/:id/upload-photo — MUST be before POST /products
  app.post('/api/shop-catalog/products/:id/upload-photo', requireAuth, uploadProductPhoto.single('photo'), compressUpload, async (req, res) => {
    try {
      if (!req.file) return res.status(400).json({ success: false, error: 'Файл не загружен' });

      const id = sanitizeId(req.params.id);
      const photoUrl = `/shop-product-photos/${req.file.filename}`;

      // Add photo to product's photos array
      let product = await loadProduct(id);
      if (!product) return res.status(404).json({ success: false, error: 'Товар не найден' });

      if (!Array.isArray(product.photos)) product.photos = [];
      product.photos.push(photoUrl);
      product.updatedAt = new Date().toISOString();
      await saveProduct(product);

      console.log(`✅ Фото товара загружено: ${id} (${req.file.size} bytes)`);
      res.json({ success: true, photoUrl, photos: product.photos });
    } catch (e) {
      console.error('POST upload-photo error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // DELETE /api/shop-catalog/products/:id/photos/:index
  app.delete('/api/shop-catalog/products/:id/photos/:index', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const index = parseInt(req.params.index, 10);

      let product = await loadProduct(id);
      if (!product) return res.status(404).json({ success: false, error: 'Товар не найден' });

      if (!Array.isArray(product.photos) || index < 0 || index >= product.photos.length) {
        return res.status(400).json({ success: false, error: 'Некорректный индекс фото' });
      }

      const removedUrl = product.photos.splice(index, 1)[0];
      product.updatedAt = new Date().toISOString();
      await saveProduct(product);

      // Try to delete physical file
      try {
        const filePath = path.join(DATA_DIR, removedUrl);
        if (await fileExists(filePath)) await fsp.unlink(filePath);
      } catch (e) { /* ignore file deletion errors */ }

      res.json({ success: true, photos: product.photos });
    } catch (e) {
      console.error('DELETE photo error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/shop-catalog/products
  app.post('/api/shop-catalog/products', requireAuth, async (req, res) => {
    try {
      const { name, description, groupId, priceRetail, priceWholesale, pricePoints, sortOrder, isWholesale } = req.body;
      if (!name) return res.status(400).json({ success: false, error: 'Название обязательно' });

      const id = `prod_${Date.now()}_${Math.random().toString(36).substr(2, 4)}`;
      const product = {
        id, name,
        description: description || '',
        groupId: groupId || null,
        priceRetail: priceRetail != null ? parseFloat(priceRetail) : null,
        priceWholesale: priceWholesale != null ? parseFloat(priceWholesale) : null,
        pricePoints: pricePoints != null ? parseInt(pricePoints, 10) : null,
        photos: [],
        isActive: true,
        isWholesale: isWholesale === true,
        sortOrder: sortOrder || 0,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };

      await saveProduct(product);
      res.json({ success: true, product });
    } catch (e) {
      console.error('POST /api/shop-catalog/products error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // PUT /api/shop-catalog/products/:id
  app.put('/api/shop-catalog/products/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      let product = await loadProduct(id);
      if (!product) return res.status(404).json({ success: false, error: 'Товар не найден' });

      const u = req.body;
      if (u.name !== undefined) product.name = u.name;
      if (u.description !== undefined) product.description = u.description;
      if (u.groupId !== undefined) product.groupId = u.groupId;
      if (u.priceRetail !== undefined) product.priceRetail = u.priceRetail != null ? parseFloat(u.priceRetail) : null;
      if (u.priceWholesale !== undefined) product.priceWholesale = u.priceWholesale != null ? parseFloat(u.priceWholesale) : null;
      if (u.pricePoints !== undefined) product.pricePoints = u.pricePoints != null ? parseInt(u.pricePoints, 10) : null;
      if (u.isActive !== undefined) product.isActive = u.isActive;
      if (u.isWholesale !== undefined) product.isWholesale = u.isWholesale;
      if (u.sortOrder !== undefined) product.sortOrder = u.sortOrder;
      product.updatedAt = new Date().toISOString();

      await saveProduct(product);
      res.json({ success: true, product });
    } catch (e) {
      console.error('PUT /api/shop-catalog/products error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // DELETE /api/shop-catalog/products/:id
  app.delete('/api/shop-catalog/products/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const productFile = path.join(PRODUCTS_DIR, `${id}.json`);
      if (await fileExists(productFile)) await fsp.unlink(productFile);

      if (USE_DB && db) {
        try { await db.deleteById('shop_products', id); }
        catch (dbErr) { console.error('DB delete product error:', dbErr.message); }
      }

      res.json({ success: true });
    } catch (e) {
      console.error('DELETE /api/shop-catalog/products error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // ==================== AUTHORIZED EMPLOYEES ====================
  // Functions loadAuthorizedEmployees/saveAuthorizedEmployees are defined at module level (exported)

  // GET /api/shop-catalog/authorized-employees
  app.get('/api/shop-catalog/authorized-employees', requireAuth, async (req, res) => {
    try {
      const list = await loadAuthorizedEmployees();
      res.json({ success: true, employees: list });
    } catch (e) {
      console.error('GET authorized-employees error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/shop-catalog/authorized-employees
  app.post('/api/shop-catalog/authorized-employees', requireAdmin, async (req, res) => {
    try {
      const { phone, name } = req.body;
      if (!phone) return res.status(400).json({ success: false, error: 'Телефон обязателен' });

      const normalizedPhone = phone.replace(/[^\d]/g, '');
      const list = await loadAuthorizedEmployees();

      if (list.some(e => e.phone === normalizedPhone)) {
        return res.status(400).json({ success: false, error: 'Уже добавлен' });
      }

      list.push({ phone: normalizedPhone, name: name || '', addedAt: new Date().toISOString() });
      await saveAuthorizedEmployees(list);

      res.json({ success: true, employees: list });
    } catch (e) {
      console.error('POST authorized-employees error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // DELETE /api/shop-catalog/authorized-employees/:phone
  app.delete('/api/shop-catalog/authorized-employees/:phone', requireAdmin, async (req, res) => {
    try {
      const phone = req.params.phone.replace(/[^\d]/g, '');
      let list = await loadAuthorizedEmployees();
      list = list.filter(e => e.phone !== phone);
      await saveAuthorizedEmployees(list);

      res.json({ success: true, employees: list });
    } catch (e) {
      console.error('DELETE authorized-employees error:', e.message);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // ==================== HELPERS ====================

  async function loadProduct(id) {
    const productFile = path.join(PRODUCTS_DIR, `${id}.json`);
    if (await fileExists(productFile)) {
      return JSON.parse(await fsp.readFile(productFile, 'utf8'));
    }
    if (USE_DB && db) {
      const row = await db.findById('shop_products', id);
      if (row) return dbProductToApi(row);
    }
    return null;
  }

  async function saveProduct(product) {
    await fsp.mkdir(PRODUCTS_DIR, { recursive: true });
    await writeJsonFile(path.join(PRODUCTS_DIR, `${product.id}.json`), product);

    if (USE_DB && db) {
      try {
        await db.upsert('shop_products', {
          id: product.id,
          name: product.name,
          description: product.description || '',
          group_id: product.groupId || null,
          price_retail: product.priceRetail,
          price_wholesale: product.priceWholesale,
          price_points: product.pricePoints,
          photos: JSON.stringify(product.photos || []),
          is_active: product.isActive !== false,
          is_wholesale: product.isWholesale === true,
          sort_order: product.sortOrder || 0,
          created_at: product.createdAt,
          updated_at: product.updatedAt,
        });
      } catch (dbErr) { console.error('DB save product error:', dbErr.message); }
    }
  }

  function dbProductToApi(row) {
    let photos = row.photos || [];
    if (typeof photos === 'string') {
      try { photos = JSON.parse(photos); } catch (e) { photos = []; }
    }
    return {
      id: row.id,
      name: row.name,
      description: row.description || '',
      groupId: row.group_id || null,
      priceRetail: row.price_retail != null ? parseFloat(row.price_retail) : null,
      priceWholesale: row.price_wholesale != null ? parseFloat(row.price_wholesale) : null,
      pricePoints: row.price_points != null ? parseInt(row.price_points, 10) : null,
      photos,
      isActive: row.is_active !== false,
      isWholesale: row.is_wholesale === true,
      sortOrder: row.sort_order || 0,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  console.log('✅ Shop Catalog API loaded');
}

module.exports = { setupShopCatalogAPI, loadAuthorizedEmployees };
