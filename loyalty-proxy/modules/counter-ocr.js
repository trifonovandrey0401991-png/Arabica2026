/**
 * Модуль OCR для распознавания чисел со счётчиков кофемашин
 *
 * Использует Tesseract OCR (локальный, бесплатный)
 * Поддерживает пресеты предобработки для разных типов машин:
 *   - standard: для экранов с тёмным текстом на светлом фоне (BW3)
 *   - standard_resize: standard + увеличение (BW4)
 *   - invert_lcd: инверсия для LCD с светлым текстом на тёмном фоне (WMF)
 */

const { exec } = require('child_process');
const util = require('util');
const fsp = require('fs').promises;
const path = require('path');
const sharp = require('sharp');

const execPromise = util.promisify(exec);

// Temp directory для обработки изображений
const TEMP_DIR = '/tmp/counter-ocr';

// Пресеты предобработки
const PRESETS = {
  // Стандартный: для экранов с тёмным текстом на светлом фоне (Thermoplan BW3)
  standard: {
    negate: false,
    resize: null,
    threshold: 128,
    psm: 7,
    parseStrategy: 'direct',
  },
  // Стандартный с увеличением: для мелкого текста (Thermoplan BW4)
  standard_resize: {
    negate: false,
    resize: 1200,
    threshold: 128,
    psm: 7,
    parseStrategy: 'direct',
  },
  // Инверсия для LCD: для светлого текста на тёмном фоне (WMF)
  invert_lcd: {
    negate: true,
    resize: 1200,
    threshold: false,
    psm: 6,
    parseStrategy: 'largest_number',
  },
};

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure temp dir exists
(async () => {
  if (!(await fileExists(TEMP_DIR))) {
    await fsp.mkdir(TEMP_DIR, { recursive: true });
  }
})();

/**
 * Распознать число со снимка счётчика кофемашины
 *
 * @param {string} imageBase64 - Изображение в base64
 * @param {object} [region] - Область обрезки (относительные координаты 0.0-1.0)
 * @param {string} [preset='standard'] - Пресет предобработки: 'standard', 'standard_resize', 'invert_lcd'
 * @returns {Promise<{number: number|null, confidence: number, rawText: string, success: boolean, error: string|null}>}
 */
async function readCounterNumber(imageBase64, region, preset) {
  const presetConfig = PRESETS[preset] || PRESETS.standard;
  const timestamp = Date.now() + '_' + Math.random().toString(36).slice(2, 6);
  const inputPath = path.join(TEMP_DIR, `counter_${timestamp}_input.jpg`);
  const processedPath = path.join(TEMP_DIR, `counter_${timestamp}_processed.png`);
  const outputBasePath = path.join(TEMP_DIR, `counter_${timestamp}_output`);

  try {
    // 1. Декодировать base64 в файл
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    await fsp.writeFile(inputPath, imageBuffer);

    // 2. Предобработка изображения с sharp
    let sharpInstance = sharp(inputPath);
    const metadata = await sharpInstance.metadata();

    // 3. Обрезка по региону (если задан)
    if (region && region.x !== undefined) {
      const left = Math.round(region.x * metadata.width);
      const top = Math.round(region.y * metadata.height);
      const width = Math.round(region.width * metadata.width);
      const height = Math.round(region.height * metadata.height);

      // Безопасная обрезка
      const safeLeft = Math.max(0, Math.min(left, metadata.width - 1));
      const safeTop = Math.max(0, Math.min(top, metadata.height - 1));
      const safeWidth = Math.min(width, metadata.width - safeLeft);
      const safeHeight = Math.min(height, metadata.height - safeTop);

      if (safeWidth > 0 && safeHeight > 0) {
        sharpInstance = sharpInstance.extract({
          left: safeLeft,
          top: safeTop,
          width: safeWidth,
          height: safeHeight,
        });
      }
    }

    // 4. Предобработка по пресету
    sharpInstance = sharpInstance.greyscale();

    if (presetConfig.negate) {
      sharpInstance = sharpInstance.negate();
    } else {
      sharpInstance = sharpInstance.normalise().sharpen();
    }

    if (presetConfig.threshold) {
      sharpInstance = sharpInstance.threshold(presetConfig.threshold);
    }

    if (presetConfig.resize) {
      sharpInstance = sharpInstance.resize({ width: presetConfig.resize, fit: 'inside' });
    }

    // Сохраняем в PNG (lossless) для лучшего OCR
    await sharpInstance.png().toFile(processedPath);

    // 5. Запуск Tesseract OCR
    const tesseractCmd = `tesseract "${processedPath}" "${outputBasePath}" --psm ${presetConfig.psm} -c tessedit_char_whitelist=0123456789 2>/dev/null`;

    await execPromise(tesseractCmd, { timeout: 10000 });

    // 6. Прочитать результат
    const outputPath = `${outputBasePath}.txt`;
    const rawText = (await fsp.readFile(outputPath, 'utf8')).trim();

    // 7. Обработка результата по стратегии
    let number = null;

    if (presetConfig.parseStrategy === 'largest_number') {
      // Для LCD-экранов: извлечь все числа и вернуть наибольшее > 100
      const matches = rawText.match(/\d+/g);
      if (matches) {
        const numbers = matches.map(n => parseInt(n, 10)).filter(n => n > 100);
        numbers.sort((a, b) => b - a);
        number = numbers.length > 0 ? numbers[0] : null;
      }
    } else {
      // Стандартная стратегия: убрать нецифровые символы
      const cleanedText = rawText.replace(/[^0-9]/g, '');
      number = cleanedText.length > 0 ? parseInt(cleanedText, 10) : null;
    }

    // 8. Оценка confidence
    const digitCount = number !== null ? number.toString().length : 0;
    const confidence = number !== null ? Math.min(0.95, 0.5 + (digitCount * 0.1)) : 0.0;

    // Очистка temp файлов
    await cleanupTempFiles([inputPath, processedPath, outputPath]);

    return {
      number,
      confidence,
      rawText,
      success: number !== null,
      error: number === null ? 'Не удалось распознать число' : null,
    };
  } catch (error) {
    console.error('[Counter OCR] Ошибка распознавания:', error.message);

    // Очистка temp файлов
    await cleanupTempFiles([inputPath, processedPath, `${outputBasePath}.txt`]);

    return {
      number: null,
      confidence: 0,
      rawText: '',
      success: false,
      error: `Ошибка OCR: ${error.message}`,
    };
  }
}

/**
 * Очистка временных файлов
 */
async function cleanupTempFiles(files) {
  for (const file of files) {
    try {
      if (await fileExists(file)) {
        await fsp.unlink(file);
      }
    } catch {
      // Игнорируем ошибки очистки
    }
  }
}

module.exports = { readCounterNumber, PRESETS };
