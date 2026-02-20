/**
 * Z-Report API Module
 * API для работы с шаблонами и распознаванием Z-отчётов
 */

const fs = require('fs').promises;
const path = require('path');

const templatesModule = require('../modules/z-report-templates');
const visionModule = require('../modules/z-report-vision');
const intelligenceModule = require('../modules/z-report-intelligence');
const { sanitizeId } = require('../utils/file_helpers');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const { requireAuth } = require('../utils/session_middleware');

// Директория для изображений шаблонов
const TEMPLATE_IMAGES_DIR = path.join(__dirname, '../data/template-images');
const REGION_SET_IMAGES_DIR = path.join(__dirname, '../data/region-set-images');

/**
 * Настройка API для Z-отчётов
 */
async function setupZReportAPI(app) {
  console.log('[Z-Report API] Инициализация...');

  // Убедимся что директории существуют
  await ensureDirectories();

  // ============ ШАБЛОНЫ ============

  // Получить все шаблоны
  app.get('/api/z-report/templates', requireAuth, async (req, res) => {
    try {
      const { shopId } = req.query;
      const templates = await templatesModule.getTemplates(shopId);
      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(templates, req.query, 'templates'));
      }
      res.json({ success: true, templates });
    } catch (error) {
      console.error('[Z-Report API] Ошибка получения шаблонов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Найти шаблон для магазина (MUST be before /:id to avoid shadowing)
  app.get('/api/z-report/templates/find', requireAuth, async (req, res) => {
    try {
      const { shopId } = req.query;
      const template = await templatesModule.findTemplateForShop(shopId);
      res.json({ success: true, template });
    } catch (error) {
      console.error('[Z-Report API] Ошибка поиска шаблона:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить шаблон по ID
  app.get('/api/z-report/templates/:id', requireAuth, async (req, res) => {
    try {
      const template = await templatesModule.getTemplate(req.params.id);
      if (template) {
        res.json({ success: true, template });
      } else {
        res.status(404).json({ success: false, error: 'Шаблон не найден' });
      }
    } catch (error) {
      console.error('[Z-Report API] Ошибка получения шаблона:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Сохранить шаблон
  app.post('/api/z-report/templates', requireAuth, async (req, res) => {
    try {
      const { template, sampleImage, regionSetImages } = req.body;

      // Сохраняем шаблон
      const saved = await templatesModule.saveTemplate(template, sampleImage);

      // Сохраняем изображения для наборов областей (форматов)
      if (regionSetImages && typeof regionSetImages === 'object') {
        for (const [setId, imageBase64] of Object.entries(regionSetImages)) {
          if (imageBase64) {
            await saveRegionSetImage(saved.id, setId, imageBase64);
          }
        }
      }

      res.json({ success: true, template: saved });
    } catch (error) {
      console.error('[Z-Report API] Ошибка сохранения шаблона:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Удалить шаблон
  app.delete('/api/z-report/templates/:id', requireAuth, async (req, res) => {
    try {
      await templatesModule.deleteTemplate(req.params.id);

      // Удаляем все изображения форматов
      await deleteAllRegionSetImages(req.params.id);

      res.json({ success: true });
    } catch (error) {
      console.error('[Z-Report API] Ошибка удаления шаблона:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Обновить статистику шаблона
  app.post('/api/z-report/templates/:id/stats', requireAuth, async (req, res) => {
    try {
      const { wasSuccessful } = req.body;
      await templatesModule.updateTemplateStats(req.params.id, wasSuccessful);
      res.json({ success: true });
    } catch (error) {
      console.error('[Z-Report API] Ошибка обновления статистики:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ИЗОБРАЖЕНИЯ ШАБЛОНОВ ============

  // Получить основное изображение шаблона
  app.get('/api/z-report/templates/:id/image', requireAuth, async (req, res) => {
    try {
      const imagePath = path.join(TEMPLATE_IMAGES_DIR, `${sanitizeId(req.params.id)}.jpg`);
      try {
        await fs.access(imagePath);
        res.sendFile(imagePath);
      } catch {
        res.status(404).json({ success: false, error: 'Изображение не найдено' });
      }
    } catch (error) {
      console.error('[Z-Report API] Ошибка получения изображения:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ИЗОБРАЖЕНИЯ ФОРМАТОВ (REGION SETS) ============

  // Сохранить изображение для формата
  app.post('/api/z-report/templates/:templateId/region-sets/:setId/image', requireAuth, async (req, res) => {
    try {
      const { templateId, setId } = req.params;
      const { imageBase64 } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение не передано' });
      }

      await saveRegionSetImage(sanitizeId(templateId), sanitizeId(setId), imageBase64);
      res.json({ success: true });
    } catch (error) {
      console.error('[Z-Report API] Ошибка сохранения изображения формата:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить изображение формата
  app.get('/api/z-report/templates/:templateId/region-sets/:setId/image', requireAuth, async (req, res) => {
    try {
      const templateId = sanitizeId(req.params.templateId);
      const setId = sanitizeId(req.params.setId);
      const imagePath = path.join(REGION_SET_IMAGES_DIR, templateId, `${setId}.jpg`);

      try {
        await fs.access(imagePath);
        res.sendFile(imagePath);
      } catch {
        // Если нет изображения для формата — пробуем основное изображение шаблона
        const mainImagePath = path.join(TEMPLATE_IMAGES_DIR, `${templateId}.jpg`);
        try {
          await fs.access(mainImagePath);
          res.sendFile(mainImagePath);
        } catch {
          res.status(404).json({ success: false, error: 'Изображение не найдено' });
        }
      }
    } catch (error) {
      console.error('[Z-Report API] Ошибка получения изображения формата:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Удалить изображение формата
  app.delete('/api/z-report/templates/:templateId/region-sets/:setId/image', requireAuth, async (req, res) => {
    try {
      const templateId = sanitizeId(req.params.templateId);
      const setId = sanitizeId(req.params.setId);
      const imagePath = path.join(REGION_SET_IMAGES_DIR, templateId, `${setId}.jpg`);

      try {
        await fs.unlink(imagePath);
      } catch {
        // Файл не существует — OK
      }

      res.json({ success: true });
    } catch (error) {
      console.error('[Z-Report API] Ошибка удаления изображения формата:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ РАСПОЗНАВАНИЕ ============

  // Распознать Z-отчёт
  app.post('/api/z-report/parse', requireAuth, async (req, res) => {
    try {
      const { imageBase64, shopAddress, explicitRegions } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение не передано' });
      }

      // Лимит размера: ~5MB base64 ≈ ~3.75MB изображение
      if (imageBase64.length > 7 * 1024 * 1024) {
        return res.status(413).json({ success: false, error: 'Изображение слишком большое (макс 5MB)' });
      }

      // Загружаем intelligence для подсказки ожидаемых диапазонов
      let expectedRanges = null;
      let learnedRegions = null;
      if (shopAddress) {
        try {
          const intelligence = await intelligenceModule.loadZReportIntelligence();
          expectedRanges = intelligenceModule.getExpectedRanges(intelligence, shopAddress);
        } catch (e) {
          console.error('[Z-Report API] Intelligence load error:', e.message);
        }
        try {
          learnedRegions = await templatesModule.getLearnedRegions(shopAddress);
        } catch (e) {
          console.error('[Z-Report API] Learned regions load error:', e.message);
        }
      }

      // Явные регионы от пользователя имеют приоритет над обученными
      const regionsToUse = explicitRegions || learnedRegions;
      const result = await visionModule.parseZReport(imageBase64, expectedRanges, regionsToUse);

      // Добавляем intelligence в ответ (для отображения подсказок в UI)
      if (expectedRanges) {
        result.expectedRanges = expectedRanges;
      }

      res.json(result);
    } catch (error) {
      console.error('[Z-Report API] Ошибка распознавания:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Распознать с использованием шаблона
  app.post('/api/z-report/parse-with-template', requireAuth, async (req, res) => {
    try {
      const { imageBase64, templateId } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение не передано' });
      }

      if (!templateId) {
        return res.status(400).json({ success: false, error: 'Не указан ID шаблона' });
      }

      // Загружаем шаблон
      const template = await templatesModule.getTemplate(templateId);
      if (!template) {
        return res.status(404).json({ success: false, error: 'Шаблон не найден' });
      }

      // Распознаём с шаблоном
      const result = await visionModule.parseZReportWithTemplate(imageBase64, template);
      res.json(result);
    } catch (error) {
      console.error('[Z-Report API] Ошибка распознавания с шаблоном:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ОБУЧЕНИЕ ============

  // Сохранить образец для обучения
  app.post('/api/z-report/training-samples', requireAuth, async (req, res) => {
    try {
      const { imageBase64, rawText, correctData, recognizedData, shopId, templateId, fieldRegions } = req.body;

      // Лимит размера изображения
      if (imageBase64 && imageBase64.length > 7 * 1024 * 1024) {
        return res.status(413).json({ success: false, error: 'Изображение слишком большое (макс 5MB)' });
      }

      const result = await templatesModule.addTrainingSample({
        imageBase64,
        rawText,
        correctData,
        recognizedData,
        shopId,
        templateId,
        fieldRegions,
      });

      // Фоновое обновление intelligence после нового образца
      intelligenceModule.buildZReportIntelligence().catch(e =>
        console.error('[Z-Report API] Intelligence rebuild error:', e.message)
      );

      // Возвращаем sample и результат обучения
      res.json({
        success: true,
        sample: result.sample,
        learningResult: result.learningResult
      });
    } catch (error) {
      console.error('[Z-Report API] Ошибка сохранения образца:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить статистику обучения
  app.get('/api/z-report/training-stats', requireAuth, async (req, res) => {
    try {
      const stats = await templatesModule.getTrainingStats();
      res.json({ success: true, ...stats });
    } catch (error) {
      console.error('[Z-Report API] Ошибка получения статистики:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить список образцов (без изображений)
  app.get('/api/z-report/training-samples', requireAuth, async (req, res) => {
    try {
      const { shopId } = req.query;
      const samples = await templatesModule.getTrainingSamplesList(shopId || null);
      res.json({ success: true, samples, total: samples.length });
    } catch (error) {
      console.error('[Z-Report API] Ошибка получения списка образцов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить изображение образца
  app.get('/api/z-report/training-samples/:id/image', requireAuth, async (req, res) => {
    try {
      const imagePath = templatesModule.getTrainingSampleImagePath(sanitizeId(req.params.id));
      try {
        await fs.access(imagePath);
        res.sendFile(imagePath);
      } catch {
        res.status(404).json({ success: false, error: 'Изображение не найдено' });
      }
    } catch (error) {
      console.error('[Z-Report API] Ошибка получения изображения образца:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Удалить образец
  app.delete('/api/z-report/training-samples/:id', requireAuth, async (req, res) => {
    try {
      const deleted = await templatesModule.deleteTrainingSample(sanitizeId(req.params.id));

      if (!deleted) {
        return res.status(404).json({ success: false, error: 'Образец не найден' });
      }

      // Фоновое обновление intelligence
      intelligenceModule.buildZReportIntelligence().catch(e =>
        console.error('[Z-Report API] Intelligence rebuild error:', e.message)
      );

      res.json({ success: true });
    } catch (error) {
      console.error('[Z-Report API] Ошибка удаления образца:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ INTELLIGENCE ============

  // Получить ожидаемые диапазоны для магазина
  app.get('/api/z-report/intelligence', requireAuth, async (req, res) => {
    try {
      const { shopAddress } = req.query;
      const intelligence = await intelligenceModule.loadZReportIntelligence();

      if (shopAddress) {
        const ranges = intelligenceModule.getExpectedRanges(intelligence, shopAddress);
        const profile = intelligence?.shopProfiles?.[shopAddress] || null;
        return res.json({
          success: true,
          shopAddress,
          expectedRanges: ranges,
          profile,
        });
      }

      // Без shopAddress — вернуть всю статистику
      res.json({
        success: true,
        shopCount: intelligence?.shopProfiles ? Object.keys(intelligence.shopProfiles).length : 0,
        shops: intelligence?.shopProfiles || {},
        updatedAt: intelligence?.updatedAt || null,
      });
    } catch (error) {
      console.error('[Z-Report API] Intelligence error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Статистика точности по всем магазинам
  app.get('/api/z-report/intelligence/stats', requireAuth, async (req, res) => {
    try {
      const intelligence = await intelligenceModule.loadZReportIntelligence();
      const profiles = intelligence?.shopProfiles || {};
      const shops = [];

      // Собираем overall accuracy
      const overall = { totalSum: { total: 0, correct: 0 }, cashSum: { total: 0, correct: 0 }, ofdNotSent: { total: 0, correct: 0 }, resourceKeys: { total: 0, correct: 0 } };

      for (const [addr, profile] of Object.entries(profiles)) {
        const accuracy = profile.accuracy || {};
        const hasRegions = !!(await templatesModule.getLearnedRegions(addr));
        shops.push({
          shopAddress: addr,
          totalReports: profile.totalReports || 0,
          accuracy,
          hasLearnedRegions: hasRegions,
        });

        for (const field of Object.keys(overall)) {
          if (accuracy[field]) {
            overall[field].total += accuracy[field].total || 0;
            overall[field].correct += accuracy[field].correct || 0;
          }
        }
      }

      // Вычисляем rate
      const overallAccuracy = {};
      for (const [field, stats] of Object.entries(overall)) {
        overallAccuracy[field] = stats.total > 0
          ? Math.round((stats.correct / stats.total) * 1000) / 1000
          : null;
      }

      res.json({
        success: true,
        shopCount: shops.length,
        overallAccuracy,
        shops,
        updatedAt: intelligence?.updatedAt || null,
      });
    } catch (error) {
      console.error('[Z-Report API] Intelligence stats error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Принудительно перестроить intelligence
  app.post('/api/z-report/intelligence/rebuild', requireAuth, async (req, res) => {
    try {
      const data = await intelligenceModule.buildZReportIntelligence();
      const shopCount = data?.shopProfiles ? Object.keys(data.shopProfiles).length : 0;
      res.json({ success: true, shopCount, updatedAt: data?.updatedAt });
    } catch (error) {
      console.error('[Z-Report API] Intelligence rebuild error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('[Z-Report API] Инициализация завершена');
}

// ============ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ============

async function ensureDirectories() {
  try {
    await fs.mkdir(TEMPLATE_IMAGES_DIR, { recursive: true });
    await fs.mkdir(REGION_SET_IMAGES_DIR, { recursive: true });
    await fs.mkdir(path.join(__dirname, '../data'), { recursive: true });
  } catch (e) {
    console.error('[Z-Report API] Ошибка создания директорий:', e);
  }
}

async function saveRegionSetImage(templateId, setId, imageBase64) {
  const templateDir = path.join(REGION_SET_IMAGES_DIR, templateId);
  await fs.mkdir(templateDir, { recursive: true });

  const imagePath = path.join(templateDir, `${setId}.jpg`);
  const imageData = imageBase64.replace(/^data:image\/\w+;base64,/, '');
  await fs.writeFile(imagePath, Buffer.from(imageData, 'base64'));

  console.log(`[Z-Report API] Сохранено изображение формата: ${templateId}/${setId}`);
}

async function deleteAllRegionSetImages(templateId) {
  const templateDir = path.join(REGION_SET_IMAGES_DIR, templateId);
  try {
    const files = await fs.readdir(templateDir);
    for (const file of files) {
      await fs.unlink(path.join(templateDir, file));
    }
    await fs.rmdir(templateDir);
  } catch {
    // Директория не существует — OK
  }
}

module.exports = { setupZReportAPI };
