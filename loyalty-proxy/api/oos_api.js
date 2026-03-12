/**
 * OOS (Out of Stock) API Module
 * API для отслеживания отсутствия товаров в магазинах
 *
 * Endpoints:
 * - GET /api/oos/settings — получить настройки (флаги + интервал)
 * - PUT /api/oos/settings — сохранить настройки (dev/admin)
 * - GET /api/oos/table — таблица остатков по магазинам
 * - GET /api/oos/report — сводка по магазинам за месяц
 * - GET /api/oos/report/:shopId/:month — детализация: товары x дни
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('../utils/async_fs');
const { fileExists } = require('../utils/file_helpers');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');
const { getMoscowDateString } = require('../utils/moscow_time');
const { loadShopProducts, getShopsWithProducts } = require('./shop_products_api');
const { loadProducts } = require('./master_catalog_api');
const { getUserMultitenantRole, loadShopManagers } = require('./shop_managers_api');
const { getShops } = require('../utils/data_cache');

const USE_DB = process.env.USE_DB_OOS === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const OOS_SETTINGS_DIR = path.join(DATA_DIR, 'oos-settings');
const OOS_EVENTS_DIR = path.join(DATA_DIR, 'oos-events');
const SETTINGS_FILE = path.join(OOS_SETTINGS_DIR, 'config.json');

/**
 * Load OOS settings (flagged product IDs + check interval)
 */
