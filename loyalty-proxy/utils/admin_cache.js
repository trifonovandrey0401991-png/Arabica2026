/**
 * Admin Cache Utility
 * Кэширование проверки isAdmin для предотвращения повторного чтения файлов
 *
 * SCALABILITY: Без кэша каждый запрос сканирует ВСЕ файлы сотрудников.
 * При 5000 сотрудниках и 100 запросах/сек = 500,000 file reads/sec
 * С кэшем = 0 file reads (после первой загрузки)
 */

const fs = require('fs');
const path = require('path');

const EMPLOYEES_DIR = '/var/www/employees';

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
 * Проверить, является ли телефон админом (с кэшированием)
 * @param {string} phone - Телефон для проверки
 * @returns {boolean} - true если админ
 */
function isAdminPhone(phone) {
  if (!phone) return false;

  const normalizedPhone = normalizePhone(phone);
  const now = Date.now();

  // Проверяем кэш
  const cached = adminCache.get(normalizedPhone);
  if (cached && (now - cached.cachedAt) < CACHE_TTL_MS) {
    return cached.isAdmin;
  }

  // Кэш промах - читаем с диска
  const isAdmin = checkAdminFromDisk(normalizedPhone);

  // Сохраняем в кэш
  adminCache.set(normalizedPhone, {
    isAdmin,
    cachedAt: now
  });

  return isAdmin;
}

/**
 * Async версия isAdminPhone (для совместимости с employee_chat_api)
 */
async function isAdminPhoneAsync(phone) {
  return isAdminPhone(phone);
}

/**
 * Проверка админа через чтение файла с диска
 */
function checkAdminFromDisk(normalizedPhone) {
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) return false;

    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8');
        const employee = JSON.parse(content);
        const empPhone = normalizePhone(employee.phone);

        if (empPhone === normalizedPhone) {
          return employee.isAdmin === true;
        }
      } catch (e) { /* skip invalid files */ }
    }
  } catch (e) {
    console.error('[AdminCache] Error checking admin from disk:', e);
  }

  return false;
}

/**
 * Предзагрузка всех админов в кэш (вызывать при старте сервера)
 * SCALABILITY: Загружает всё ОДИН раз, а не при каждом запросе
 */
function preloadAdminCache() {
  console.log('[AdminCache] Preloading admin cache...');
  const startTime = Date.now();

  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) {
      console.log('[AdminCache] Employees directory not found');
      return;
    }

    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));
    const now = Date.now();
    let adminCount = 0;
    let totalCount = 0;

    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8');
        const employee = JSON.parse(content);
        const empPhone = normalizePhone(employee.phone);

        if (empPhone) {
          adminCache.set(empPhone, {
            isAdmin: employee.isAdmin === true,
            cachedAt: now
          });
          totalCount++;
          if (employee.isAdmin) adminCount++;
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
  invalidateCache,
  clearCache,
  getCacheStats,
  normalizePhone
};
