/**
 * Модуль машинного зрения для подсчёта сигарет
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 *
 * Функции:
 * - Хранение образцов для обучения
 * - Подсчёт загруженных фото по товарам
 * - Подготовка данных для ML модели
 */

const fsp = require('fs').promises;
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile, withLock } = require('../utils/async_fs');
const db = require('../utils/db');

const USE_DB = process.env.USE_DB_CIGARETTE_VISION === 'true';

// YOLO ML Wrapper для детекции
let yoloWrapper = null;
try {
  yoloWrapper = require('../ml/yolo-wrapper');
  console.log('[Cigarette Vision] YOLO wrapper loaded');
} catch (e) {
  console.warn('[Cigarette Vision] YOLO wrapper not available:', e.message);
}

// Пути к данным
const DATA_DIR = path.join(__dirname, '..', 'data');
const SAMPLES_FILE = path.join(DATA_DIR, 'cigarette-training-samples.json');
const STATS_FILE = path.join(DATA_DIR, 'cigarette-training-stats.json');
const SETTINGS_FILE = path.join(DATA_DIR, 'cigarette-training-settings.json');
const IMAGES_DIR = path.join(DATA_DIR, 'cigarette-training-images');

// Путь к магазинам (из основной системы)
const SHOPS_DIR = '/var/www/shops';

// ============ РАЗДЕЛЬНЫЕ ДАТАСЕТЫ ДЛЯ ДВУХ МОДЕЛЕЙ ============
// Типы обучения
const TRAINING_TYPES = {
  DISPLAY: 'display',   // Пересменка: обнаружение на выкладке (далеко, много товаров)
  COUNTING: 'counting', // Пересчёт: подсчёт пачек (близко, один товар)
};

// Директории для раздельных датасетов
const DISPLAY_TRAINING_DIR = path.join(DATA_DIR, 'display-training');
const COUNTING_TRAINING_DIR = path.join(DATA_DIR, 'counting-training');
const COUNTING_PENDING_DIR = path.join(DATA_DIR, 'counting-pending'); // Ожидающие подтверждения админа

// Структура поддиректорий для каждого типа
const getTrainingPaths = (trainingType) => {
  const baseDir = trainingType === TRAINING_TYPES.COUNTING
    ? COUNTING_TRAINING_DIR
    : DISPLAY_TRAINING_DIR;

  return {
    baseDir,
    imagesDir: path.join(baseDir, 'images'),
    labelsDir: path.join(baseDir, 'labels'),
    samplesFile: path.join(baseDir, 'samples.json'),
    classMappingFile: path.join(baseDir, 'class-mapping.json'),
  };
};

// Пути для pending counting (ожидающие подтверждения)
const getCountingPendingPaths = () => {
  return {
    baseDir: COUNTING_PENDING_DIR,
    imagesDir: path.join(COUNTING_PENDING_DIR, 'images'),
    samplesFile: path.join(COUNTING_PENDING_DIR, 'samples.json'),
  };
};

// Инициализация pending директории
async function initCountingPending() {
  const paths = getCountingPendingPaths();
  if (!(await fileExists(paths.baseDir))) await fsp.mkdir(paths.baseDir, { recursive: true });
  if (!(await fileExists(paths.imagesDir))) await fsp.mkdir(paths.imagesDir, { recursive: true });
  if (!(await fileExists(paths.samplesFile))) await writeJsonFile(paths.samplesFile, []);
  return paths;
}

// Загрузить pending samples
async function loadPendingCountingSamples() {
  const paths = getCountingPendingPaths();
  if (!(await fileExists(paths.samplesFile))) return [];
  try {
    return JSON.parse(await fsp.readFile(paths.samplesFile, 'utf8'));
  } catch (e) {
    return [];
  }
}

// Сохранить pending samples
async function savePendingCountingSamples(samples) {
  const paths = await initCountingPending();
  await writeJsonFile(paths.samplesFile, samples);
}

// Путь к единой YOLO-модели (display_detector.pt и counting_detector.pt не используются)
const UNIFIED_MODEL = require('../ml/yolo-wrapper').DEFAULT_MODEL;

// Дефолтные настройки (можно изменить через API)
const DEFAULT_SETTINGS = {
  requiredRecountPhotos: 10,
  requiredDisplayPhotosPerShop: 3,
  requiredCountingPhotos: 10,
  maxCountingPhotosPerProduct: 50,
  catalogSource: 'recount-questions',
  positiveSamplesEnabled: true,
  positiveSampleRate: 0.1,
  maxPositiveSamplesPerProduct: 50,
  positiveSamplesMaxAgeDays: 180,
};

// Кэш настроек с TTL
let settingsCache = null;
let settingsCacheTime = 0;
const SETTINGS_CACHE_TTL = 5 * 60 * 1000; // 5 минут

/**
 * Загрузить настройки
 */
async function loadSettings() {
  if (settingsCache && Date.now() - settingsCacheTime < SETTINGS_CACHE_TTL) return settingsCache;

  if (USE_DB) {
    try {
      const row = await db.findById('app_settings', 'cigarette_vision_settings', 'key');
      if (row && row.data) {
        settingsCache = row.data;
        settingsCacheTime = Date.now();
        return settingsCache;
      }
    } catch (e) {
      console.error('[Cigarette Vision] DB loadSettings error:', e.message);
    }
  }

  try {
    if (await fileExists(SETTINGS_FILE)) {
      settingsCache = JSON.parse(await fsp.readFile(SETTINGS_FILE, 'utf8'));
    } else {
      settingsCache = { ...DEFAULT_SETTINGS };
      await saveSettings(settingsCache);
    }
  } catch (e) {
    console.error('Ошибка загрузки настроек:', e);
    settingsCache = { ...DEFAULT_SETTINGS };
  }
  settingsCacheTime = Date.now();
  return settingsCache;
}

/**
 * Сохранить настройки
 */
async function saveSettings(settings) {
  try {
    await writeJsonFile(SETTINGS_FILE, settings);
    settingsCache = settings;
    settingsCacheTime = Date.now();

    if (USE_DB) {
      try {
        await db.upsert('app_settings', {
          key: 'cigarette_vision_settings',
          data: settings,
          updated_at: new Date().toISOString(),
        }, 'key');
      } catch (dbErr) {
        console.error('[Cigarette Vision] DB saveSettings error:', dbErr.message);
      }
    }

    return true;
  } catch (e) {
    console.error('Ошибка сохранения настроек:', e);
    return false;
  }
}

/**
 * Получить настройки
 */
async function getSettings() {
  return await loadSettings();
}

/**
 * Обновить настройки
 */
async function updateSettings(newSettings) {
  const current = await loadSettings();
  const updated = { ...current, ...newSettings };
  return (await saveSettings(updated)) ? updated : null;
}

// Для обратной совместимости
const REQUIRED_PHOTOS_COUNT = 20;

/**
 * Инициализация модуля - создание необходимых директорий и файлов
 */
async function init() {
  if (!(await fileExists(DATA_DIR))) {
    await fsp.mkdir(DATA_DIR, { recursive: true });
  }
  if (!(await fileExists(IMAGES_DIR))) {
    await fsp.mkdir(IMAGES_DIR, { recursive: true });
  }

  if (!(await fileExists(SAMPLES_FILE))) {
    await writeJsonFile(SAMPLES_FILE, { samples: [] });
  }
  if (!(await fileExists(STATS_FILE))) {
    await writeJsonFile(STATS_FILE, { lastUpdated: null });
  }
}

// Initialize on module load
(async () => {
  await init();
})();

/**
 * Загрузить все магазины из основной системы
 */
async function loadAllShops() {
  try {
    if (!(await fileExists(SHOPS_DIR))) {
      console.warn('[Cigarette Vision] Директория магазинов не найдена:', SHOPS_DIR);
      return [];
    }

    const shops = [];
    const files = (await fsp.readdir(SHOPS_DIR)).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const content = await fsp.readFile(path.join(SHOPS_DIR, file), 'utf8');
        const shop = JSON.parse(content);
        if (shop.address) {
          shops.push({
            id: shop.id,
            name: shop.name,
            address: shop.address,
          });
        }
      } catch (e) {
        console.error(`Ошибка чтения файла магазина ${file}:`, e.message);
      }
    }

    return shops;
  } catch (error) {
    console.error('Ошибка загрузки магазинов:', error);
    return [];
  }
}

/**
 * Загрузить все образцы
 */
