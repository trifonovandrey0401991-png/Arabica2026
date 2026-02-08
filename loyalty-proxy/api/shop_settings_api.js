/**
 * Shop Settings API - Настройки магазинов для РКО
 * Включает интервалы смен, аббревиатуры, ИНН, руководителя, номера документов
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

function setupShopSettingsAPI(app) {
  // Получить настройки магазина
  app.get('/api/shop-settings/:shopAddress', async (req, res) => {
    try {
      const shopAddress = decodeURIComponent(req.params.shopAddress);
      console.log('GET /api/shop-settings:', shopAddress);

      const settingsDir = `${DATA_DIR}/shop-settings`;
      if (!await fileExists(settingsDir)) {
        await fsp.mkdir(settingsDir, { recursive: true });
      }

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);

      if (!await fileExists(settingsFile)) {
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
      console.log('📝 POST /api/shop-settings');
      console.log('   Тело запроса:', JSON.stringify(req.body, null, 2));

      const settingsDir = `${DATA_DIR}/shop-settings`;
      console.log('   Проверка директории:', settingsDir);

      if (!await fileExists(settingsDir)) {
        console.log('   Создание директории:', settingsDir);
        await fsp.mkdir(settingsDir, { recursive: true });
        console.log('   ✅ Директория создана');
      } else {
        console.log('   ✅ Директория существует');
      }

      const shopAddress = req.body.shopAddress;
      if (!shopAddress) {
        console.log('   ❌ Адрес магазина не указан');
        return res.status(400).json({
          success: false,
          error: 'Адрес магазина не указан'
        });
      }

      console.log('   Адрес магазина:', shopAddress);
      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
      console.log('   Очищенный адрес:', sanitizedAddress);

      const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);
      console.log('   Файл настроек:', settingsFile);

      // Если файл существует, сохраняем lastDocumentNumber из старого файла
      let lastDocumentNumber = req.body.lastDocumentNumber || 0;
      if (await fileExists(settingsFile)) {
        try {
          console.log('   Чтение существующего файла...');
          const oldContent = await fsp.readFile(settingsFile, 'utf8');
          const oldSettings = JSON.parse(oldContent);
          if (oldSettings.lastDocumentNumber !== undefined) {
            lastDocumentNumber = oldSettings.lastDocumentNumber;
            console.log('   Сохранен lastDocumentNumber:', lastDocumentNumber);
          }
        } catch (e) {
          console.error('   ⚠️ Ошибка чтения старого файла:', e);
        }
      } else {
        console.log('   Файл не существует, будет создан новый');
      }

      const settings = {
        shopAddress: shopAddress,
        address: req.body.address || '',
        inn: req.body.inn || '',
        directorName: req.body.directorName || '',
        lastDocumentNumber: lastDocumentNumber,
        // Интервалы времени для смен
        morningShiftStart: req.body.morningShiftStart || null,
        morningShiftEnd: req.body.morningShiftEnd || null,
        dayShiftStart: req.body.dayShiftStart || null,
        dayShiftEnd: req.body.dayShiftEnd || null,
        nightShiftStart: req.body.nightShiftStart || null,
        nightShiftEnd: req.body.nightShiftEnd || null,
        // Аббревиатуры для смен
        morningAbbreviation: req.body.morningAbbreviation || null,
        dayAbbreviation: req.body.dayAbbreviation || null,
        nightAbbreviation: req.body.nightAbbreviation || null,
        updatedAt: new Date().toISOString(),
      };

      if (await fileExists(settingsFile)) {
        try {
          const oldContent = await fsp.readFile(settingsFile, 'utf8');
          const oldSettings = JSON.parse(oldContent);
          if (oldSettings.createdAt) {
            settings.createdAt = oldSettings.createdAt;
            console.log('   Сохранена дата создания:', settings.createdAt);
          }
        } catch (e) {
          console.error('   ⚠️ Ошибка при чтении createdAt:', e);
        }
      } else {
        settings.createdAt = new Date().toISOString();
        console.log('   Установлена новая дата создания:', settings.createdAt);
      }

      console.log('   Сохранение настроек:', JSON.stringify(settings, null, 2));

      try {
        await fsp.writeFile(settingsFile, JSON.stringify(settings, null, 2), 'utf8');
        console.log('   ✅ Настройки магазина сохранены:', settingsFile);

        res.json({
          success: true,
          message: 'Настройки успешно сохранены',
          settings: settings
        });
      } catch (writeError) {
        console.error('   ❌ Ошибка записи файла:', writeError);
        throw writeError;
      }
    } catch (error) {
      console.error('❌ Ошибка сохранения настроек магазина:', error);
      console.error('   Stack:', error.stack);
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

      const settingsDir = `${DATA_DIR}/shop-settings`;
      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);

      if (!await fileExists(settingsFile)) {
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

      const settingsDir = `${DATA_DIR}/shop-settings`;
      if (!await fileExists(settingsDir)) {
        await fsp.mkdir(settingsDir, { recursive: true });
      }

      const sanitizedAddress = shopAddress.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const settingsFile = path.join(settingsDir, `${sanitizedAddress}.json`);

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

  console.log('✅ Shop Settings API initialized');
}

module.exports = { setupShopSettingsAPI };
