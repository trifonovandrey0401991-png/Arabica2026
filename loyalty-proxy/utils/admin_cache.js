/**
 * Admin Cache Utility
 * Кэширование проверки isAdmin/developer для предотвращения повторного чтения файлов
 *
 * SCALABILITY: Без кэша каждый запрос сканирует ВСЕ файлы сотрудников.
 * При 5000 сотрудниках и 100 запросах/сек = 500,000 file reads/sec
 * С кэшем = 0 file reads (после первой загрузки)
 *
 * NOTE: Developer role имеет те же права что и admin
 */

const fs = require('fs');
const fsp = fs.promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// ============================================
// ADMIN CACHE
// ============================================

// Кэш: phone -> { isAdmin: boolean, cachedAt: timestamp }
const adminCache = new Map();

// TTL кэша: 5 минут (сотрудники редко меняют статус)
const CACHE_TTL_MS = 5 * 60 * 1000;

// Флаг для предзагрузки
let preloadComplete = false;

/**
 * Нормализация телефона для консистентного ключа кэша
 */
function normalizePhone(phone) {
  if (!phone) return '';
  return phone.replace(/[\s+]/g, '');
}

/**
 * Проверить, является ли телефон админом (чистый cache lookup, без I/O)
 * Кэш обновляется асинхронно каждые 5 минут
 * @param {string} phone - Телефон для проверки
 * @returns {boolean} - true если админ
 */
function isAdminPhone(phone) {
  if (!phone) return false;
  const normalizedPhone = normalizePhone(phone);
  const cached = adminCache.get(normalizedPhone);
  return cached ? cached.isAdmin : false;
}

/**
 * Async версия isAdminPhone (для совместимости с employee_chat_api)
 */
async function isAdminPhoneAsync(phone) {
  return isAdminPhone(phone);
}

/**
 * Async предзагрузка всех админов в кэш
 * Не блокирует event loop (используется fsp.readdir/readFile)
 */
async function preloadAdminCache() {
  const startTime = Date.now();

  try {
    try {
      await fsp.access(EMPLOYEES_DIR);
    } catch (e) {
      console.log('[AdminCache] Employees directory not found');
      return;
    }

    const allFiles = await fsp.readdir(EMPLOYEES_DIR);
    const files = allFiles.filter(f => f.endsWith('.json'));
    const now = Date.now();
    let adminCount = 0;
    let totalCount = 0;

    for (const file of files) {
      try {
        const content = await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
        const employee = JSON.parse(content);
        const empPhone = normalizePhone(employee.phone);

        if (empPhone) {
          const hasAdminRights = employee.isAdmin === true || employee.role === 'developer';
          adminCache.set(empPhone, {
            isAdmin: hasAdminRights,
            cachedAt: now
          });
          totalCount++;
          if (hasAdminRights) adminCount++;
        }
      } catch (e) { /* skip */ }
    }

    preloadComplete = true;
    const elapsed = Date.now() - startTime;
    console.log(`[AdminCache] Preloaded ${totalCount} employees (${adminCount} admins) in ${elapsed}ms`);
  } catch (e) {
    console.error('[AdminCache] Preload error:', e);
  }
}

/**
 * Запустить периодическое обновление кэша (каждые 5 минут)
 */
function startPeriodicRebuild() {
  setInterval(() => {
    preloadAdminCache().catch(e => {
      console.error('[AdminCache] Periodic rebuild error:', e.message);
    });
  }, CACHE_TTL_MS);
}

/**
 * Инвалидировать кэш для конкретного телефона
 * Вызывать при обновлении сотрудника
 */
function invalidateCache(phone) {
  if (!phone) return;
  const normalizedPhone = normalizePhone(phone);
  adminCache.delete(normalizedPhone);
  console.log(`[AdminCache] Invalidated cache for: ${normalizedPhone}`);
}

/**
 * Очистить весь кэш
 */
function clearCache() {
  adminCache.clear();
  preloadComplete = false;
  console.log('[AdminCache] Cache cleared');
}

/**
 * Получить статистику кэша
 */
function getCacheStats() {
  return {
    size: adminCache.size,
    preloadComplete,
    ttlMs: CACHE_TTL_MS
  };
}

module.exports = {
  isAdminPhone,
  isAdminPhoneAsync,
  preloadAdminCache,
  startPeriodicRebuild,
  invalidateCache,
  clearCache,
  getCacheStats,
  normalizePhone
};
