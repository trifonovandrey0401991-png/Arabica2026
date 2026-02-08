/**
 * Loyalty Promo API
 * Настройки акции лояльности (баллы за напитки)
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const LOYALTY_PROMO_FILE = `${DATA_DIR}/loyalty-promo.json`;

function setupLoyaltyPromoAPI(app, { loadAllEmployeesForWithdrawals } = {}) {
  // GET /api/loyalty-promo - получить настройки акции
  app.get('/api/loyalty-promo', async (req, res) => {
    try {
      let settings = {
        promoText: 'При покупке 9 напитков 10-й бесплатно',
        pointsRequired: 9,
        drinksToGive: 1,
        success: true
      };

      if (await fileExists(LOYALTY_PROMO_FILE)) {
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
  app.post('/api/loyalty-promo', async (req, res) => {
    try {
      const { promoText, pointsRequired, drinksToGive, employeePhone } = req.body;

      // Проверка на админа или разработчика
      const normalizedPhone = (employeePhone || '').replace(/[\s\+]/g, '');
      const employees = loadAllEmployeesForWithdrawals ? await loadAllEmployeesForWithdrawals() : [];
      const employee = employees.find(e => e.phone && e.phone.replace(/[\s\+]/g, '') === normalizedPhone);
      const isAdminOrDev = employee && (employee.isAdmin === true || employee.role === 'developer');
      if (!isAdminOrDev) {
        console.log('POST /api/loyalty-promo: denied for non-admin', normalizedPhone);
        return res.status(403).json({ success: false, error: 'Доступ запрещён' });
      }

      const settings = {
        promoText: promoText || '',
        pointsRequired: parseInt(pointsRequired) || 9,
        drinksToGive: parseInt(drinksToGive) || 1,
        updatedAt: new Date().toISOString(),
        updatedBy: normalizedPhone
      };

      await fsp.writeFile(LOYALTY_PROMO_FILE, JSON.stringify(settings, null, 2), 'utf8');
      console.log('POST /api/loyalty-promo:', settings.pointsRequired + '+' + settings.drinksToGive, 'by', normalizedPhone);
      res.json({ success: true, ...settings });
    } catch (e) {
      console.error('Error saving loyalty-promo:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  console.log('✅ Loyalty Promo API initialized');
}

module.exports = { setupLoyaltyPromoAPI };
