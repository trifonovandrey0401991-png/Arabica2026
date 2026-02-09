/**
 * Z-Report OCR Module
 * Извлекает полный текст из фото Z-отчётов
 *
 * Двухуровневая стратегия:
 *   1. EasyOCR (нейросеть) через /ocr-text — основной движок (русский + английский)
 *   2. Tesseract OCR — fallback (rus+eng, полный текст, не только цифры)
 *
 * В отличие от counter-ocr.js (числа), этот модуль возвращает ПОЛНЫЙ ТЕКСТ
 * для последующего regex-парсинга в z-report-vision.js
 */

const { exec } = require('child_process');
const util = require('util');
const fsp = require('fs').promises;
const path = require('path');
const http = require('http');

const execPromise = util.promisify(exec);

const TEMP_DIR = '/tmp/counter-ocr';
const EASYOCR_TEXT_URL = 'http://127.0.0.1:5001/ocr-text';

async function fileExists(fp) {
  try { await fsp.access(fp); return true; } catch { return false; }
}

(async () => {
  if (!(await fileExists(TEMP_DIR))) {
    await fsp.mkdir(TEMP_DIR, { recursive: true });
  }
})();

/**
 * Вызов EasyOCR /ocr-text эндпоинта (полный текст)
 */
function callEasyOCRText(imagePath) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({ imagePath });
    const url = new URL(EASYOCR_TEXT_URL);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout: 90000, // 90 сек — Z-отчёты больше чем счётчики
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(new Error('Invalid JSON from OCR text server'));
        }
      });
    });
    req.on('error', (e) => reject(e));
    req.on('timeout', () => { req.destroy(); reject(new Error('OCR text server timeout')); });
    req.write(body);
    req.end();
  });
}

/**
 * Проверка доступности EasyOCR сервиса
 */
function checkEasyOCR() {
  return new Promise((resolve) => {
    const req = http.get('http://127.0.0.1:5001/health', { timeout: 3000 }, (res) => {
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
  });
}

/**
 * Tesseract fallback — полный текст (русский + английский)
 * Без ограничения по символам (в отличие от counter-ocr.js)
 */
async function tesseractFullText(inputPath) {
  const ts = Date.now() + '_' + Math.random().toString(36).slice(2, 6);
  const processedPath = path.join(TEMP_DIR, `zr_${ts}_proc.png`);
  const outputBasePath = path.join(TEMP_DIR, `zr_${ts}_out`);

  try {
    // Ленивый require — sharp может быть не установлен
    const sharp = require('sharp');
    // Предобработка: серый, нормализация, резкость, ресайз
    await sharp(inputPath)
      .greyscale()
      .normalise()
      .sharpen()
      .resize({ width: 1200, fit: 'inside' })
      .png()
      .toFile(processedPath);

    // Полный текст: rus+eng, psm 6 (блок текста)
    const cmd = `tesseract "${processedPath}" "${outputBasePath}" -l rus+eng --psm 6 2>/dev/null`;
    await execPromise(cmd, { timeout: 30000 });

    const rawText = (await fsp.readFile(`${outputBasePath}.txt`, 'utf8')).trim();

    await cleanupTempFiles([processedPath, `${outputBasePath}.txt`]);
    return { text: rawText, success: true };
  } catch (e) {
    console.error('[Z-Report OCR] Tesseract error:', e.message);
    await cleanupTempFiles([processedPath, `${outputBasePath}.txt`]);
    return { text: '', success: false, error: e.message };
  }
}

/**
 * Основная функция: извлечь полный текст из фото Z-отчёта
 *
 * @param {string} imageBase64 - Изображение в base64 (с или без data:image/... префикса)
 * @returns {Promise<{text, method, charCount, lineCount, success, error}>}
 */
async function extractZReportText(imageBase64) {
  const ts = Date.now() + '_' + Math.random().toString(36).slice(2, 6);
  const inputPath = path.join(TEMP_DIR, `zreport_${ts}_input.jpg`);

  try {
    // Убираем data URI префикс если есть
    const cleanBase64 = imageBase64.replace(/^data:image\/\w+;base64,/, '');
    const imageBuffer = Buffer.from(cleanBase64, 'base64');
    await fsp.writeFile(inputPath, imageBuffer);

    // === Попытка 1: EasyOCR (предпочтительно) ===
    const easyOCRAvailable = await checkEasyOCR();
    if (easyOCRAvailable) {
      try {
        console.log('[Z-Report OCR] Пробую EasyOCR /ocr-text...');
        const easyResult = await callEasyOCRText(inputPath);

        if (easyResult.success && easyResult.text && easyResult.text.length > 20) {
          console.log(`[Z-Report OCR] EasyOCR успех: ${easyResult.charCount} символов, ${easyResult.lineCount} строк`);
          await cleanupTempFiles([inputPath]);
          return {
            text: easyResult.text,
            method: 'easyocr',
            charCount: easyResult.charCount,
            lineCount: easyResult.lineCount,
            success: true,
          };
        } else {
          console.log('[Z-Report OCR] EasyOCR вернул мало текста, пробую Tesseract...');
        }
      } catch (easyErr) {
        console.log('[Z-Report OCR] EasyOCR ошибка, переключаюсь на Tesseract:', easyErr.message);
      }
    } else {
      console.log('[Z-Report OCR] EasyOCR недоступен, использую Tesseract...');
    }

    // === Попытка 2: Tesseract полный текст ===
    console.log('[Z-Report OCR] Пробую Tesseract (rus+eng)...');
    const tessResult = await tesseractFullText(inputPath);

    if (tessResult.success && tessResult.text.length > 20) {
      console.log(`[Z-Report OCR] Tesseract успех: ${tessResult.text.length} символов`);
      await cleanupTempFiles([inputPath]);
      return {
        text: tessResult.text,
        method: 'tesseract',
        charCount: tessResult.text.length,
        lineCount: tessResult.text.split('\n').length,
        success: true,
      };
    }

    // === Обе попытки провалились ===
    await cleanupTempFiles([inputPath]);
    console.log('[Z-Report OCR] Все методы OCR не дали результата');
    return {
      text: '',
      method: 'none',
      charCount: 0,
      lineCount: 0,
      success: false,
      error: 'Не удалось распознать текст на изображении',
    };

  } catch (error) {
    console.error('[Z-Report OCR] Критическая ошибка:', error.message);
    await cleanupTempFiles([inputPath]);
    return {
      text: '',
      method: 'error',
      charCount: 0,
      lineCount: 0,
      success: false,
      error: `Ошибка OCR: ${error.message}`,
    };
  }
}

async function cleanupTempFiles(files) {
  for (const file of files) {
    try {
      if (await fileExists(file)) await fsp.unlink(file);
    } catch { /* ignore */ }
  }
}

module.exports = { extractZReportText };
