/**
 * Shift AI Verification API
 * API для ИИ проверки товаров при пересменке
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const { requireAuth } = require('../utils/session_middleware');
const db = require('../utils/db');

const USE_DB = process.env.USE_DB_SHIFT_AI === 'true';

// Директории
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const SHIFT_AI_SETTINGS_DIR = `${DATA_DIR}/shift-ai-settings`;
const SHIFT_AI_ANNOTATIONS_DIR = `${DATA_DIR}/shift-ai-annotations`;
const MASTER_CATALOG_DIR = `${DATA_DIR}/master-catalog`;
const DBF_STOCKS_DIR = `${DATA_DIR}/dbf-stocks`;

// Убедимся что директории существуют
(async () => {
  for (const dir of [SHIFT_AI_SETTINGS_DIR, SHIFT_AI_ANNOTATIONS_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

/**
 * Загрузить мастер-каталог товаров
 */
async function loadMasterCatalog() {
  try {
    const catalogFile = path.join(MASTER_CATALOG_DIR, 'products.json');
    if (await fileExists(catalogFile)) {
      const data = await fsp.readFile(catalogFile, 'utf8');
      return JSON.parse(data);
    }
    return [];
  } catch (error) {
    console.error('[ShiftAI] Ошибка загрузки мастер-каталога:', error);
    return [];
  }
}

/**
 * Загрузить настройки ИИ для товаров
 */
async function loadAiSettings() {
  if (USE_DB) {
    try {
      const row = await db.findById('app_settings', 'shift_ai_settings', 'key');
      if (row && row.data) return row.data;
    } catch (e) {
      console.error('[ShiftAI] DB loadAiSettings error:', e.message);
    }
  }
  try {
    const settingsFile = path.join(SHIFT_AI_SETTINGS_DIR, 'products.json');
    if (await fileExists(settingsFile)) {
      const data = await fsp.readFile(settingsFile, 'utf8');
      return JSON.parse(data);
    }
    return {};
  } catch (error) {
    console.error('[ShiftAI] Ошибка загрузки настроек ИИ:', error);
    return {};
  }
}

/**
 * Сохранить настройки ИИ для товаров
 */
async function saveAiSettings(settings) {
  try {
    const settingsFile = path.join(SHIFT_AI_SETTINGS_DIR, 'products.json');
    await writeJsonFile(settingsFile, settings);

    if (USE_DB) {
      try {
        await db.upsert('app_settings', {
          key: 'shift_ai_settings',
          data: settings,
          updated_at: new Date().toISOString(),
        }, 'key');
      } catch (dbErr) {
        console.error('[ShiftAI] DB saveAiSettings error:', dbErr.message);
      }
    }

    return true;
  } catch (error) {
    console.error('[ShiftAI] Ошибка сохранения настроек ИИ:', error);
    return false;
  }
}

/**
 * Загрузить остатки товара из DBF (mock - в реальности будет интеграция)
 */
async function loadProductStock(shopAddress, barcode) {
  try {
    // Формируем путь к файлу остатков магазина
    const shopFileName = shopAddress.replace(/[^a-zA-Z0-9а-яА-Я]/g, '_');
    const stockFile = path.join(DBF_STOCKS_DIR, `${shopFileName}.json`);

    if (await fileExists(stockFile)) {
      const data = await fsp.readFile(stockFile, 'utf8');
      const stocks = JSON.parse(data);
      const item = stocks.find(s => s.barcode === barcode);
      return item ? item.quantity : null;
    }
    return null;
  } catch (error) {
    console.error('[ShiftAI] Ошибка загрузки остатков:', error);
    return null;
  }
}

/**
 * Загрузить образцы для товара (для YOLO)
 */
async function loadSamplesForProduct(productId) {
  try {
    const cigaretteVision = require('../modules/cigarette-vision');
    return await cigaretteVision.getSamplesForProduct(productId);
  } catch (error) {
    console.error('[ShiftAI] Ошибка загрузки образцов:', error);
    return [];
  }
}

/**
 * Проверить готовность ИИ для товара в конкретном магазине
 * Возвращает { isReady, reason, recountComplete, displayComplete }
 */
