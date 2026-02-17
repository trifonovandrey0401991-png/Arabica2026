/**
 * Shop Coordinates API
 * Manages shop location coordinates for proximity checks
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');

const USE_DB = process.env.USE_DB_SHOP_COORDINATES === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SHOP_COORDINATES_DIR = path.join(DATA_DIR, 'shop-coordinates');

async function ensureDir() {
  await fsp.mkdir(SHOP_COORDINATES_DIR, { recursive: true });
}

// Initialize directory on module load (async IIFE)
(async () => {
  try {
    await ensureDir();
  } catch (e) {
    console.error('Failed to create shop-coordinates directory:', e);
  }
})();

function setupShopCoordinatesAPI(app) {
  // ===== GET ALL SHOP COORDINATES =====
  app.get('/api/shop-coordinates', async (req, res) => {
    try {
      console.log('GET /api/shop-coordinates');

      if (USE_DB) {
        const rows = await db.findAll('shop_coordinates', { orderBy: 'created_at', orderDir: 'ASC' });
        return res.json({ success: true, coordinates: rows.map(r => r.data) });
      }

      const coordinates = [];

      if (await fileExists(SHOP_COORDINATES_DIR)) {
        const files = await fsp.readdir(SHOP_COORDINATES_DIR);
        const jsonFiles = files.filter(f => f.endsWith('.json'));

        for (const file of jsonFiles) {
          try {
            const content = await fsp.readFile(path.join(SHOP_COORDINATES_DIR, file), 'utf8');
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

      if (USE_DB) {
        const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
        const row = await db.findById('shop_coordinates', sanitizedAddress);
        return res.json({ success: true, coordinates: row ? row.data : null });
      }

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const filePath = path.join(SHOP_COORDINATES_DIR, `${sanitizedAddress}.json`);

      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        const coords = JSON.parse(content);
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

      await ensureDir();

      const sanitizedAddress = coords.shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const filePath = path.join(SHOP_COORDINATES_DIR, `${sanitizedAddress}.json`);

      coords.updatedAt = new Date().toISOString();
      await writeJsonFile(filePath, coords);

      if (USE_DB) {
        try { await db.upsert('shop_coordinates', { id: sanitizedAddress, data: coords, created_at: coords.updatedAt, updated_at: coords.updatedAt }); }
        catch (dbErr) { console.error('DB save shop_coordinates error:', dbErr.message); }
      }

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

      await ensureDir();

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
      const filePath = path.join(SHOP_COORDINATES_DIR, `${sanitizedAddress}.json`);

      let coords = { shopAddress };
      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        coords = JSON.parse(content);
      }

      const updated = { ...coords, ...updates, updatedAt: new Date().toISOString() };
      await writeJsonFile(filePath, updated);

      if (USE_DB) {
        try { await db.upsert('shop_coordinates', { id: sanitizedAddress, data: updated, updated_at: updated.updatedAt }); }
        catch (dbErr) { console.error('DB update shop_coordinates error:', dbErr.message); }
      }

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

      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);

        if (USE_DB) {
          try { await db.deleteById('shop_coordinates', sanitizedAddress); }
          catch (dbErr) { console.error('DB delete shop_coordinates error:', dbErr.message); }
        }

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

      let shopCoords = null;

      if (USE_DB) {
        const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
        const row = await db.findById('shop_coordinates', sanitizedAddress);
        if (!row) {
          return res.json({ success: true, isNear: true, message: 'No coordinates set for shop' });
        }
        shopCoords = row.data;
      } else {
        const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-а-яА-ЯёЁ\s,\.]/g, '_');
        const filePath = path.join(SHOP_COORDINATES_DIR, `${sanitizedAddress}.json`);

        if (!(await fileExists(filePath))) {
          return res.json({ success: true, isNear: true, message: 'No coordinates set for shop' });
        }

        const content = await fsp.readFile(filePath, 'utf8');
        shopCoords = JSON.parse(content);
      }

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

  console.log(`✅ Shop Coordinates API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = { setupShopCoordinatesAPI };
