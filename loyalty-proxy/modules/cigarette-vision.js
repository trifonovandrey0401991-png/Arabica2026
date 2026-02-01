/**
 * Модуль машинного зрения для подсчёта сигарет
 *
 * Функции:
 * - Хранение образцов для обучения
 * - Подсчёт загруженных фото по товарам
 * - Подготовка данных для ML модели
 */

const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

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
function initCountingPending() {
  const paths = getCountingPendingPaths();
  if (!fs.existsSync(paths.baseDir)) fs.mkdirSync(paths.baseDir, { recursive: true });
  if (!fs.existsSync(paths.imagesDir)) fs.mkdirSync(paths.imagesDir, { recursive: true });
  if (!fs.existsSync(paths.samplesFile)) fs.writeFileSync(paths.samplesFile, '[]');
  return paths;
}

// Загрузить pending samples
function loadPendingCountingSamples() {
  const paths = getCountingPendingPaths();
  if (!fs.existsSync(paths.samplesFile)) return [];
  try {
    return JSON.parse(fs.readFileSync(paths.samplesFile, 'utf8'));
  } catch (e) {
    return [];
  }
}

// Сохранить pending samples
function savePendingCountingSamples(samples) {
  const paths = initCountingPending();
  fs.writeFileSync(paths.samplesFile, JSON.stringify(samples, null, 2));
}

// Пути к моделям
const DISPLAY_MODEL = path.join(__dirname, '..', 'ml', 'models', 'display_detector.pt');
const COUNTING_MODEL = path.join(__dirname, '..', 'ml', 'models', 'counting_detector.pt');

// Дефолтные настройки (можно изменить через API)
const DEFAULT_SETTINGS = {
  requiredRecountPhotos: 10,  // Крупный план пачки (10 шаблонов) - ОБЩИЙ для всех магазинов
  requiredDisplayPhotosPerShop: 3,  // Фото выкладки НА КАЖДЫЙ МАГАЗИН
  requiredCountingPhotos: 10,  // Фото с пересчёта - ОБЩИЙ для всех магазинов
  maxCountingPhotosPerProduct: 50,  // Лимит фото пересчёта на товар
  // Источник каталога товаров:
  // "recount-questions" - текущий каталог (вопросы пересчёта)
  // "master-catalog" - единый мастер-каталог (новый)
  catalogSource: 'recount-questions',
  // Настройки positive samples (успешные распознавания)
  positiveSamplesEnabled: true,        // Включить сохранение успешных распознаваний
  positiveSampleRate: 0.1,             // Процент сохраняемых (10%)
  maxPositiveSamplesPerProduct: 50,    // Лимит на товар
  positiveSamplesMaxAgeDays: 180,      // Автоудаление через 6 месяцев
};

// Кэш настроек
let settingsCache = null;

/**
 * Загрузить настройки
 */
function loadSettings() {
  if (settingsCache) return settingsCache;

  try {
    if (fs.existsSync(SETTINGS_FILE)) {
      settingsCache = JSON.parse(fs.readFileSync(SETTINGS_FILE, 'utf8'));
    } else {
      settingsCache = { ...DEFAULT_SETTINGS };
      saveSettings(settingsCache);
    }
  } catch (e) {
    console.error('Ошибка загрузки настроек:', e);
    settingsCache = { ...DEFAULT_SETTINGS };
  }
  return settingsCache;
}

/**
 * Сохранить настройки
 */
function saveSettings(settings) {
  try {
    fs.writeFileSync(SETTINGS_FILE, JSON.stringify(settings, null, 2));
    settingsCache = settings;
    return true;
  } catch (e) {
    console.error('Ошибка сохранения настроек:', e);
    return false;
  }
}

/**
 * Получить настройки
 */
function getSettings() {
  return loadSettings();
}

/**
 * Обновить настройки
 */
function updateSettings(newSettings) {
  const current = loadSettings();
  const updated = { ...current, ...newSettings };
  return saveSettings(updated) ? updated : null;
}

// Для обратной совместимости
const REQUIRED_PHOTOS_COUNT = 20;

/**
 * Инициализация модуля - создание необходимых директорий и файлов
 */
function init() {
  // Создаём директории если не существуют
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
  if (!fs.existsSync(IMAGES_DIR)) {
    fs.mkdirSync(IMAGES_DIR, { recursive: true });
  }

  // Создаём файлы если не существуют
  if (!fs.existsSync(SAMPLES_FILE)) {
    fs.writeFileSync(SAMPLES_FILE, JSON.stringify({ samples: [] }, null, 2));
  }
  if (!fs.existsSync(STATS_FILE)) {
    fs.writeFileSync(STATS_FILE, JSON.stringify({ lastUpdated: null }, null, 2));
  }
}

/**
 * Загрузить все магазины из основной системы
 */
