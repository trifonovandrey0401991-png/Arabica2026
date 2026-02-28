/**
 * Loyalty Promo API
 * Настройки акции лояльности (баллы за напитки)
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth, requireAdmin } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_LOYALTY_PROMO === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const LOYALTY_PROMO_FILE = `${DATA_DIR}/loyalty-promo.json`;

function setupLoyaltyPromoAPI(app, { loadAllEmployeesForWithdrawals } = {}) {
  // GET /api/loyalty-promo - получить настройки акции (публичный - это просто маркетинговый текст)
  app.get('/api/loyalty-promo', async (req, res) => {
    try {
      let settings = {
        promoText: 'Копите баллы и обменивайте на напитки и товары!',
        pointsRequired: 9,
        drinksToGive: 1,
        pointsPerScan: 1,   // Default: 1 loyalty point per QR scan (configurable)
        success: true
      };

      if (USE_DB) {
        const row = await db.findById('app_settings', 'loyalty_promo', 'key');
        if (row) settings = { ...settings, ...row.data, success: true };
      } else if (await fileExists(LOYALTY_PROMO_FILE)) {
        const data = JSON.parse(await fsp.readFile(LOYALTY_PROMO_FILE, 'utf8'));
        settings = { ...settings, ...data, success: true };
      }

      console.log('GET /api/loyalty-promo:', settings.pointsRequired + '+' + settings.drinksToGive);
      res.json(settings);
    } catch (e) {
      console.error('Error getting loyalty-promo:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/loyalty-promo - сохранить настройки акции (только админ)
  app.post('/api/loyalty-promo', requireAdmin, async (req, res) => {
    try {
      const { promoText, pointsRequired, drinksToGive, pointsPerScan } = req.body;

      const settings = {
        promoText: promoText || '',
        pointsRequired: parseInt(pointsRequired) || 9,
        drinksToGive: parseInt(drinksToGive) || 1,
        pointsPerScan: parseInt(pointsPerScan) || 10,
        updatedAt: new Date().toISOString(),
        updatedBy: req.user.phone
      };

      await writeJsonFile(LOYALTY_PROMO_FILE, settings);

      if (USE_DB) {
        try { await db.upsert('app_settings', { key: 'loyalty_promo', data: settings, updated_at: settings.updatedAt }, 'key'); }
        catch (dbErr) { console.error('DB save loyalty_promo error:', dbErr.message); }
      }

      console.log('POST /api/loyalty-promo:', settings.pointsRequired + '+' + settings.drinksToGive, 'pointsPerScan:', settings.pointsPerScan, 'by', req.user.phone);
      res.json({ success: true, ...settings });
    } catch (e) {
      console.error('Error saving loyalty-promo:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  console.log(`✅ Loyalty Promo API initialized ${USE_DB ? '(DB mode)' : '(file mode)'}`);
}

module.exports = { setupLoyaltyPromoAPI };
