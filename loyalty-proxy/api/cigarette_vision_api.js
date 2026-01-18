/**
 * Cigarette Vision API Module
 * API для работы с машинным зрением подсчёта сигарет
 */

const fs = require('fs');
const path = require('path');

const cigaretteVision = require('../modules/cigarette-vision');

// Загрузка вопросов пересчёта (нужен доступ к основным данным)
let recountQuestionsCache = [];

/**
 * Загрузить вопросы пересчёта из файла
 */
function loadRecountQuestions() {
  try {
    const questionsFile = path.join(__dirname, '../data/recount-questions.json');
    if (fs.existsSync(questionsFile)) {
      const data = JSON.parse(fs.readFileSync(questionsFile, 'utf8'));
      recountQuestionsCache = data.questions || data || [];
      console.log(`[Cigarette Vision API] Загружено ${recountQuestionsCache.length} вопросов пересчёта`);
    }
  } catch (error) {
    console.error('[Cigarette Vision API] Ошибка загрузки вопросов пересчёта:', error);
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

  // Загрузить образец для обучения
  app.post('/api/cigarette-vision/samples', async (req, res) => {
    try {
      const {
        imageBase64,
        productId,
        barcode,
        productName,
        type,
        shopAddress,
        employeeName,
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
        shopAddress,
        employeeName,
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

  console.log('[Cigarette Vision API] Готово');
}

module.exports = {
  setupCigaretteVisionAPI,
  loadRecountQuestions,
};