async function loadSamples() {
  if (USE_DB) {
    try {
      const rows = await db.findAll('cigarette_samples', { orderBy: 'created_at', orderDir: 'ASC' });
      return rows.map(r => r.data);
    } catch (e) {
      console.error('[Cigarette Vision] DB loadSamples error:', e.message);
    }
  }
  try {
    await init();
    const data = await fsp.readFile(SAMPLES_FILE, 'utf8');
    return JSON.parse(data).samples || [];
  } catch (error) {
    console.error('Ошибка загрузки образцов:', error);
    return [];
  }
}

/**
 * Сохранить образцы
 */
async function saveSamples(samples) {
  try {
    await init();
    await writeJsonFile(SAMPLES_FILE, { samples });

    if (USE_DB) {
      try {
        for (const sample of samples) {
          await db.upsert('cigarette_samples', {
            id: sample.id,
            product_id: sample.productId || null,
            type: sample.type || null,
            shop_address: sample.shopAddress || null,
            data: sample,
            created_at: sample.createdAt || new Date().toISOString(),
          });
        }
      } catch (dbErr) {
        console.error('[Cigarette Vision] DB saveSamples error:', dbErr.message);
      }
    }

    return true;
  } catch (error) {
    console.error('Ошибка сохранения образцов:', error);
    return false;
  }
}

/**
 * Получить список товаров с информацией об обучении
 */
async function getProductsWithTrainingInfo(recountQuestions, productGroup = null) {
  const samples = await loadSamples();
  const settings = await loadSettings();
  const shops = await loadAllShops();

  const requiredRecount = settings.requiredRecountPhotos || 10;
  const requiredDisplayPerShop = settings.requiredDisplayPhotosPerShop || 3;

  const recountPhotosByProduct = {};
  const completedTemplatesByProduct = {};
  const displayPhotosByProductAndShop = {};

  samples.forEach(sample => {
    const productId = sample.productId;
    const barcode = sample.barcode;

    if (sample.type === 'display') {
      if (sample.shopAddress) {
        if (productId) {
          const keyById = `${productId}|${sample.shopAddress}`;
          displayPhotosByProductAndShop[keyById] = (displayPhotosByProductAndShop[keyById] || 0) + 1;
        }
        if (barcode && barcode !== productId) {
          const keyByBarcode = `${barcode}|${sample.shopAddress}`;
          displayPhotosByProductAndShop[keyByBarcode] = (displayPhotosByProductAndShop[keyByBarcode] || 0) + 1;
        }
      }
    } else {
      if (productId) {
        recountPhotosByProduct[productId] = (recountPhotosByProduct[productId] || 0) + 1;
      }
      if (barcode && barcode !== productId) {
        recountPhotosByProduct[barcode] = (recountPhotosByProduct[barcode] || 0) + 1;
      }

      if (sample.templateId) {
        const key = productId || barcode;
        if (!completedTemplatesByProduct[key]) {
          completedTemplatesByProduct[key] = new Set();
        }
        completedTemplatesByProduct[key].add(sample.templateId);
        if (barcode && barcode !== key) {
          if (!completedTemplatesByProduct[barcode]) {
            completedTemplatesByProduct[barcode] = new Set();
          }
          completedTemplatesByProduct[barcode].add(sample.templateId);
        }
      }
    }
  });

  let products = recountQuestions.map(q => {
    const recountPhotos = recountPhotosByProduct[q.id] || recountPhotosByProduct[q.barcode] || 0;
    const completedTemplatesSet = completedTemplatesByProduct[q.id] || completedTemplatesByProduct[q.barcode] || new Set();
    const completedTemplates = Array.from(completedTemplatesSet).sort((a, b) => a - b);
    const isRecountComplete = completedTemplates.length >= requiredRecount;

    const perShopDisplayStats = shops.map(shop => {
      const keyById = `${q.id}|${shop.address}`;
      const keyByBarcode = `${q.barcode}|${shop.address}`;
      const count = displayPhotosByProductAndShop[keyById] || displayPhotosByProductAndShop[keyByBarcode] || 0;
      return {
        shopAddress: shop.address,
        shopName: shop.name,
        shopId: shop.id,
        displayPhotosCount: count,
        requiredDisplayPhotos: requiredDisplayPerShop,
        isDisplayComplete: count >= requiredDisplayPerShop,
      };
    });

    const totalDisplayPhotos = perShopDisplayStats.reduce((sum, s) => sum + s.displayPhotosCount, 0);
    const shopsWithAiReady = perShopDisplayStats.filter(s => s.isDisplayComplete).length;
    const isDisplayComplete = shopsWithAiReady > 0;

    return {
      id: q.id,
      barcode: q.barcode || q.id,
      productGroup: q.productGroup || '',
      productName: q.productName || q.question || '',
      grade: q.grade || 1,
      isAiActive: q.isAiActive || false,
      trainingPhotosCount: recountPhotos + totalDisplayPhotos,
      requiredPhotosCount: requiredRecount + requiredDisplayPerShop,
      isTrainingComplete: isRecountComplete && isDisplayComplete,
      recountPhotosCount: recountPhotos,
      requiredRecountPhotos: requiredRecount,
      isRecountComplete: isRecountComplete,
      completedTemplates: completedTemplates,
      displayPhotosCount: totalDisplayPhotos,
      requiredDisplayPhotos: requiredDisplayPerShop,
      isDisplayComplete: isDisplayComplete,
      perShopDisplayStats: perShopDisplayStats,
      totalDisplayPhotos: totalDisplayPhotos,
      requiredDisplayPhotosPerShop: requiredDisplayPerShop,
      shopsWithAiReady: shopsWithAiReady,
      totalShops: shops.length,
    };
  });

  if (productGroup) {
    products = products.filter(p => p.productGroup === productGroup);
  }

  return products;
}

/**
 * Получить список уникальных групп товаров
 */
function getProductGroups(recountQuestions) {
  const groups = new Set();
  recountQuestions.forEach(q => {
    if (q.productGroup) {
      groups.add(q.productGroup);
    }
  });
  return Array.from(groups).sort();
}

/**
 * Получить статистику обучения
 */
async function getTrainingStats(recountQuestions) {
  const samples = await loadSamples();
  const products = await getProductsWithTrainingInfo(recountQuestions);

  const recountPhotos = samples.filter(s => s.type === 'recount' || !s.type).length;
  const displayPhotos = samples.filter(s => s.type === 'display').length;

  const productsWithPhotos = products.filter(p => p.trainingPhotosCount > 0).length;
  const productsFullyTrained = products.filter(p => p.isTrainingComplete).length;

  const totalProgress = products.reduce((sum, p) => {
    return sum + Math.min(p.trainingPhotosCount / REQUIRED_PHOTOS_COUNT * 100, 100);
  }, 0);
  const overallProgress = products.length > 0 ? totalProgress / products.length : 0;

  return {
    totalProducts: products.length,
    productsWithPhotos,
    productsFullyTrained,
    totalRecountPhotos: recountPhotos,
    totalDisplayPhotos: displayPhotos,
    overallProgress: Math.round(overallProgress * 10) / 10,
  };
}

// Директория для YOLO аннотаций
const LABELS_DIR = path.join(DATA_DIR, 'cigarette-training-labels');

/**
 * Сохранить образец для обучения
 */
async function saveTrainingSample({
  imageBase64,
  productId,
  barcode,
  productName,
  type = 'recount',
  templateId = null,
  shopAddress,
  employeeName,
  boundingBoxes = [],
}) {
  try {
    await init();

    if (!(await fileExists(LABELS_DIR))) {
      await fsp.mkdir(LABELS_DIR, { recursive: true });
    }

    const id = uuidv4();
    const timestamp = new Date().toISOString();

    const imageBuffer = Buffer.from(imageBase64, 'base64');
    const imageFileName = `${id}.jpg`;
    const imagePath = path.join(IMAGES_DIR, imageFileName);
    await fsp.writeFile(imagePath, imageBuffer);

    if (boundingBoxes && boundingBoxes.length > 0) {
      const labelFileName = `${id}.txt`;
      const labelPath = path.join(LABELS_DIR, labelFileName);

      const classId = await getClassIdForProduct(productId);
      const yoloLines = boundingBoxes.map(box => {
        const xCenter = box.xCenter || box.x_center || 0;
        const yCenter = box.yCenter || box.y_center || 0;
        const width = box.width || 0;
        const height = box.height || 0;
        return `${classId} ${xCenter.toFixed(6)} ${yCenter.toFixed(6)} ${width.toFixed(6)} ${height.toFixed(6)}`;
      }).join('\n');

      await fsp.writeFile(labelPath, yoloLines);
      console.log(`[Cigarette Vision] YOLO аннотация сохранена: ${labelFileName} (${boundingBoxes.length} boxes)`);
    }

    const sample = {
      id,
      productId,
      barcode,
      productName,
      type,
      templateId,
      shopAddress,
      employeeName,
      imageFileName,
      imageUrl: `/api/cigarette-vision/images/${imageFileName}`,
      boundingBoxes: boundingBoxes || [],
      annotationCount: boundingBoxes ? boundingBoxes.length : 0,
      createdAt: timestamp,
    };

    const samples = await loadSamples();
    samples.push(sample);
    await saveSamples(samples);

    console.log(`[Cigarette Vision] Образец сохранён: ${productName} (${type}, template=${templateId}, ${boundingBoxes ? boundingBoxes.length : 0} аннотаций)`);

    return { success: true, sample };
  } catch (error) {
    console.error('Ошибка сохранения образца:', error);
    return { success: false, error: error.message };
  }
}

