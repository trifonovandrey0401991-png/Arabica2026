/**
 * OOS (Out of Stock) Scheduler
 *
 * Periodically checks stock levels for flagged products across all shops.
 * When a flagged product hits stock <= 0, records an OOS event and sends
 * push notifications to developers, managers, and store managers.
 *
 * Env variables:
 * - OOS_SCHEDULER_ENABLED=true/false (default: false)
 *
 * Check interval is configurable via OOS settings (default: 60 minutes).
 */

const { getMoscowDateString } = require('../utils/moscow_time');
const { sendPushToPhone, getAdminAndDeveloperPhones } = require('../utils/push_service');
const { loadShopProducts } = require('./shop_products_api');
const { loadShopManagers } = require('./shop_managers_api');
const { loadOosSettings, saveOosEvent, eventExistsToday, buildMasterMap, getShopName, filterShopsByRole } = require('./oos_api');
const { getShops } = require('../utils/data_cache');

const ENABLED = process.env.OOS_SCHEDULER_ENABLED === 'true';

let schedulerTimer = null;
let isRunning = false;
let currentIntervalMinutes = 60;

/**
 * Start the OOS scheduler
 */
function startOosScheduler() {
  if (!ENABLED) {
    console.log('[OOS Scheduler] DISABLED (set OOS_SCHEDULER_ENABLED=true)');
    return;
  }

  console.log('[OOS Scheduler] Starting...');

  // Load interval from settings and start
  loadOosSettings().then(settings => {
    currentIntervalMinutes = settings.checkIntervalMinutes || 60;
    console.log(`[OOS Scheduler] Check interval: ${currentIntervalMinutes} min`);
    scheduleNext();
  }).catch(e => {
    console.error('[OOS Scheduler] Error loading settings:', e.message);
    scheduleNext();
  });

  // Allow dynamic restart from API
  global._oosSchedulerRestart = restartWithInterval;
}

/**
 * Restart scheduler with new interval
 */
function restartWithInterval(newIntervalMinutes) {
  if (schedulerTimer) {
    clearTimeout(schedulerTimer);
    schedulerTimer = null;
  }
  currentIntervalMinutes = newIntervalMinutes;
  console.log(`[OOS Scheduler] Restarted with interval: ${currentIntervalMinutes} min`);
  scheduleNext();
}

/**
 * Schedule next check
 */
function scheduleNext() {
  if (schedulerTimer) clearTimeout(schedulerTimer);
  schedulerTimer = setTimeout(() => {
    runOosCheck().finally(() => scheduleNext());
  }, currentIntervalMinutes * 60 * 1000);
}

/**
 * Main check function
 */
async function runOosCheck() {
  if (isRunning) return;
  isRunning = true;

  try {
    const settings = await loadOosSettings();
    const flaggedIds = new Set(settings.flaggedProductIds || []);

    if (flaggedIds.size === 0) {
      console.log('[OOS Scheduler] No flagged products, skipping');
      return;
    }

    // Build master catalog map
    const masterMap = await buildMasterMap();

    // Find flagged barcodes
    const flaggedBarcodes = new Map(); // barcode → {id, name}
    for (const [barcode, info] of masterMap) {
      if (flaggedIds.has(info.id)) {
        flaggedBarcodes.set(barcode, info);
      }
    }

    if (flaggedBarcodes.size === 0) {
      console.log('[OOS Scheduler] No matching barcodes found in master catalog');
      return;
    }

    const today = getMoscowDateString();
    const allShops = getShops() || [];
    const shopIds = allShops.map(s => s.id).filter(Boolean);
    const newEvents = [];

    for (const shopId of shopIds) {
      const shopData = await loadShopProducts(shopId);
      const products = shopData.products || [];

      // Build kod→stock map
      const kodStockMap = new Map();
      for (const p of products) {
        if (p.kod) kodStockMap.set(p.kod, p.stock || 0);
      }

      // Check each flagged barcode
      for (const [barcode, info] of flaggedBarcodes) {
        if (!kodStockMap.has(barcode)) continue; // Product not in this shop

        const stock = kodStockMap.get(barcode);
        if (stock > 0) continue; // In stock, skip

        // Stock <= 0 — check if already recorded today
        const exists = await eventExistsToday(shopId, barcode);
        if (exists) continue;

        // Create new OOS event
        const event = {
          id: `oos_${shopId}_${barcode}_${today}`,
          shop_id: shopId,
          product_barcode: barcode,
          product_name: info.name,
          date: today,
          stock: stock,
          notified: false,
          created_at: new Date().toISOString(),
        };

        await saveOosEvent(event);
        newEvents.push({ ...event, shopId });
      }
    }

    if (newEvents.length > 0) {
      console.log(`[OOS Scheduler] Found ${newEvents.length} new OOS events`);
      await sendOosNotifications(newEvents);
    } else {
      console.log('[OOS Scheduler] No new OOS events');
    }
  } catch (error) {
    console.error('[OOS Scheduler] Error:', error);
  } finally {
    isRunning = false;
  }
}

/**
 * Send push notifications for new OOS events
 */
async function sendOosNotifications(events) {
  try {
    // Get developer phones
    const devPhones = await getAdminAndDeveloperPhones();

    // Get manager data
    const managersData = await loadShopManagers();
    const managers = managersData.managers || [];
    const storeManagers = managersData.storeManagers || [];

    // Group events by shop for cleaner notifications
    const byShop = {};
    for (const event of events) {
      if (!byShop[event.shop_id]) byShop[event.shop_id] = [];
      byShop[event.shop_id].push(event);
    }

    for (const [shopId, shopEvents] of Object.entries(byShop)) {
      const shopName = getShopName(shopId);

      // Build notification text
      const productNames = shopEvents.map(e => e.product_name).slice(0, 5);
      const title = `Товар закончился — ${shopName}`;
      const body = productNames.join(', ') +
        (shopEvents.length > 5 ? ` и ещё ${shopEvents.length - 5}` : '');

      const data = {
        type: 'oos_alert',
        shopId,
        count: String(shopEvents.length),
      };

      // Collect recipients (deduplicate by phone)
      const recipientPhones = new Set(devPhones);

      // Find manager (admin) for this shop
      for (const manager of managers) {
        const managedShops = manager.managedShops || [];
        if (managedShops.includes(shopId) && manager.phone) {
          recipientPhones.add(manager.phone.replace(/[^\d]/g, ''));
        }
      }

      // Find store manager for this shop
      for (const sm of storeManagers) {
        const smShops = sm.managedShopIds || (sm.shopId ? [sm.shopId] : []);
        if (smShops.includes(shopId) && sm.phone) {
          recipientPhones.add(sm.phone.replace(/[^\d]/g, ''));
        }
      }

      // Send to each recipient
      for (const phone of recipientPhones) {
        await sendPushToPhone(phone, title, body, data, 'oos_channel');
      }

      console.log(`[OOS Scheduler] Sent OOS notification for ${shopName}: ${shopEvents.length} products to ${recipientPhones.size} recipients`);
    }

    // Mark events as notified
    for (const event of events) {
      event.notified = true;
      await saveOosEvent(event);
    }
  } catch (error) {
    console.error('[OOS Scheduler] Notification error:', error);
  }
}

module.exports = {
  startOosScheduler,
};
