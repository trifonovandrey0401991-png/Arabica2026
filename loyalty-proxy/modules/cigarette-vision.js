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
const IMAGES_DIR = path.join(DATA_DIR, 'cigarette-training-images');

// Минимальное количество фото для обучения
const REQUIRED_PHOTOS_COUNT = 50;

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

  // Подсчитываем количество фото для каждого товара
  const photoCountByProduct = {};
  samples.forEach(sample => {
    const key = sample.productId || sample.barcode;
    photoCountByProduct[key] = (photoCountByProduct[key] || 0) + 1;
  });

  // Фильтруем и обогащаем данные
  let products = recountQuestions.map(q => {
    const photosCount = photoCountByProduct[q.id] || photoCountByProduct[q.barcode] || 0;
    return {
      id: q.id,
      barcode: q.barcode || q.id,
      productGroup: q.productGroup || '',
      productName: q.productName || q.question || '',
      grade: q.grade || 1,
      trainingPhotosCount: photosCount,
      requiredPhotosCount: REQUIRED_PHOTOS_COUNT,
      isTrainingComplete: photosCount >= REQUIRED_PHOTOS_COUNT,
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

/**
 * Сохранить образец для обучения
 */
async function saveTrainingSample({
  imageBase64,
  productId,
  barcode,
  productName,
  type = 'recount',
  shopAddress,
  employeeName,
}) {
  try {
    init();

    const id = uuidv4();
    const timestamp = new Date().toISOString();

    // Сохраняем изображение
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    const imageFileName = `${id}.jpg`;
    const imagePath = path.join(IMAGES_DIR, imageFileName);
    fs.writeFileSync(imagePath, imageBuffer);

    // Создаём запись об образце
    const sample = {
      id,
      productId,
      barcode,
      productName,
      type,
      shopAddress,
      employeeName,
      imageFileName,
      imageUrl: `/api/cigarette-vision/images/${imageFileName}`,
      createdAt: timestamp,
    };

    // Добавляем в список
    const samples = loadSamples();
    samples.push(sample);
    saveSamples(samples);

    console.log(`[Cigarette Vision] Образец сохранён: ${productName} (${type})`);

    return { success: true, sample };
  } catch (error) {
    console.error('Ошибка сохранения образца:', error);
    return { success: false, error: error.message };
  }
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
  REQUIRED_PHOTOS_COUNT,
};