// Кэш маппинга productId -> classId
let classMapping = null;
const CLASS_MAPPING_FILE = path.join(DATA_DIR, 'class-mapping.json');

/**
 * Получить classId для товара (создаёт новый если не существует)
 */
async function getClassIdForProduct(productId) {
  if (classMapping === null) {
    if (await fileExists(CLASS_MAPPING_FILE)) {
      try {
        classMapping = JSON.parse(await fsp.readFile(CLASS_MAPPING_FILE, 'utf8'));
      } catch (e) {
        classMapping = {};
      }
    } else {
      classMapping = {};
    }
  }

  if (classMapping[productId] !== undefined) {
    return classMapping[productId];
  }

  const maxId = Object.values(classMapping).reduce((max, id) => Math.max(max, id), -1);
  const newId = maxId + 1;
  classMapping[productId] = newId;

  await writeJsonFile(CLASS_MAPPING_FILE, classMapping);
  console.log(`[Cigarette Vision] Новый classId для ${productId}: ${newId}`);

  return newId;
}

/**
 * Получить маппинг всех товаров -> classId
 */
async function getClassMapping() {
  if (classMapping === null) {
    if (await fileExists(CLASS_MAPPING_FILE)) {
      try {
        classMapping = JSON.parse(await fsp.readFile(CLASS_MAPPING_FILE, 'utf8'));
      } catch (e) {
        classMapping = {};
      }
    } else {
      classMapping = {};
    }
  }
  return classMapping;
}

/**
 * Получить образцы для товара
 */
async function getSamplesForProduct(productId) {
  const samples = await loadSamples();
  return samples.filter(s => s.productId === productId || s.barcode === productId);
}

/**
 * Удалить образец
 */