function loadAllShops() {
  try {
    if (!fs.existsSync(SHOPS_DIR)) {
      console.warn('[Cigarette Vision] Директория магазинов не найдена:', SHOPS_DIR);
      return [];
    }

    const shops = [];
    const files = fs.readdirSync(SHOPS_DIR).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(SHOPS_DIR, file), 'utf8');
        const shop = JSON.parse(content);
        if (shop.address) {  // Только магазины с адресом
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
function loadSamples() {
  try {
    init();
    const data = fs.readFileSync(SAMPLES_FILE, 'utf8');
    return JSON.parse(data).samples || [];
  } catch (error) {
    console.error('Ошибка загрузки образцов:', error);
    return [];
  }
}

/**
 * Сохранить образцы
 */
function saveSamples(samples) {
  try {
    init();
    fs.writeFileSync(SAMPLES_FILE, JSON.stringify({ samples }, null, 2));
    return true;
  } catch (error) {
    console.error('Ошибка сохранения образцов:', error);
    return false;
  }
}

/**
 * Получить список товаров с информацией об обучении
 * @param {Array} recountQuestions - Вопросы пересчёта (из основной базы)
 * @param {string} productGroup - Фильтр по группе товаров
 */
function getProductsWithTrainingInfo(recountQuestions, productGroup = null) {
  const samples = loadSamples();
  const settings = loadSettings();
  const shops = loadAllShops();  // Загружаем реальные магазины

  const requiredRecount = settings.requiredRecountPhotos || 10;
  const requiredDisplayPerShop = settings.requiredDisplayPhotosPerShop || 3;  // Per-shop

  // Подсчитываем количество фото для каждого товара (раздельно по типам)
  const recountPhotosByProduct = {};
  const completedTemplatesByProduct = {};  // Выполненные шаблоны (1-10)

  // НОВОЕ: Подсчёт фото выкладки по (productId, shopAddress)
  const displayPhotosByProductAndShop = {};

  samples.forEach(sample => {
    // Индексируем по productId И по barcode (для совместимости разных каталогов)
    const productId = sample.productId;
    const barcode = sample.barcode;

    if (sample.type === 'display') {
      // Per-shop подсчёт для выкладки
      if (sample.shopAddress) {
        // Сохраняем под productId
        if (productId) {
          const keyById = `${productId}|${sample.shopAddress}`;
          displayPhotosByProductAndShop[keyById] = (displayPhotosByProductAndShop[keyById] || 0) + 1;
        }
        // Также сохраняем под barcode для кросс-каталожного поиска
        if (barcode && barcode !== productId) {
          const keyByBarcode = `${barcode}|${sample.shopAddress}`;
          displayPhotosByProductAndShop[keyByBarcode] = (displayPhotosByProductAndShop[keyByBarcode] || 0) + 1;
        }
      }
    } else {
      // recount или без типа - общий для всех магазинов
      if (productId) {
        recountPhotosByProduct[productId] = (recountPhotosByProduct[productId] || 0) + 1;
      }
      if (barcode && barcode !== productId) {
        recountPhotosByProduct[barcode] = (recountPhotosByProduct[barcode] || 0) + 1;
      }

      // Собираем выполненные шаблоны (только для recount)
      if (sample.templateId) {
        const key = productId || barcode;
        if (!completedTemplatesByProduct[key]) {
          completedTemplatesByProduct[key] = new Set();
        }
        completedTemplatesByProduct[key].add(sample.templateId);
        // Также под barcode
        if (barcode && barcode !== key) {
          if (!completedTemplatesByProduct[barcode]) {
            completedTemplatesByProduct[barcode] = new Set();
          }
          completedTemplatesByProduct[barcode].add(sample.templateId);
        }
      }
    }
  });

  // Фильтруем и обогащаем данные
  let products = recountQuestions.map(q => {
    const productKey = q.id || q.barcode;
    const recountPhotos = recountPhotosByProduct[q.id] || recountPhotosByProduct[q.barcode] || 0;

    // Получаем выполненные шаблоны (Set -> Array)
    const completedTemplatesSet = completedTemplatesByProduct[q.id] || completedTemplatesByProduct[q.barcode] || new Set();
    const completedTemplates = Array.from(completedTemplatesSet).sort((a, b) => a - b);

    // Крупный план: завершено когда все 10 шаблонов выполнены
    const isRecountComplete = completedTemplates.length >= requiredRecount;

    // НОВОЕ: Per-shop статистика для выкладки
    const perShopDisplayStats = shops.map(shop => {
      // Ищем фото по id товара И по barcode (могут отличаться в разных каталогах)
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

    // Общее количество фото выкладки (для датасета - сумма по всем магазинам)
    const totalDisplayPhotos = perShopDisplayStats.reduce((sum, s) => sum + s.displayPhotosCount, 0);

    // Количество магазинов где ИИ готов (выкладка завершена)
    const shopsWithAiReady = perShopDisplayStats.filter(s => s.isDisplayComplete).length;

    // Для обратной совместимости: displayPhotosCount = общее количество
    // isDisplayComplete = true если хотя бы в одном магазине завершено (для общей статистики)
    const isDisplayComplete = shopsWithAiReady > 0;

    return {
      id: q.id,
      barcode: q.barcode || q.id,
      productGroup: q.productGroup || '',
      productName: q.productName || q.question || '',
      grade: q.grade || 1,
      isAiActive: q.isAiActive || false,  // Статус ИИ проверки
      // Общая статистика (обратная совместимость)
      trainingPhotosCount: recountPhotos + totalDisplayPhotos,
      requiredPhotosCount: requiredRecount + requiredDisplayPerShop,
      isTrainingComplete: isRecountComplete && isDisplayComplete,
      // Крупный план (общий для всех магазинов)
      recountPhotosCount: recountPhotos,
      requiredRecountPhotos: requiredRecount,
      isRecountComplete: isRecountComplete,
      completedTemplates: completedTemplates,
      // Выкладка - общая статистика (обратная совместимость)
      displayPhotosCount: totalDisplayPhotos,
      requiredDisplayPhotos: requiredDisplayPerShop,  // Теперь это per-shop
      isDisplayComplete: isDisplayComplete,
      // НОВОЕ: Per-shop статистика выкладки
      perShopDisplayStats: perShopDisplayStats,
      totalDisplayPhotos: totalDisplayPhotos,
      requiredDisplayPhotosPerShop: requiredDisplayPerShop,
      shopsWithAiReady: shopsWithAiReady,
      totalShops: shops.length,
    };
  });

  // Фильтруем по группе если указана
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
function getTrainingStats(recountQuestions) {
  const samples = loadSamples();
  const products = getProductsWithTrainingInfo(recountQuestions);

  // Подсчёт фото по типам
  const recountPhotos = samples.filter(s => s.type === 'recount' || !s.type).length;
  const displayPhotos = samples.filter(s => s.type === 'display').length;

  // Подсчёт товаров
  const productsWithPhotos = products.filter(p => p.trainingPhotosCount > 0).length;
  const productsFullyTrained = products.filter(p => p.isTrainingComplete).length;

  // Общий прогресс (сумма всех прогрессов / количество товаров)
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
    init();

    // Создаём директорию для labels если не существует
    if (!fs.existsSync(LABELS_DIR)) {
      fs.mkdirSync(LABELS_DIR, { recursive: true });
    }

    const id = uuidv4();
    const timestamp = new Date().toISOString();

    // Сохраняем изображение
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    const imageFileName = `${id}.jpg`;
    const imagePath = path.join(IMAGES_DIR, imageFileName);
    fs.writeFileSync(imagePath, imageBuffer);

    // Сохраняем YOLO аннотации если есть
    if (boundingBoxes && boundingBoxes.length > 0) {
      const labelFileName = `${id}.txt`;
      const labelPath = path.join(LABELS_DIR, labelFileName);

      // Формат YOLO: class_id x_center y_center width height
      // Используем productId как classId (нужно будет создать маппинг)
      const classId = getClassIdForProduct(productId);
      const yoloLines = boundingBoxes.map(box => {
        const xCenter = box.xCenter || box.x_center || 0;
        const yCenter = box.yCenter || box.y_center || 0;
        const width = box.width || 0;
        const height = box.height || 0;
        return `${classId} ${xCenter.toFixed(6)} ${yCenter.toFixed(6)} ${width.toFixed(6)} ${height.toFixed(6)}`;
      }).join('\n');

      fs.writeFileSync(labelPath, yoloLines);
      console.log(`[Cigarette Vision] YOLO аннотация сохранена: ${labelFileName} (${boundingBoxes.length} boxes)`);
    }

    // Создаём запись об образце
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

    // Добавляем в список
    const samples = loadSamples();
    samples.push(sample);
    saveSamples(samples);

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
function getClassIdForProduct(productId) {
  // Загружаем маппинг если не загружен
  if (classMapping === null) {
    if (fs.existsSync(CLASS_MAPPING_FILE)) {
      try {
        classMapping = JSON.parse(fs.readFileSync(CLASS_MAPPING_FILE, 'utf8'));
      } catch (e) {
        classMapping = {};
      }
    } else {
      classMapping = {};
    }
  }

  // Если товар уже есть — возвращаем его classId
  if (classMapping[productId] !== undefined) {
    return classMapping[productId];
  }

  // Создаём новый classId
  const maxId = Object.values(classMapping).reduce((max, id) => Math.max(max, id), -1);
  const newId = maxId + 1;
  classMapping[productId] = newId;

  // Сохраняем маппинг
  fs.writeFileSync(CLASS_MAPPING_FILE, JSON.stringify(classMapping, null, 2));
  console.log(`[Cigarette Vision] Новый classId для ${productId}: ${newId}`);

  return newId;
}

/**
 * Получить маппинг всех товаров -> classId
 */
function getClassMapping() {
  if (classMapping === null) {
    if (fs.existsSync(CLASS_MAPPING_FILE)) {
      try {
        classMapping = JSON.parse(fs.readFileSync(CLASS_MAPPING_FILE, 'utf8'));
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
function getSamplesForProduct(productId) {
  const samples = loadSamples();
  return samples.filter(s => s.productId === productId || s.barcode === productId);
}

/**
 * Удалить образец
 */
function deleteSample(sampleId) {
  try {
    const samples = loadSamples();
    const sampleIndex = samples.findIndex(s => s.id === sampleId);

    if (sampleIndex === -1) {
      return { success: false, error: 'Образец не найден' };
    }

    const sample = samples[sampleIndex];

    // Удаляем файл изображения
    if (sample.imageFileName) {
      const imagePath = path.join(IMAGES_DIR, sample.imageFileName);
      if (fs.existsSync(imagePath)) {
        fs.unlinkSync(imagePath);
      }
    }

    // Удаляем из списка
    samples.splice(sampleIndex, 1);
    saveSamples(samples);

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
 * @param {Object} params - Параметры
 * @param {string} params.imageBase64 - Изображение в base64
 * @param {Array} params.detectedProducts - Список распознанных товаров
 * @param {string} params.shopAddress - Адрес магазина
 * @param {Array} params.boxes - Bounding boxes из детекции (для YOLO обучения)
 * @returns {Object} - Результат сохранения
 */
async function savePositiveSample({
  imageBase64,
  detectedProducts,
  shopAddress,
  boxes = [],  // НОВОЕ: raw boxes из YOLO детекции
}) {
  try {
    const settings = loadSettings();

    // Проверяем включена ли функция
    if (!settings.positiveSamplesEnabled) {
      return { success: false, skipped: true, reason: 'Positive samples отключены' };
    }

    // Проверяем вероятность сохранения (10% по умолчанию)
    const sampleRate = settings.positiveSampleRate || 0.1;
    if (Math.random() > sampleRate) {
      return { success: false, skipped: true, reason: 'Не попал в выборку' };
    }

    if (!detectedProducts || detectedProducts.length === 0) {
      return { success: false, skipped: true, reason: 'Нет распознанных товаров' };
    }

    init();

    const maxPerProduct = settings.maxPositiveSamplesPerProduct || 50;
    const samples = loadSamples();
    const savedCount = { total: 0, rotated: 0 };

    // Сохраняем для каждого распознанного товара
    for (const detected of detectedProducts) {
      const productId = detected.productId || detected.barcode;

      // Считаем существующие positive samples для этого товара
      const existingPositive = samples.filter(
        s => (s.productId === productId || s.barcode === productId) && s.type === 'positive'
      );

      // Если лимит превышен - удаляем самые старые
      if (existingPositive.length >= maxPerProduct) {
        // Сортируем по дате (старые первыми)
        existingPositive.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));

        // Удаляем самый старый
        const toDelete = existingPositive[0];
        const deleteResult = deleteSampleInternal(samples, toDelete.id);
        if (deleteResult.deleted) {
          savedCount.rotated++;
          console.log(`[Positive Samples] Ротация: удалён старый sample ${toDelete.id} для ${productId}`);
        }
      }

      // Сохраняем новый positive sample
      const id = uuidv4();
      const timestamp = new Date().toISOString();

      // Сохраняем изображение
      const imageBuffer = Buffer.from(imageBase64, 'base64');
      const imageFileName = `positive_${id}.jpg`;
      const imagePath = path.join(IMAGES_DIR, imageFileName);
      fs.writeFileSync(imagePath, imageBuffer);

      // НОВОЕ: Собираем bounding boxes для этого товара из raw boxes
      const productBoxes = boxes.filter(box => box.productId === productId);

      // НОВОЕ: Сохраняем YOLO label файл если есть boxes
      let yoloAnnotationCount = 0;
      if (productBoxes.length > 0) {
        // Создаём директорию для labels если не существует
        if (!fs.existsSync(LABELS_DIR)) {
          fs.mkdirSync(LABELS_DIR, { recursive: true });
        }

        const labelFileName = `positive_${id}.txt`;
        const labelPath = path.join(LABELS_DIR, labelFileName);

        // Конвертируем x1,y1,x2,y2 в YOLO формат: class x_center y_center width height
        const classId = getClassIdForProduct(productId);
        const yoloLines = productBoxes.map(box => {
          // box.box содержит { x1, y1, x2, y2 } normalized 0-1
          const b = box.box;
          const xCenter = (b.x1 + b.x2) / 2;
          const yCenter = (b.y1 + b.y2) / 2;
          const width = b.x2 - b.x1;
          const height = b.y2 - b.y1;
          return `${classId} ${xCenter.toFixed(6)} ${yCenter.toFixed(6)} ${width.toFixed(6)} ${height.toFixed(6)}`;
        }).join('\n');

        fs.writeFileSync(labelPath, yoloLines);
        yoloAnnotationCount = productBoxes.length;
        console.log(`[Positive Samples] YOLO label сохранён: ${labelFileName} (${yoloAnnotationCount} boxes)`);
      }

      // Создаём запись
      const sample = {
        id,
        productId,
        barcode: detected.barcode || productId,
        productName: detected.productName || '',
        type: 'positive',  // Маркер positive sample
        shopAddress: shopAddress || '',
        confidence: detected.confidence || detected.maxConfidence || 0,
        count: detected.count || 1,
        imageFileName,
        imageUrl: `/api/cigarette-vision/images/${imageFileName}`,
        boundingBoxes: productBoxes.map(b => b.box),  // Сохраняем boxes для справки
        annotationCount: yoloAnnotationCount,  // Теперь есть аннотации!
        createdAt: timestamp,
      };

      samples.push(sample);
      savedCount.total++;
    }

    saveSamples(samples);

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
function deleteSampleInternal(samples, sampleId) {
  const sampleIndex = samples.findIndex(s => s.id === sampleId);

  if (sampleIndex === -1) {
    return { deleted: false };
  }

  const sample = samples[sampleIndex];

  // Удаляем файл изображения
  if (sample.imageFileName) {
    const imagePath = path.join(IMAGES_DIR, sample.imageFileName);
    if (fs.existsSync(imagePath)) {
      try {
        fs.unlinkSync(imagePath);
      } catch (e) {
        console.warn(`[Positive Samples] Не удалось удалить файл ${imagePath}:`, e.message);
      }
    }

    // Удаляем YOLO label если есть (для positive samples имя файла positive_${id}.txt)
    // Выводим имя label из имени изображения (меняем .jpg на .txt)
    const labelFileName = sample.imageFileName ? sample.imageFileName.replace(/\.jpg$/, '.txt') : (sample.id + '.txt');
    const labelPath = path.join(LABELS_DIR, labelFileName);
    if (fs.existsSync(labelPath)) {
      try {
        fs.unlinkSync(labelPath);
      } catch (e) {
        // Игнорируем ошибки удаления label
      }
    }
  }

  // Удаляем из массива
  samples.splice(sampleIndex, 1);

  return { deleted: true };
}

/**
 * Очистка старых positive samples (старше N дней)
 */
function cleanupOldPositiveSamples() {
  try {
    const settings = loadSettings();
    const maxAgeDays = settings.positiveSamplesMaxAgeDays || 180;
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - maxAgeDays);

    const samples = loadSamples();
    const initialCount = samples.length;
    let deletedCount = 0;

    // Фильтруем только positive samples старше cutoff
    const toDelete = samples.filter(s => {
      if (s.type !== 'positive') return false;
      const createdAt = new Date(s.createdAt);
      return createdAt < cutoffDate;
    });

    // Удаляем старые
    for (const sample of toDelete) {
      const result = deleteSampleInternal(samples, sample.id);
      if (result.deleted) {
        deletedCount++;
      }
    }

    if (deletedCount > 0) {
      saveSamples(samples);
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
function getPositiveSamplesStats() {
  try {
    const samples = loadSamples();
    const positiveSamples = samples.filter(s => s.type === 'positive');

    // Группируем по товарам
    const byProduct = {};
    positiveSamples.forEach(s => {
      const key = s.productId || s.barcode;
      if (!byProduct[key]) {
        byProduct[key] = { count: 0, productName: s.productName };
      }
      byProduct[key].count++;
    });

    // Группируем по магазинам
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
 * @param {string} imageBase64 - Изображение в формате base64
 * @param {string} productId - ID товара для фильтрации (опционально)
 * @param {number} confidence - Минимальная уверенность (0-1)
 */
async function detectAndCount(imageBase64, productId = null, confidence = 0.5) {
  // Проверяем доступность YOLO wrapper
  if (!yoloWrapper) {
    return {
      success: false,
      error: 'ML модуль не загружен. Проверьте установку зависимостей.',
      count: 0,
      confidence: 0,
      boxes: [],
    };
  }

  // Проверяем, обучена ли модель
  if (!yoloWrapper.isModelReady()) {
    // Возвращаем информативное сообщение о статусе обучения
    const samples = loadSamples();
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
    // Вызываем YOLO детекцию
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
 * @param {string} imageBase64 - Изображение в формате base64
 * @param {string[]} expectedProducts - Список ожидаемых товаров (productId)
 * @param {number} confidence - Минимальная уверенность (0-1)
 */
async function checkDisplay(imageBase64, expectedProducts = [], confidence = 0.3) {
  // Проверяем доступность YOLO wrapper
  if (!yoloWrapper) {
    return {
      success: false,
      error: 'ML модуль не загружен. Проверьте установку зависимостей.',
      missingProducts: expectedProducts,
      detectedProducts: [],
    };
  }

  // Проверяем, обучена ли модель
  if (!yoloWrapper.isModelReady()) {
    const samples = loadSamples();
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
    // Вызываем YOLO проверку выкладки
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
 * @param {string} outputDir - Путь для сохранения датасета
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
 * @param {string} dataYaml - Путь к data.yaml
 * @param {number} epochs - Количество эпох обучения
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

  // isTrained = true если модель существует (проверяем оба источника)
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
function initTypedTraining(trainingType) {
  const paths = getTrainingPaths(trainingType);

  if (!fs.existsSync(paths.baseDir)) {
    fs.mkdirSync(paths.baseDir, { recursive: true });
  }
  if (!fs.existsSync(paths.imagesDir)) {
    fs.mkdirSync(paths.imagesDir, { recursive: true });
  }
  if (!fs.existsSync(paths.labelsDir)) {
    fs.mkdirSync(paths.labelsDir, { recursive: true });
  }
  if (!fs.existsSync(paths.samplesFile)) {
    fs.writeFileSync(paths.samplesFile, JSON.stringify({ samples: [] }, null, 2));
  }

  return paths;
}

/**
 * Загрузить образцы для конкретного типа обучения
 */
function loadTypedSamples(trainingType) {
  try {
    const paths = initTypedTraining(trainingType);
    const data = fs.readFileSync(paths.samplesFile, 'utf8');
    return JSON.parse(data).samples || [];
  } catch (error) {
    console.error(`[Typed Training] Ошибка загрузки образцов ${trainingType}:`, error);
    return [];
  }
}

/**
 * Сохранить образцы для конкретного типа обучения
 */
function saveTypedSamples(trainingType, samples) {
  try {
    const paths = initTypedTraining(trainingType);
    fs.writeFileSync(paths.samplesFile, JSON.stringify({ samples }, null, 2));
    return true;
  } catch (error) {
    console.error(`[Typed Training] Ошибка сохранения образцов ${trainingType}:`, error);
    return false;
  }
}

/**
 * Получить classId для товара в конкретном датасете
 */
function getTypedClassId(trainingType, productId) {
  const paths = initTypedTraining(trainingType);

  let classMapping = {};
  if (fs.existsSync(paths.classMappingFile)) {
    try {
      classMapping = JSON.parse(fs.readFileSync(paths.classMappingFile, 'utf8'));
    } catch (e) {
      classMapping = {};
    }
  }

  if (classMapping[productId] !== undefined) {
    return classMapping[productId];
  }

  // Создаём новый classId
  const maxId = Object.values(classMapping).reduce((max, id) => Math.max(max, id), -1);
  const newId = maxId + 1;
  classMapping[productId] = newId;

  fs.writeFileSync(paths.classMappingFile, JSON.stringify(classMapping, null, 2));
  console.log(`[Typed Training] ${trainingType}: новый classId для ${productId}: ${newId}`);

  return newId;
}

/**
 * Сохранить positive sample в раздельный датасет
 * @param {string} trainingType - 'display' или 'counting'
 * @param {Object} params - Параметры образца
 */
async function saveTypedPositiveSample(trainingType, {
  imageBase64,
  detectedProducts,
  shopAddress,
  boxes = [],
}) {
  try {
    const settings = loadSettings();

    // Проверяем включена ли функция
    if (!settings.positiveSamplesEnabled) {
      return { success: false, skipped: true, reason: 'Positive samples отключены' };
    }

    // Проверяем вероятность сохранения (10% по умолчанию)
    const sampleRate = settings.positiveSampleRate || 0.1;
    if (Math.random() > sampleRate) {
      return { success: false, skipped: true, reason: 'Не попал в выборку' };
    }

    if (!detectedProducts || detectedProducts.length === 0) {
      return { success: false, skipped: true, reason: 'Нет распознанных товаров' };
    }

    const paths = initTypedTraining(trainingType);
    const maxPerProduct = settings.maxPositiveSamplesPerProduct || 50;
    const samples = loadTypedSamples(trainingType);
    const savedCount = { total: 0, rotated: 0, withLabels: 0 };

    // Сохраняем для каждого распознанного товара
    for (const detected of detectedProducts) {
      const productId = detected.productId || detected.barcode;

      // Считаем существующие positive samples для этого товара
      const existingPositive = samples.filter(
        s => (s.productId === productId || s.barcode === productId)
      );

      // Если лимит превышен - удаляем самые старые (FIFO)
      if (existingPositive.length >= maxPerProduct) {
        existingPositive.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
        const toDelete = existingPositive[0];

        // Удаляем файлы
        const imgPath = path.join(paths.imagesDir, toDelete.imageFileName);
        const lblPath = path.join(paths.labelsDir, toDelete.imageFileName.replace(/\.jpg$/, '.txt'));
        try {
          if (fs.existsSync(imgPath)) fs.unlinkSync(imgPath);
          if (fs.existsSync(lblPath)) fs.unlinkSync(lblPath);
        } catch (e) { /* ignore */ }

        // Удаляем из массива
        const idx = samples.findIndex(s => s.id === toDelete.id);
        if (idx !== -1) {
          samples.splice(idx, 1);
          savedCount.rotated++;
        }
      }

      // Сохраняем новый positive sample
      const id = uuidv4();
      const timestamp = new Date().toISOString();
      const imageFileName = `${trainingType}_${id}.jpg`;

      // Сохраняем изображение
      const imageBuffer = Buffer.from(imageBase64, 'base64');
      fs.writeFileSync(path.join(paths.imagesDir, imageFileName), imageBuffer);

      // Собираем bounding boxes для этого товара
      const productBoxes = boxes.filter(box => box.productId === productId);

      // Сохраняем YOLO label если есть boxes
      let annotationCount = 0;
      if (productBoxes.length > 0) {
        const labelFileName = imageFileName.replace(/\.jpg$/, '.txt');
        const classId = getTypedClassId(trainingType, productId);

        const yoloLines = productBoxes.map(box => {
          const b = box.box;
          const xCenter = (b.x1 + b.x2) / 2;
          const yCenter = (b.y1 + b.y2) / 2;
          const width = b.x2 - b.x1;
          const height = b.y2 - b.y1;
          return `${classId} ${xCenter.toFixed(6)} ${yCenter.toFixed(6)} ${width.toFixed(6)} ${height.toFixed(6)}`;
        }).join('\n');

        fs.writeFileSync(path.join(paths.labelsDir, labelFileName), yoloLines);
        annotationCount = productBoxes.length;
        savedCount.withLabels++;
      }

      // Создаём запись
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

    saveTypedSamples(trainingType, samples);
    console.log(`[Typed Training] ${trainingType}: сохранено ${savedCount.total}, с labels: ${savedCount.withLabels}, ротировано: ${savedCount.rotated}`);

    return { success: true, savedCount, trainingType };
  } catch (error) {
    console.error(`[Typed Training] Ошибка сохранения ${trainingType}:`, error);
    return { success: false, error: error.message };
  }
}

/**
 * Сохранить фото с пересчёта в PENDING (ожидание подтверждения админа)
 * Фото НЕ попадает в обучение пока админ не подтвердит
 * @param {Object} params - Параметры
 * @param {string} params.imageBase64 - Изображение в base64
 * @param {string} params.productId - ID товара (barcode)
 * @param {string} params.productName - Название товара
 * @param {string} params.shopAddress - Адрес магазина
 * @param {number} params.employeeAnswer - Ответ сотрудника (количество)
 */
async function saveCountingTrainingSample({
  imageBase64,
  productId,
  productName,
  shopAddress,
  employeeAnswer,
}) {
  try {
    if (!imageBase64 || !productId) {
      return { success: false, error: 'imageBase64 и productId обязательны' };
    }

    const paths = initCountingPending();
    const samples = loadPendingCountingSamples();

    // Лимит pending фото на товар (чтобы не засорять)
    const maxPendingPerProduct = 20;
    const existingForProduct = samples.filter(
      s => (s.productId === productId || s.barcode === productId)
    );

    // Если лимит превышен - удаляем самый старый (FIFO)
    if (existingForProduct.length >= maxPendingPerProduct) {
      existingForProduct.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
      const toDelete = existingForProduct[0];

      const imgPath = path.join(paths.imagesDir, toDelete.imageFileName);
      try {
        if (fs.existsSync(imgPath)) fs.unlinkSync(imgPath);
      } catch (e) { /* ignore */ }

      const idx = samples.findIndex(s => s.id === toDelete.id);
      if (idx !== -1) {
        samples.splice(idx, 1);
        console.log(`[Counting Pending] Ротация: удалён старый pending для ${productId}`);
      }
    }

    // Сохраняем новое фото в pending
    const id = uuidv4();
    const timestamp = new Date().toISOString();
    const imageFileName = `pending_${productId}_${id}.jpg`;

    const imageBuffer = Buffer.from(imageBase64, 'base64');
    fs.writeFileSync(path.join(paths.imagesDir, imageFileName), imageBuffer);

    const sample = {
      id,
      productId,
      barcode: productId,
      productName: productName || '',
      type: 'counting-pending',
      status: 'pending',  // pending | approved | rejected
      shopAddress: shopAddress || '',
      employeeAnswer: employeeAnswer || null,
      imageFileName,
      imageUrl: `/api/cigarette-vision/counting-pending-images/${imageFileName}`,
      createdAt: timestamp,
    };

    samples.push(sample);
    savePendingCountingSamples(samples);

    console.log(`[Counting Pending] Фото добавлено в очередь для ${productName || productId}, pending: ${existingForProduct.length + 1}`);

    return { success: true, sample, status: 'pending' };
  } catch (error) {
    console.error('[Counting Pending] Ошибка сохранения:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Подтвердить pending фото (переместить в counting-training)
 * @param {string} sampleId - ID pending образца
 * @returns {Object} - Результат
 */
function approveCountingPendingSample(sampleId) {
  try {
    const pendingPaths = initCountingPending();
    const pendingSamples = loadPendingCountingSamples();

    const idx = pendingSamples.findIndex(s => s.id === sampleId);
    if (idx === -1) {
      return { success: false, error: 'Pending образец не найден' };
    }

    const pendingSample = pendingSamples[idx];
    const trainingType = TRAINING_TYPES.COUNTING;
    const trainingPaths = initTypedTraining(trainingType);
    const trainingSamples = loadTypedSamples(trainingType);

    // Проверяем лимит в training
    const settings = loadSettings();
    const maxPerProduct = settings.maxCountingPhotosPerProduct || 50;
    const existingForProduct = trainingSamples.filter(
      s => (s.productId === pendingSample.productId || s.barcode === pendingSample.productId)
    );

    // FIFO ротация если лимит
    if (existingForProduct.length >= maxPerProduct) {
      existingForProduct.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
      const toDelete = existingForProduct[0];

      const imgPath = path.join(trainingPaths.imagesDir, toDelete.imageFileName);
      const lblPath = path.join(trainingPaths.labelsDir, toDelete.imageFileName.replace(/\.jpg$/, '.txt'));
      try {
        if (fs.existsSync(imgPath)) fs.unlinkSync(imgPath);
        if (fs.existsSync(lblPath)) fs.unlinkSync(lblPath);
      } catch (e) { /* ignore */ }

      const delIdx = trainingSamples.findIndex(s => s.id === toDelete.id);
      if (delIdx !== -1) trainingSamples.splice(delIdx, 1);
    }

    // Перемещаем изображение из pending в training
    const newImageFileName = `counting_${pendingSample.productId}_${pendingSample.id}.jpg`;
    const srcPath = path.join(pendingPaths.imagesDir, pendingSample.imageFileName);
    const dstPath = path.join(trainingPaths.imagesDir, newImageFileName);

    if (fs.existsSync(srcPath)) {
      fs.copyFileSync(srcPath, dstPath);
      fs.unlinkSync(srcPath);
    }

    // Создаём запись в training
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
      createdAt: pendingSample.createdAt,
      approvedAt: new Date().toISOString(),
    };

    trainingSamples.push(trainingSample);
    saveTypedSamples(trainingType, trainingSamples);

    // Удаляем из pending
    pendingSamples.splice(idx, 1);
    savePendingCountingSamples(pendingSamples);

    console.log(`[Counting Pending] Подтверждено фото для ${pendingSample.productName || pendingSample.productId}`);

    return { success: true, sample: trainingSample };
  } catch (error) {
    console.error('[Counting Pending] Ошибка подтверждения:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Отклонить pending фото (удалить)
 * @param {string} sampleId - ID pending образца
 * @returns {Object} - Результат
 */
function rejectCountingPendingSample(sampleId) {
  try {
    const paths = initCountingPending();
    const samples = loadPendingCountingSamples();

    const idx = samples.findIndex(s => s.id === sampleId);
    if (idx === -1) {
      return { success: false, error: 'Pending образец не найден' };
    }

    const sample = samples[idx];

    // Удаляем изображение
    const imgPath = path.join(paths.imagesDir, sample.imageFileName);
    try {
      if (fs.existsSync(imgPath)) fs.unlinkSync(imgPath);
    } catch (e) { /* ignore */ }

    // Удаляем из списка
    samples.splice(idx, 1);
    savePendingCountingSamples(samples);

    console.log(`[Counting Pending] Отклонено фото для ${sample.productName || sample.productId}`);

    return { success: true };
  } catch (error) {
    console.error('[Counting Pending] Ошибка отклонения:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Получить все pending фото пересчёта
 * @returns {Array} - Массив pending образцов
 */
function getAllPendingCountingSamples() {
  return loadPendingCountingSamples();
}

/**
 * Получить pending фото для конкретного товара
 * @param {string} productId - ID товара (barcode)
 * @returns {Array} - Массив pending образцов
 */
function getPendingCountingSamplesForProduct(productId) {
  const samples = loadPendingCountingSamples();
  return samples.filter(
    s => (s.productId === productId || s.barcode === productId)
  );
}

/**
 * Получить количество pending фото для товара
 * @param {string} productId - ID товара (barcode)
 * @returns {number} - Количество pending фото
 */
function getPendingCountingPhotosCount(productId) {
  const samples = loadPendingCountingSamples();
  return samples.filter(
    s => (s.productId === productId || s.barcode === productId)
  ).length;
}

/**
 * Получить количество фото пересчёта для товара
 * @param {string} productId - ID товара (barcode)
 * @returns {number} - Количество фото
 */
function getCountingPhotosCount(productId) {
  try {
    const samples = loadTypedSamples(TRAINING_TYPES.COUNTING);
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
 * @param {string} productId - ID товара (barcode)
 * @returns {Array} - Массив образцов
 */
function getCountingSamplesForProduct(productId) {
  try {
    const samples = loadTypedSamples(TRAINING_TYPES.COUNTING);
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
 * @param {string} sampleId - ID образца
 * @returns {Object} - Результат
 */
function deleteCountingSample(sampleId) {
  try {
    const trainingType = TRAINING_TYPES.COUNTING;
    const paths = getTrainingPaths(trainingType);
    const samples = loadTypedSamples(trainingType);

    const idx = samples.findIndex(s => s.id === sampleId);
    if (idx === -1) {
      return { success: false, error: 'Образец не найден' };
    }

    const sample = samples[idx];

    // Удаляем файлы
    const imgPath = path.join(paths.imagesDir, sample.imageFileName);
    const lblPath = path.join(paths.labelsDir, sample.imageFileName.replace(/\.jpg$/, '.txt'));
    try {
      if (fs.existsSync(imgPath)) fs.unlinkSync(imgPath);
      if (fs.existsSync(lblPath)) fs.unlinkSync(lblPath);
    } catch (e) { /* ignore */ }

    // Удаляем из массива
    samples.splice(idx, 1);
    saveTypedSamples(trainingType, samples);

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
function getTypedTrainingStats(trainingType) {
  try {
    const samples = loadTypedSamples(trainingType);
    const paths = getTrainingPaths(trainingType);

    // Подсчёт по товарам
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

    // Проверяем существование модели
    const modelPath = trainingType === TRAINING_TYPES.COUNTING ? COUNTING_MODEL : DISPLAY_MODEL;
    const modelExists = fs.existsSync(modelPath);

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
function cleanupTypedSamples(trainingType, maxAgeDays = 180) {
  try {
    const paths = getTrainingPaths(trainingType);
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - maxAgeDays);

    const samples = loadTypedSamples(trainingType);
    let deletedCount = 0;

    const toKeep = samples.filter(s => {
      const createdAt = new Date(s.createdAt);
      if (createdAt < cutoffDate) {
        // Удаляем файлы
        const imgPath = path.join(paths.imagesDir, s.imageFileName);
        const lblPath = path.join(paths.labelsDir, s.imageFileName.replace(/\.jpg$/, '.txt'));
        try {
          if (fs.existsSync(imgPath)) fs.unlinkSync(imgPath);
          if (fs.existsSync(lblPath)) fs.unlinkSync(lblPath);
        } catch (e) { /* ignore */ }
        deletedCount++;
        return false;
      }
      return true;
    });

    if (deletedCount > 0) {
      saveTypedSamples(trainingType, toKeep);
      console.log(`[Typed Training] ${trainingType}: очищено ${deletedCount} старых образцов`);
    }

    return { success: true, deletedCount, remaining: toKeep.length };
  } catch (error) {
    console.error(`[Typed Training] Ошибка очистки ${trainingType}:`, error);
    return { success: false, error: error.message };
  }
}

// ============ СИСТЕМА ОБРАТНОЙ СВЯЗИ И АВТООТКЛЮЧЕНИЯ ИИ ============

// Файл для хранения статистики ошибок по товарам
const AI_ERRORS_FILE = path.join(DATA_DIR, 'ai-errors-stats.json');
// Директория для "проблемных" фото (для анализа и переобучения)
const PROBLEM_SAMPLES_DIR = path.join(DATA_DIR, 'problem-samples');

// Настройки автоотключения
const AI_ERROR_THRESHOLD = 5;  // После 5 ошибок подряд - отключаем ИИ
const ERROR_RESET_DAYS = 7;    // Сбрасываем счётчик через 7 дней без ошибок

/**
 * Загрузить статистику ошибок ИИ
 */
function loadAiErrorsStats() {
  try {
    if (fs.existsSync(AI_ERRORS_FILE)) {
      return JSON.parse(fs.readFileSync(AI_ERRORS_FILE, 'utf8'));
    }
  } catch (e) {
    console.error('[AI Errors] Ошибка загрузки статистики:', e.message);
  }
  return { products: {} };
}

/**
 * Сохранить статистику ошибок ИИ
 */
function saveAiErrorsStats(stats) {
  try {
    fs.writeFileSync(AI_ERRORS_FILE, JSON.stringify(stats, null, 2));
  } catch (e) {
    console.error('[AI Errors] Ошибка сохранения статистики:', e.message);
  }
}

/**
 * Сообщить об ошибке ИИ от сотрудника (информационная метка)
 * НЕ увеличивает счётчик ошибок - это делает только админ через reportAdminAiDecision()
 * @param {Object} params
 * @param {string} params.productId - ID товара
 * @param {string} params.productName - Название товара
 * @param {number} params.expectedCount - Ожидаемое количество (по программе)
 * @param {number} params.aiCount - Количество от ИИ
 * @param {string} params.imageBase64 - Фото для анализа
 * @param {string} params.shopAddress - Адрес магазина
 * @param {string} params.employeeName - Имя сотрудника
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
    const stats = loadAiErrorsStats();
    const now = new Date();

    // Инициализируем запись для товара если нет
    if (!stats.products[productId]) {
      stats.products[productId] = {
        productName: productName || '',
        consecutiveErrors: 0,
        totalErrors: 0,
        pendingReports: 0,  // Ожидают проверки админом
        lastErrorAt: null,
        isDisabled: false,
        disabledAt: null,
        errorHistory: [],
      };
    }

    const product = stats.products[productId];
    product.productName = productName || product.productName;
    // НЕ увеличиваем consecutiveErrors и totalErrors - это сделает админ
    product.pendingReports = (product.pendingReports || 0) + 1;
    product.lastReportAt = now.toISOString();

    // Сохраняем в историю (последние 20 ошибок) - для информации админу
    product.errorHistory.unshift({
      timestamp: now.toISOString(),
      expectedCount,
      aiCount,
      shopAddress: shopAddress || '',
      employeeName: employeeName || '',
      status: 'pending',  // Ожидает решения админа
    });
    if (product.errorHistory.length > 20) {
      product.errorHistory = product.errorHistory.slice(0, 20);
    }

    saveAiErrorsStats(stats);

    // Сохраняем проблемное фото для просмотра админом
    let savedFileName = null;
    if (imageBase64) {
      const saveResult = await saveProblemSample({
        productId,
        productName,
        expectedCount,
        aiCount,
        imageBase64,
        shopAddress,
        status: 'pending',  // Ожидает решения админа
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
 * ТОЛЬКО эта функция увеличивает счётчик для автоотключения
 * @param {Object} params
 * @param {string} params.productId - ID товара
 * @param {string} params.productName - Название товара
 * @param {string} params.decision - "approved_for_training" | "rejected_bad_photo"
 * @param {string} params.adminName - Имя админа
 * @param {string} params.imageBase64 - Фото (если approved, сохраняем в training)
 * @param {number} params.expectedCount - Ожидаемое количество
 * @param {number} params.aiCount - Количество от ИИ
 * @param {string} params.shopAddress - Адрес магазина
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
    const stats = loadAiErrorsStats();
    const now = new Date();

    // Инициализируем запись для товара если нет
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

    // Уменьшаем счётчик pending
    if (product.pendingReports > 0) {
      product.pendingReports--;
    }

    // Сохраняем решение админа
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
      // Админ подтвердил: ИИ ошибся
      product.consecutiveErrors++;
      product.totalErrors++;
      product.lastErrorAt = now.toISOString();

      // Проверяем порог автоотключения
      if (product.consecutiveErrors >= AI_ERROR_THRESHOLD && !product.isDisabled) {
        product.isDisabled = true;
        product.disabledAt = now.toISOString();
        console.log(`[AI Errors] ⚠️ ИИ ОТКЛЮЧЕН для товара ${productId} (${productName}) после ${product.consecutiveErrors} подтверждённых ошибок`);
      }

      // Сохраняем фото в counting-training датасет
      if (imageBase64) {
        try {
          await saveTypedPositiveSample(TRAINING_TYPES.COUNTING, {
            imageBase64,
            detectedProducts: [{
              productId,
              barcode: productId,
              productName: productName || '',
              count: expectedCount || 0,  // Правильное количество
            }],
            shopAddress: shopAddress || '',
            boxes: [],  // Без boxes - админ добавит аннотацию позже
          });
          console.log(`[AI Errors] Фото добавлено в counting-training: ${productId}`);
        } catch (e) {
          console.warn(`[AI Errors] Не удалось сохранить в training:`, e.message);
        }
      }

      console.log(`[AI Errors] Админ ${adminName} подтвердил ошибку ИИ: ${productId} (consecutiveErrors: ${product.consecutiveErrors})`);
    } else if (decision === 'rejected_bad_photo') {
      // Админ отклонил: фото плохое, ИИ не виноват
      // НЕ увеличиваем счётчик
      console.log(`[AI Errors] Админ ${adminName} отклонил жалобу на ИИ: ${productId} (плохое фото)`);
    }

    saveAiErrorsStats(stats);

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
 * @param {string} status - "pending" (ожидает) | "approved" | "rejected"
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
    // Создаём директорию
    const productDir = path.join(PROBLEM_SAMPLES_DIR, productId);
    if (!fs.existsSync(productDir)) {
      fs.mkdirSync(productDir, { recursive: true });
    }

    // Ограничиваем количество проблемных фото (макс 30 на товар)
    const existingFiles = fs.readdirSync(productDir).filter(f => f.endsWith('.jpg'));
    if (existingFiles.length >= 30) {
      // Удаляем самый старый
      existingFiles.sort();
      const oldest = existingFiles[0];
      fs.unlinkSync(path.join(productDir, oldest));
      // Удаляем метаданные
      const metaFile = oldest.replace('.jpg', '.json');
      if (fs.existsSync(path.join(productDir, metaFile))) {
        fs.unlinkSync(path.join(productDir, metaFile));
      }
    }

    // Сохраняем фото
    const id = uuidv4().slice(0, 8);
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const fileName = `problem_${timestamp}_${id}.jpg`;
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    fs.writeFileSync(path.join(productDir, fileName), imageBuffer);

    // Сохраняем метаданные
    const metaFileName = fileName.replace('.jpg', '.json');
    fs.writeFileSync(path.join(productDir, metaFileName), JSON.stringify({
      productId,
      productName,
      expectedCount,
      aiCount,
      shopAddress,
      status,  // pending | approved | rejected
      createdAt: new Date().toISOString(),
    }, null, 2));

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
function isProductAiDisabled(productId) {
  const stats = loadAiErrorsStats();
  const product = stats.products[productId];

  if (!product) return false;

  // Проверяем автоматический сброс (если давно не было ошибок)
  if (product.isDisabled && product.lastErrorAt) {
    const daysSinceLastError = (Date.now() - new Date(product.lastErrorAt).getTime()) / (1000 * 60 * 60 * 24);
    if (daysSinceLastError >= ERROR_RESET_DAYS) {
      // Автоматически включаем ИИ обратно
      product.isDisabled = false;
      product.consecutiveErrors = 0;
      product.disabledAt = null;
      saveAiErrorsStats(stats);
      console.log(`[AI Errors] ИИ автоматически включен для ${productId} (прошло ${daysSinceLastError.toFixed(1)} дней без ошибок)`);
      return false;
    }
  }

  return product.isDisabled;
}

/**
 * Получить полный статус ИИ для товара
 */
function getProductAiStatus(productId) {
  const stats = loadAiErrorsStats();
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

  // Проверяем автосброс
  const isDisabled = isProductAiDisabled(productId);

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
function resetProductAiErrors(productId) {
  const stats = loadAiErrorsStats();

  if (!stats.products[productId]) {
    return { success: false, error: 'Товар не найден в статистике ошибок' };
  }

  stats.products[productId].consecutiveErrors = 0;
  stats.products[productId].isDisabled = false;
  stats.products[productId].disabledAt = null;
  // Не очищаем историю и totalErrors - для аналитики

  saveAiErrorsStats(stats);
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
function reportAiSuccess(productId) {
  const stats = loadAiErrorsStats();

  if (stats.products[productId]) {
    stats.products[productId].consecutiveErrors = 0;
    saveAiErrorsStats(stats);
  }

  return { success: true };
}

/**
 * Получить список всех проблемных товаров
 */
function getProblematicProducts() {
  const stats = loadAiErrorsStats();
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

  // Сортируем по количеству ошибок
  result.sort((a, b) => b.totalErrors - a.totalErrors);

  return result;
}

/**
 * Получить проблемные фото для товара (для ручной аннотации)
 */
function getProblemSamples(productId) {
  try {
    const productDir = path.join(PROBLEM_SAMPLES_DIR, productId);
    if (!fs.existsSync(productDir)) {
      return { success: true, samples: [] };
    }

    const files = fs.readdirSync(productDir).filter(f => f.endsWith('.jpg'));
    const samples = files.map(fileName => {
      const metaFile = fileName.replace('.jpg', '.json');
      const metaPath = path.join(productDir, metaFile);
      let meta = {};
      if (fs.existsSync(metaPath)) {
        try {
          meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        } catch (e) { /* ignore */ }
      }

      return {
        fileName,
        imageUrl: `/api/cigarette-vision/problem-samples/${productId}/${fileName}`,
        ...meta,
      };
    });

    return { success: true, samples };
  } catch (error) {
    return { success: false, error: error.message, samples: [] };
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
  loadAllShops,  // НОВОЕ: загрузка магазинов
  REQUIRED_PHOTOS_COUNT,
  // Новые функции для ML
  exportTrainingData,
  trainModel,
  getModelStatus,
  // Positive samples (успешные распознавания)
  savePositiveSample,
  cleanupOldPositiveSamples,
  getPositiveSamplesStats,
  // Раздельные датасеты для display/counting
  TRAINING_TYPES,
  saveTypedPositiveSample,
  getTypedTrainingStats,
  cleanupTypedSamples,
  loadTypedSamples,
  getTrainingPaths,
  DISPLAY_MODEL,
  COUNTING_MODEL,
  // Counting training (фото с пересчёта)
  saveCountingTrainingSample,
  getCountingPhotosCount,
  getCountingSamplesForProduct,
  deleteCountingSample,
  // Counting pending (ожидающие подтверждения админа)
  getCountingPendingPaths,
  loadPendingCountingSamples,
  getAllPendingCountingSamples,
  getPendingCountingSamplesForProduct,
  getPendingCountingPhotosCount,
  approveCountingPendingSample,
  rejectCountingPendingSample,
  // Система обратной связи и автоотключения ИИ
  reportAiError,
  reportAdminAiDecision,  // НОВОЕ: решение админа по ошибке ИИ
  reportAiSuccess,
  isProductAiDisabled,
  getProductAiStatus,
  resetProductAiErrors,
  getProblematicProducts,
  getProblemSamples,
  PROBLEM_SAMPLES_DIR,
  AI_ERROR_THRESHOLD,
};
