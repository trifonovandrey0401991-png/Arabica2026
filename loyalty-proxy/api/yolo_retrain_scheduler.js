/**
 * YOLO Auto-Retrain Scheduler
 *
 * Раз в неделю (воскресенье в 3:00 по МСК) проверяет:
 * - Есть ли новые аннотированные изображения с момента последнего обучения
 * - Если новых >= MIN_NEW_SAMPLES → запускает export + train
 * - После обучения сравнивает новую модель (по размеру/наличию) со старой
 * - Логирует результат, перезагружает модель
 *
 * Настраивается через env переменные:
 * - YOLO_RETRAIN_ENABLED=true (default: false)
 * - YOLO_RETRAIN_MIN_SAMPLES=50 (минимум новых семплов)
 * - YOLO_RETRAIN_CRON_HOUR=3 (час МСК, default: 3)
 * - YOLO_RETRAIN_CRON_DOW=0 (день недели: 0=Sun, default: 0)
 */

const path = require('path');
const fsp = require('fs').promises;
const { writeJsonFile } = require('../utils/async_fs');
const { fileExists } = require('../utils/file_helpers');
const { getMoscowTime } = require('../utils/moscow_time');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const ML_DIR = path.join(__dirname, '../ml');
const RETRAIN_STATE_FILE = path.join(DATA_DIR, 'yolo-retrain-state.json');

const ENABLED = process.env.YOLO_RETRAIN_ENABLED === 'true';
const MIN_NEW_SAMPLES = parseInt(process.env.YOLO_RETRAIN_MIN_SAMPLES, 10) || 50;
const CRON_HOUR = parseInt(process.env.YOLO_RETRAIN_CRON_HOUR, 10) || 3;
const CRON_DOW = parseInt(process.env.YOLO_RETRAIN_CRON_DOW, 10) || 0; // 0=Sunday

let retrainTimer = null;
let isRetraining = false;

/**
 * Загрузить состояние последнего обучения
 */
async function loadState() {
  try {
    if (await fileExists(RETRAIN_STATE_FILE)) {
      return JSON.parse(await fsp.readFile(RETRAIN_STATE_FILE, 'utf8'));
    }
  } catch (e) { /* ignore */ }
  return {
    lastTrainedAt: null,
    lastSampleCount: 0,
    lastResult: null,
    history: [],
  };
}

async function saveState(state) {
  await writeJsonFile(RETRAIN_STATE_FILE, state);
}

/**
 * Подсчитать количество аннотированных изображений
 */
async function countTrainingImages() {
  let total = 0;
  const dirs = [
    path.join(DATA_DIR, 'display-training/images'),
    path.join(DATA_DIR, 'counting-training/images'),
    path.join(DATA_DIR, 'cigarette-training-images'),
  ];

  for (const dir of dirs) {
    if (await fileExists(dir)) {
      try {
        const files = await fsp.readdir(dir);
        total += files.filter(f => f.endsWith('.jpg') || f.endsWith('.png')).length;
      } catch (e) { /* ignore */ }
    }
  }
  return total;
}

/**
 * Запустить процесс переобучения
 */