async function loadOosSettings() {
  try {
    if (USE_DB) {
      const row = await db.findById('app_settings', 'oos_config', 'key');
      if (row && row.data) return row.data;
    }

    if (await fileExists(SETTINGS_FILE)) {
      const content = await fsp.readFile(SETTINGS_FILE, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error('[OOS API] Error loading settings:', e.message);
  }
  return { flaggedProductIds: [], checkIntervalMinutes: 60 };
}

/**
 * Save OOS settings (dual-write: JSON + DB)
 */
async function saveOosSettings(settings) {
  try {
    await fsp.mkdir(OOS_SETTINGS_DIR, { recursive: true });
    await writeJsonFile(SETTINGS_FILE, settings);

    if (USE_DB) {
      try {
        await db.upsert('app_settings', {
          key: 'oos_config',
          data: settings,
          updated_at: new Date().toISOString(),
        }, 'key');
      } catch (dbErr) {
        console.error('[OOS API] DB save settings error:', dbErr.message);
      }
    }
    return true;
  } catch (e) {
    console.error('[OOS API] Error saving settings:', e.message);
    return false;
  }
}

/**
 * Load OOS events for a month (YYYY-MM)
 */
async function loadOosEvents(month) {
  try {
    if (USE_DB) {
      const result = await db.query(
        `SELECT * FROM oos_events WHERE date LIKE $1 ORDER BY date, product_name`,
        [`${month}%`]
      );
      return (result && result.rows) ? result.rows : [];
    }

    const filePath = path.join(OOS_EVENTS_DIR, `${month}.json`);
    if (await fileExists(filePath)) {
      const content = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error(`[OOS API] Error loading events for ${month}:`, e.message);
  }
  return [];
}

/**
 * Save an OOS event (dual-write)
 */
async function saveOosEvent(event) {
  try {
    // JSON backup — append to monthly file
    const month = event.date.substring(0, 7); // YYYY-MM
    await fsp.mkdir(OOS_EVENTS_DIR, { recursive: true });
    const filePath = path.join(OOS_EVENTS_DIR, `${month}.json`);

    let events = [];
    if (await fileExists(filePath)) {
      const content = await fsp.readFile(filePath, 'utf8');
      events = JSON.parse(content);
    }

    // Avoid duplicates
    const existingIdx = events.findIndex(e => e.id === event.id);
    if (existingIdx >= 0) {
      events[existingIdx] = event;
    } else {
      events.push(event);
    }
    await writeJsonFile(filePath, events);

    // DB
    if (USE_DB) {
      try {
        await db.upsert('oos_events', {
          id: event.id,
          shop_id: event.shop_id,
          product_barcode: event.product_barcode,
          product_name: event.product_name,
          date: event.date,
          stock: event.stock,
          notified: event.notified || false,
          created_at: event.created_at || new Date().toISOString(),
        });
      } catch (dbErr) {
        console.error('[OOS API] DB save event error:', dbErr.message);
      }
    }

    return true;
  } catch (e) {
    console.error('[OOS API] Error saving event:', e.message);
    return false;
  }
}

/**
 * Check if event exists for today
 */
async function eventExistsToday(shopId, barcode) {
  const today = getMoscowDateString();
  const eventId = `oos_${shopId}_${barcode}_${today}`;

  try {
    if (USE_DB) {
      const row = await db.findById('oos_events', eventId);
      return !!row;
    }

    const month = today.substring(0, 7);
    const events = await loadOosEvents(month);
    return events.some(e => e.id === eventId);
  } catch (e) {
    return false;
  }
}

/**
 * Get all shops from data_cache (real shops from Управление → Магазины)
 */
function getAllShopsList() {
  const cached = getShops();
  if (cached && cached.length > 0) return cached;
  return [];
}

/**
 * Get shop name by shopId (address) from cached shops
 */
function getShopName(shopId) {
  const shops = getAllShopsList();
  const shop = shops.find(s => s.id === shopId);
  if (shop) return shop.name || shop.title || shopId;
  return shopId;
}

/**
 * Filter shops by user role
 */
async function filterShopsByRole(allShopIds, userPhone) {
  const role = await getUserMultitenantRole(userPhone);
  if (role.role === 'developer') return allShopIds;
  if (role.role === 'admin' && role.managedShopIds && role.managedShopIds.length > 0) {
    return allShopIds.filter(id => role.managedShopIds.includes(id));
  }
  if (role.role === 'manager' && role.managedShopIds && role.managedShopIds.length > 0) {
    return allShopIds.filter(id => role.managedShopIds.includes(id));
  }
  return [];
}

/**
 * Build master catalog barcode→name map
 */
async function buildMasterMap() {
  const masterProducts = await loadProducts();
  const map = new Map();
  for (const p of masterProducts) {
    if (p.barcode && p.name) {
      map.set(p.barcode, { id: p.id, name: p.name, group: p.group || '' });
    }
  }
  return map;
}

function setupOosAPI(app) {
  console.log('[OOS API] Initializing...');

  // Create dirs
  fsp.mkdir(OOS_SETTINGS_DIR, { recursive: true }).catch(() => {});
  fsp.mkdir(OOS_EVENTS_DIR, { recursive: true }).catch(() => {});

  // ============ SETTINGS ============

  app.get('/api/oos/settings', requireAuth, async (req, res) => {
    try {
      const settings = await loadOosSettings();
      res.json({ success: true, settings });
    } catch (error) {
      console.error('[OOS API] GET settings error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/oos/settings', requireAuth, async (req, res) => {
    try {
      const phone = req.user?.phone;
      if (!phone) return res.status(401).json({ success: false, error: 'Unauthorized' });

      // Only developer or admin
      const role = await getUserMultitenantRole(phone);
      if (role.role !== 'developer' && role.role !== 'admin') {
        return res.status(403).json({ success: false, error: 'Access denied' });
      }

      const { flaggedProductIds, checkIntervalMinutes } = req.body;

      if (!Array.isArray(flaggedProductIds)) {
        return res.status(400).json({ success: false, error: 'flaggedProductIds must be an array' });
      }

      const interval = Math.max(5, Math.min(1440, parseInt(checkIntervalMinutes, 10) || 60));

      const settings = {
        flaggedProductIds,
        checkIntervalMinutes: interval,
        updatedAt: new Date().toISOString(),
        updatedBy: phone,
      };

      const saved = await saveOosSettings(settings);
      if (saved) {
        // Notify scheduler about interval change
        if (global._oosSchedulerRestart) {
          global._oosSchedulerRestart(interval);
        }
        res.json({ success: true, settings });
      } else {
        res.status(500).json({ success: false, error: 'Failed to save settings' });
      }
    } catch (error) {
      console.error('[OOS API] PUT settings error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ TABLE (live stock data) ============

  app.get('/api/oos/table', requireAuth, async (req, res) => {
    try {
      const phone = req.user?.phone;
      const settings = await loadOosSettings();
      const flaggedIds = new Set(settings.flaggedProductIds || []);

      if (flaggedIds.size === 0) {
        return res.json({ success: true, rows: [], shops: [] });
      }

      // Build master catalog map: barcode → {id, name}
      const masterMap = await buildMasterMap();

      // Find which barcodes are flagged
      const flaggedBarcodes = new Map(); // barcode → name
      for (const [barcode, info] of masterMap) {
        if (flaggedIds.has(info.id)) {
          flaggedBarcodes.set(barcode, info.name);
        }
      }

      // Get ALL real shops from Управление → Магазины
      const allShops = getAllShopsList();
      let shopIds = allShops.map(s => s.id).filter(Boolean);

      // Filter by role
      if (phone) {
        shopIds = await filterShopsByRole(shopIds, phone);
      }

      // Build table data
      const shopNames = {};
      const shopLastSync = {};
      const rows = new Map(); // barcode → { barcode, productName, shops: { shopId: stock } }

      for (const shopId of shopIds) {
        const shopName = getShopName(shopId);
        shopNames[shopId] = shopName;

        const shopData = await loadShopProducts(shopId);
        shopLastSync[shopId] = shopData.lastSync || null;
        const products = shopData.products || [];

        // Build kod→stock map for this shop
        const kodStockMap = new Map();
        for (const p of products) {
          if (p.kod) kodStockMap.set(p.kod, p.stock || 0);
        }

        // Check each flagged barcode
        for (const [barcode, productName] of flaggedBarcodes) {
          const stock = kodStockMap.has(barcode) ? kodStockMap.get(barcode) : null;

          if (!rows.has(barcode)) {
            rows.set(barcode, {
              barcode,
              productName,
              shops: {},
            });
          }
          rows.get(barcode).shops[shopId] = stock;
        }
      }

      // Filter: only show products where at least one shop has stock <= 0
      const filteredRows = [];
      for (const row of rows.values()) {
        const hasZero = Object.values(row.shops).some(s => s !== null && s <= 0);
        const allPositive = Object.values(row.shops).every(s => s === null || s > 0);
        if (hasZero && !allPositive) {
          filteredRows.push(row);
        } else if (hasZero) {
          filteredRows.push(row);
        }
      }

      // Sort by name
      filteredRows.sort((a, b) => a.productName.localeCompare(b.productName, 'ru'));

      res.json({
        success: true,
        rows: filteredRows,
        shops: Object.entries(shopNames).map(([id, name]) => ({ id, name, lastSync: shopLastSync[id] || null })),
      });
    } catch (error) {
      console.error('[OOS API] GET table error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ REPORT (monthly OOS summary) ============

  app.get('/api/oos/report', requireAuth, async (req, res) => {
    try {
      const phone = req.user?.phone;
      const month = req.query.month || getMoscowDateString().substring(0, 7);

      // Get ALL real shops
      const allShops = getAllShopsList();
      let shopIds = allShops.map(s => s.id).filter(Boolean);

      if (phone) {
        shopIds = await filterShopsByRole(shopIds, phone);
      }

      // Load events for the month
      const events = await loadOosEvents(month);

      // Count OOS incidents per shop
      const shopCounts = {};
      for (const event of events) {
        if (!shopIds.includes(event.shop_id)) continue;
        shopCounts[event.shop_id] = (shopCounts[event.shop_id] || 0) + 1;
      }

      // Check which shops have DBF data
      const shopsWithDbf = new Set();
      const dbfShops = await getShopsWithProducts();
      for (const s of dbfShops) {
        if (s.shopId) shopsWithDbf.add(s.shopId);
      }

      // Build response
      const shops = [];
      for (const shopId of shopIds) {
        const shopName = getShopName(shopId);
        const hasDbf = shopsWithDbf.has(shopId);
        shops.push({
          shopId,
          shopName,
          oosCount: hasDbf ? (shopCounts[shopId] || 0) : -1, // -1 = no DBF data
          hasDbf,
        });
      }

      // Sort by OOS count descending
      shops.sort((a, b) => b.oosCount - a.oosCount);

      // Get available months
      let availableMonths = [month];
      try {
        if (USE_DB) {
          const monthResult = await db.query(
            `SELECT DISTINCT SUBSTRING(date, 1, 7) AS month FROM oos_events ORDER BY month DESC`
          );
          const monthRows = (monthResult && monthResult.rows) ? monthResult.rows : [];
          if (monthRows.length > 0) {
            availableMonths = monthRows.map(r => r.month);
          }
        } else {
          if (await fileExists(OOS_EVENTS_DIR)) {
            const files = await fsp.readdir(OOS_EVENTS_DIR);
            availableMonths = files
              .filter(f => f.endsWith('.json'))
              .map(f => f.replace('.json', ''))
              .sort()
              .reverse();
          }
        }
      } catch (e) {
        // keep default
      }

      res.json({
        success: true,
        month,
        shops,
        availableMonths,
      });
    } catch (error) {
      console.error('[OOS API] GET report error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ REPORT DETAIL (shop + month → products x days) ============

  app.get('/api/oos/report/:shopId/:month', requireAuth, async (req, res) => {
    try {
      const { shopId, month } = req.params;
      const phone = req.user?.phone;

      // Access check
      if (phone) {
        const allowed = await filterShopsByRole([shopId], phone);
        if (allowed.length === 0) {
          return res.status(403).json({ success: false, error: 'Access denied' });
        }
      }

      const shopName = getShopName(shopId);
      const events = await loadOosEvents(month);

      // Filter to this shop
      const shopEvents = events.filter(e => e.shop_id === shopId);

      // Build grid: products x days
      const productDays = {}; // barcode → { name, days: { dayNum: stock } }
      for (const event of shopEvents) {
        const day = parseInt(event.date.split('-')[2], 10);
        if (!productDays[event.product_barcode]) {
          productDays[event.product_barcode] = {
            barcode: event.product_barcode,
            productName: event.product_name,
            days: {},
          };
        }
        productDays[event.product_barcode].days[day] = event.stock;
      }

      // Sort by name
      const products = Object.values(productDays);
      products.sort((a, b) => a.productName.localeCompare(b.productName, 'ru'));

      // Days in month
      const [year, mon] = month.split('-').map(Number);
      const daysInMonth = new Date(year, mon, 0).getDate();

      res.json({
        success: true,
        shopId,
        shopName,
        month,
        daysInMonth,
        products,
      });
    } catch (error) {
      console.error('[OOS API] GET report detail error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`[OOS API] Ready ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = {
  setupOosAPI,
  loadOosSettings,
  saveOosEvent,
  eventExistsToday,
  loadOosEvents,
  buildMasterMap,
  filterShopsByRole,
  getShopName,
};
