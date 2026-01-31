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

// Дефолтные настройки (можно изменить через API)
const DEFAULT_SETTINGS = {
  requiredRecountPhotos: 10,  // Крупный план пачки (10 шаблонов) - ОБЩИЙ для всех магазинов
  requiredDisplayPhotosPerShop: 3,  // Фото выкладки НА КАЖДЫЙ МАГАЗИН
  // Источник каталога товаров:
  // "recount-questions" - текущий каталог (вопросы пересчёта)
  // "master-catalog" - единый мастер-каталог (новый)
  catalogSource: 'recount-questions',
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
};