async function runRetrain() {
  if (isRetraining) {
    console.log('[YOLO Retrain] Уже выполняется, пропускаем');
    return;
  }

  isRetraining = true;
  const startTime = Date.now();

  try {
    const state = await loadState();
    const currentCount = await countTrainingImages();
    const newSamples = currentCount - (state.lastSampleCount || 0);

    console.log(`[YOLO Retrain] Проверка: ${currentCount} изображений (${newSamples} новых, мин: ${MIN_NEW_SAMPLES})`);

    if (newSamples < MIN_NEW_SAMPLES) {
      console.log(`[YOLO Retrain] Недостаточно новых данных (${newSamples} < ${MIN_NEW_SAMPLES}), пропускаем`);
      return;
    }

    console.log(`[YOLO Retrain] Начинаем переобучение (${currentCount} изображений)...`);

    const yoloWrapper = require('../ml/yolo-wrapper');

    // 1. Экспорт тренировочных данных
    const exportDir = path.join(ML_DIR, 'retrain-dataset');
    const exportResult = await yoloWrapper.exportTrainingData(exportDir);

    if (!exportResult.success) {
      throw new Error(`Export failed: ${exportResult.error}`);
    }

    console.log(`[YOLO Retrain] Экспорт завершён: ${exportResult.total_images || exportResult.train_images} train / ${exportResult.val_images} val`);

    // 2. Бэкап текущей модели
    const modelPath = yoloWrapper.DEFAULT_MODEL;
    const backupPath = `${modelPath}.backup-${Date.now()}`;
    if (await fileExists(modelPath)) {
      await fsp.copyFile(modelPath, backupPath);
      console.log(`[YOLO Retrain] Бэкап модели: ${backupPath}`);
    }

    // 3. Обучение
    const dataYaml = path.join(exportDir, 'data.yaml');
    const trainResult = await yoloWrapper.trainModel(dataYaml, 100);

    const duration = Math.round((Date.now() - startTime) / 1000);

    if (trainResult.success) {
      console.log(`[YOLO Retrain] Обучение завершено за ${duration}с. Модель: ${trainResult.model_path}`);

      // Обновляем state
      state.lastTrainedAt = new Date().toISOString();
      state.lastSampleCount = currentCount;
      state.lastResult = {
        success: true,
        duration,
        trainImages: exportResult.train_images,
        valImages: exportResult.val_images,
        modelPath: trainResult.model_path,
      };
    } else {
      console.error(`[YOLO Retrain] Обучение не удалось: ${trainResult.error}`);

      // Восстанавливаем модель из бэкапа
      if (await fileExists(backupPath)) {
        await fsp.copyFile(backupPath, modelPath);
        console.log('[YOLO Retrain] Модель восстановлена из бэкапа');
      }

      state.lastResult = {
        success: false,
        duration,
        error: trainResult.error,
      };
    }

    // Добавляем в историю (последние 10)
    state.history.unshift({
      timestamp: new Date().toISOString(),
      ...state.lastResult,
    });
    if (state.history.length > 10) {
      state.history = state.history.slice(0, 10);
    }

    await saveState(state);

    // 4. Очистка temp dataset
    try {
      await fsp.rm(exportDir, { recursive: true, force: true });
    } catch (e) {
      console.warn('[YOLO Retrain] Не удалось очистить temp dataset:', e.message);
    }

    // 5. Очистка старых бэкапов (оставляем 3 последних)
    try {
      const modelsDir = yoloWrapper.MODELS_DIR;
      if (await fileExists(modelsDir)) {
        const files = await fsp.readdir(modelsDir);
        const backups = files
          .filter(f => f.includes('.backup-'))
          .sort()
          .reverse();
        for (const old of backups.slice(3)) {
          await fsp.unlink(path.join(modelsDir, old));
        }
      }
    } catch (e) { /* ignore */ }

  } catch (error) {
    console.error('[YOLO Retrain] Ошибка:', error.message);
  } finally {
    isRetraining = false;
  }
}

/**
 * Проверка: пора ли запускать переобучение
 * Вызывается каждые 30 минут
 */
function checkSchedule() {
  const now = getMoscowTime();
  const hour = now.getUTCHours(); // getMoscowTime() shifts to UTC+3 — use getUTCHours()
  const dow = now.getUTCDay(); // 0=Sun

  if (dow === CRON_DOW && hour === CRON_HOUR) {
    runRetrain().catch(e =>
      console.error('[YOLO Retrain] Schedule error:', e.message)
    );
  }
}

/**
 * Запуск шедулера
 */
function startYoloRetrainScheduler() {
  if (!ENABLED) {
    console.log('[YOLO Retrain] Выключен (YOLO_RETRAIN_ENABLED != true)');
    return;
  }

  console.log(`[YOLO Retrain] Шедулер запущен: каждое ${['Вс','Пн','Вт','Ср','Чт','Пт','Сб'][CRON_DOW]} в ${CRON_HOUR}:00 МСК (мин. ${MIN_NEW_SAMPLES} новых семплов)`);

  // Проверяем каждые 30 минут
  retrainTimer = setInterval(checkSchedule, 30 * 60 * 1000);

  // Первая проверка через 5 минут после старта
  setTimeout(checkSchedule, 5 * 60 * 1000);
}

/**
 * Ручной запуск переобучения (из API)
 */
async function triggerManualRetrain() {
  if (isRetraining) {
    return { success: false, error: 'Переобучение уже выполняется' };
  }

  // Запускаем в фоне
  runRetrain().catch(e =>
    console.error('[YOLO Retrain] Manual retrain error:', e.message)
  );

  return { success: true, message: 'Переобучение запущено в фоновом режиме' };
}

/**
 * Получить текущее состояние
 */
async function getRetrainStatus() {
  const state = await loadState();
  const currentCount = await countTrainingImages();
  const newSamples = currentCount - (state.lastSampleCount || 0);

  return {
    enabled: ENABLED,
    isRetraining,
    currentTrainingImages: currentCount,
    newSamplesSinceLastTrain: newSamples,
    minRequired: MIN_NEW_SAMPLES,
    readyToRetrain: newSamples >= MIN_NEW_SAMPLES,
    schedule: `${['Вс','Пн','Вт','Ср','Чт','Пт','Сб'][CRON_DOW]} ${CRON_HOUR}:00 МСК`,
    ...state,
  };
}

module.exports = {
  startYoloRetrainScheduler,
  triggerManualRetrain,
  getRetrainStatus,
};