async function checkAiReadinessForShop(productId, barcode, shopAddress) {
  try {
    const cigaretteVision = require('../modules/cigarette-vision');
    const samples = await cigaretteVision.loadSamples();
    const settings = await cigaretteVision.getSettings();

    const requiredRecount = settings.requiredRecountPhotos || 10;
    const requiredDisplayPerShop = settings.requiredDisplayPhotosPerShop || 3;

    // Подсчитываем фото крупного плана (общие)
    const completedTemplates = new Set();
    let recountCount = 0;

    // Подсчитываем фото выкладки для этого магазина
    let displayCountForShop = 0;

    samples.forEach(sample => {
      // Ищем по productId ИЛИ по barcode (для кросс-каталожной совместимости)
      const sampleProductId = sample.productId;
      const sampleBarcode = sample.barcode;
      const matchesById = sampleProductId && (sampleProductId === productId || sampleProductId === barcode);
      const matchesByBarcode = sampleBarcode && (sampleBarcode === productId || sampleBarcode === barcode);
      if (!matchesById && !matchesByBarcode) return;

      if (sample.type === 'display') {
        // Считаем только фото этого магазина
        if (sample.shopAddress === shopAddress) {
          displayCountForShop++;
        }
      } else {
        // recount - общие фото
        recountCount++;
        if (sample.templateId) {
          completedTemplates.add(sample.templateId);
        }
      }
    });

    const isRecountComplete = completedTemplates.size >= requiredRecount;
    const isDisplayComplete = displayCountForShop >= requiredDisplayPerShop;
    const isReady = isRecountComplete && isDisplayComplete;

    let reason = '';
    if (!isRecountComplete) {
      reason = `Крупный план: ${completedTemplates.size}/${requiredRecount}`;
    } else if (!isDisplayComplete) {
      reason = `Выкладка для магазина: ${displayCountForShop}/${requiredDisplayPerShop}`;
    }

    return {
      isReady,
      reason,
      recountComplete: isRecountComplete,
      recountCount: completedTemplates.size,
      requiredRecount,
      displayComplete: isDisplayComplete,
      displayCountForShop,
      requiredDisplayPerShop,
    };
  } catch (error) {
    console.error('[ShiftAI] Ошибка проверки готовности ИИ:', error);
    return {
      isReady: false,
      reason: 'Ошибка проверки: ' + error.message,
      recountComplete: false,
      displayComplete: false,
    };
  }
}

/**
 * Проверить, обучена ли модель YOLO
 */
async function checkModelStatus() {
  try {
    const cigaretteVision = require('../modules/cigarette-vision');
    const status = await cigaretteVision.getModelStatus();
    return status;
  } catch (error) {
    console.error('[ShiftAI] Ошибка проверки статуса модели:', error);
    return { isTrained: false, samplesCount: 0 };
  }
}

/**
 * Настройка API
 */
