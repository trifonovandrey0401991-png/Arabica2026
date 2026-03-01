/**
 * Store Links API
 * Настройки ссылок на магазины приложений (Google Play / App Store)
 * Используется для генерации QR-кодов в диалоге «Код приглашения»
 */

const fsp = require('fs').promises;
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth, requireAdmin } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_STORE_LINKS !== 'false'; // default true

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const STORE_LINKS_FILE = `${DATA_DIR}/store-links.json`;

function setupStoreLinksAPI(app) {
  // GET /api/app-settings/store-links — получить ссылки на магазины
  app.get('/api/app-settings/store-links', requireAuth, async (req, res) => {
    try {
      let settings = { android_url: '', ios_url: '' };

      if (USE_DB) {
        const row = await db.findById('app_settings', 'store_links', 'key');
        if (row) settings = { ...settings, ...row.data };
      } else if (await fileExists(STORE_LINKS_FILE)) {
        const data = JSON.parse(await fsp.readFile(STORE_LINKS_FILE, 'utf8'));
        settings = { ...settings, ...data };
      }

      res.json({ success: true, ...settings });
    } catch (err) {
      console.error('GET /api/app-settings/store-links error:', err.message);
      res.status(500).json({ success: false, error: err.message });
    }
  });

  // POST /api/app-settings/store-links — сохранить ссылки (только админ)
  app.post('/api/app-settings/store-links', requireAdmin, async (req, res) => {
    try {
      const { android_url, ios_url } = req.body;

      const settings = {
        android_url: (android_url || '').trim(),
        ios_url: (ios_url || '').trim(),
        updated_at: new Date().toISOString(),
      };

      // Dual-write: JSON first, then DB
      await writeJsonFile(STORE_LINKS_FILE, settings);

      if (USE_DB) {
        try {
          await db.upsert('app_settings', {
            key: 'store_links',
            data: settings,
            updated_at: settings.updated_at,
          }, 'key');
        } catch (dbErr) {
          console.error('DB save store_links error:', dbErr.message);
        }
      }

      console.log('POST /api/app-settings/store-links:', settings.android_url ? 'android=' + settings.android_url : 'no-android', settings.ios_url ? 'ios=' + settings.ios_url : 'no-ios', 'by', req.user.phone);
      res.json({ success: true, ...settings });
    } catch (err) {
      console.error('POST /api/app-settings/store-links error:', err.message);
      res.status(500).json({ success: false, error: err.message });
    }
  });
}

module.exports = { setupStoreLinksAPI };
