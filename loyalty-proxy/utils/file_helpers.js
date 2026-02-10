/**
 * Shared File Helpers
 * Общие утилиты для файловых операций, используемые всеми API модулями
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

/**
 * Проверить существование файла/директории
 */
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

/**
 * Создать директорию если не существует
 */
async function ensureDir(dirPath) {
  if (!(await fileExists(dirPath))) {
    await fsp.mkdir(dirPath, { recursive: true });
  }
}

/**
 * Загрузить JSON файл (возвращает defaultValue если не найден)
 */
async function loadJsonFile(filePath, defaultValue = null) {
  try {
    if (!(await fileExists(filePath))) return defaultValue;
    const content = await fsp.readFile(filePath, 'utf8');
    return JSON.parse(content);
  } catch {
    return defaultValue;
  }
}

/**
 * Сохранить JSON файл
 */
async function saveJsonFile(filePath, data) {
  await fsp.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');
}

/**
 * Sanitize ID — защита от path traversal
 */
function sanitizeId(id) {
  if (!id || typeof id !== 'string') return '';
  return id.replace(/[^a-zA-Z0-9_\-\.]/g, '_');
}

/**
 * Проверить что путь не выходит за пределы базовой директории
 */
function isPathSafe(baseDir, filePath) {
  const resolvedBase = path.resolve(baseDir);
  const resolvedPath = path.resolve(filePath);
  return resolvedPath.startsWith(resolvedBase);
}

/**
 * Sanitize phone — только цифры (защита от path traversal + нормализация)
 */
function sanitizePhone(phone) {
  if (!phone) return '';
  return phone.replace(/[^\d]/g, '');
}

/**
 * Нормализация телефона — единая функция для всего бэкенда
 * Убирает ВСЕ нецифровые символы: пробелы, +, скобки, дефисы и т.д.
 * Результат: только цифры, например "79001234567"
 */
const normalizePhone = sanitizePhone;

/**
 * Маскирование телефона для логов (PII protection)
 * '79001234567' → '7900***67'
 */
function maskPhone(phone) {
  if (!phone) return '***';
  const s = String(phone);
  if (s.length <= 6) return '***';
  return s.substring(0, 4) + '***' + s.substring(s.length - 2);
}

module.exports = {
  DATA_DIR,
  fileExists,
  ensureDir,
  loadJsonFile,
  saveJsonFile,
  sanitizeId,
  isPathSafe,
  sanitizePhone,
  normalizePhone,
  maskPhone,
};
