/**
 * Shops API - Управление магазинами
 * Примечание: Shop Settings API вынесен в отдельный модуль shop_settings_api.js
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SHOPS_DIR = path.join(DATA_DIR, 'shops');

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Initialize directory on module load
(async () => {
  try {
    await fsp.mkdir(SHOPS_DIR, { recursive: true });
  } catch (e) {
    console.error('Failed to create shops directory:', e);
  }
})();

function setupShopsAPI(app) {
  app.get('/api/shops', async (req, res) => {
    try {
      console.log('GET /api/shops');
      const shops = [];

      if (await fileExists(SHOPS_DIR)) {
        const allFiles = await fsp.readdir(SHOPS_DIR);
        // Only read individual shop files (shop_*.json), skip aggregate shops.json
        const files = allFiles.filter(f => f.endsWith('.json') && f.startsWith('shop_'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(SHOPS_DIR, file), 'utf8');
            const shop = JSON.parse(content);
            // Skip entries without valid address
            if (shop.address && shop.address.trim()) {
              shops.push(shop);
            }
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      res.json({ success: true, shops });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET shop by ID
  app.get('/api/shops/:id', async (req, res) => {
    try {
      const { id } = req.params;
      console.log(`GET /api/shops/${id}`);

      const allFiles = await fsp.readdir(SHOPS_DIR);
      const files = allFiles.filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const content = await fsp.readFile(path.join(SHOPS_DIR, file), 'utf8');
          const shop = JSON.parse(content);
          if (shop.id === id) {
            return res.json({ success: true, shop });
          }
        } catch (e) {
          console.error(`Error reading ${file}:`, e);
        }
      }

      res.status(404).json({ success: false, error: 'Shop not found' });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT - Update shop (for geolocation and other updates)
  app.put('/api/shops/:id', async (req, res) => {
    try {
      const { id } = req.params;
      const updates = req.body;
      console.log(`PUT /api/shops/${id}`, updates);

      const allFiles = await fsp.readdir(SHOPS_DIR);
      const files = allFiles.filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const filePath = path.join(SHOPS_DIR, file);
          const content = await fsp.readFile(filePath, 'utf8');
          const shop = JSON.parse(content);

          if (shop.id === id) {
            // Update allowed fields
            if (updates.name !== undefined) shop.name = updates.name;
            if (updates.address !== undefined) shop.address = updates.address;
            if (updates.latitude !== undefined) shop.latitude = updates.latitude;
            if (updates.longitude !== undefined) shop.longitude = updates.longitude;
            shop.updatedAt = new Date().toISOString();

            await fsp.writeFile(filePath, JSON.stringify(shop, null, 2), 'utf8');
            console.log(`✅ Shop ${id} updated successfully`);
            return res.json({ success: true, shop });
          }
        } catch (e) {
          console.error(`Error processing ${file}:`, e);
        }
      }

      res.status(404).json({ success: false, error: 'Shop not found' });
    } catch (error) {
      console.error('Error updating shop:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Shop Settings API moved to shop_settings_api.js

  console.log('✅ Shops API initialized');
}

module.exports = { setupShopsAPI };