async function deleteSample(sampleId) {
  try {
    const samples = await loadSamples();
    const sampleIndex = samples.findIndex(s => s.id === sampleId);

    if (sampleIndex === -1) {
      return { success: false, error: 'Образец не найден' };
    }

    const sample = samples[sampleIndex];

    if (sample.imageFileName) {
      const imagePath = path.join(IMAGES_DIR, sample.imageFileName);
      if (await fileExists(imagePath)) {
        await fsp.unlink(imagePath);
      }
    }

    samples.splice(sampleIndex, 1);
    await saveSamples(samples);

    return { success: true };
  } catch (error) {
    console.error('Ошибка удаления образца:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Получить изображение образца
 */
function getImagePath(fileName) {
  return path.join(IMAGES_DIR, fileName);
}

// ============ POSITIVE SAMPLES (успешные распознавания) ============

/**
 * Сохранить positive sample (успешное распознавание) с лимитом и ротацией
 */
async function savePositiveSample({
  imageBase64,
  detectedProducts,
  shopAddress,
  boxes = [],
}) {
  try {
    const settings = await loadSettings();

    if (!settings.positiveSamplesEnabled) {
      return { success: false, skipped: true, reason: 'Positive samples отключены' };
    }

    const sampleRate = settings.positiveSampleRate || 0.1;
    if (Math.random() > sampleRate) {
      return { success: false, skipped: true, reason: 'Не попал в выборку' };
    }

    if (!detectedProducts || detectedProducts.length === 0) {
      return { success: false, skipped: true, reason: 'Нет распознанных товаров' };
    }

    await init();

    const maxPerProduct = settings.maxPositiveSamplesPerProduct || 50;
    const samples = await loadSamples();
    const savedCount = { total: 0, rotated: 0 };

    for (const detected of detectedProducts) {
      const productId = detected.productId || detected.barcode;

      const existingPositive = samples.filter(
        s => (s.productId === productId || s.barcode === productId) && s.type === 'positive'
      );

      if (existingPositive.length >= maxPerProduct) {
        existingPositive.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
        const toDelete = existingPositive[0];
        const deleteResult = await deleteSampleInternal(samples, toDelete.id);
        if (deleteResult.deleted) {
          savedCount.rotated++;
          console.log(`[Positive Samples] Ротация: удалён старый sample ${toDelete.id} для ${productId}`);
        }
      }

      const id = uuidv4();
      const timestamp = new Date().toISOString();

      const imageBuffer = Buffer.from(imageBase64, 'base64');
      const imageFileName = `positive_${id}.jpg`;
      const imagePath = path.join(IMAGES_DIR, imageFileName);
      await fsp.writeFile(imagePath, imageBuffer);

      const productBoxes = boxes.filter(box => box.productId === productId);

      let yoloAnnotationCount = 0;
      if (productBoxes.length > 0) {
        if (!(await fileExists(LABELS_DIR))) {
          await fsp.mkdir(LABELS_DIR, { recursive: true });
        }

        const labelFileName = `positive_${id}.txt`;
        const labelPath = path.join(LABELS_DIR, labelFileName);

        const classId = await getClassIdForProduct(productId);
        const yoloLines = productBoxes.map(box => {
          const b = box.box;
          const xCenter = (b.x1 + b.x2) / 2;
          const yCenter = (b.y1 + b.y2) / 2;
          const width = b.x2 - b.x1;
          const height = b.y2 - b.y1;
          return `${classId} ${xCenter.toFixed(6)} ${yCenter.toFixed(6)} ${width.toFixed(6)} ${height.toFixed(6)}`;
        }).join('\n');

        await fsp.writeFile(labelPath, yoloLines);
        yoloAnnotationCount = productBoxes.length;
        console.log(`[Positive Samples] YOLO label сохранён: ${labelFileName} (${yoloAnnotationCount} boxes)`);
      }

      const sample = {
        id,
        productId,
        barcode: detected.barcode || productId,
        productName: detected.productName || '',
        type: 'positive',
        shopAddress: shopAddress || '',
        confidence: detected.confidence || detected.maxConfidence || 0,
        count: detected.count || 1,
        imageFileName,
        imageUrl: `/api/cigarette-vision/images/${imageFileName}`,
        boundingBoxes: productBoxes.map(b => b.box),
        annotationCount: yoloAnnotationCount,
        createdAt: timestamp,
      };

      samples.push(sample);
      savedCount.total++;
    }

    await saveSamples(samples);

    console.log(`[Positive Samples] Сохранено ${savedCount.total} samples, ротировано ${savedCount.rotated}`);

    return { success: true, savedCount };
  } catch (error) {
    console.error('[Positive Samples] Ошибка сохранения:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Внутренняя функция удаления sample из массива
 */
async function deleteSampleInternal(samples, sampleId) {
  const sampleIndex = samples.findIndex(s => s.id === sampleId);

  if (sampleIndex === -1) {
    return { deleted: false };
  }

  const sample = samples[sampleIndex];

  if (sample.imageFileName) {
    const imagePath = path.join(IMAGES_DIR, sample.imageFileName);
    if (await fileExists(imagePath)) {
      try {
        await fsp.unlink(imagePath);
      } catch (e) {
        console.warn(`[Positive Samples] Не удалось удалить файл ${imagePath}:`, e.message);
      }
    }

    const labelFileName = sample.imageFileName ? sample.imageFileName.replace(/\.jpg$/, '.txt') : (sample.id + '.txt');
    const labelPath = path.join(LABELS_DIR, labelFileName);
    if (await fileExists(labelPath)) {
      try {
        await fsp.unlink(labelPath);
      } catch (e) {
        // Игнорируем ошибки удаления label
      }
    }
  }

  samples.splice(sampleIndex, 1);

  return { deleted: true };
}

/**
 * Очистка старых positive samples (старше N дней)
 */
async function cleanupOldPositiveSamples() {
  try {
    const settings = await loadSettings();
    const maxAgeDays = settings.positiveSamplesMaxAgeDays || 180;
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - maxAgeDays);

    const samples = await loadSamples();
    let deletedCount = 0;

    const toDelete = samples.filter(s => {
      if (s.type !== 'positive') return false;
      const createdAt = new Date(s.createdAt);
      return createdAt < cutoffDate;
    });

    for (const sample of toDelete) {
      const result = await deleteSampleInternal(samples, sample.id);
      if (result.deleted) {
        deletedCount++;
      }
    }

    if (deletedCount > 0) {
      await saveSamples(samples);
      console.log(`[Positive Samples] Очистка: удалено ${deletedCount} старых samples (старше ${maxAgeDays} дней)`);
    }

    return { success: true, deletedCount, remaining: samples.length };
  } catch (error) {
    console.error('[Positive Samples] Ошибка очистки:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Получить статистику positive samples
 */
async function getPositiveSamplesStats() {
  try {
    const samples = await loadSamples();
    const positiveSamples = samples.filter(s => s.type === 'positive');

    const byProduct = {};
    positiveSamples.forEach(s => {
      const key = s.productId || s.barcode;
      if (!byProduct[key]) {
        byProduct[key] = { count: 0, productName: s.productName };
      }
      byProduct[key].count++;
    });

    const byShop = {};
    positiveSamples.forEach(s => {
      const key = s.shopAddress || 'unknown';
      byShop[key] = (byShop[key] || 0) + 1;
    });

    return {
      totalPositiveSamples: positiveSamples.length,
      productsWithPositive: Object.keys(byProduct).length,
      byProduct,
      byShop,
    };
  } catch (error) {
    console.error('[Positive Samples] Ошибка получения статистики:', error);
    return { totalPositiveSamples: 0, error: error.message };
  }
}

// ============ END POSITIVE SAMPLES ============

/**
 * Детекция и подсчёт сигарет на изображении
 */
async function detectAndCount(imageBase64, productId = null, confidence = 0.5) {
  if (!yoloWrapper) {
    return {
      success: false,
      error: 'ML модуль не загружен. Проверьте установку зависимостей.',
      count: 0,
      confidence: 0,
      boxes: [],
    };
  }

  if (!yoloWrapper.isModelReady()) {
    const samples = await loadSamples();
    const totalSamples = samples.length;
    const samplesWithAnnotations = samples.filter(s => s.annotationCount > 0).length;

    return {
      success: false,
      error: `Модель ещё не обучена. Загружено ${totalSamples} образцов (${samplesWithAnnotations} с аннотациями). Требуется минимум 50 аннотированных образцов для обучения.`,
      count: 0,
      confidence: 0,
      boxes: [],
      trainingStatus: {
        totalSamples,
        annotatedSamples: samplesWithAnnotations,
        requiredSamples: 50,
        isReady: samplesWithAnnotations >= 50
      }
    };
  }

  try {
    const result = await yoloWrapper.detectAndCount(imageBase64, productId, confidence);

    if (result.success) {
      console.log(`[Cigarette Vision] Обнаружено ${result.count} объектов (confidence: ${result.confidence})`);
    } else {
      console.warn('[Cigarette Vision] Ошибка детекции:', result.error);
    }

    return result;
  } catch (error) {
    console.error('[Cigarette Vision] Ошибка вызова YOLO:', error);
    return {
      success: false,
      error: `Ошибка ML модели: ${error.message}`,
      count: 0,
      confidence: 0,
      boxes: [],
    };
  }
}

/**
 * Проверка выкладки - обнаружение товаров на витрине
 */
async function checkDisplay(imageBase64, expectedProducts = [], confidence = 0.3) {
  if (!yoloWrapper) {
    return {
      success: false,
      error: 'ML модуль не загружен. Проверьте установку зависимостей.',
      missingProducts: expectedProducts,
      detectedProducts: [],
    };
  }

  if (!yoloWrapper.isModelReady()) {
    const samples = await loadSamples();
    const displaySamples = samples.filter(s => s.type === 'display').length;

    return {
      success: false,
      error: `Модель не обучена для проверки выкладки. Загружено ${displaySamples} фото выкладки. Требуется минимум 100 для обучения.`,
      missingProducts: expectedProducts,
      detectedProducts: [],
      trainingStatus: {
        displaySamples,
        requiredSamples: 100,
        isReady: displaySamples >= 100
      }
    };
  }

  try {
    const result = await yoloWrapper.checkDisplay(imageBase64, expectedProducts, confidence);

    if (result.success) {
      console.log(`[Cigarette Vision] Выкладка: обнаружено ${result.totalDetected} товаров, отсутствует ${result.missingProducts?.length || 0}`);
    } else {
      console.warn('[Cigarette Vision] Ошибка проверки выкладки:', result.error);
    }

    return result;
  } catch (error) {
    console.error('[Cigarette Vision] Ошибка вызова YOLO:', error);
    return {
      success: false,
      error: `Ошибка ML модели: ${error.message}`,
      missingProducts: expectedProducts,
      detectedProducts: [],
    };
  }
}

/**
 * Экспорт данных для обучения в YOLO формат
 */
async function exportTrainingData(outputDir) {
  if (!yoloWrapper) {
    return {
      success: false,
      error: 'ML модуль не загружен'
    };
  }

  return await yoloWrapper.exportTrainingData(outputDir);
}

/**
 * Запустить обучение модели
 */
async function trainModel(dataYaml, epochs = 100) {
  if (!yoloWrapper) {
    return {
      success: false,
      error: 'ML модуль не загружен'
    };
  }

  return await yoloWrapper.trainModel(dataYaml, epochs);
}

/**
 * Получить статус ML модели
 */
async function getModelStatus() {
  if (!yoloWrapper) {
    return {
      available: false,
      isTrained: false,
      error: 'ML модуль не загружен'
    };
  }

  const status = await yoloWrapper.checkStatus();
  const modelInfo = yoloWrapper.getModelInfo();

  const isTrained = status.model_exists || modelInfo.exists || false;

  return {
    available: true,
    isTrained: isTrained,
    ...status,
    model: modelInfo
  };
}

// ============ РАЗДЕЛЬНЫЕ ДАТАСЕТЫ: ФУНКЦИИ ============

/**
 * Инициализация директорий для раздельного обучения
 */
async function initTypedTraining(trainingType) {
  const paths = getTrainingPaths(trainingType);

  if (!(await fileExists(paths.baseDir))) {
    await fsp.mkdir(paths.baseDir, { recursive: true });
  }
  if (!(await fileExists(paths.imagesDir))) {
    await fsp.mkdir(paths.imagesDir, { recursive: true });
  }
  if (!(await fileExists(paths.labelsDir))) {
    await fsp.mkdir(paths.labelsDir, { recursive: true });
  }
  if (!(await fileExists(paths.samplesFile))) {
    await writeJsonFile(paths.samplesFile, { samples: [] });
  }

  return paths;
}

/**
 * Загрузить образцы для конкретного типа обучения
 */
async function loadTypedSamples(trainingType) {
  try {
    const paths = await initTypedTraining(trainingType);
    const data = await fsp.readFile(paths.samplesFile, 'utf8');
    return JSON.parse(data).samples || [];
  } catch (error) {
    console.error(`[Typed Training] Ошибка загрузки образцов ${trainingType}:`, error);
    return [];
  }
}

/**
 * Сохранить образцы для конкретного типа обучения
 */
async function saveTypedSamples(trainingType, samples) {
  try {
    const paths = await initTypedTraining(trainingType);
    await writeJsonFile(paths.samplesFile, { samples });
    return true;
  } catch (error) {
    console.error(`[Typed Training] Ошибка сохранения образцов ${trainingType}:`, error);
    return false;
  }
}

/**
 * Получить classId для товара в конкретном датасете
 */
async function getTypedClassId(trainingType, productId) {
  const paths = await initTypedTraining(trainingType);

  return await withLock(`class-mapping-${trainingType}`, async () => {
    let classMapping = {};
    if (await fileExists(paths.classMappingFile)) {
      try {
        classMapping = JSON.parse(await fsp.readFile(paths.classMappingFile, 'utf8'));
      } catch (e) {
        classMapping = {};
      }
    }

    if (classMapping[productId] !== undefined) {
      return classMapping[productId];
    }

    const maxId = Object.values(classMapping).reduce((max, id) => Math.max(max, id), -1);
    const newId = maxId + 1;
    classMapping[productId] = newId;

    await writeJsonFile(paths.classMappingFile, classMapping);
    console.log(`[Typed Training] ${trainingType}: новый classId для ${productId}: ${newId}`);

    return newId;
  });
}

/**
 * Сохранить positive sample в раздельный датасет
 */
async function saveTypedPositiveSample(trainingType, {
  imageBase64,
  detectedProducts,
  shopAddress,
  boxes = [],
  force = false,
}) {
  try {
    const settings = await loadSettings();

    if (!force && !settings.positiveSamplesEnabled) {
      return { success: false, skipped: true, reason: 'Positive samples отключены' };
    }

    if (!force) {
      const sampleRate = settings.positiveSampleRate || 0.1;
      if (Math.random() > sampleRate) {
        return { success: false, skipped: true, reason: 'Не попал в выборку' };
      }
    }

    if (!detectedProducts || detectedProducts.length === 0) {
      return { success: false, skipped: true, reason: 'Нет распознанных товаров' };
    }

    const paths = await initTypedTraining(trainingType);
    const maxPerProduct = settings.maxPositiveSamplesPerProduct || 50;
    const samples = await loadTypedSamples(trainingType);
    const savedCount = { total: 0, rotated: 0, withLabels: 0 };

    for (const detected of detectedProducts) {
      const productId = detected.productId || detected.barcode;

      const existingPositive = samples.filter(
        s => (s.productId === productId || s.barcode === productId)
      );

      if (existingPositive.length >= maxPerProduct) {
        existingPositive.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
        const toDelete = existingPositive[0];

        const imgPath = path.join(paths.imagesDir, toDelete.imageFileName);
        const lblPath = path.join(paths.labelsDir, toDelete.imageFileName.replace(/\.jpg$/, '.txt'));
        try {
          if (await fileExists(imgPath)) await fsp.unlink(imgPath);
          if (await fileExists(lblPath)) await fsp.unlink(lblPath);
        } catch (e) { /* ignore */ }

        const idx = samples.findIndex(s => s.id === toDelete.id);
        if (idx !== -1) {
          samples.splice(idx, 1);
          savedCount.rotated++;
        }
      }

      const id = uuidv4();
      const timestamp = new Date().toISOString();
      const imageFileName = `${trainingType}_${id}.jpg`;

      const imageBuffer = Buffer.from(imageBase64, 'base64');
      await fsp.writeFile(path.join(paths.imagesDir, imageFileName), imageBuffer);

      const productBoxes = boxes.filter(box =>
        box.productId === productId || (!box.productId && boxes.length === 1)
      );

      let annotationCount = 0;
      if (productBoxes.length > 0) {
        const labelFileName = imageFileName.replace(/\.jpg$/, '.txt');
        const classId = await getTypedClassId(trainingType, productId);

        const yoloLines = productBoxes.map(box => {
          // Поддержка двух форматов: {box: {x1,y1,x2,y2}} и {x,y,width,height}
          const b = box.box || box;
          let xCenter, yCenter, width, height;
          if (b.x1 !== undefined && b.x2 !== undefined) {
            xCenter = (b.x1 + b.x2) / 2;
            yCenter = (b.y1 + b.y2) / 2;
            width = b.x2 - b.x1;
            height = b.y2 - b.y1;
          } else {
            // Формат {x, y, width, height} (относительные координаты)
            xCenter = b.x + b.width / 2;
            yCenter = b.y + b.height / 2;
            width = b.width;
            height = b.height;
          }
          if (isNaN(xCenter) || isNaN(yCenter) || isNaN(width) || isNaN(height)) {
            return null; // Пропускаем невалидные боксы
          }
          return `${classId} ${xCenter.toFixed(6)} ${yCenter.toFixed(6)} ${width.toFixed(6)} ${height.toFixed(6)}`;
        }).filter(Boolean).join('\n');

        await fsp.writeFile(path.join(paths.labelsDir, labelFileName), yoloLines);
        annotationCount = productBoxes.length;
        savedCount.withLabels++;
      }

      const sample = {
        id,
        productId,
        barcode: detected.barcode || productId,
        productName: detected.productName || '',
        trainingType,
        shopAddress: shopAddress || '',
        confidence: detected.confidence || detected.maxConfidence || 0,
        count: detected.count || 1,
        imageFileName,
        boundingBoxes: productBoxes.map(b => b.box),
        annotationCount,
        createdAt: timestamp,
      };

      samples.push(sample);
      savedCount.total++;
    }

    await saveTypedSamples(trainingType, samples);
    console.log(`[Typed Training] ${trainingType}: сохранено ${savedCount.total}, с labels: ${savedCount.withLabels}, ротировано: ${savedCount.rotated}`);

    return { success: true, savedCount, trainingType };
  } catch (error) {
    console.error(`[Typed Training] Ошибка сохранения ${trainingType}:`, error);
    return { success: false, error: error.message };
  }
}

/**
 * Сохранить фото с пересчёта в PENDING (ожидание подтверждения админа)
 */
async function saveCountingTrainingSample({
  imageBase64,
  productId,
  productName,
  shopAddress,
  employeeAnswer,
  selectedRegion,
}) {
  try {
    if (!imageBase64 || !productId) {
      return { success: false, error: 'imageBase64 и productId обязательны' };
    }

    const paths = await initCountingPending();
    const samples = await loadPendingCountingSamples();

    const maxPendingPerProduct = 20;
    const existingForProduct = samples.filter(
      s => (s.productId === productId || s.barcode === productId)
    );

    if (existingForProduct.length >= maxPendingPerProduct) {
      existingForProduct.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
      const toDelete = existingForProduct[0];

      const imgPath = path.join(paths.imagesDir, toDelete.imageFileName);
      try {
        if (await fileExists(imgPath)) await fsp.unlink(imgPath);
      } catch (e) { /* ignore */ }

      const idx = samples.findIndex(s => s.id === toDelete.id);
      if (idx !== -1) {
        samples.splice(idx, 1);
        console.log(`[Counting Pending] Ротация: удалён старый pending для ${productId}`);
      }
    }

    const id = uuidv4();
    const timestamp = new Date().toISOString();
    const imageFileName = `pending_${productId}_${id}.jpg`;

    const imageBuffer = Buffer.from(imageBase64, 'base64');
    await fsp.writeFile(path.join(paths.imagesDir, imageFileName), imageBuffer);

    const sample = {
      id,
      productId,
      barcode: productId,
      productName: productName || '',
      type: 'counting-pending',
      status: 'pending',
      shopAddress: shopAddress || '',
      employeeAnswer: employeeAnswer || null,
      selectedRegion: selectedRegion || null,
      imageFileName,
      imageUrl: `/api/cigarette-vision/counting-pending-images/${imageFileName}`,
      createdAt: timestamp,
    };

    samples.push(sample);
    await savePendingCountingSamples(samples);

    console.log(`[Counting Pending] Фото добавлено в очередь для ${productName || productId}, pending: ${existingForProduct.length + 1}`);

    return { success: true, sample, status: 'pending' };
  } catch (error) {
    console.error('[Counting Pending] Ошибка сохранения:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Подтвердить pending фото (переместить в counting-training)
 */
async function approveCountingPendingSample(sampleId) {
  try {
    await initCountingPending();
    const pendingPaths = getCountingPendingPaths();
    const pendingSamples = await loadPendingCountingSamples();

    const idx = pendingSamples.findIndex(s => s.id === sampleId);
    if (idx === -1) {
      return { success: false, error: 'Pending образец не найден' };
    }

    const pendingSample = pendingSamples[idx];
    const trainingType = TRAINING_TYPES.COUNTING;
    const trainingPaths = await initTypedTraining(trainingType);
    const trainingSamples = await loadTypedSamples(trainingType);

    const settings = await loadSettings();
    const maxPerProduct = settings.maxCountingPhotosPerProduct || 50;
    const existingForProduct = trainingSamples.filter(
      s => (s.productId === pendingSample.productId || s.barcode === pendingSample.productId)
    );

    if (existingForProduct.length >= maxPerProduct) {
      existingForProduct.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
      const toDelete = existingForProduct[0];

      const imgPath = path.join(trainingPaths.imagesDir, toDelete.imageFileName);
      const lblPath = path.join(trainingPaths.labelsDir, toDelete.imageFileName.replace(/\.jpg$/, '.txt'));
      try {
        if (await fileExists(imgPath)) await fsp.unlink(imgPath);
        if (await fileExists(lblPath)) await fsp.unlink(lblPath);
      } catch (e) { /* ignore */ }

      const delIdx = trainingSamples.findIndex(s => s.id === toDelete.id);
      if (delIdx !== -1) trainingSamples.splice(delIdx, 1);
    }

    const newImageFileName = `counting_${pendingSample.productId}_${pendingSample.id}.jpg`;
    const srcPath = path.join(pendingPaths.imagesDir, pendingSample.imageFileName);
    const dstPath = path.join(trainingPaths.imagesDir, newImageFileName);

    if (await fileExists(srcPath)) {
      await fsp.copyFile(srcPath, dstPath);
      await fsp.unlink(srcPath);
    }

    const trainingSample = {
      id: pendingSample.id,
      productId: pendingSample.productId,
      barcode: pendingSample.productId,
      productName: pendingSample.productName || '',
      trainingType,
      type: 'counting',
      shopAddress: pendingSample.shopAddress || '',
      employeeAnswer: pendingSample.employeeAnswer || null,
      imageFileName: newImageFileName,
      imageUrl: `/api/cigarette-vision/counting-images/${newImageFileName}`,
      boundingBoxes: [],
      annotationCount: 0,
      labeled: false, // Нет bounding box аннотаций — исключить из YOLO обучения
      createdAt: pendingSample.createdAt,
      approvedAt: new Date().toISOString(),
    };

    trainingSamples.push(trainingSample);
    await saveTypedSamples(trainingType, trainingSamples);

    pendingSamples.splice(idx, 1);
    await savePendingCountingSamples(pendingSamples);

    console.log(`[Counting Pending] Подтверждено фото для ${pendingSample.productName || pendingSample.productId}`);

    return { success: true, sample: trainingSample };
  } catch (error) {
    console.error('[Counting Pending] Ошибка подтверждения:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Отклонить pending фото (удалить)
 */
async function rejectCountingPendingSample(sampleId) {
  try {
    const paths = await initCountingPending();
    const samples = await loadPendingCountingSamples();

    const idx = samples.findIndex(s => s.id === sampleId);
    if (idx === -1) {
      return { success: false, error: 'Pending образец не найден' };
    }

    const sample = samples[idx];

    const imgPath = path.join(paths.imagesDir, sample.imageFileName);
    try {
      if (await fileExists(imgPath)) await fsp.unlink(imgPath);
    } catch (e) { /* ignore */ }

    samples.splice(idx, 1);
    await savePendingCountingSamples(samples);

    console.log(`[Counting Pending] Отклонено фото для ${sample.productName || sample.productId}`);

    return { success: true };
  } catch (error) {
    console.error('[Counting Pending] Ошибка отклонения:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Получить все pending фото пересчёта
 */
async function getAllPendingCountingSamples() {
  return await loadPendingCountingSamples();
}

/**
 * Получить pending фото для конкретного товара
 */
async function getPendingCountingSamplesForProduct(productId) {
  const samples = await loadPendingCountingSamples();
  return samples.filter(
    s => (s.productId === productId || s.barcode === productId)
  );
}

/**
 * Получить количество pending фото для товара
 */
async function getPendingCountingPhotosCount(productId) {
  const samples = await loadPendingCountingSamples();
  return samples.filter(
    s => (s.productId === productId || s.barcode === productId)
  ).length;
}

/**
 * Получить количество фото пересчёта для товара
 */
async function getCountingPhotosCount(productId) {
  try {
    const samples = await loadTypedSamples(TRAINING_TYPES.COUNTING);
    return samples.filter(
      s => (s.productId === productId || s.barcode === productId)
    ).length;
  } catch (error) {
    console.error('[Counting Training] Ошибка подсчёта фото:', error);
    return 0;
  }
}

/**
 * Получить все фото пересчёта для товара
 */
async function getCountingSamplesForProduct(productId) {
  try {
    const samples = await loadTypedSamples(TRAINING_TYPES.COUNTING);
    return samples.filter(
      s => (s.productId === productId || s.barcode === productId)
    );
  } catch (error) {
    console.error('[Counting Training] Ошибка получения образцов:', error);
    return [];
  }
}

/**
 * Удалить фото пересчёта
 */
async function deleteCountingSample(sampleId) {
  try {
    const trainingType = TRAINING_TYPES.COUNTING;
    const paths = getTrainingPaths(trainingType);
    const samples = await loadTypedSamples(trainingType);

    const idx = samples.findIndex(s => s.id === sampleId);
    if (idx === -1) {
      return { success: false, error: 'Образец не найден' };
    }

    const sample = samples[idx];

    const imgPath = path.join(paths.imagesDir, sample.imageFileName);
    const lblPath = path.join(paths.labelsDir, sample.imageFileName.replace(/\.jpg$/, '.txt'));
    try {
      if (await fileExists(imgPath)) await fsp.unlink(imgPath);
      if (await fileExists(lblPath)) await fsp.unlink(lblPath);
    } catch (e) { /* ignore */ }

    samples.splice(idx, 1);
    await saveTypedSamples(trainingType, samples);

    console.log(`[Counting Training] Удалён образец ${sampleId}`);
    return { success: true };
  } catch (error) {
    console.error('[Counting Training] Ошибка удаления:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Получить статистику раздельного датасета
 */
async function getTypedTrainingStats(trainingType) {
  try {
    const samples = await loadTypedSamples(trainingType);
    const paths = getTrainingPaths(trainingType);

    const byProduct = {};
    let withAnnotations = 0;

    samples.forEach(s => {
      const key = s.productId || s.barcode;
      if (!byProduct[key]) {
        byProduct[key] = { count: 0, withLabels: 0, productName: s.productName };
      }
      byProduct[key].count++;
      if (s.annotationCount > 0) {
        byProduct[key].withLabels++;
        withAnnotations++;
      }
    });

    const modelPath = UNIFIED_MODEL; // Единая модель для обоих типов
    const modelExists = await fileExists(modelPath);

    return {
      trainingType,
      totalSamples: samples.length,
      samplesWithAnnotations: withAnnotations,
      uniqueProducts: Object.keys(byProduct).length,
      byProduct,
      modelExists,
      modelPath,
      paths: {
        images: paths.imagesDir,
        labels: paths.labelsDir,
      },
    };
  } catch (error) {
    console.error(`[Typed Training] Ошибка получения статистики ${trainingType}:`, error);
    return { trainingType, totalSamples: 0, error: error.message };
  }
}

/**
 * Очистка старых образцов в раздельном датасете
 */
async function cleanupTypedSamples(trainingType, maxAgeDays = 180) {
  try {
    const paths = getTrainingPaths(trainingType);
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - maxAgeDays);

    const samples = await loadTypedSamples(trainingType);
    let deletedCount = 0;

    const toKeep = [];
    for (const s of samples) {
      const createdAt = new Date(s.createdAt);
      if (createdAt < cutoffDate) {
        const imgPath = path.join(paths.imagesDir, s.imageFileName);
        const lblPath = path.join(paths.labelsDir, s.imageFileName.replace(/\.jpg$/, '.txt'));
        try {
          if (await fileExists(imgPath)) await fsp.unlink(imgPath);
          if (await fileExists(lblPath)) await fsp.unlink(lblPath);
        } catch (e) { /* ignore */ }
        deletedCount++;
      } else {
        toKeep.push(s);
      }
    }

    if (deletedCount > 0) {
      await saveTypedSamples(trainingType, toKeep);
      console.log(`[Typed Training] ${trainingType}: очищено ${deletedCount} старых образцов`);
    }

    return { success: true, deletedCount, remaining: toKeep.length };
  } catch (error) {
    console.error(`[Typed Training] Ошибка очистки ${trainingType}:`, error);
    return { success: false, error: error.message };
  }
}

// ============ СИСТЕМА ОБРАТНОЙ СВЯЗИ И АВТООТКЛЮЧЕНИЯ ИИ ============

const AI_ERRORS_FILE = path.join(DATA_DIR, 'ai-errors-stats.json');
const PROBLEM_SAMPLES_DIR = path.join(DATA_DIR, 'problem-samples');

const AI_ERROR_THRESHOLD = 20;
const ERROR_RESET_DAYS = 7;

/**
 * Загрузить статистику ошибок ИИ
 */
async function loadAiErrorsStats() {
  try {
    if (await fileExists(AI_ERRORS_FILE)) {
      return JSON.parse(await fsp.readFile(AI_ERRORS_FILE, 'utf8'));
    }
  } catch (e) {
    console.error('[AI Errors] Ошибка загрузки статистики:', e.message);
  }
  return { products: {} };
}

/**
 * Сохранить статистику ошибок ИИ
 */
async function saveAiErrorsStats(stats) {
  try {
    await writeJsonFile(AI_ERRORS_FILE, stats);
  } catch (e) {
    console.error('[AI Errors] Ошибка сохранения статистики:', e.message);
  }
}

/**
 * Сообщить об ошибке ИИ от сотрудника (информационная метка)
 */
async function reportAiError({
  productId,
  productName,
  expectedCount,
  aiCount,
  imageBase64,
  shopAddress,
  employeeName,
}) {
  try {
    const stats = await loadAiErrorsStats();
    const now = new Date();

    if (!stats.products[productId]) {
      stats.products[productId] = {
        productName: productName || '',
        consecutiveErrors: 0,
        totalErrors: 0,
        pendingReports: 0,
        lastErrorAt: null,
        isDisabled: false,
        disabledAt: null,
        errorHistory: [],
      };
    }

    const product = stats.products[productId];
    product.productName = productName || product.productName;
    product.pendingReports = (product.pendingReports || 0) + 1;
    product.lastReportAt = now.toISOString();

    product.errorHistory.unshift({
      timestamp: now.toISOString(),
      expectedCount,
      aiCount,
      shopAddress: shopAddress || '',
      employeeName: employeeName || '',
      status: 'pending',
    });
    if (product.errorHistory.length > 20) {
      product.errorHistory = product.errorHistory.slice(0, 20);
    }

    await saveAiErrorsStats(stats);

    let savedFileName = null;
    if (imageBase64) {
      const saveResult = await saveProblemSample({
        productId,
        productName,
        expectedCount,
        aiCount,
        imageBase64,
        shopAddress,
        status: 'pending',
      });
      savedFileName = saveResult.fileName;
    }

    console.log(`[AI Errors] Сотрудник сообщил об ошибке ИИ: ${productId} (${productName}) - ожидает решения админа`);

    return {
      success: true,
      productId,
      pendingReports: product.pendingReports,
      consecutiveErrors: product.consecutiveErrors,
      totalErrors: product.totalErrors,
      isDisabled: product.isDisabled,
      threshold: AI_ERROR_THRESHOLD,
      savedFileName,
      message: 'Жалоба сохранена, ожидает решения администратора',
    };
  } catch (error) {
    console.error('[AI Errors] Ошибка сохранения:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Решение админа по ошибке ИИ
 */
async function reportAdminAiDecision({
  productId,
  productName,
  decision,
  adminName,
  imageBase64,
  expectedCount,
  aiCount,
  shopAddress,
}) {
  try {
    const stats = await loadAiErrorsStats();
    const now = new Date();

    if (!stats.products[productId]) {
      stats.products[productId] = {
        productName: productName || '',
        consecutiveErrors: 0,
        totalErrors: 0,
        pendingReports: 0,
        lastErrorAt: null,
        isDisabled: false,
        disabledAt: null,
        errorHistory: [],
        adminDecisions: [],
      };
    }

    const product = stats.products[productId];
    product.productName = productName || product.productName;

    if (product.pendingReports > 0) {
      product.pendingReports--;
    }

    if (!product.adminDecisions) {
      product.adminDecisions = [];
    }
    product.adminDecisions.unshift({
      timestamp: now.toISOString(),
      decision,
      adminName,
      expectedCount,
      aiCount,
      shopAddress,
    });
    if (product.adminDecisions.length > 50) {
      product.adminDecisions = product.adminDecisions.slice(0, 50);
    }

    if (decision === 'approved_for_training') {
      product.consecutiveErrors++;
      product.totalErrors++;
      product.lastErrorAt = now.toISOString();

      if (product.consecutiveErrors >= AI_ERROR_THRESHOLD && !product.isDisabled) {
        product.isDisabled = true;
        product.disabledAt = now.toISOString();
        console.log(`[AI Errors] ⚠️ ИИ ОТКЛЮЧЕН для товара ${productId} (${productName}) после ${product.consecutiveErrors} подтверждённых ошибок`);
      }

      if (imageBase64) {
        try {
          await saveTypedPositiveSample(TRAINING_TYPES.COUNTING, {
            imageBase64,
            detectedProducts: [{
              productId,
              barcode: productId,
              productName: productName || '',
              count: expectedCount || 0,
            }],
            shopAddress: shopAddress || '',
            boxes: [],
          });
          console.log(`[AI Errors] Фото добавлено в counting-training: ${productId}`);
        } catch (e) {
          console.warn(`[AI Errors] Не удалось сохранить в training:`, e.message);
        }
      }

      console.log(`[AI Errors] Админ ${adminName} подтвердил ошибку ИИ: ${productId} (consecutiveErrors: ${product.consecutiveErrors})`);
    } else if (decision === 'rejected_bad_photo') {
      console.log(`[AI Errors] Админ ${adminName} отклонил жалобу на ИИ: ${productId} (плохое фото)`);
    }

    await saveAiErrorsStats(stats);

    return {
      success: true,
      productId,
      decision,
      adminName,
      consecutiveErrors: product.consecutiveErrors,
      totalErrors: product.totalErrors,
      isDisabled: product.isDisabled,
      threshold: AI_ERROR_THRESHOLD,
    };
  } catch (error) {
    console.error('[AI Errors] Ошибка сохранения решения админа:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Сохранить проблемное фото для анализа/переобучения
 */
async function saveProblemSample({
  productId,
  productName,
  expectedCount,
  aiCount,
  imageBase64,
  shopAddress,
  status = 'pending',
}) {
  try {
    const safeProductId = path.basename(String(productId));
    const productDir = path.join(PROBLEM_SAMPLES_DIR, safeProductId);
    if (!(await fileExists(productDir))) {
      await fsp.mkdir(productDir, { recursive: true });
    }

    const existingFiles = (await fsp.readdir(productDir)).filter(f => f.endsWith('.jpg'));
    if (existingFiles.length >= 30) {
      existingFiles.sort();
      const oldest = existingFiles[0];
      await fsp.unlink(path.join(productDir, oldest));
      const metaFile = oldest.replace('.jpg', '.json');
      if (await fileExists(path.join(productDir, metaFile))) {
        await fsp.unlink(path.join(productDir, metaFile));
      }
    }

    const id = uuidv4().slice(0, 8);
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const fileName = `problem_${timestamp}_${id}.jpg`;
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    await fsp.writeFile(path.join(productDir, fileName), imageBuffer);

    const metaFileName = fileName.replace('.jpg', '.json');
    await writeJsonFile(path.join(productDir, metaFileName), {
      productId,
      productName,
      expectedCount,
      aiCount,
      shopAddress,
      status,
      createdAt: new Date().toISOString(),
    });

    console.log(`[AI Errors] Проблемное фото сохранено: ${productId}/${fileName} (status: ${status})`);
    return { success: true, fileName };
  } catch (error) {
    console.error('[AI Errors] Ошибка сохранения проблемного фото:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Проверить отключен ли ИИ для товара
 */
async function isProductAiDisabled(productId) {
  const stats = await loadAiErrorsStats();
  const product = stats.products[productId];

  if (!product) return false;

  if (product.isDisabled && product.lastErrorAt) {
    const daysSinceLastError = (Date.now() - new Date(product.lastErrorAt).getTime()) / (1000 * 60 * 60 * 24);
    if (daysSinceLastError >= ERROR_RESET_DAYS) {
      product.isDisabled = false;
      product.consecutiveErrors = 0;
      product.disabledAt = null;
      await saveAiErrorsStats(stats);
      console.log(`[AI Errors] ИИ автоматически включен для ${productId} (прошло ${daysSinceLastError.toFixed(1)} дней без ошибок)`);
      return false;
    }
  }

  return product.isDisabled;
}

/**
 * Получить полный статус ИИ для товара
 */
async function getProductAiStatus(productId) {
  const stats = await loadAiErrorsStats();
  const product = stats.products[productId];

  if (!product) {
    return {
      productId,
      exists: false,
      isDisabled: false,
      consecutiveErrors: 0,
      totalErrors: 0,
      threshold: AI_ERROR_THRESHOLD,
      resetDays: ERROR_RESET_DAYS,
    };
  }

  const isDisabled = await isProductAiDisabled(productId);

  return {
    productId,
    exists: true,
    productName: product.productName,
    isDisabled,
    consecutiveErrors: product.consecutiveErrors,
    totalErrors: product.totalErrors,
    lastErrorAt: product.lastErrorAt,
    disabledAt: product.disabledAt,
    errorHistory: product.errorHistory || [],
    threshold: AI_ERROR_THRESHOLD,
    resetDays: ERROR_RESET_DAYS,
  };
}

/**
 * Сбросить счётчик ошибок и включить ИИ (ручной сброс админом)
 */
async function resetProductAiErrors(productId) {
  const stats = await loadAiErrorsStats();

  if (!stats.products[productId]) {
    return { success: false, error: 'Товар не найден в статистике ошибок' };
  }

  stats.products[productId].consecutiveErrors = 0;
  stats.products[productId].isDisabled = false;
  stats.products[productId].disabledAt = null;

  await saveAiErrorsStats(stats);
  console.log(`[AI Errors] Счётчик ошибок сброшен для ${productId}, ИИ включен`);

  return {
    success: true,
    productId,
    message: 'ИИ включен, счётчик ошибок сброшен',
  };
}

/**
 * Сообщить об успешном распознавании (сбрасывает счётчик consecutiveErrors)
 */
async function reportAiSuccess(productId) {
  const stats = await loadAiErrorsStats();

  if (stats.products[productId]) {
    stats.products[productId].consecutiveErrors = 0;
    await saveAiErrorsStats(stats);
  }

  return { success: true };
}

/**
 * Получить список всех проблемных товаров
 */
async function getProblematicProducts() {
  const stats = await loadAiErrorsStats();
  const result = [];

  for (const [productId, product] of Object.entries(stats.products)) {
    if (product.totalErrors > 0) {
      result.push({
        productId,
        productName: product.productName,
        isDisabled: product.isDisabled,
        consecutiveErrors: product.consecutiveErrors,
        totalErrors: product.totalErrors,
        lastErrorAt: product.lastErrorAt,
      });
    }
  }

  result.sort((a, b) => b.totalErrors - a.totalErrors);

  return result;
}

/**
 * Получить проблемные фото для товара (для ручной аннотации)
 */
async function getProblemSamples(productId) {
  try {
    const safeProductId = path.basename(String(productId));
    const productDir = path.join(PROBLEM_SAMPLES_DIR, safeProductId);
    if (!(await fileExists(productDir))) {
      return { success: true, samples: [] };
    }

    const files = (await fsp.readdir(productDir)).filter(f => f.endsWith('.jpg'));
    const samples = [];

    for (const fileName of files) {
      const metaFile = fileName.replace('.jpg', '.json');
      const metaPath = path.join(productDir, metaFile);
      let meta = {};
      if (await fileExists(metaPath)) {
        try {
          meta = JSON.parse(await fsp.readFile(metaPath, 'utf8'));
        } catch (e) { /* ignore */ }
      }

      samples.push({
        fileName,
        imageUrl: `/api/cigarette-vision/problem-samples/${productId}/${fileName}`,
        ...meta,
      });
    }

    return { success: true, samples };
  } catch (error) {
    return { success: false, error: error.message, samples: [] };
  }
}

// ============ СТАТИСТИКА ТОЧНОСТИ РАСПОЗНАВАНИЯ ИИ ============

const RECOGNITION_STATS_DIR = '/var/www/ai-recognition-stats';
const RECOGNITION_STATS_FILE = path.join(RECOGNITION_STATS_DIR, 'stats.json');

let recognitionStatsCache = null;
let recognitionStatsCacheTime = 0;
const RECOGNITION_STATS_CACHE_TTL = 5 * 60 * 1000; // 5 минут

/**
 * Загрузить статистику распознаваний
 */
async function loadRecognitionStats() {
  try {
    if (recognitionStatsCache !== null && Date.now() - recognitionStatsCacheTime < RECOGNITION_STATS_CACHE_TTL) {
      return recognitionStatsCache;
    }

    if (!(await fileExists(RECOGNITION_STATS_FILE))) {
      return {};
    }

    const data = await fsp.readFile(RECOGNITION_STATS_FILE, 'utf8');
    recognitionStatsCache = JSON.parse(data);
    recognitionStatsCacheTime = Date.now();
    return recognitionStatsCache;
  } catch (error) {
    console.error('[Cigarette Vision] Ошибка загрузки статистики распознаваний:', error);
    return {};
  }
}

/**
 * Сохранить статистику распознаваний
 */
async function saveRecognitionStats(stats) {
  try {
    if (!(await fileExists(RECOGNITION_STATS_DIR))) {
      await fsp.mkdir(RECOGNITION_STATS_DIR, { recursive: true });
    }

    await writeJsonFile(RECOGNITION_STATS_FILE, stats);
    recognitionStatsCache = stats;
    recognitionStatsCacheTime = Date.now();
    return true;
  } catch (error) {
    console.error('[Cigarette Vision] Ошибка сохранения статистики распознаваний:', error);
    return false;
  }
}

/**
 * Записать попытку распознавания
 */
async function recordRecognitionAttempt(productId, type, success, metadata = {}) {
  try {
    const stats = await loadRecognitionStats();

    if (!stats[productId]) {
      stats[productId] = {
        display: { attempts: 0, successes: 0 },
        counting: { attempts: 0, successes: 0 },
      };
    }

    if (!stats[productId][type]) {
      stats[productId][type] = { attempts: 0, successes: 0 };
    }

    stats[productId][type].attempts++;
    if (success) {
      stats[productId][type].successes++;
    }

    stats[productId][type].lastAttempt = new Date().toISOString();
    if (metadata.shopAddress) {
      stats[productId][type].lastShop = metadata.shopAddress;
    }

    await saveRecognitionStats(stats);

    console.log(`[Cigarette Vision] Записана попытка распознавания: ${productId} (${type}) - ${success ? 'успех' : 'провал'}`);
    return true;
  } catch (error) {
    console.error('[Cigarette Vision] Ошибка записи попытки распознавания:', error);
    return false;
  }
}

/**
 * Получить статистику распознаваний для товара
 */
async function getProductRecognitionStats(productId) {
  const stats = await loadRecognitionStats();
  const productStats = stats[productId] || {
    display: { attempts: 0, successes: 0 },
    counting: { attempts: 0, successes: 0 },
  };

  const calcAccuracy = (data) => {
    if (!data || data.attempts === 0) {
      return null;
    }
    return Math.round((data.successes / data.attempts) * 100);
  };

  return {
    display: {
      accuracy: calcAccuracy(productStats.display),
      attempts: productStats.display?.attempts || 0,
      successes: productStats.display?.successes || 0,
      lastAttempt: productStats.display?.lastAttempt || null,
    },
    counting: {
      accuracy: calcAccuracy(productStats.counting),
      attempts: productStats.counting?.attempts || 0,
      successes: productStats.counting?.successes || 0,
      lastAttempt: productStats.counting?.lastAttempt || null,
    },
  };
}

/**
 * Получить статистику распознаваний для всех товаров
 */
async function getAllRecognitionStats() {
  const stats = await loadRecognitionStats();
  const result = {};

  for (const productId of Object.keys(stats)) {
    result[productId] = await getProductRecognitionStats(productId);
  }

  return result;
}

/**
 * Сбросить статистику распознаваний для товара
 */
async function resetRecognitionStats(productId, type = null) {
  try {
    const stats = await loadRecognitionStats();

    if (!stats[productId]) {
      return true;
    }

    if (type) {
      stats[productId][type] = { attempts: 0, successes: 0 };
    } else {
      stats[productId] = {
        display: { attempts: 0, successes: 0 },
        counting: { attempts: 0, successes: 0 },
      };
    }

    await saveRecognitionStats(stats);
    console.log(`[Cigarette Vision] Сброшена статистика для ${productId}${type ? ` (${type})` : ''}`);
    return true;
  } catch (error) {
    console.error('[Cigarette Vision] Ошибка сброса статистики:', error);
    return false;
  }
}

module.exports = {
  init,
  getProductsWithTrainingInfo,
  getProductGroups,
  getTrainingStats,
  saveTrainingSample,
  getSamplesForProduct,
  deleteSample,
  getImagePath,
  detectAndCount,
  checkDisplay,
  getClassMapping,
  getClassIdForProduct,
  getSettings,
  updateSettings,
  loadSamples,
  loadAllShops,
  REQUIRED_PHOTOS_COUNT,
  exportTrainingData,
  trainModel,
  getModelStatus,
  savePositiveSample,
  cleanupOldPositiveSamples,
  getPositiveSamplesStats,
  TRAINING_TYPES,
  saveTypedPositiveSample,
  getTypedTrainingStats,
  cleanupTypedSamples,
  loadTypedSamples,
  getTrainingPaths,
  UNIFIED_MODEL,
  saveCountingTrainingSample,
  getCountingPhotosCount,
  getCountingSamplesForProduct,
  deleteCountingSample,
  getCountingPendingPaths,
  loadPendingCountingSamples,
  getAllPendingCountingSamples,
  getPendingCountingSamplesForProduct,
  getPendingCountingPhotosCount,
  approveCountingPendingSample,
  rejectCountingPendingSample,
  reportAiError,
  reportAdminAiDecision,
  reportAiSuccess,
  isProductAiDisabled,
  getProductAiStatus,
  resetProductAiErrors,
  getProblematicProducts,
  getProblemSamples,
  PROBLEM_SAMPLES_DIR,
  AI_ERROR_THRESHOLD,
  recordRecognitionAttempt,
  getProductRecognitionStats,
  getAllRecognitionStats,
  resetRecognitionStats,
};
