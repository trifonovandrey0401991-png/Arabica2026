/**
 * Модуль OCR для распознавания чисел со счётчиков кофемашин
 *
 * Использует Tesseract OCR (локальный, бесплатный)
 * Оптимизирован для цифр: --psm 7 -c tessedit_char_whitelist=0123456789
 */

const { exec } = require('child_process');
const util = require('util');
const fsp = require('fs').promises;
const path = require('path');
const sharp = require('sharp');

const execPromise = util.promisify(exec);

// Temp directory для обработки изображений
const TEMP_DIR = '/tmp/counter-ocr';

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
 * @param {number} region.x - X координата (0.0-1.0)
 * @param {number} region.y - Y координата (0.0-1.0)
 * @param {number} region.width - Ширина (0.0-1.0)
 * @param {number} region.height - Высота (0.0-1.0)
 * @returns {Promise<{number: number|null, confidence: number, rawText: string, success: boolean, error: string|null}>}
 */
async function readCounterNumber(imageBase64, region) {
  const timestamp = Date.now();
  const inputPath = path.join(TEMP_DIR, `counter_${timestamp}_input.jpg`);
  const processedPath = path.join(TEMP_DIR, `counter_${timestamp}_processed.jpg`);
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

    // 4. Улучшение контраста: преобразование в градации серого, увеличение контраста
    await sharpInstance
      .greyscale()
      .normalise()       // Нормализация контраста
      .sharpen()         // Повышение резкости
      .threshold(128)    // Бинаризация (чёрное/белое)
      .toFile(processedPath);

    // 5. Запуск Tesseract OCR
    // --psm 7: одна строка текста
    // -c tessedit_char_whitelist=0123456789: только цифры
    const tesseractCmd = `tesseract "${processedPath}" "${outputBasePath}" --psm 7 -c tessedit_char_whitelist=0123456789 2>/dev/null`;

    await execPromise(tesseractCmd, { timeout: 10000 });

    // 6. Прочитать результат
    const outputPath = `${outputBasePath}.txt`;
    const rawText = (await fsp.readFile(outputPath, 'utf8')).trim();

    // 7. Обработка: убрать пробелы, запятые, оставить цифры
    const cleanedText = rawText.replace(/[^0-9]/g, '');
    const number = cleanedText.length > 0 ? parseInt(cleanedText, 10) : null;

    // 8. Оценка confidence
    const digitCount = cleanedText.length;
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

module.exports = { readCounterNumber };
