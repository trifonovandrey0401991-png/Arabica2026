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

  // Детекция с сохранением в датасет для дообучения (используется в пересчёте)
  app.post('/api/cigarette-vision/count-with-training', async (req, res) => {
    try {
      const { imageBase64, productId, productName, shopAddress } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение обязательно' });
      }

      if (!productId) {
        return res.status(400).json({ success: false, error: 'ID товара обязателен' });
      }

      console.log(`[Cigarette Vision API] count-with-training: productId=${productId}, productName=${productName}, shopAddress=${shopAddress}`);

      // Выполняем детекцию
      const result = await cigaretteVision.detectAndCount(imageBase64, productId);

      // Если детекция успешна, сохраняем образец для обучения
      if (result.success && result.count > 0) {
        try {
          await cigaretteVision.savePositiveSample({
            imageBase64,
            productId,
            productName: productName || productId,
            count: result.count,
            shopAddress,
            source: 'recount',
          });
          console.log(`[Cigarette Vision API] Образец сохранён для обучения: ${productName}, count=${result.count}`);
        } catch (saveError) {
          console.error('[Cigarette Vision API] Ошибка сохранения образца:', saveError.message);
          // Не прерываем - детекция уже выполнена
        }
      }

      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка детекции с обучением:', error);
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
      const {
        requiredRecountPhotos,
        requiredDisplayPhotos,
        catalogSource,
        // Настройки positive samples
        positiveSamplesEnabled,
        positiveSampleRate,
        maxPositiveSamplesPerProduct,
        positiveSamplesMaxAgeDays,
      } = req.body;

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

      // Настройки positive samples
      if (positiveSamplesEnabled !== undefined) {
        newSettings.positiveSamplesEnabled = Boolean(positiveSamplesEnabled);
      }
      if (positiveSampleRate !== undefined) {
        newSettings.positiveSampleRate = Math.max(0.01, Math.min(1, parseFloat(positiveSampleRate) || 0.1));
      }
      if (maxPositiveSamplesPerProduct !== undefined) {
        newSettings.maxPositiveSamplesPerProduct = Math.max(10, Math.min(200, parseInt(maxPositiveSamplesPerProduct) || 50));
      }
      if (positiveSamplesMaxAgeDays !== undefined) {
        newSettings.positiveSamplesMaxAgeDays = Math.max(30, Math.min(365, parseInt(positiveSamplesMaxAgeDays) || 180));
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

  // ============ POSITIVE SAMPLES API ============

  // Получить статистику positive samples
  app.get('/api/cigarette-vision/positive-samples/stats', (req, res) => {
    try {
      const stats = cigaretteVision.getPositiveSamplesStats();
      res.json({ success: true, ...stats });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения статистики positive samples:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Ручной запуск очистки старых positive samples (для админа)
  app.post('/api/cigarette-vision/positive-samples/cleanup', (req, res) => {
    try {
      const result = cigaretteVision.cleanupOldPositiveSamples();
      res.json({ success: true, ...result });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка очистки positive samples:', error);
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

  // ============ ПОДСЧЁТ С ОБУЧЕНИЕМ (COUNTING) ============

  // Детекция и подсчёт с сохранением в counting датасет
  // Используется для пересчёта товаров
  // ВАЖНО: Сохраняет ВСЕ фото для товаров с isAiActive=true (для обучения)
  app.post('/api/cigarette-vision/count-with-training', async (req, res) => {
    try {
      const { imageBase64, productId, productName, shopAddress, isAiActive, employeeAnswer } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение обязательно' });
      }

      if (!productId) {
        return res.status(400).json({ success: false, error: 'ID товара обязателен' });
      }

      // Выполняем детекцию
      const result = await cigaretteVision.detectAndCount(imageBase64, productId);

      // НОВАЯ ЛОГИКА: Сохраняем фото для товаров с isAiActive=true (для обучения)
      // Не зависит от результата детекции - сохраняем ВСЕ фото
      if (isAiActive === true) {
        cigaretteVision.saveCountingTrainingSample({
          imageBase64,
          productId,
          productName: productName || '',
          shopAddress: shopAddress || '',
          employeeAnswer: employeeAnswer || null,
        }).then(saveResult => {
          if (saveResult.success) {
            console.log(`[Cigarette Vision API] Counting sample сохранён для ${productName || productId}`);
          }
        }).catch(err => {
          console.warn('[Cigarette Vision API] Ошибка сохранения counting sample:', err.message);
        });
      }

      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка подсчёта с обучением:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ COUNTING SAMPLES API ============

  // Получить фото пересчёта для товара
  app.get('/api/cigarette-vision/counting-samples/:productId', (req, res) => {
    try {
      const { productId } = req.params;
      const samples = cigaretteVision.getCountingSamplesForProduct(productId);
      res.json({ success: true, samples, count: samples.length });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения counting samples:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Удалить фото пересчёта
  app.delete('/api/cigarette-vision/counting-samples/:sampleId', (req, res) => {
    try {
      const { sampleId } = req.params;
      const result = cigaretteVision.deleteCountingSample(sampleId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка удаления counting sample:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Отдача изображений counting
  app.get('/api/cigarette-vision/counting-images/:fileName', (req, res) => {
    try {
      const paths = cigaretteVision.getTrainingPaths(cigaretteVision.TRAINING_TYPES.COUNTING);
      const imagePath = path.join(paths.imagesDir, req.params.fileName);

      if (fs.existsSync(imagePath)) {
        res.sendFile(imagePath);
      } else {
        res.status(404).json({ success: false, error: 'Изображение не найдено' });
      }
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения counting image:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ COUNTING PENDING API (ожидающие подтверждения) ============

  // Получить все pending фото (для админа)
  app.get('/api/cigarette-vision/counting-pending', (req, res) => {
    try {
      const samples = cigaretteVision.getAllPendingCountingSamples();
      res.json({ success: true, samples, count: samples.length });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения pending samples:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить pending фото для товара
  app.get('/api/cigarette-vision/counting-pending/product/:productId', (req, res) => {
    try {
      const { productId } = req.params;
      const samples = cigaretteVision.getPendingCountingSamplesForProduct(productId);
      res.json({ success: true, samples, count: samples.length });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения pending для товара:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Подтвердить pending фото (переместить в training)
  app.post('/api/cigarette-vision/counting-pending/:sampleId/approve', (req, res) => {
    try {
      const { sampleId } = req.params;
      const result = cigaretteVision.approveCountingPendingSample(sampleId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка подтверждения pending:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Отклонить pending фото (удалить)
  app.delete('/api/cigarette-vision/counting-pending/:sampleId', (req, res) => {
    try {
      const { sampleId } = req.params;
      const result = cigaretteVision.rejectCountingPendingSample(sampleId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка отклонения pending:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Отдача изображений pending
  app.get('/api/cigarette-vision/counting-pending-images/:fileName', (req, res) => {
    try {
      const paths = cigaretteVision.getCountingPendingPaths();
      const imagePath = path.join(paths.imagesDir, req.params.fileName);

      if (fs.existsSync(imagePath)) {
        res.sendFile(imagePath);
      } else {
        res.status(404).json({ success: false, error: 'Изображение не найдено' });
      }
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения pending image:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ СТАТИСТИКА РАЗДЕЛЬНЫХ ДАТАСЕТОВ ============

  // Получить статистику датасета display (пересменка)
  app.get('/api/cigarette-vision/typed-stats/display', (req, res) => {
    try {
      const stats = cigaretteVision.getTypedTrainingStats(cigaretteVision.TRAINING_TYPES.DISPLAY);
      res.json({ success: true, ...stats });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения статистики display:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить статистику датасета counting (пересчёт)
  app.get('/api/cigarette-vision/typed-stats/counting', (req, res) => {
    try {
      const stats = cigaretteVision.getTypedTrainingStats(cigaretteVision.TRAINING_TYPES.COUNTING);
      res.json({ success: true, ...stats });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения статистики counting:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить объединённую статистику обоих датасетов
  app.get('/api/cigarette-vision/typed-stats', (req, res) => {
    try {
      const displayStats = cigaretteVision.getTypedTrainingStats(cigaretteVision.TRAINING_TYPES.DISPLAY);
      const countingStats = cigaretteVision.getTypedTrainingStats(cigaretteVision.TRAINING_TYPES.COUNTING);

      res.json({
        success: true,
        display: displayStats,
        counting: countingStats,
        summary: {
          totalDisplaySamples: displayStats.totalSamples,
          totalCountingSamples: countingStats.totalSamples,
          displayWithAnnotations: displayStats.samplesWithAnnotations,
          countingWithAnnotations: countingStats.samplesWithAnnotations,
          displayModelExists: displayStats.modelExists,
          countingModelExists: countingStats.modelExists,
        },
      });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения объединённой статистики:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Очистка раздельных датасетов
  app.post('/api/cigarette-vision/typed-cleanup/:type', (req, res) => {
    try {
      const { type } = req.params;
      const { maxAgeDays } = req.body;

      if (type !== 'display' && type !== 'counting') {
        return res.status(400).json({ success: false, error: 'Тип должен быть display или counting' });
      }

      const result = cigaretteVision.cleanupTypedSamples(type, maxAgeDays || 180);
      res.json({ success: true, type, ...result });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка очистки typed samples:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ АВТООЧИСТКА СТАРЫХ POSITIVE SAMPLES ============

  // Запускаем очистку раз в сутки (24 часа)
  const CLEANUP_INTERVAL_MS = 24 * 60 * 60 * 1000;

  // Первая очистка через 5 минут после старта
  setTimeout(() => {
    console.log('[Cigarette Vision API] Запуск первичной очистки positive samples...');
    // Старый общий датасет
    const result = cigaretteVision.cleanupOldPositiveSamples();
    console.log(`[Cigarette Vision API] Общий датасет: удалено ${result.deletedCount || 0} старых samples`);

    // Раздельные датасеты (используем строки напрямую для надёжности)
    const displayResult = cigaretteVision.cleanupTypedSamples('display');
    const countingResult = cigaretteVision.cleanupTypedSamples('counting');
    console.log(`[Cigarette Vision API] Display: удалено ${displayResult.deletedCount || 0}, Counting: удалено ${countingResult.deletedCount || 0}`);
  }, 5 * 60 * 1000);

  // Регулярная очистка каждые 24 часа
  setInterval(() => {
    console.log('[Cigarette Vision API] Запуск ежедневной очистки...');
    // Старый общий датасет
    const result = cigaretteVision.cleanupOldPositiveSamples();
    console.log(`[Cigarette Vision API] Общий датасет: удалено ${result.deletedCount || 0} старых samples`);

    // Раздельные датасеты (используем строки напрямую для надёжности)
    const displayResult = cigaretteVision.cleanupTypedSamples('display');
    const countingResult = cigaretteVision.cleanupTypedSamples('counting');
    console.log(`[Cigarette Vision API] Display: удалено ${displayResult.deletedCount || 0}, Counting: удалено ${countingResult.deletedCount || 0}`);
  }, CLEANUP_INTERVAL_MS);

  // ============ СИСТЕМА ОБРАТНОЙ СВЯЗИ И АВТООТКЛЮЧЕНИЯ ИИ ============

  // Сообщить об ошибке ИИ
  app.post('/api/cigarette-vision/report-error', async (req, res) => {
    try {
      const {
        productId,
        productName,
        expectedCount,
        aiCount,
        imageBase64,
        shopAddress,
        employeeName,
      } = req.body;

      if (!productId) {
        return res.status(400).json({ success: false, error: 'productId обязателен' });
      }

      const result = await cigaretteVision.reportAiError({
        productId,
        productName,
        expectedCount,
        aiCount,
        imageBase64,
        shopAddress,
        employeeName,
      });

      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка report-error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить статус ИИ для товара
  app.get('/api/cigarette-vision/product-ai-status/:productId', (req, res) => {
    try {
      const { productId } = req.params;
      const status = cigaretteVision.getProductAiStatus(productId);
      res.json({ success: true, ...status });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка product-ai-status:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Проверить отключен ли ИИ для товара (быстрая проверка)
  app.get('/api/cigarette-vision/is-ai-disabled/:productId', (req, res) => {
    try {
      const { productId } = req.params;
      const isDisabled = cigaretteVision.isProductAiDisabled(productId);
      res.json({ success: true, productId, isDisabled });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Сбросить счётчик ошибок и включить ИИ (админ)
  app.post('/api/cigarette-vision/reset-product-ai/:productId', (req, res) => {
    try {
      const { productId } = req.params;
      const result = cigaretteVision.resetProductAiErrors(productId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка reset-product-ai:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Решение админа по ошибке ИИ (подтвердить или отклонить)
  app.post('/api/cigarette-vision/admin-ai-decision', async (req, res) => {
    try {
      const {
        productId,
        productName,
        decision,  // "approved_for_training" | "rejected_bad_photo"
        adminName,
        imageBase64,
        expectedCount,
        aiCount,
        shopAddress,
      } = req.body;

      if (!productId) {
        return res.status(400).json({ success: false, error: 'productId обязателен' });
      }

      if (!decision || !['approved_for_training', 'rejected_bad_photo'].includes(decision)) {
        return res.status(400).json({
          success: false,
          error: 'decision должен быть "approved_for_training" или "rejected_bad_photo"'
        });
      }

      if (!adminName) {
        return res.status(400).json({ success: false, error: 'adminName обязателен' });
      }

      const result = await cigaretteVision.reportAdminAiDecision({
        productId,
        productName,
        decision,
        adminName,
        imageBase64,
        expectedCount,
        aiCount,
        shopAddress,
      });

      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка admin-ai-decision:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить список всех проблемных товаров
  app.get('/api/cigarette-vision/problematic-products', (req, res) => {
    try {
      const products = cigaretteVision.getProblematicProducts();
      res.json({ success: true, products, count: products.length });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка problematic-products:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить проблемные фото для товара
  app.get('/api/cigarette-vision/problem-samples/:productId', (req, res) => {
    try {
      const { productId } = req.params;
      const result = cigaretteVision.getProblemSamples(productId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка problem-samples:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Отдача проблемных фото (для просмотра)
  app.get('/api/cigarette-vision/problem-samples/:productId/:fileName', (req, res) => {
    try {
      const { productId, fileName } = req.params;
      const filePath = path.join(cigaretteVision.PROBLEM_SAMPLES_DIR, productId, fileName);

      if (!fs.existsSync(filePath)) {
        return res.status(404).json({ success: false, error: 'Файл не найден' });
      }

      res.sendFile(filePath);
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('[Cigarette Vision API] Готово (+ scheduler очистки positive samples каждые 24ч)');
}

module.exports = {
  setupCigaretteVisionAPI,
  loadRecountQuestions,
};
