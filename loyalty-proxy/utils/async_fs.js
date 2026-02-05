/**
 * Async File System Utilities
 *
 * Асинхронные обёртки для fs операций.
 * Заменяют sync вызовы для предотвращения блокировки event loop.
 *
 * Обновлено: 2026-02-06 - добавлен file locking для защиты от race conditions
 */

const fs = require('fs');
const fsp = require('fs').promises;
const path = require('path');
const { withLock, getStats: getLockStats } = require('./file_lock');

/**
 * Асинхронная проверка существования файла/директории
 * @param {string} filePath - путь к файлу
 * @returns {Promise<boolean>}
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
 * Асинхронное чтение JSON файла
 * @param {string} filePath - путь к файлу
 * @param {*} defaultValue - значение по умолчанию если файл не существует
 * @returns {Promise<*>}
 */
async function readJsonFile(filePath, defaultValue = null) {
  try {
    const content = await fsp.readFile(filePath, 'utf8');
    return JSON.parse(content);
  } catch (err) {
    if (err.code === 'ENOENT') {
      return defaultValue;
    }
    throw err;
  }
}

/**
 * Асинхронная запись JSON файла с защитой от race conditions
 * @param {string} filePath - путь к файлу
 * @param {*} data - данные для записи
 * @param {Object} options - опции
 * @param {boolean} options.createDir - создать директорию если не существует (default: true)
 * @param {boolean} options.useLock - использовать file locking (default: true)
 * @param {number} options.lockTimeout - таймаут блокировки в мс (default: 30000)
 * @returns {Promise<void>}
 */
async function writeJsonFile(filePath, data, options = {}) {
  const { createDir = true, useLock = true, lockTimeout = 30000 } = options;

  const writeOperation = async () => {
    if (createDir) {
      const dir = path.dirname(filePath);
      await fsp.mkdir(dir, { recursive: true });
    }
    // Прямая запись (атомарность через locking)
    await fsp.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');
  };

  if (useLock) {
    await withLock(filePath, writeOperation, { timeout: lockTimeout });
  } else {
    await writeOperation();
  }
}

/**
 * Асинхронное чтение текстового файла
 * @param {string} filePath - путь к файлу
 * @param {string} defaultValue - значение по умолчанию
 * @returns {Promise<string>}
 */
async function readTextFile(filePath, defaultValue = '') {
  try {
    return await fsp.readFile(filePath, 'utf8');
  } catch (err) {
    if (err.code === 'ENOENT') {
      return defaultValue;
    }
    throw err;
  }
}

/**
 * Асинхронная запись текстового файла с защитой от race conditions
 * @param {string} filePath - путь к файлу
 * @param {string} content - содержимое
 * @param {Object} options - опции
 * @param {boolean} options.createDir - создать директорию если не существует (default: true)
 * @param {boolean} options.useLock - использовать file locking (default: true)
 * @param {number} options.lockTimeout - таймаут блокировки в мс (default: 30000)
 * @returns {Promise<void>}
 */
async function writeTextFile(filePath, content, options = {}) {
  const { createDir = true, useLock = true, lockTimeout = 30000 } = options;

  const writeOperation = async () => {
    if (createDir) {
      const dir = path.dirname(filePath);
      await fsp.mkdir(dir, { recursive: true });
    }
    // Прямая запись (атомарность через locking)
    await fsp.writeFile(filePath, content, 'utf8');
  };

  if (useLock) {
    await withLock(filePath, writeOperation, { timeout: lockTimeout });
  } else {
    await writeOperation();
  }
}

/**
 * Асинхронное чтение директории
 * @param {string} dirPath - путь к директории
 * @returns {Promise<string[]>}
 */
async function readDirectory(dirPath) {
  try {
    return await fsp.readdir(dirPath);
  } catch (err) {
    if (err.code === 'ENOENT') {
      return [];
    }
    throw err;
  }
}

/**
 * Асинхронное создание директории
 * @param {string} dirPath - путь к директории
 * @returns {Promise<void>}
 */
async function ensureDir(dirPath) {
  await fsp.mkdir(dirPath, { recursive: true });
}

/**
 * Асинхронное удаление файла (игнорирует если не существует)
 * @param {string} filePath - путь к файлу
 * @returns {Promise<boolean>} - true если удалён, false если не существовал
 */
async function removeFile(filePath) {
  try {
    await fsp.unlink(filePath);
    return true;
  } catch (err) {
    if (err.code === 'ENOENT') {
      return false;
    }
    throw err;
  }
}

/**
 * Асинхронное получение информации о файле
 * @param {string} filePath - путь к файлу
 * @returns {Promise<fs.Stats|null>}
 */
async function getStats(filePath) {
  try {
    return await fsp.stat(filePath);
  } catch (err) {
    if (err.code === 'ENOENT') {
      return null;
    }
    throw err;
  }
}

/**
 * Асинхронное чтение всех JSON файлов из директории
 * @param {string} dirPath - путь к директории
 * @param {string} pattern - паттерн файлов (по умолчанию .json)
 * @returns {Promise<Array<{filename: string, data: *}>>}
 */
async function readJsonDirectory(dirPath, pattern = '.json') {
  const files = await readDirectory(dirPath);
  const jsonFiles = files.filter(f => f.endsWith(pattern));

  const results = await Promise.all(
    jsonFiles.map(async (filename) => {
      const filePath = path.join(dirPath, filename);
      const data = await readJsonFile(filePath);
      return { filename, data };
    })
  );

  return results.filter(r => r.data !== null);
}

// Синхронные версии для обратной совместимости (пометить как deprecated)
const sync = {
  fileExists: fs.existsSync,
  readJsonFile: (filePath, defaultValue = null) => {
    try {
      const content = fs.readFileSync(filePath, 'utf8');
      return JSON.parse(content);
    } catch (err) {
      if (err.code === 'ENOENT') return defaultValue;
      throw err;
    }
  },
  writeJsonFile: (filePath, data) => {
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
  }
};

module.exports = {
  // Async functions (recommended)
  fileExists,
  readJsonFile,
  writeJsonFile,
  readTextFile,
  writeTextFile,
  readDirectory,
  ensureDir,
  removeFile,
  getStats,
  readJsonDirectory,

  // File locking utilities
  withLock,
  getLockStats,

  // Sync fallbacks (deprecated, for gradual migration)
  sync
};
