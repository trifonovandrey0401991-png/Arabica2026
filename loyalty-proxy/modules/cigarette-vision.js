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

// Пути к данным
const DATA_DIR = path.join(__dirname, '..', 'data');
const SAMPLES_FILE = path.join(DATA_DIR, 'cigarette-training-samples.json');
const STATS_FILE = path.join(DATA_DIR, 'cigarette-training-stats.json');
const SETTINGS_FILE = path.join(DATA_DIR, 'cigarette-training-settings.json');
const IMAGES_DIR = path.join(DATA_DIR, 'cigarette-training-images');

// Дефолтные настройки (можно изменить через API)
const DEFAULT_SETTINGS = {
  requiredRecountPhotos: 10,  // Крупный план пачки (10 шаблонов)
  requiredDisplayPhotos: 10,  // Фото выкладки
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

  const requiredRecount = settings.requiredRecountPhotos || 10;
  const requiredDisplay = settings.requiredDisplayPhotos || 10;

  // Подсчитываем количество фото для каждого товара (раздельно по типам)
  const recountPhotosByProduct = {};
  const displayPhotosByProduct = {};
  const completedTemplatesByProduct = {};  // Выполненные шаблоны (1-10)

  samples.forEach(sample => {
    const key = sample.productId || sample.barcode;
    if (sample.type === 'display') {
      displayPhotosByProduct[key] = (displayPhotosByProduct[key] || 0) + 1;
    } else {
      // recount или без типа
      recountPhotosByProduct[key] = (recountPhotosByProduct[key] || 0) + 1;

      // Собираем выполненные шаблоны (только для recount)
      if (sample.templateId) {
        if (!completedTemplatesByProduct[key]) {
          completedTemplatesByProduct[key] = new Set();
        }
        completedTemplatesByProduct[key].add(sample.templateId);
      }
    }
  });

  // Фильтруем и обогащаем данные
  let products = recountQuestions.map(q => {
    const recountPhotos = recountPhotosByProduct[q.id] || recountPhotosByProduct[q.barcode] || 0;
    const displayPhotos = displayPhotosByProduct[q.id] || displayPhotosByProduct[q.barcode] || 0;
    const totalPhotos = recountPhotos + displayPhotos;

    // Получаем выполненные шаблоны (Set -> Array)
    const completedTemplatesSet = completedTemplatesByProduct[q.id] || completedTemplatesByProduct[q.barcode] || new Set();
    const completedTemplates = Array.from(completedTemplatesSet).sort((a, b) => a - b);

    // Обучение завершено когда все шаблоны выполнены + нужное кол-во фото выкладки
    const isRecountComplete = completedTemplates.length >= requiredRecount;
    const isDisplayComplete = displayPhotos >= requiredDisplay;

    return {
      id: q.id,
      barcode: q.barcode || q.id,
      productGroup: q.productGroup || '',
      productName: q.productName || q.question || '',
      grade: q.grade || 1,
      // Общая статистика
      trainingPhotosCount: totalPhotos,
      requiredPhotosCount: requiredRecount + requiredDisplay,
      isTrainingComplete: isRecountComplete && isDisplayComplete,
      // Раздельная статистика
      recountPhotosCount: recountPhotos,
      requiredRecountPhotos: requiredRecount,
      isRecountComplete: isRecountComplete,
      completedTemplates: completedTemplates,  // Массив выполненных шаблонов [1, 3, 5...]
      displayPhotosCount: displayPhotos,
      requiredDisplayPhotos: requiredDisplay,
      isDisplayComplete: isDisplayComplete,
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
 * Детекция и подсчёт (заглушка - будет реализовано с ML моделью)
 */
async function detectAndCount(imageBase64, productId) {
  // TODO: Интеграция с ML моделью (YOLOv8)
  // Пока возвращаем заглушку
  return {
    success: false,
    error: 'Модель ещё не обучена. Добавьте больше фотографий для обучения.',
    count: 0,
    confidence: 0,
    boxes: [],
  };
}

/**
 * Проверка выкладки (заглушка - будет реализовано с ML моделью)
 */
async function checkDisplay(imageBase64, shopAddress) {
  // TODO: Интеграция с ML моделью
  return {
    success: false,
    error: 'Модель ещё не обучена. Добавьте больше фотографий для обучения.',
    missingProducts: [],
    detectedProducts: [],
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
  REQUIRED_PHOTOS_COUNT,
};
