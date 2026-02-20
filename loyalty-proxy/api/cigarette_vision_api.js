/**
 * Cigarette Vision API Module
 * API для работы с машинным зрением подсчёта сигарет
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { requireAuth } = require('../utils/session_middleware');

const cigaretteVision = require('../modules/cigarette-vision');

// Директория с вопросами пересчёта (та же что в index.js)
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const RECOUNT_QUESTIONS_DIR = `${DATA_DIR}/recount-questions`;

// Sanitize filename to prevent path traversal
function sanitizeFileName(name) {
  if (!name || typeof name !== 'string') return '';
  return path.basename(name).replace(/[^a-zA-Z0-9_\-\.]/g, '_');
}

// Кэш вопросов пересчёта
let recountQuestionsCache = [];

/**
 * Загрузить вопросы пересчёта из директории
 */
async function loadRecountQuestions() {
  try {
    if (!(await fileExists(RECOUNT_QUESTIONS_DIR))) {
      console.log('[Cigarette Vision API] Директория вопросов пересчёта не существует');
      recountQuestionsCache = [];
      return;
    }

    const files = await fsp.readdir(RECOUNT_QUESTIONS_DIR);
    const questions = [];

    for (const file of files) {
      if (file.endsWith('.json')) {
        try {
          const filePath = path.join(RECOUNT_QUESTIONS_DIR, file);
          const data = await fsp.readFile(filePath, 'utf8');
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
async function setupCigaretteVisionAPI(app) {
  console.log('[Cigarette Vision API] Инициализация...');

  // Инициализируем модуль
  cigaretteVision.init();

  // Загружаем вопросы пересчёта
  await loadRecountQuestions();

  // ============ ТОВАРЫ ============

  // Получить товары с информацией об обучении
  app.get('/api/cigarette-vision/products', requireAuth, async (req, res) => {
    try {
      const { productGroup } = req.query;

      // Перезагружаем вопросы для актуальности
      await loadRecountQuestions();

      const products = await cigaretteVision.getProductsWithTrainingInfo(
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
  app.get('/api/cigarette-vision/products/groups', requireAuth, async (req, res) => {
    try {
      await loadRecountQuestions();
      const groups = cigaretteVision.getProductGroups(recountQuestionsCache);
      res.json({ success: true, groups });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения групп:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ СТАТИСТИКА ============

  // Получить статистику обучения
  app.get('/api/cigarette-vision/stats', requireAuth, async (req, res) => {
    try {
      await loadRecountQuestions();
      const stats = await cigaretteVision.getTrainingStats(recountQuestionsCache);
      res.json(stats);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения статистики:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ОБРАЗЦЫ ДЛЯ ОБУЧЕНИЯ ============

  // Загрузить образец для обучения (с аннотациями bounding boxes)
  app.post('/api/cigarette-vision/samples', requireAuth, async (req, res) => {
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
  app.get('/api/cigarette-vision/samples', requireAuth, async (req, res) => {
    try {
      const { productId } = req.query;

      if (!productId) {
        return res.status(400).json({ success: false, error: 'ID товара обязателен' });
      }

      const samples = await cigaretteVision.getSamplesForProduct(productId);
      res.json({ success: true, samples });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения образцов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Удалить образец
  app.delete('/api/cigarette-vision/samples/:id', requireAuth, async (req, res) => {
    try {
      const result = await cigaretteVision.deleteSample(req.params.id);

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
  app.get('/api/cigarette-vision/images/:fileName', requireAuth, async (req, res) => {
    try {
      const imagePath = cigaretteVision.getImagePath(sanitizeFileName(req.params.fileName));

      if (await fileExists(imagePath)) {
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
  app.post('/api/cigarette-vision/detect', requireAuth, async (req, res) => {
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
  app.post('/api/cigarette-vision/display-check', requireAuth, async (req, res) => {
    try {
      const { imageBase64, shopAddress, productId } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение обязательно' });
      }

      const expectedProducts = productId ? [productId] : [];
      const result = await cigaretteVision.checkDisplay(imageBase64, expectedProducts);

      // Записываем статистику распознавания для display (если передан productId)
      if (productId) {
        const isSuccessfulDetection = result.success && result.detected;
        await cigaretteVision.recordRecognitionAttempt(productId, 'display', isSuccessfulDetection, {
          shopAddress: shopAddress || '',
        });
        // Сбрасываем счётчик consecutiveErrors при успехе
        if (isSuccessfulDetection) {
          await cigaretteVision.reportAiSuccess(productId);
        }
      }

      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка проверки выкладки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ СТАТУС МОДЕЛИ ============

  // Получить статус модели YOLO
  app.get('/api/cigarette-vision/model-status', requireAuth, async (req, res) => {
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
  app.post('/api/cigarette-vision/export-training', requireAuth, async (req, res) => {
    try {
      const { outputDir } = req.body;
      // Validate outputDir is within DATA_DIR to prevent path traversal
      if (outputDir && !path.resolve(outputDir).startsWith(path.resolve(DATA_DIR))) {
        return res.status(400).json({ success: false, error: 'Недопустимый путь экспорта' });
      }
      const result = await cigaretteVision.exportTrainingData(outputDir);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка экспорта данных:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Запуск обучения модели
  app.post('/api/cigarette-vision/train', requireAuth, async (req, res) => {
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
  app.get('/api/cigarette-vision/settings', requireAuth, async (req, res) => {
    try {
      const settings = await cigaretteVision.getSettings();
      res.json({ success: true, settings });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения настроек:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Обновить настройки
  app.put('/api/cigarette-vision/settings', requireAuth, async (req, res) => {
    try {
      const {
        requiredRecountPhotos,
        requiredDisplayPhotos,
        requiredDisplayPhotosPerShop, // Flutter sends this name
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
      // Accept both parameter names (Flutter sends requiredDisplayPhotosPerShop)
      const displayPhotosValue = requiredDisplayPhotosPerShop ?? requiredDisplayPhotos;
      if (displayPhotosValue !== undefined) {
        newSettings.requiredDisplayPhotosPerShop = Math.max(1, Math.min(50, parseInt(displayPhotosValue) || 3));
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

      const updated = await cigaretteVision.updateSettings(newSettings);
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
  app.get('/api/cigarette-vision/positive-samples/stats', requireAuth, async (req, res) => {
    try {
      const stats = await cigaretteVision.getPositiveSamplesStats();
      res.json({ success: true, ...stats });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения статистики positive samples:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Ручной запуск очистки старых positive samples (для админа)
  app.post('/api/cigarette-vision/positive-samples/cleanup', requireAuth, async (req, res) => {
    try {
      const result = await cigaretteVision.cleanupOldPositiveSamples();
      res.json({ success: true, ...result });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка очистки positive samples:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ВСЕ ОБРАЗЦЫ (для админки) ============

  // Получить все образцы с фильтрацией
  app.get('/api/cigarette-vision/samples/all', requireAuth, async (req, res) => {
    try {
      const { productId, type, limit, offset } = req.query;
      let samples = await cigaretteVision.loadSamples();

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
  app.post('/api/cigarette-vision/count-with-training', requireAuth, async (req, res) => {
    try {
      const { imageBase64, productId, productName, shopAddress, isAiActive, employeeAnswer, selectedRegion } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение обязательно' });
      }

      if (!productId) {
        return res.status(400).json({ success: false, error: 'ID товара обязателен' });
      }

      console.log(`[Cigarette Vision API] count-with-training: productId=${productId}, productName=${productName}, shopAddress=${shopAddress}, isAiActive=${isAiActive} (type: ${typeof isAiActive})`);

      // Выполняем детекцию
      const result = await cigaretteVision.detectAndCount(imageBase64, productId);

      // Записываем статистику распознавания
      // success = true если ИИ нашёл хотя бы один объект
      const isSuccessfulDetection = result.success && result.count > 0;
      await cigaretteVision.recordRecognitionAttempt(productId, 'counting', isSuccessfulDetection, {
        shopAddress: shopAddress || '',
        detectedCount: result.count || 0,
        expectedCount: employeeAnswer || null,
      });

      // Авто-сохранение убрано: фото уходит на обучение только после проверки админом
      // через POST /api/cigarette-vision/submit-report-photo-for-training

      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка подсчёта с обучением:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ COUNTING SAMPLES API ============

  // Получить фото пересчёта для товара
  app.get('/api/cigarette-vision/counting-samples/:productId', requireAuth, async (req, res) => {
    try {
      const { productId } = req.params;
      const samples = await cigaretteVision.getCountingSamplesForProduct(productId);
      res.json({ success: true, samples, count: samples.length });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения counting samples:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Удалить фото пересчёта
  app.delete('/api/cigarette-vision/counting-samples/:sampleId', requireAuth, async (req, res) => {
    try {
      const { sampleId } = req.params;
      const result = await cigaretteVision.deleteCountingSample(sampleId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка удаления counting sample:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Отдача изображений counting
  app.get('/api/cigarette-vision/counting-images/:fileName', requireAuth, async (req, res) => {
    try {
      const paths = cigaretteVision.getTrainingPaths(cigaretteVision.TRAINING_TYPES.COUNTING);
      const imagePath = path.join(paths.imagesDir, sanitizeFileName(req.params.fileName));

      if (await fileExists(imagePath)) {
        res.sendFile(imagePath);
      } else {
        res.status(404).json({ success: false, error: 'Изображение не найдено' });
      }
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения counting image:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ SUBMIT REPORT PHOTO FOR TRAINING ============

  // Отправить фото из отчёта пересчёта в counting-pending (по решению админа)
  // Фото уже на сервере — читаем по photoUrl, не передаём base64 с телефона
  app.post('/api/cigarette-vision/submit-report-photo-for-training', requireAuth, async (req, res) => {
    try {
      const { photoUrl, productId, productName, shopAddress, employeeAnswer, selectedRegion } = req.body;

      if (!photoUrl || !productId) {
        return res.status(400).json({ success: false, error: 'photoUrl и productId обязательны' });
      }

      // Определяем путь к файлу на диске по photoUrl
      let imagePath;
      const fileName = path.basename(new URL(photoUrl, 'https://arabica26.ru').pathname);
      const safeName = sanitizeFileName(fileName);

      if (photoUrl.includes('/shift-photos/')) {
        imagePath = path.join(DATA_DIR, 'shift-photos', safeName);
      } else {
        return res.status(400).json({ success: false, error: 'Неподдерживаемый формат photoUrl' });
      }

      if (!(await fileExists(imagePath))) {
        return res.status(404).json({ success: false, error: 'Файл фото не найден на сервере' });
      }

      const imageBuffer = await fsp.readFile(imagePath);
      const imageBase64 = imageBuffer.toString('base64');

      const result = await cigaretteVision.saveCountingTrainingSample({
        imageBase64,
        productId,
        productName: productName || '',
        shopAddress: shopAddress || '',
        employeeAnswer: employeeAnswer || null,
        selectedRegion: selectedRegion || null,
      });

      console.log(`[Cigarette Vision API] Фото из отчёта отправлено на обучение: ${productName || productId}`);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка отправки фото из отчёта на обучение:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ COUNTING PENDING API (ожидающие подтверждения) ============

  // Получить все pending фото (для админа)
  app.get('/api/cigarette-vision/counting-pending', requireAuth, async (req, res) => {
    try {
      const samples = await cigaretteVision.getAllPendingCountingSamples();
      res.json({ success: true, samples, count: samples.length });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения pending samples:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить pending фото для товара
  app.get('/api/cigarette-vision/counting-pending/product/:productId', requireAuth, async (req, res) => {
    try {
      const { productId } = req.params;
      const samples = await cigaretteVision.getPendingCountingSamplesForProduct(productId);
      res.json({ success: true, samples, count: samples.length });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения pending для товара:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Подтвердить pending фото (переместить в training)
  app.post('/api/cigarette-vision/counting-pending/:sampleId/approve', requireAuth, async (req, res) => {
    try {
      const { sampleId } = req.params;
      const result = await cigaretteVision.approveCountingPendingSample(sampleId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка подтверждения pending:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Отклонить pending фото (удалить)
  app.delete('/api/cigarette-vision/counting-pending/:sampleId', requireAuth, async (req, res) => {
    try {
      const { sampleId } = req.params;
      const result = await cigaretteVision.rejectCountingPendingSample(sampleId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка отклонения pending:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Отдача изображений pending
  app.get('/api/cigarette-vision/counting-pending-images/:fileName', requireAuth, async (req, res) => {
    try {
      const paths = cigaretteVision.getCountingPendingPaths();
      const imagePath = path.join(paths.imagesDir, sanitizeFileName(req.params.fileName));

      if (await fileExists(imagePath)) {
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
  app.get('/api/cigarette-vision/typed-stats/display', requireAuth, async (req, res) => {
    try {
      const stats = await cigaretteVision.getTypedTrainingStats(cigaretteVision.TRAINING_TYPES.DISPLAY);
      res.json({ success: true, ...stats });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения статистики display:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить статистику датасета counting (пересчёт)
  app.get('/api/cigarette-vision/typed-stats/counting', requireAuth, async (req, res) => {
    try {
      const stats = await cigaretteVision.getTypedTrainingStats(cigaretteVision.TRAINING_TYPES.COUNTING);
      res.json({ success: true, ...stats });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка получения статистики counting:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить объединённую статистику обоих датасетов
  app.get('/api/cigarette-vision/typed-stats', requireAuth, async (req, res) => {
    try {
      const displayStats = await cigaretteVision.getTypedTrainingStats(cigaretteVision.TRAINING_TYPES.DISPLAY);
      const countingStats = await cigaretteVision.getTypedTrainingStats(cigaretteVision.TRAINING_TYPES.COUNTING);

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
  app.post('/api/cigarette-vision/typed-cleanup/:type', requireAuth, async (req, res) => {
    try {
      const { type } = req.params;
      const { maxAgeDays } = req.body;

      if (type !== 'display' && type !== 'counting') {
        return res.status(400).json({ success: false, error: 'Тип должен быть display или counting' });
      }

      const result = await cigaretteVision.cleanupTypedSamples(type, maxAgeDays || 180);
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
  setTimeout(async () => {
    try {
      console.log('[Cigarette Vision API] Запуск первичной очистки positive samples...');
      const result = await cigaretteVision.cleanupOldPositiveSamples();
      console.log(`[Cigarette Vision API] Общий датасет: удалено ${result.deletedCount || 0} старых samples`);

      const displayResult = await cigaretteVision.cleanupTypedSamples('display');
      const countingResult = await cigaretteVision.cleanupTypedSamples('counting');
      console.log(`[Cigarette Vision API] Display: удалено ${displayResult.deletedCount || 0}, Counting: удалено ${countingResult.deletedCount || 0}`);
    } catch (err) {
      console.error('[Cigarette Vision API] Ошибка первичной очистки:', err.message);
    }
  }, 5 * 60 * 1000);

  // Регулярная очистка каждые 24 часа
  setInterval(async () => {
    try {
      console.log('[Cigarette Vision API] Запуск ежедневной очистки...');
      const result = await cigaretteVision.cleanupOldPositiveSamples();
      console.log(`[Cigarette Vision API] Общий датасет: удалено ${result.deletedCount || 0} старых samples`);

      const displayResult = await cigaretteVision.cleanupTypedSamples('display');
      const countingResult = await cigaretteVision.cleanupTypedSamples('counting');
      console.log(`[Cigarette Vision API] Display: удалено ${displayResult.deletedCount || 0}, Counting: удалено ${countingResult.deletedCount || 0}`);
    } catch (err) {
      console.error('[Cigarette Vision API] Ошибка ежедневной очистки:', err.message);
    }
  }, CLEANUP_INTERVAL_MS);

  // ============ СИСТЕМА ОБРАТНОЙ СВЯЗИ И АВТООТКЛЮЧЕНИЯ ИИ ============

  // Сообщить об ошибке ИИ
  app.post('/api/cigarette-vision/report-error', requireAuth, async (req, res) => {
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
  app.get('/api/cigarette-vision/product-ai-status/:productId', requireAuth, async (req, res) => {
    try {
      const { productId } = req.params;
      const status = await cigaretteVision.getProductAiStatus(productId);
      res.json({ success: true, ...status });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка product-ai-status:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Проверить отключен ли ИИ для товара (быстрая проверка)
  app.get('/api/cigarette-vision/is-ai-disabled/:productId', requireAuth, async (req, res) => {
    try {
      const { productId } = req.params;
      const isDisabled = await cigaretteVision.isProductAiDisabled(productId);
      res.json({ success: true, productId, isDisabled });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Сбросить счётчик ошибок и включить ИИ (админ)
  app.post('/api/cigarette-vision/reset-product-ai/:productId', requireAuth, async (req, res) => {
    try {
      const { productId } = req.params;
      const result = await cigaretteVision.resetProductAiErrors(productId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка reset-product-ai:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Решение админа по ошибке ИИ (подтвердить или отклонить)
  app.post('/api/cigarette-vision/admin-ai-decision', requireAuth, async (req, res) => {
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
  app.get('/api/cigarette-vision/problematic-products', requireAuth, async (req, res) => {
    try {
      const products = await cigaretteVision.getProblematicProducts();
      res.json({ success: true, products, count: products.length });
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка problematic-products:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить проблемные фото для товара
  app.get('/api/cigarette-vision/problem-samples/:productId', requireAuth, async (req, res) => {
    try {
      const { productId } = req.params;
      const result = await cigaretteVision.getProblemSamples(productId);
      res.json(result);
    } catch (error) {
      console.error('[Cigarette Vision API] Ошибка problem-samples:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Отдача проблемных фото (для просмотра)
  app.get('/api/cigarette-vision/problem-samples/:productId/:fileName', requireAuth, async (req, res) => {
    try {
      const { productId, fileName } = req.params;
      const filePath = path.join(cigaretteVision.PROBLEM_SAMPLES_DIR, sanitizeFileName(productId), sanitizeFileName(fileName));

      if (!(await fileExists(filePath))) {
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
