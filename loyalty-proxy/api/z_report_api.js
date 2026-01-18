/**
 * Z-Report API Module
 * API для работы с шаблонами и распознаванием Z-отчётов
 */

const fs = require('fs').promises;
const path = require('path');

const templatesModule = require('../modules/z-report-templates');
const visionModule = require('../modules/z-report-vision');

// Директория для изображений шаблонов
const TEMPLATE_IMAGES_DIR = path.join(__dirname, '../data/template-images');
const REGION_SET_IMAGES_DIR = path.join(__dirname, '../data/region-set-images');

/**
 * Настройка API для Z-отчётов
 */
function setupZReportAPI(app) {
  console.log('[Z-Report API] Инициализация...');

  // Убедимся что директории существуют
  ensureDirectories();

  // ============ ШАБЛОНЫ ============

  // Получить все шаблоны
  app.get('/api/z-report/templates', async (req, res) => {
    try {
      const { shopId } = req.query;
      const templates = await templatesModule.getTemplates(shopId);
      res.json({ success: true, templates });
    } catch (error) {
      console.error('[Z-Report API] Ошибка получения шаблонов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить шаблон по ID
  app.get('/api/z-report/templates/:id', async (req, res) => {
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
  app.post('/api/z-report/templates', async (req, res) => {
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
  app.delete('/api/z-report/templates/:id', async (req, res) => {
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

  // Найти шаблон для магазина
  app.get('/api/z-report/templates/find', async (req, res) => {
    try {
      const { shopId } = req.query;
      const template = await templatesModule.findTemplateForShop(shopId);
      res.json({ success: true, template });
    } catch (error) {
      console.error('[Z-Report API] Ошибка поиска шаблона:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Обновить статистику шаблона
  app.post('/api/z-report/templates/:id/stats', async (req, res) => {
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
  app.get('/api/z-report/templates/:id/image', async (req, res) => {
    try {
      const imagePath = path.join(TEMPLATE_IMAGES_DIR, `${req.params.id}.jpg`);
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
  app.post('/api/z-report/templates/:templateId/region-sets/:setId/image', async (req, res) => {
    try {
      const { templateId, setId } = req.params;
      const { imageBase64 } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение не передано' });
      }

      await saveRegionSetImage(templateId, setId, imageBase64);
      res.json({ success: true });
    } catch (error) {
      console.error('[Z-Report API] Ошибка сохранения изображения формата:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить изображение формата
  app.get('/api/z-report/templates/:templateId/region-sets/:setId/image', async (req, res) => {
    try {
      const { templateId, setId } = req.params;
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
  app.delete('/api/z-report/templates/:templateId/region-sets/:setId/image', async (req, res) => {
    try {
      const { templateId, setId } = req.params;
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
  app.post('/api/z-report/parse', async (req, res) => {
    try {
      const { imageBase64 } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение не передано' });
      }

      const result = await visionModule.parseZReport(imageBase64);
      res.json(result);
    } catch (error) {
      console.error('[Z-Report API] Ошибка распознавания:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Распознать с использованием шаблона
  app.post('/api/z-report/parse-with-template', async (req, res) => {
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
  app.post('/api/z-report/training-samples', async (req, res) => {
    try {
      const { imageBase64, rawText, correctData, recognizedData, shopId, templateId } = req.body;

      const result = await templatesModule.addTrainingSample({
        imageBase64,
        rawText,
        correctData,
        recognizedData,
        shopId,
        templateId,
      });

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
  app.get('/api/z-report/training-stats', async (req, res) => {
    try {
      const stats = await templatesModule.getTrainingStats();
      res.json({ success: true, ...stats });
    } catch (error) {
      console.error('[Z-Report API] Ошибка получения статистики:', error);
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
