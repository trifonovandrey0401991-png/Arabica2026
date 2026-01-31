/**
 * Cigarette Vision API Module
 * API для работы с машинным зрением подсчёта сигарет
 */

const fs = require('fs');
const path = require('path');

const cigaretteVision = require('../modules/cigarette-vision');

// Директория с вопросами пересчёта (та же что в index.js)
const RECOUNT_QUESTIONS_DIR = '/var/www/recount-questions';

// Кэш вопросов пересчёта
let recountQuestionsCache = [];

/**
 * Загрузить вопросы пересчёта из директории
 */
function loadRecountQuestions() {
  try {
    if (!fs.existsSync(RECOUNT_QUESTIONS_DIR)) {
      console.log('[Cigarette Vision API] Директория вопросов пересчёта не существует');
      recountQuestionsCache = [];
      return;
    }

    const files = fs.readdirSync(RECOUNT_QUESTIONS_DIR);
    const questions = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        try {
          const filePath = path.join(RECOUNT_QUESTIONS_DIR, file);
          const data = fs.readFileSync(filePath, 'utf8');
          const question = JSON.parse(data);
          questions.push(question);
        } catch (error) {
          console.error(`[Cigarette Vision API] Ошибка чтения вопроса ${file}:`, error);
        }
      }
    }

    recountQuestionsCache = questions;
    console.log(`[Cigarette Vision API] Загружено ${recountQuestionsCache.length} вопросов пересчёта`);
  } catch (error) {
    console.error('[Cigarette Vision API] Ошибка загрузки вопросов пересчёта:', error);
    recountQuestionsCache = [];
  }
}

/**
 * Настройка API для машинного зрения сигарет
 */
