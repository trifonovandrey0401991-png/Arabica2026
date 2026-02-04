const fs = require('fs');
const path = require('path');

const SHOP_COORDINATES_DIR = '/var/www/shop-coordinates';

if (!fs.existsSync(SHOP_COORDINATES_DIR)) {
  fs.mkdirSync(SHOP_COORDINATES_DIR, { recursive: true });
}

function setupShopCoordinatesAPI(app) {
  // ===== GET ALL SHOP COORDINATES =====
  app.get('/api/shop-coordinates', async (req, res) => {
    try {
      console.log('GET /api/shop-coordinates');
      const coordinates = [];

      if (fs.existsSync(SHOP_COORDINATES_DIR)) {
        const files = fs.readdirSync(SHOP_COORDINATES_DIR).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = fs.readFileSync(path.join(SHOP_COORDINATES_DIR, file), 'utf8');
            coordinates.push(JSON.parse(content));
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      res.json({ success: true, coordinates });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET SHOP COORDINATES BY ADDRESS =====
  app.get('/api/shop-coordinates/:shopAddress', async (req, res) => {
    try {
      const { shopAddress } = req.params;
      console.log('GET /api/shop-coordinates:', shopAddress);

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const filePath = path.join(SHOP_COORDINATES_DIR, `${sanitizedAddress}.json`);

      if (fs.existsSync(filePath)) {
        const coords = JSON.parse(fs.readFileSync(filePath, 'utf8'));
        res.json({ success: true, coordinates: coords });
      } else {
        res.json({ success: true, coordinates: null });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SET/UPDATE SHOP COORDINATES =====
  app.post('/api/shop-coordinates', async (req, res) => {
    try {
      const coords = req.body;
      console.log('POST /api/shop-coordinates:', coords.shopAddress);

      if (!coords.shopAddress) {
        return res.status(400).json({ success: false, error: 'shopAddress is required' });
      }

      const sanitizedAddress = coords.shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const filePath = path.join(SHOP_COORDINATES_DIR, `${sanitizedAddress}.json`);

      coords.updatedAt = new Date().toISOString();
      fs.writeFileSync(filePath, JSON.stringify(coords, null, 2), 'utf8');

      res.json({ success: true, coordinates: coords });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== UPDATE SHOP COORDINATES =====
  app.put('/api/shop-coordinates/:shopAddress', async (req, res) => {
    try {
      const { shopAddress } = req.params;
      const updates = req.body;
      console.log('PUT /api/shop-coordinates:', shopAddress);

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const filePath = path.join(SHOP_COORDINATES_DIR, `${sanitizedAddress}.json`);

      let coords = { shopAddress };
      if (fs.existsSync(filePath)) {
        coords = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      }

      const updated = { ...coords, ...updates, updatedAt: new Date().toISOString() };
      fs.writeFileSync(filePath, JSON.stringify(updated, null, 2), 'utf8');

      res.json({ success: true, coordinates: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== DELETE SHOP COORDINATES =====
  app.delete('/api/shop-coordinates/:shopAddress', async (req, res) => {
    try {
      const { shopAddress } = req.params;
      console.log('DELETE /api/shop-coordinates:', shopAddress);

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const filePath = path.join(SHOP_COORDINATES_DIR, `${sanitizedAddress}.json`);

      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Coordinates not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CHECK IF EMPLOYEE IS NEAR SHOP =====
  app.post('/api/shop-coordinates/check-proximity', async (req, res) => {
    try {
      const { shopAddress, latitude, longitude, maxDistance = 100 } = req.body;
      console.log('POST /api/shop-coordinates/check-proximity:', shopAddress);

      if (!shopAddress || latitude === undefined || longitude === undefined) {
        return res.status(400).json({
          success: false,
          error: 'shopAddress, latitude, and longitude are required'
        });
      }

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const filePath = path.join(SHOP_COORDINATES_DIR, `${sanitizedAddress}.json`);

      if (!fs.existsSync(filePath)) {
        return res.json({ success: true, isNear: true, message: 'No coordinates set for shop' });
      }

      const shopCoords = JSON.parse(fs.readFileSync(filePath, 'utf8'));

      // Calculate distance using Haversine formula
      const toRad = (deg) => deg * Math.PI / 180;
      const R = 6371000; // Earth radius in meters

      const dLat = toRad(latitude - shopCoords.latitude);
      const dLon = toRad(longitude - shopCoords.longitude);
      const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(toRad(shopCoords.latitude)) * Math.cos(toRad(latitude)) *
                Math.sin(dLon/2) * Math.sin(dLon/2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
      const distance = R * c;

      const isNear = distance <= maxDistance;

      res.json({
        success: true,
        isNear,
        distance: Math.round(distance),
        maxDistance,
        shopCoordinates: { latitude: shopCoords.latitude, longitude: shopCoords.longitude }
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Shop Coordinates API initialized');
}

module.exports = { setupShopCoordinatesAPI };
