/**
 * Shop Settings API - Настройки магазинов для РКО
 * Включает интервалы смен, аббревиатуры, ИНН, руководителя
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SETTINGS_DIR = path.join(DATA_DIR, 'shop-settings');

// Проверка существования файла (async)
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Убедиться что директория существует (async)
async function ensureDir() {
  await fsp.mkdir(SETTINGS_DIR, { recursive: true });
}

// Получить имя файла по адресу магазина (async)
async function getSettingsFile(shopAddress) {
  await ensureDir();

  // Сначала ищем файл по содержимому shopAddress (самый надёжный способ)
  let files = [];
  try {
    files = await fsp.readdir(SETTINGS_DIR);
  } catch {
    files = [];
  }

  for (const file of files) {
    if (!file.endsWith('.json')) continue;
    try {
      const content = await fsp.readFile(path.join(SETTINGS_DIR, file), 'utf8');
      const data = JSON.parse(content);
      if (data.shopAddress === shopAddress) {
        return path.join(SETTINGS_DIR, file);
      }
    } catch (e) {
      // Ignore parse errors
    }
  }

  // Если не найден, создаём новый файл
  const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
  return path.join(SETTINGS_DIR, `${sanitizedAddress}.json`);
}

function setup(app) {
  // Получить настройки магазина
  app.get('/api/shop-settings/:shopAddress', async (req, res) => {
    try {
      const shopAddress = decodeURIComponent(req.params.shopAddress);
      console.log('GET /api/shop-settings:', shopAddress);

      await ensureDir();

      const settingsFile = await getSettingsFile(shopAddress);

      if (!(await fileExists(settingsFile))) {
        return res.json({
          success: true,
          settings: null
        });
      }

      const content = await fsp.readFile(settingsFile, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Ошибка получения настроек магазина:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при получении настроек магазина'
      });
    }
  });

  // Сохранить настройки магазина
  app.post('/api/shop-settings', async (req, res) => {
    try {
      console.log('POST /api/shop-settings');
      console.log('   Тело запроса:', JSON.stringify(req.body, null, 2));

      await ensureDir();

      const shopAddress = req.body.shopAddress;
      if (!shopAddress) {
        console.log('   Адрес магазина не указан');
        return res.status(400).json({
          success: false,
          error: 'Адрес магазина не указан'
        });
      }

      const settingsFile = await getSettingsFile(shopAddress);
      console.log('   Файл настроек:', settingsFile);

      // Если файл существует, сохраняем некоторые поля из старого файла
      let existingSettings = {};
      if (await fileExists(settingsFile)) {
        try {
          const oldContent = await fsp.readFile(settingsFile, 'utf8');
          existingSettings = JSON.parse(oldContent);
          console.log('   Загружены существующие настройки');
        } catch (e) {
          console.error('   Ошибка чтения старого файла:', e);
        }
      }

      // Собираем настройки
      const settings = {
        shopAddress: shopAddress,
        address: req.body.address || existingSettings.address || '',
        inn: req.body.inn || existingSettings.inn || '',
        directorName: req.body.directorName || existingSettings.directorName || '',
        lastDocumentNumber: existingSettings.lastDocumentNumber || 0,
        updatedAt: new Date().toISOString(),
        // Интервалы времени для смен
        morningShiftStart: req.body.morningShiftStart !== undefined ? req.body.morningShiftStart : existingSettings.morningShiftStart,
        morningShiftEnd: req.body.morningShiftEnd !== undefined ? req.body.morningShiftEnd : existingSettings.morningShiftEnd,
        dayShiftStart: req.body.dayShiftStart !== undefined ? req.body.dayShiftStart : existingSettings.dayShiftStart,
        dayShiftEnd: req.body.dayShiftEnd !== undefined ? req.body.dayShiftEnd : existingSettings.dayShiftEnd,
        nightShiftStart: req.body.nightShiftStart !== undefined ? req.body.nightShiftStart : existingSettings.nightShiftStart,
        nightShiftEnd: req.body.nightShiftEnd !== undefined ? req.body.nightShiftEnd : existingSettings.nightShiftEnd,
        // Аббревиатуры
        morningAbbreviation: req.body.morningAbbreviation !== undefined ? req.body.morningAbbreviation : existingSettings.morningAbbreviation,
        dayAbbreviation: req.body.dayAbbreviation !== undefined ? req.body.dayAbbreviation : existingSettings.dayAbbreviation,
        nightAbbreviation: req.body.nightAbbreviation !== undefined ? req.body.nightAbbreviation : existingSettings.nightAbbreviation,
        // Дата создания
        createdAt: existingSettings.createdAt || new Date().toISOString(),
      };

      await fsp.writeFile(settingsFile, JSON.stringify(settings, null, 2), 'utf8');
      console.log('   Настройки магазина сохранены:', settingsFile);

      res.json({
        success: true,
        message: 'Настройки успешно сохранены'
      });
    } catch (error) {
      console.error('Ошибка сохранения настроек магазина:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при сохранении настроек'
      });
    }
  });

  // Получить следующий номер документа для магазина
  app.get('/api/shop-settings/:shopAddress/document-number', async (req, res) => {
    try {
      const shopAddress = decodeURIComponent(req.params.shopAddress);
      console.log('GET /api/shop-settings/:shopAddress/document-number:', shopAddress);

      const settingsFile = await getSettingsFile(shopAddress);

      if (!(await fileExists(settingsFile))) {
        return res.json({
          success: true,
          documentNumber: 1
        });
      }

      const content = await fsp.readFile(settingsFile, 'utf8');
      const settings = JSON.parse(content);

      let nextNumber = (settings.lastDocumentNumber || 0) + 1;
      if (nextNumber > 50000) {
        nextNumber = 1;
      }

      res.json({
        success: true,
        documentNumber: nextNumber
      });
    } catch (error) {
      console.error('Ошибка получения номера документа:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при получении номера документа'
      });
    }
  });

  // Обновить номер документа для магазина
  app.post('/api/shop-settings/:shopAddress/document-number', async (req, res) => {
    try {
      const shopAddress = decodeURIComponent(req.params.shopAddress);
      const { documentNumber } = req.body;
      console.log('POST /api/shop-settings/:shopAddress/document-number:', shopAddress, documentNumber);

      await ensureDir();

      const settingsFile = await getSettingsFile(shopAddress);

      let settings = {};
      if (await fileExists(settingsFile)) {
        const content = await fsp.readFile(settingsFile, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.shopAddress = shopAddress;
        settings.createdAt = new Date().toISOString();
      }

      settings.lastDocumentNumber = documentNumber || 0;
      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(settingsFile, JSON.stringify(settings, null, 2), 'utf8');
      console.log('Номер документа обновлен:', settingsFile);

      res.json({
        success: true,
        message: 'Номер документа успешно обновлен'
      });
    } catch (error) {
      console.error('Ошибка обновления номера документа:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при обновлении номера документа'
      });
    }
  });

  console.log('   Shop Settings API loaded');
}

module.exports = { setup };