function setupCigaretteVisionAPI(app) {
  console.log('[Cigarette Vision API] Инициализация...');

  // Инициализируем модуль
  cigaretteVision.init();

  // Загружаем вопросы пересчёта
  loadRecountQuestions();

  // ============ ТОВАРЫ ============

  // Получить товары с информацией об обучении
  app.get('/api/cigarette-vision/products', (req, res) => {
    try {
      const { productGroup } = req.query;

      // Перезагружаем вопросы для актуальности
      loadRecountQuestions();

      const products = cigaretteVision.getProductsWithTrainingInfo(
        recountQuestionsCache,
        productGroup || null
      );

      res.json({ success: true, products });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения товаров:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить группы товаров
  app.get('/api/cigarette-vision/products/groups', (req, res) => {
    try {
      loadRecountQuestions();
      const groups = cigaretteVision.getProductGroups(recountQuestionsCache);
      res.json({ success: true, groups });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения групп:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ СТАТИСТИКА ============

  // Получить статистику обучения
  app.get('/api/cigarette-vision/stats', (req, res) => {
    try {
      loadRecountQuestions();
      const stats = cigaretteVision.getTrainingStats(recountQuestionsCache);
      res.json(stats);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения статистики:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ОБРАЗЦЫ ДЛЯ ОБУЧЕНИЯ ============

  // Загрузить образец для обучения (с аннотациями bounding boxes)
  app.post('/api/cigarette-vision/samples', async (req, res) => {
    try {
      const {
        imageBase64,
        productId,
        barcode,
        productName,
        type,
        templateId,
        shopAddress,
        employeeName,
        boundingBoxes,
      } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение обязательно' });
      }

      if (!productId && !barcode) {
        return res.status(400).json({ success: false, error: 'ID товара или штрих-код обязателен' });
      }

      const result = await cigaretteVision.saveTrainingSample({
        imageBase64,
        productId: productId || barcode,
        barcode: barcode || productId,
        productName: productName || '',
        type: type || 'recount',
        templateId: templateId || null,
        shopAddress,
        employeeName,
        boundingBoxes: boundingBoxes || [],
      });

      if (result.success) {
        res.json({ success: true, sample: result.sample });
      } else {
        res.status(500).json({ success: false, error: result.error });
      }
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка загрузки образца:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить образцы для товара
  app.get('/api/cigarette-vision/samples', (req, res) => {
    try {
      const { productId } = req.query;

      if (!productId) {
        return res.status(400).json({ success: false, error: 'ID товара обязателен' });
      }

      const samples = cigaretteVision.getSamplesForProduct(productId);
      res.json({ success: true, samples });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения образцов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Удалить образец
  app.delete('/api/cigarette-vision/samples/:id', (req, res) => {
    try {
      const result = cigaretteVision.deleteSample(req.params.id);

      if (result.success) {
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: result.error });
      }
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка удаления образца:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ИЗОБРАЖЕНИЯ ============

  // Получить изображение образца
  app.get('/api/cigarette-vision/images/:fileName', (req, res) => {
    try {
      const imagePath = cigaretteVision.getImagePath(req.params.fileName);

      if (fs.existsSync(imagePath)) {
        res.sendFile(imagePath);
      } else {
        res.status(404).json({ success: false, error: 'Изображение не найдено' });
      }
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения изображения:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ДЕТЕКЦИЯ (ML) ============

  // Детекция и подсчёт пачек
  app.post('/api/cigarette-vision/detect', async (req, res) => {
    try {
      const { imageBase64, productId } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение обязательно' });
      }

      if (!productId) {
        return res.status(400).json({ success: false, error: 'ID товара обязателен' });
      }

      const result = await cigaretteVision.detectAndCount(imageBase64, productId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка детекции:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Проверка выкладки
  app.post('/api/cigarette-vision/display-check', async (req, res) => {
    try {
      const { imageBase64, shopAddress } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение обязательно' });
      }

      const result = await cigaretteVision.checkDisplay(imageBase64, shopAddress);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка проверки выкладки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ СТАТУС МОДЕЛИ ============

  // Получить статус модели YOLO
  app.get('/api/cigarette-vision/model-status', async (req, res) => {
    try {
      const status = await cigaretteVision.getModelStatus();
      res.json({ success: true, ...status });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения статуса модели:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ОБУЧЕНИЕ МОДЕЛИ ============

  // Экспорт данных для обучения
  app.post('/api/cigarette-vision/export-training', async (req, res) => {
    try {
      const { outputDir } = req.body;
      const result = await cigaretteVision.exportTrainingData(outputDir);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка экспорта данных:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Запуск обучения модели
  app.post('/api/cigarette-vision/train', async (req, res) => {
    try {
      const { dataYaml, epochs } = req.body;

      if (!dataYaml) {
        return res.status(400).json({ success: false, error: 'Путь к data.yaml обязателен' });
      }

      const result = await cigaretteVision.trainModel(dataYaml, epochs || 100);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка обучения модели:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ НАСТРОЙКИ ============

  // Получить настройки
  app.get('/api/cigarette-vision/settings', (req, res) => {
    try {
      const settings = cigaretteVision.getSettings();
      res.json({ success: true, settings });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения настроек:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Обновить настройки
  app.put('/api/cigarette-vision/settings', (req, res) => {
    try {
      const { requiredRecountPhotos, requiredDisplayPhotos, catalogSource } = req.body;

      const newSettings = {};
      if (requiredRecountPhotos !== undefined) {
        newSettings.requiredRecountPhotos = Math.max(1, Math.min(50, parseInt(requiredRecountPhotos) || 10));
      }
      if (requiredDisplayPhotos !== undefined) {
        newSettings.requiredDisplayPhotos = Math.max(1, Math.min(50, parseInt(requiredDisplayPhotos) || 10));
      }
      // Источник каталога: recount-questions или master-catalog
      if (catalogSource !== undefined) {
        const validSources = ['recount-questions', 'master-catalog'];
        if (validSources.includes(catalogSource)) {
          newSettings.catalogSource = catalogSource;
        }
      }

      const updated = cigaretteVision.updateSettings(newSettings);
      if (updated) {
        res.json({ success: true, settings: updated });
      } else {
        res.status(500).json({ success: false, error: 'Ошибка сохранения настроек' });
      }
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка обновления настроек:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ВСЕ ОБРАЗЦЫ (для админки) ============

  // Получить все образцы с фильтрацией
  app.get('/api/cigarette-vision/samples/all', (req, res) => {
    try {
      const { productId, type, limit, offset } = req.query;
      let samples = cigaretteVision.loadSamples();

      // Фильтрация по productId
      if (productId) {
        samples = samples.filter(s => s.productId === productId || s.barcode === productId);
      }

      // Фильтрация по типу
      if (type) {
        samples = samples.filter(s => s.type === type);
      }

      // Сортировка по дате (новые первые)
      samples.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      const total = samples.length;

      // Пагинация
      const offsetNum = parseInt(offset) || 0;
      const limitNum = parseInt(limit) || 50;
      samples = samples.slice(offsetNum, offsetNum + limitNum);

      res.json({
        success: true,
        samples,
        total,
        offset: offsetNum,
        limit: limitNum,
      });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения всех образцов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('[Cigarette Vision API] Готово');
}

module.exports = {
  setupCigaretteVisionAPI,
  loadRecountQuestions,
};
