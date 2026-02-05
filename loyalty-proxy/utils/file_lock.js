/**
 * File Locking Utility
 *
 * Предотвращает race conditions при параллельной записи в файлы.
 * Использует in-memory блокировки с очередью ожидания.
 *
 * Создано: 2026-02-06
 */

/**
 * Хранилище активных блокировок
 * key: normalized file path
 * value: { queue: Promise[], locked: boolean }
 */
const locks = new Map();

/**
 * Статистика для мониторинга
 */
const stats = {
  totalLocks: 0,
  currentLocks: 0,
  maxConcurrentLocks: 0,
  totalWaitTime: 0,
  lockTimeouts: 0
};

/**
 * Настройки по умолчанию
 */
const DEFAULT_OPTIONS = {
  timeout: 30000,      // 30 секунд максимум ожидания
  retryDelay: 10,      // 10мс между проверками
  debugMode: false     // Логирование для отладки
};

/**
 * Нормализация пути файла для использования как ключа
 * @param {string} filePath
 * @returns {string}
 */
function normalizePath(filePath) {
  return filePath.replace(/\\/g, '/').toLowerCase();
}

/**
 * Получение или создание записи блокировки
 * @param {string} filePath
 * @returns {Object}
 */
function getLockEntry(filePath) {
  const key = normalizePath(filePath);
  if (!locks.has(key)) {
    locks.set(key, {
      locked: false,
      queue: [],
      holder: null,
      acquiredAt: null
    });
  }
  return locks.get(key);
}

/**
 * Захват блокировки на файл
 * @param {string} filePath - путь к файлу
 * @param {Object} options - опции
 * @returns {Promise<Function>} - функция для освобождения блокировки
 */
async function acquireLock(filePath, options = {}) {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  const entry = getLockEntry(filePath);
  const startTime = Date.now();

  // Если уже заблокирован - ждём в очереди
  if (entry.locked) {
    await new Promise((resolve, reject) => {
      const timeoutId = setTimeout(() => {
        // Удаляем из очереди при таймауте
        const idx = entry.queue.indexOf(resolve);
        if (idx > -1) entry.queue.splice(idx, 1);
        stats.lockTimeouts++;
        reject(new Error(`Lock timeout for ${filePath} after ${opts.timeout}ms`));
      }, opts.timeout);

      entry.queue.push(() => {
        clearTimeout(timeoutId);
        resolve();
      });
    });
  }

  // Захватываем блокировку
  entry.locked = true;
  entry.holder = new Error().stack; // Для отладки - кто захватил
  entry.acquiredAt = Date.now();

  // Обновляем статистику
  stats.totalLocks++;
  stats.currentLocks++;
  stats.totalWaitTime += (Date.now() - startTime);
  if (stats.currentLocks > stats.maxConcurrentLocks) {
    stats.maxConcurrentLocks = stats.currentLocks;
  }

  if (opts.debugMode) {
    console.log(`[FileLock] Acquired: ${filePath}`);
  }

  // Возвращаем функцию освобождения
  return () => releaseLock(filePath, opts);
}

/**
 * Освобождение блокировки
 * @param {string} filePath
 * @param {Object} options
 */
function releaseLock(filePath, options = {}) {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  const key = normalizePath(filePath);
  const entry = locks.get(key);

  if (!entry) return;

  stats.currentLocks--;

  if (opts.debugMode) {
    const holdTime = Date.now() - (entry.acquiredAt || 0);
    console.log(`[FileLock] Released: ${filePath} (held for ${holdTime}ms)`);
  }

  // Если есть очередь - передаём следующему
  if (entry.queue.length > 0) {
    const next = entry.queue.shift();
    next();
  } else {
    // Очередь пуста - снимаем блокировку
    entry.locked = false;
    entry.holder = null;
    entry.acquiredAt = null;
  }

  // Очистка неиспользуемых записей (каждые 100 операций)
  if (stats.totalLocks % 100 === 0) {
    cleanupUnusedLocks();
  }
}

/**
 * Выполнение операции с блокировкой
 * @param {string} filePath - путь к файлу
 * @param {Function} operation - async функция для выполнения
 * @param {Object} options - опции
 * @returns {Promise<*>} - результат операции
 */
async function withLock(filePath, operation, options = {}) {
  const release = await acquireLock(filePath, options);
  try {
    return await operation();
  } finally {
    release();
  }
}

/**
 * Проверка состояния блокировки
 * @param {string} filePath
 * @returns {boolean}
 */
function isLocked(filePath) {
  const key = normalizePath(filePath);
  const entry = locks.get(key);
  return entry ? entry.locked : false;
}

/**
 * Получение информации о блокировке
 * @param {string} filePath
 * @returns {Object|null}
 */
function getLockInfo(filePath) {
  const key = normalizePath(filePath);
  const entry = locks.get(key);
  if (!entry || !entry.locked) return null;

  return {
    locked: entry.locked,
    queueLength: entry.queue.length,
    acquiredAt: entry.acquiredAt,
    holdTime: Date.now() - entry.acquiredAt
  };
}

/**
 * Очистка неиспользуемых блокировок
 */
function cleanupUnusedLocks() {
  for (const [key, entry] of locks.entries()) {
    if (!entry.locked && entry.queue.length === 0) {
      locks.delete(key);
    }
  }
}

/**
 * Принудительное освобождение всех блокировок (только для тестов/аварийных ситуаций)
 */
function forceReleaseAll() {
  console.warn('[FileLock] Force releasing all locks!');
  for (const [key, entry] of locks.entries()) {
    entry.locked = false;
    entry.queue.forEach(resolve => resolve());
    entry.queue = [];
  }
  locks.clear();
  stats.currentLocks = 0;
}

/**
 * Получение статистики
 * @returns {Object}
 */
function getStats() {
  return {
    ...stats,
    activeLocks: locks.size,
    avgWaitTime: stats.totalLocks > 0
      ? Math.round(stats.totalWaitTime / stats.totalLocks)
      : 0
  };
}

/**
 * Сброс статистики
 */
function resetStats() {
  stats.totalLocks = 0;
  stats.currentLocks = 0;
  stats.maxConcurrentLocks = 0;
  stats.totalWaitTime = 0;
  stats.lockTimeouts = 0;
}

module.exports = {
  acquireLock,
  releaseLock,
  withLock,
  isLocked,
  getLockInfo,
  getStats,
  resetStats,
  forceReleaseAll,
  // Константы для использования в других модулях
  DEFAULT_OPTIONS
};
