/**
 * OCR Engine — общая инфраструктура для EasyOCR/Tesseract
 *
 * Вынесены дублирующиеся функции из counter-ocr.js и z-report-ocr.js:
 *   - checkEasyOCR() — проверка доступности Python-микросервиса
 *   - callEasyOCREndpoint() — HTTP-вызов к EasyOCR серверу
 *   - cleanupTempFiles() — удаление временных файлов
 *   - tempFilePath() — генерация уникального имени temp-файла
 *   - TEMP_DIR — общая директория для временных файлов
 */

const http = require('http');
const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');

const TEMP_DIR = '/tmp/counter-ocr';
const EASYOCR_HOST = '127.0.0.1';
const EASYOCR_PORT = 5001;

// Инициализация temp dir
(async () => {
  if (!(await fileExists(TEMP_DIR))) {
    await fsp.mkdir(TEMP_DIR, { recursive: true });
  }
})();

/**
 * Проверка доступности EasyOCR микросервиса
 * @returns {Promise<boolean>}
 */
function checkEasyOCR() {
  return new Promise((resolve) => {
    const req = http.get(`http://${EASYOCR_HOST}:${EASYOCR_PORT}/health`, { timeout: 3000 }, (res) => {
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
  });
}

/**
 * HTTP-вызов к EasyOCR серверу (обобщённая версия)
 *
 * @param {string} endpoint - путь эндпоинта (/ocr или /ocr-text)
 * @param {Object} payload - тело запроса (imagePath, preset, expectedRange, ...)
 * @param {number} timeout - таймаут в мс (по умолчанию 60000)
 * @returns {Promise<Object>} — ответ от сервера
 */
function callEasyOCREndpoint(endpoint, payload, timeout = 60000) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(payload);
    const options = {
      hostname: EASYOCR_HOST,
      port: EASYOCR_PORT,
      path: endpoint,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
      timeout,
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(new Error(`Invalid JSON from OCR server ${endpoint}`));
        }
      });
    });
    req.on('error', (e) => reject(e));
    req.on('timeout', () => { req.destroy(); reject(new Error(`OCR server timeout ${endpoint}`)); });
    req.write(body);
    req.end();
  });
}

/**
 * Удаление временных файлов
 * @param {string[]} files — массив путей для удаления
 */
async function cleanupTempFiles(files) {
  for (const file of files) {
    try {
      if (await fileExists(file)) await fsp.unlink(file);
    } catch { /* ignore */ }
  }
}

/**
 * Генерация уникального имени temp-файла
 * @param {string} prefix — префикс (ocr, zreport, zr_region)
 * @param {string} ext — расширение (jpg, png)
 * @returns {string} — полный путь к temp-файлу
 */
function tempFilePath(prefix, ext = 'jpg') {
  const ts = Date.now() + '_' + Math.random().toString(36).slice(2, 6);
  return path.join(TEMP_DIR, `${prefix}_${ts}.${ext}`);
}

module.exports = {
  TEMP_DIR,
  checkEasyOCR,
  callEasyOCREndpoint,
  cleanupTempFiles,
  tempFilePath,
};
