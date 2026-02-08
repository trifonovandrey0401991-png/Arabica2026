/**
 * Loyalty Promo API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const LOYALTY_PROMO_FILE = `${DATA_DIR}/loyalty-promo.json`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Helper functions
async function loadPromos() {
  try {
    if (await fileExists(LOYALTY_PROMO_FILE)) {
      const data = await fsp.readFile(LOYALTY_PROMO_FILE, 'utf8');
      return JSON.parse(data).promos || [];
    }
  } catch (e) {
    console.error('Error loading loyalty-promo:', e);
  }
  return [];
}

async function loadPromoFile() {
  try {
    if (await fileExists(LOYALTY_PROMO_FILE)) {
      const data = await fsp.readFile(LOYALTY_PROMO_FILE, 'utf8');
      return JSON.parse(data);
    }
  } catch (e) {
    console.error('Error loading loyalty-promo file:', e);
  }
  return { promos: [] };
}

async function savePromos(promos) {
  const data = { promos, updatedAt: new Date().toISOString() };

  // Preserve other fields like promoText, pointsRequired, drinksToGive
  try {
    const existing = await loadPromoFile();
    data.promoText = existing.promoText;
    data.pointsRequired = existing.pointsRequired;
    data.drinksToGive = existing.drinksToGive;
  } catch (e) {
    // Ignore - new file
  }

  await fsp.writeFile(LOYALTY_PROMO_FILE, JSON.stringify(data, null, 2), 'utf8');
}

function setupLoyaltyPromoAPI(app) {
  // ===== GET ALL PROMOS =====
  app.get('/api/loyalty-promo', async (req, res) => {
    try {
      console.log('GET /api/loyalty-promo');
      const { active, type } = req.query;

      let promos = await loadPromos();

      // Filter by active status
      if (active === 'true') {
        const now = new Date();
        promos = promos.filter(p => {
          if (!p.isActive) return false;
          if (p.startDate && new Date(p.startDate) > now) return false;
          if (p.endDate && new Date(p.endDate) < now) return false;
          return true;
        });
      } else if (active === 'false') {
        promos = promos.filter(p => !p.isActive);
      }

      // Filter by type
      if (type) {
        promos = promos.filter(p => p.type === type);
      }

      promos.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      // Load full file to get additional fields
      const fullData = await loadPromoFile();
      res.json({
        success: true,
        promos,
        promoText: fullData.promoText || "",
        pointsRequired: fullData.pointsRequired || 9,
        drinksToGive: fullData.drinksToGive || 1
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET SINGLE PROMO =====
  app.get('/api/loyalty-promo/:promoId', async (req, res) => {
    try {
      const { promoId } = req.params;
      const promos = await loadPromos();
      const promo = promos.find(p => p.id === promoId);

      if (promo) {
        res.json({ success: true, promo });
      } else {
        res.status(404).json({ success: false, error: 'Promo not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== CREATE PROMO =====
  app.post('/api/loyalty-promo', async (req, res) => {
    try {
      const promo = req.body;
      console.log('POST /api/loyalty-promo:', promo.name);

      if (!promo.name || !promo.type) {
        return res.status(400).json({
          success: false,
          error: 'name and type are required'
        });
      }

      const promos = await loadPromos();

      if (!promo.id) {
        promo.id = `promo_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      promo.createdAt = new Date().toISOString();
      promo.isActive = promo.isActive !== false;

      promos.push(promo);
      await savePromos(promos);

      res.json({ success: true, promo });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== UPDATE PROMO =====
  app.put('/api/loyalty-promo/:promoId', async (req, res) => {
    try {
      const { promoId } = req.params;
      const updates = req.body;
      console.log('PUT /api/loyalty-promo:', promoId);

      const promos = await loadPromos();
      const index = promos.findIndex(p => p.id === promoId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Promo not found' });
      }

      promos[index] = {
        ...promos[index],
        ...updates,
        updatedAt: new Date().toISOString()
      };

      await savePromos(promos);
      res.json({ success: true, promo: promos[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== DELETE PROMO =====
  app.delete('/api/loyalty-promo/:promoId', async (req, res) => {
    try {
      const { promoId } = req.params;
      console.log('DELETE /api/loyalty-promo:', promoId);

      const promos = await loadPromos();
      const index = promos.findIndex(p => p.id === promoId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Promo not found' });
      }

      promos.splice(index, 1);
      await savePromos(promos);

      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ACTIVATE/DEACTIVATE PROMO =====
  app.post('/api/loyalty-promo/:promoId/toggle', async (req, res) => {
    try {
      const { promoId } = req.params;
      console.log('POST /api/loyalty-promo/:promoId/toggle:', promoId);

      const promos = await loadPromos();
      const index = promos.findIndex(p => p.id === promoId);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Promo not found' });
      }

      promos[index].isActive = !promos[index].isActive;
      promos[index].updatedAt = new Date().toISOString();

      await savePromos(promos);
      res.json({ success: true, promo: promos[index] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== GET ACTIVE PROMOS FOR CLIENT =====
  app.get('/api/loyalty-promo/active/client', async (req, res) => {
    try {
      console.log('GET /api/loyalty-promo/active/client');
      const now = new Date();

      let promos = (await loadPromos()).filter(p => {
        if (!p.isActive) return false;
        if (p.startDate && new Date(p.startDate) > now) return false;
        if (p.endDate && new Date(p.endDate) < now) return false;
        return true;
      });

      // Return simplified info for clients
      promos = promos.map(p => ({
        id: p.id,
        name: p.name,
        description: p.description,
        type: p.type,
        discount: p.discount,
        bonusMultiplier: p.bonusMultiplier,
        imageUrl: p.imageUrl,
        startDate: p.startDate,
        endDate: p.endDate
      }));

      res.json({ success: true, promos });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('Loyalty Promo API initialized');
}

module.exports = { setupLoyaltyPromoAPI };
