/**
 * Shops API - Управление магазинами
 * Примечание: Shop Settings API вынесен в отдельный модуль shop_settings_api.js
 */

const fs = require('fs');
const path = require('path');

const SHOPS_DIR = '/var/www/shops';

if (!fs.existsSync(SHOPS_DIR)) {
  fs.mkdirSync(SHOPS_DIR, { recursive: true });
}

function setupShopsAPI(app) {
  app.get('/api/shops', (req, res) => {
    try {
      console.log('GET /api/shops');
      const shops = [];

      if (fs.existsSync(SHOPS_DIR)) {
        const files = fs.readdirSync(SHOPS_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(SHOPS_DIR, file), 'utf8');
            shops.push(JSON.parse(content));
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
  app.get('/api/shops/:id', (req, res) => {
    try {
      const { id } = req.params;
      console.log(`GET /api/shops/${id}`);

      const files = fs.readdirSync(SHOPS_DIR).filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const content = fs.readFileSync(path.join(SHOPS_DIR, file), 'utf8');
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
  app.put('/api/shops/:id', (req, res) => {
    try {
      const { id } = req.params;
      const updates = req.body;
      console.log(`PUT /api/shops/${id}`, updates);

      const files = fs.readdirSync(SHOPS_DIR).filter(f => f.endsWith('.json'));

      for (const file of files) {
        try {
          const filePath = path.join(SHOPS_DIR, file);
          const content = fs.readFileSync(filePath, 'utf8');
          const shop = JSON.parse(content);

          if (shop.id === id) {
            // Update allowed fields
            if (updates.name !== undefined) shop.name = updates.name;
            if (updates.address !== undefined) shop.address = updates.address;
            if (updates.latitude !== undefined) shop.latitude = updates.latitude;
            if (updates.longitude !== undefined) shop.longitude = updates.longitude;
            shop.updatedAt = new Date().toISOString();

            fs.writeFileSync(filePath, JSON.stringify(shop, null, 2), 'utf8');
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