function setupShiftAiVerificationAPI(app) {
  console.log('[ShiftAI] Инициализация API...');

  // ============ ТОВАРЫ ============

  // Получить товары с настройками ИИ
  app.get('/api/shift-ai/products', requireAuth, async (req, res) => {
    try {
      const { shopId, group } = req.query;

      // Загружаем мастер-каталог
      const catalog = await loadMasterCatalog();

      // Загружаем настройки ИИ
      const aiSettings = await loadAiSettings();

      // Объединяем данные
      let products = catalog.map(product => {
        const settings = aiSettings[product.barcode] || {};
        return {
          productId: product.id || product.barcode,
          barcode: product.barcode,
          productName: product.name,
          productGroup: product.group,
          isAiActive: settings.isAiActive || false,
          trainingPhotosCount: settings.trainingPhotosCount || 0,
        };
      });

      // Фильтрация по группе
      if (group) {
        products = products.filter(p => p.productGroup === group);
      }

      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(products, req.query, 'products'));
      }
      res.json({ success: true, products });
    } catch (error) {
      console.error('[ShiftAI] Ошибка получения товаров:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить группы товаров
  app.get('/api/shift-ai/product-groups', requireAuth, async (req, res) => {
    try {
      const catalog = await loadMasterCatalog();
      const groups = [...new Set(catalog.map(p => p.group).filter(Boolean))];
      groups.sort();

      res.json({ success: true, groups });
    } catch (error) {
      console.error('[ShiftAI] Ошибка получения групп:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Обновить настройки ИИ для товара
  app.put('/api/shift-ai/products/:barcode', requireAuth, async (req, res) => {
    try {
      const { barcode } = req.params;
      const { isAiActive } = req.body;

      const settings = await loadAiSettings();

      if (!settings[barcode]) {
        settings[barcode] = {};
      }

      if (isAiActive !== undefined) {
        settings[barcode].isAiActive = isAiActive;
      }

      settings[barcode].updatedAt = new Date().toISOString();

      if (await saveAiSettings(settings)) {
        res.json({ success: true, settings: settings[barcode] });
      } else {
        res.status(500).json({ success: false, error: 'Ошибка сохранения' });
      }
    } catch (error) {
      console.error('[ShiftAI] Ошибка обновления настроек:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Получить активные товары для магазина (для проверки при пересменке)
  app.get('/api/shift-ai/active-products/:shopId', requireAuth, async (req, res) => {
    try {
      const { shopId } = req.params;

      const catalog = await loadMasterCatalog();
      const aiSettings = await loadAiSettings();

      // Фильтруем только активные товары
      const activeProducts = catalog
        .filter(product => {
          const settings = aiSettings[product.barcode];
          return settings && settings.isAiActive === true;
        })
        .map(product => ({
          productId: product.id || product.barcode,
          barcode: product.barcode,
          productName: product.name,
          productGroup: product.group,
        }));

      res.json({ success: true, products: activeProducts });
    } catch (error) {
      console.error('[ShiftAI] Ошибка получения активных товаров:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ПРОВЕРКА ============

  // Проверить фото с помощью YOLO
  app.post('/api/shift-ai/verify', requireAuth, async (req, res) => {
    try {
      const { imagesBase64, shopAddress } = req.body;

      if (!imagesBase64 || !Array.isArray(imagesBase64) || imagesBase64.length === 0) {
        return res.status(400).json({ success: false, error: 'Изображения обязательны' });
      }

      if (!shopAddress) {
        return res.status(400).json({ success: false, error: 'Адрес магазина обязателен для проверки' });
      }

      // Проверяем статус модели
      const modelStatus = await checkModelStatus();

      if (!modelStatus.isTrained) {
        return res.json({
          success: false,
          modelTrained: false,
          missingProducts: [],
          detectedProducts: [],
          skippedProducts: [],
          error: 'Модель YOLO ещё не обучена. Необходимо загрузить образцы.',
        });
      }

      // Загружаем активные товары
      const catalog = await loadMasterCatalog();
      const aiSettings = await loadAiSettings();

      const activeProducts = catalog
        .filter(product => {
          const settings = aiSettings[product.barcode];
          return settings && settings.isAiActive === true;
        });

      if (activeProducts.length === 0) {
        return res.json({
          success: true,
          modelTrained: true,
          missingProducts: [],
          detectedProducts: [],
          skippedProducts: [],
          message: 'Нет товаров с включённой ИИ проверкой',
        });
      }

      // НОВОЕ: Фильтруем товары по per-shop готовности ИИ
      const readyProducts = [];
      const skippedProducts = [];

      for (const product of activeProducts) {
        const productId = product.id || product.barcode;
        const readiness = await checkAiReadinessForShop(productId, product.barcode, shopAddress);

        if (readiness.isReady) {
          readyProducts.push(product);
        } else {
          skippedProducts.push({
            productId: productId,
            barcode: product.barcode,
            productName: product.name,
            reason: readiness.reason,
            recountComplete: readiness.recountComplete,
            recountCount: readiness.recountCount,
            requiredRecount: readiness.requiredRecount,
            displayComplete: readiness.displayComplete,
            displayCountForShop: readiness.displayCountForShop,
            requiredDisplayPerShop: readiness.requiredDisplayPerShop,
          });
        }
      }

      if (readyProducts.length === 0) {
        return res.json({
          success: true,
          modelTrained: true,
          missingProducts: [],
          detectedProducts: [],
          skippedProducts: skippedProducts,
          message: `ИИ не готов для этого магазина. Пропущено товаров: ${skippedProducts.length}`,
          shopAddress: shopAddress,
        });
      }

      // Интеграция с YOLO детекцией
      const cigaretteVision = require('../modules/cigarette-vision');

      // Список ожидаемых товаров (productId)
      const expectedProductIds = readyProducts.map(p => p.id || p.barcode);

      // Запускаем детекцию на всех фото и объединяем результаты
      const allDetectedIds = new Set();
      const detectionsByProduct = {};
      // НОВОЕ: Собираем все raw boxes для positive samples
      const allBoxes = [];
      let bestImageForPositive = null;
      let bestImageBoxes = [];

      for (const imageBase64 of imagesBase64) {
        try {
          const result = await cigaretteVision.checkDisplay(
            imageBase64,
            expectedProductIds,
            0.3 // confidence threshold
          );

          if (result.success && result.detectedProducts) {
            result.detectedProducts.forEach(detected => {
              allDetectedIds.add(detected.productId);
              if (!detectionsByProduct[detected.productId]) {
                detectionsByProduct[detected.productId] = {
                  productId: detected.productId,
                  count: 0,
                  maxConfidence: 0,
                };
              }
              detectionsByProduct[detected.productId].count += detected.count || 1;
              detectionsByProduct[detected.productId].maxConfidence = Math.max(
                detectionsByProduct[detected.productId].maxConfidence,
                detected.avgConfidence || 0
              );
            });

            // НОВОЕ: Собираем boxes для positive samples
            if (result.boxes && result.boxes.length > 0) {
              allBoxes.push(...result.boxes);
              // Выбираем фото с наибольшим количеством детекций
              if (result.boxes.length > bestImageBoxes.length) {
                bestImageBoxes = result.boxes;
                bestImageForPositive = imageBase64;
              }
            }
          }
        } catch (e) {
          console.error('[ShiftAI] Ошибка детекции на фото:', e.message);
        }
      }

      // Формируем списки найденных и отсутствующих товаров
      const detectedProducts = [];
      const missingProducts = [];

      for (const product of readyProducts) {
        const productId = product.id || product.barcode;
        const stockQuantity = await loadProductStock(shopAddress, product.barcode);

        if (allDetectedIds.has(productId)) {
          // Товар найден на фото
          const detection = detectionsByProduct[productId];
          detectedProducts.push({
            productId: productId,
            barcode: product.barcode,
            productName: product.name,
            confidence: detection.maxConfidence,
            count: detection.count,
          });
        } else {
          // Товар НЕ найден на фото
          missingProducts.push({
            productId: productId,
            barcode: product.barcode,
            productName: product.name,
            stockQuantity: stockQuantity,
            status: 'notConfirmed',
          });
        }
      }

      // ============ POSITIVE SAMPLES (DISPLAY) ============
      // Пересменка → сохраняем ТОЛЬКО в display-training датасет
      // Эти фото выкладки не нужны для пересчёта и наоборот
      if (detectedProducts.length > 0 && bestImageForPositive && bestImageBoxes.length > 0) {
        // Сохраняем в DISPLAY датасет (фото выкладки для обнаружения товаров)
        cigaretteVision.saveTypedPositiveSample(cigaretteVision.TRAINING_TYPES.DISPLAY, {
          imageBase64: bestImageForPositive,
          detectedProducts: detectedProducts,
          shopAddress: shopAddress,
          boxes: bestImageBoxes,
        }).catch(err => {
          console.warn('[ShiftAI] Ошибка сохранения display sample:', err.message);
        });
      } else if (detectedProducts.length > 0 && imagesBase64.length > 0) {
        // Fallback: если boxes нет, всё равно сохраняем (без аннотаций)
        const randomImageIndex = Math.floor(Math.random() * imagesBase64.length);
        const imageToSave = imagesBase64[randomImageIndex];

        cigaretteVision.saveTypedPositiveSample(cigaretteVision.TRAINING_TYPES.DISPLAY, {
          imageBase64: imageToSave,
          detectedProducts: detectedProducts,
          shopAddress: shopAddress,
          boxes: [],
        }).catch(err => {
          console.warn('[ShiftAI] Ошибка сохранения display sample:', err.message);
        });
      }

      res.json({
        success: true,
        modelTrained: true,
        missingProducts: missingProducts,
        detectedProducts: detectedProducts,
        skippedProducts: skippedProducts,
        message: skippedProducts.length > 0
          ? `Проверено: ${readyProducts.length}, пропущено (не обучено для магазина): ${skippedProducts.length}`
          : `Найдено: ${detectedProducts.length}, не найдено: ${missingProducts.length}`,
        shopAddress: shopAddress,
      });
    } catch (error) {
      console.error('[ShiftAI] Ошибка проверки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ АННОТАЦИИ ============

  // Сохранить аннотацию (BBox) от сотрудника
  app.post('/api/shift-ai/annotations', requireAuth, async (req, res) => {
    try {
      const {
        imageBase64,
        productId,
        barcode,
        productName,
        boundingBox, // { x, y, width, height } normalized 0-1
        shopAddress,
        employeeName,
      } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение обязательно' });
      }

      if (!productId && !barcode) {
        return res.status(400).json({ success: false, error: 'ID товара или штрих-код обязателен' });
      }

      if (!boundingBox) {
        return res.status(400).json({ success: false, error: 'Bounding box обязателен' });
      }

      // Сохраняем аннотацию для обучения YOLO
      const annotationId = `ann_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
      const annotationFile = path.join(SHIFT_AI_ANNOTATIONS_DIR, `${annotationId}.json`);

      const annotation = {
        id: annotationId,
        productId: productId || barcode,
        barcode: barcode || productId,
        productName: productName || '',
        boundingBox: boundingBox,
        shopAddress: shopAddress || '',
        employeeName: employeeName || '',
        createdAt: new Date().toISOString(),
        source: 'shift_verification',
      };

      // Сохраняем изображение
      const imageFileName = `${annotationId}.jpg`;
      const imagePath = path.join(SHIFT_AI_ANNOTATIONS_DIR, imageFileName);
      const imageData = imageBase64.replace(/^data:image\/\w+;base64,/, '');
      await fsp.writeFile(imagePath, Buffer.from(imageData, 'base64'));

      annotation.imagePath = imagePath;

      // Сохраняем аннотацию
      await writeJsonFile(annotationFile, annotation);

      if (USE_DB) {
        try {
          await db.upsert('shift_ai_annotations', {
            id: annotationId,
            product_id: annotation.productId,
            barcode: annotation.barcode,
            shop_address: annotation.shopAddress,
            data: annotation,
            created_at: annotation.createdAt,
          });
        } catch (dbErr) {
          console.error('[ShiftAI] DB save annotation error:', dbErr.message);
        }
      }

      // Обновляем счётчик образцов для товара
      const settings = await loadAiSettings();
      if (!settings[barcode]) {
        settings[barcode] = {};
      }
      settings[barcode].trainingPhotosCount = (settings[barcode].trainingPhotosCount || 0) + 1;
      await saveAiSettings(settings);

      console.log(`[ShiftAI] Сохранена аннотация: ${annotationId} для товара ${barcode}`);

      res.json({ success: true, annotation: annotation });
    } catch (error) {
      console.error('[ShiftAI] Ошибка сохранения аннотации:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ПЕРЕПРОВЕРКА BBOX ============

  // Перепроверить товар в выделенной области BBox с помощью YOLO
  // Используется когда сотрудник выделяет товар на фото после неудачного распознавания
  app.post('/api/shift-ai/verify-bbox', requireAuth, async (req, res) => {
    try {
      const {
        imageBase64,
        boundingBox, // { x, y, width, height } normalized 0-1
        productId,
        barcode,
        productName,
        shopAddress,
        employeeName,
      } = req.body;

      if (!imageBase64) {
        return res.status(400).json({ success: false, error: 'Изображение обязательно' });
      }

      if (!productId && !barcode) {
        return res.status(400).json({ success: false, error: 'ID товара или штрих-код обязателен' });
      }

      if (!boundingBox || boundingBox.x === undefined || boundingBox.y === undefined) {
        return res.status(400).json({ success: false, error: 'Bounding box обязателен' });
      }

      const cigaretteVision = require('../modules/cigarette-vision');

      // Запускаем YOLO детекцию на полном изображении с указанием BBox области интереса
      // YOLO будет искать товар productId/barcode в указанной области
      const result = await cigaretteVision.checkDisplay(
        imageBase64,
        [productId || barcode],  // Ищем только один товар
        0.25  // Пониженный порог уверенности для BBox области
      );

      let detected = false;
      let confidence = null;

      if (result.success && result.detectedProducts && result.detectedProducts.length > 0) {
        // Проверяем нашёлся ли наш товар
        const found = result.detectedProducts.find(
          d => d.productId === productId || d.productId === barcode
        );
        if (found) {
          detected = true;
          confidence = found.avgConfidence || found.confidence || 0.5;
        }
      }

      // Записываем статистику распознавания
      cigaretteVision.recordRecognitionAttempt(
        productId || barcode,
        'bbox_verification',
        detected,
        {
          shopAddress: shopAddress || '',
          employeeName: employeeName || '',
          boundingBox: boundingBox,
          source: 'employee_bbox',
        }
      );

      // Если ИИ нашёл товар - сохраняем аннотацию как pending (ожидает одобрения админа)
      let annotationId = null;
      if (detected) {
        try {
          annotationId = `ann_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
          const annotationFile = path.join(SHIFT_AI_ANNOTATIONS_DIR, `${annotationId}.json`);

          // Сохраняем изображение
          const imageFileName = `${annotationId}.jpg`;
          const imagePath = path.join(SHIFT_AI_ANNOTATIONS_DIR, imageFileName);
          const imageData = imageBase64.replace(/^data:image\/\w+;base64,/, '');
          await fsp.writeFile(imagePath, Buffer.from(imageData, 'base64'));

          const annotation = {
            id: annotationId,
            productId: productId || barcode,
            barcode: barcode || productId,
            productName: productName || '',
            boundingBox: boundingBox,
            shopAddress: shopAddress || '',
            employeeName: employeeName || '',
            imagePath: imagePath,
            status: 'pending', // Ожидает одобрения админа
            source: 'employee_bbox_verification',
            createdAt: new Date().toISOString(),
          };

          await writeJsonFile(annotationFile, annotation);

          if (USE_DB) {
            try {
              await db.upsert('shift_ai_annotations', {
                id: annotationId,
                product_id: annotation.productId,
                barcode: annotation.barcode,
                shop_address: annotation.shopAddress,
                data: annotation,
                created_at: annotation.createdAt,
              });
            } catch (dbErr) {
              console.error('[ShiftAI] DB save pending annotation error:', dbErr.message);
            }
          }

          console.log(`[ShiftAI] BBox verification успешно, аннотация сохранена как pending: ${annotationId}`);
        } catch (saveErr) {
          console.warn('[ShiftAI] Ошибка сохранения pending annotation:', saveErr.message);
        }
      }

      console.log(`[ShiftAI] BBox verification: ${productName || barcode} - ${detected ? 'НАЙДЕН' : 'НЕ НАЙДЕН'} (confidence: ${confidence})`);

      res.json({
        success: true,
        detected: detected,
        confidence: confidence,
        productId: productId || barcode,
        annotationId: annotationId,
        message: detected
          ? `Товар распознан с уверенностью ${Math.round((confidence || 0) * 100)}%`
          : 'Товар не найден на фото. Попробуйте другое фото или другую область.',
      });
    } catch (error) {
      console.error('[ShiftAI] Ошибка verify-bbox:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ГОТОВНОСТЬ ДЛЯ МАГАЗИНА ============

  // Проверить готовность ИИ для конкретного магазина (per-shop)
  app.get('/api/shift-ai/readiness/:shopAddress', requireAuth, async (req, res) => {
    try {
      const { shopAddress } = req.params;
      const decodedAddress = decodeURIComponent(shopAddress);

      const catalog = await loadMasterCatalog();
      const aiSettings = await loadAiSettings();

      // Фильтруем только активные товары
      const activeProducts = catalog.filter(product => {
        const settings = aiSettings[product.barcode];
        return settings && settings.isAiActive === true;
      });

      // Проверяем готовность каждого товара для этого магазина
      const readyProducts = [];
      const notReadyProducts = [];

      for (const product of activeProducts) {
        const productId = product.id || product.barcode;
        const readiness = await checkAiReadinessForShop(productId, product.barcode, decodedAddress);

        const productInfo = {
          productId: productId,
          barcode: product.barcode,
          productName: product.name,
          productGroup: product.group,
          ...readiness,
        };

        if (readiness.isReady) {
          readyProducts.push(productInfo);
        } else {
          notReadyProducts.push(productInfo);
        }
      }

      res.json({
        success: true,
        shopAddress: decodedAddress,
        totalActiveProducts: activeProducts.length,
        readyCount: readyProducts.length,
        notReadyCount: notReadyProducts.length,
        readyProducts: readyProducts,
        notReadyProducts: notReadyProducts,
        isShopReady: readyProducts.length > 0,
        message: readyProducts.length > 0
          ? `ИИ готов для ${readyProducts.length} из ${activeProducts.length} товаров`
          : `ИИ не готов для этого магазина. Необходимо добавить фото выкладки.`,
      });
    } catch (error) {
      console.error('[ShiftAI] Ошибка проверки готовности:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ СТАТУС ============

  // Получить статус модели YOLO
  app.get('/api/shift-ai/model-status', requireAuth, async (req, res) => {
    try {
      const status = await checkModelStatus();

      // Подсчитываем аннотации
      let annotationsCount = 0;
      if (await fileExists(SHIFT_AI_ANNOTATIONS_DIR)) {
        const files = await fsp.readdir(SHIFT_AI_ANNOTATIONS_DIR);
        annotationsCount = files.filter(f => f.endsWith('.json')).length;
      }

      res.json({
        success: true,
        isTrained: status.isTrained || false,
        samplesCount: status.samplesCount || 0,
        shiftAnnotationsCount: annotationsCount,
        message: status.isTrained
          ? 'Модель обучена и готова к использованию'
          : 'Модель ещё не обучена. Загрузите образцы товаров.',
      });
    } catch (error) {
      console.error('[ShiftAI] Ошибка получения статуса:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ ОСТАТКИ ============

  // Получить остатки товара
  app.get('/api/shift-ai/stock/:shopAddress/:barcode', requireAuth, async (req, res) => {
    try {
      const { shopAddress, barcode } = req.params;

      const decodedAddress = decodeURIComponent(shopAddress);
      const quantity = await loadProductStock(decodedAddress, barcode);

      res.json({
        success: true,
        barcode: barcode,
        shopAddress: decodedAddress,
        quantity: quantity,
        hasStock: quantity !== null && quantity > 0,
      });
    } catch (error) {
      console.error('[ShiftAI] Ошибка получения остатков:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ СТАТИСТИКА ============

  // Получить статистику обучения
  app.get('/api/shift-ai/stats', requireAuth, async (req, res) => {
    try {
      const catalog = await loadMasterCatalog();
      const aiSettings = await loadAiSettings();

      let activeCount = 0;
      let totalTrainingPhotos = 0;

      catalog.forEach(product => {
        const settings = aiSettings[product.barcode];
        if (settings) {
          if (settings.isAiActive) activeCount++;
          totalTrainingPhotos += settings.trainingPhotosCount || 0;
        }
      });

      let annotationsCount = 0;
      if (await fileExists(SHIFT_AI_ANNOTATIONS_DIR)) {
        const files = await fsp.readdir(SHIFT_AI_ANNOTATIONS_DIR);
        annotationsCount = files.filter(f => f.endsWith('.json')).length;
      }

      res.json({
        success: true,
        stats: {
          totalProducts: catalog.length,
          activeProducts: activeCount,
          totalTrainingPhotos: totalTrainingPhotos,
          shiftAnnotations: annotationsCount,
        },
      });
    } catch (error) {
      console.error('[ShiftAI] Ошибка получения статистики:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ АННОТАЦИИ: APPROVE / REJECT ============

  // Одобрить аннотацию — загрузить фото для обучения YOLO
  app.put('/api/shift-ai/annotations/:id/approve', requireAuth, async (req, res) => {
    try {
      const { id } = req.params;
      const annotationFile = path.join(SHIFT_AI_ANNOTATIONS_DIR, `${id}.json`);

      if (!(await fileExists(annotationFile))) {
        return res.status(404).json({ success: false, error: 'Аннотация не найдена' });
      }

      const annotation = JSON.parse(await fsp.readFile(annotationFile, 'utf8'));

      if (annotation.status === 'approved') {
        return res.json({ success: true, message: 'Уже одобрена' });
      }

      // Загружаем фото для обучения YOLO
      if (annotation.imagePath && await fileExists(annotation.imagePath)) {
        const imageBuffer = await fsp.readFile(annotation.imagePath);
        const imageBase64 = imageBuffer.toString('base64');

        const cigaretteVision = require('../modules/cigarette-vision');
        await cigaretteVision.saveTypedPositiveSample(
          cigaretteVision.TRAINING_TYPES.DISPLAY,
          {
            imageBase64: imageBase64,
            detectedProducts: [{
              productId: annotation.productId,
              barcode: annotation.barcode,
              productName: annotation.productName,
            }],
            shopAddress: annotation.shopAddress,
            boxes: [annotation.boundingBox],
            source: 'admin_approved_bbox',
          }
        );
      }

      // Обновляем статус
      annotation.status = 'approved';
      annotation.approvedAt = new Date().toISOString();
      await writeJsonFile(annotationFile, annotation);

      if (USE_DB) {
        try {
          await db.upsert('shift_ai_annotations', {
            id: id,
            product_id: annotation.productId,
            barcode: annotation.barcode,
            shop_address: annotation.shopAddress,
            data: annotation,
            created_at: annotation.createdAt,
          });
        } catch (dbErr) {
          console.error('[ShiftAI] DB approve annotation error:', dbErr.message);
        }
      }

      console.log(`[ShiftAI] Аннотация одобрена: ${id}`);
      res.json({ success: true, message: 'Аннотация одобрена и фото загружено для обучения' });
    } catch (error) {
      console.error('[ShiftAI] Ошибка одобрения аннотации:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Отклонить аннотацию — НЕ использовать для обучения
  app.put('/api/shift-ai/annotations/:id/reject', requireAuth, async (req, res) => {
    try {
      const { id } = req.params;
      const annotationFile = path.join(SHIFT_AI_ANNOTATIONS_DIR, `${id}.json`);

      if (!(await fileExists(annotationFile))) {
        return res.status(404).json({ success: false, error: 'Аннотация не найдена' });
      }

      const annotation = JSON.parse(await fsp.readFile(annotationFile, 'utf8'));

      annotation.status = 'rejected';
      annotation.rejectedAt = new Date().toISOString();
      await writeJsonFile(annotationFile, annotation);

      if (USE_DB) {
        try {
          await db.upsert('shift_ai_annotations', {
            id: id,
            product_id: annotation.productId,
            barcode: annotation.barcode,
            shop_address: annotation.shopAddress,
            data: annotation,
            created_at: annotation.createdAt,
          });
        } catch (dbErr) {
          console.error('[ShiftAI] DB reject annotation error:', dbErr.message);
        }
      }

      console.log(`[ShiftAI] Аннотация отклонена: ${id}`);
      res.json({ success: true, message: 'Аннотация отклонена' });
    } catch (error) {
      console.error('[ShiftAI] Ошибка отклонения аннотации:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('[ShiftAI] API инициализировано');
}

module.exports = { setupShiftAiVerificationAPI };
