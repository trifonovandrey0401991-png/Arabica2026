/**
 * Admin Cache Utility
 * Кэширование проверки isAdmin/developer/isManager для предотвращения повторного чтения файлов
 *
 * SCALABILITY: Без кэша каждый запрос сканирует ВСЕ файлы сотрудников.
 * При 5000 сотрудниках и 100 запросах/сек = 500,000 file reads/sec
 * С кэшем = 0 file reads (после первой загрузки)
 *
 * NOTE: Developer role имеет те же права что и admin
 * NOTE: Управляющие (managers) из shop-managers имеют отдельный флаг isManager (2026-03-03)
 *       isManager НЕ даёт полный admin доступ — только к тем модулям, где это явно разрешено
 */

const fs = require('fs');
const fsp = fs.promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const SHOP_MANAGERS_FILE = `${DATA_DIR}/shop-managers.json`;

// ============================================
// ADMIN CACHE
// ============================================

// Кэш: phone -> { isAdmin: boolean, isManager: boolean, cachedAt: timestamp }
const adminCache = new Map();

// TTL кэша: 5 минут (сотрудники редко меняют статус)
const CACHE_TTL_MS = 5 * 60 * 1000;

// Флаг для предзагрузки
let preloadComplete = false;

/**
 * Нормализация телефона для консистентного ключа кэша
 * M-11: Унифицировано — только цифры (как sanitizePhone в file_helpers)
 */
function normalizePhone(phone) {
  if (!phone) return '';
  return phone.replace(/[^\d]/g, '');
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
 * Проверить, является ли телефон управляющим (чистый cache lookup, без I/O)
 * Управляющие — это managers из shop-managers, у них ограниченные админ-права
 * @param {string} phone - Телефон для проверки
 * @returns {boolean} - true если управляющий
 */
function isManagerPhone(phone) {
  if (!phone) return false;
  const normalizedPhone = normalizePhone(phone);
  const cached = adminCache.get(normalizedPhone);
  return cached ? cached.isManager : false;
}

/**
 * Async версия isAdminPhone (для совместимости с employee_chat_api)
 */
async function isAdminPhoneAsync(phone) {
  return isAdminPhone(phone);
}

/**
 * Async предзагрузка всех админов и управляющих в кэш
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

    // Регистрируем всех сотрудников (без прав — роли берутся ТОЛЬКО из shop-managers)
    for (const file of files) {
      try {
        const content = await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
        const employee = JSON.parse(content);
        const empPhone = normalizePhone(employee.phone);

        if (empPhone) {
          adminCache.set(empPhone, {
            isAdmin: false,
            isManager: false,
            cachedAt: now
          });
          totalCount++;
        }
      } catch (e) { /* skip */ }
    }

    // Роли берутся ТОЛЬКО из shop-managers:
    // Разработчики (developers) → isAdmin=true
    // Управляющие (managers) → isAdmin=true (полный доступ к своим магазинам)
    // Заведующие (storeManagers) → isManager=true
    let managerCount = 0;
    let storeManagerCount = 0;
    try {
      let shopManagersData = null;

      if (process.env.USE_DB_SHOP_MANAGERS === 'true') {
        try {
          const db = require('./db');
          const row = await db.findById('app_settings', 'shop_managers', 'key');
          if (row && row.data) shopManagersData = row.data;
        } catch (dbErr) {
          console.error('[AdminCache] DB shop-managers read error:', dbErr.message);
        }
      }

      // Fallback на файл
      if (!shopManagersData) {
        try {
          await fsp.access(SHOP_MANAGERS_FILE);
          const content = await fsp.readFile(SHOP_MANAGERS_FILE, 'utf8');
          shopManagersData = JSON.parse(content);
        } catch (fileErr) { /* file not found — ok */ }
      }

      if (shopManagersData) {
        // Разработчики из shop-managers → isAdmin
        if (Array.isArray(shopManagersData.developers)) {
          for (const devPhone of shopManagersData.developers) {
            const normalized = normalizePhone(devPhone);
            if (normalized) {
              const existing = adminCache.get(normalized);
              if (!existing || !existing.isAdmin) {
                adminCache.set(normalized, {
                  isAdmin: true,
                  isManager: existing?.isManager || false,
                  cachedAt: now
                });
                adminCount++;
              }
            }
          }
        }

        // Управляющие (managers) → isAdmin=true (полный доступ к своим магазинам)
        if (Array.isArray(shopManagersData.managers)) {
          for (const manager of shopManagersData.managers) {
            const normalized = normalizePhone(manager.phone);
            if (normalized) {
              adminCache.set(normalized, {
                isAdmin: true,
                isManager: true,
                cachedAt: now
              });
              managerCount++;
            }
          }
        }

        // Заведующие (storeManagers) → isManager=true (ограниченные права)
        if (Array.isArray(shopManagersData.storeManagers)) {
          for (const sm of shopManagersData.storeManagers) {
            const smPhone = normalizePhone(sm.phone);
            if (smPhone) {
              const existing = adminCache.get(smPhone);
              adminCache.set(smPhone, {
                isAdmin: existing?.isAdmin || false,
                isManager: true,
                cachedAt: now
              });
              storeManagerCount++;
            }
          }
        }
      }
    } catch (smErr) {
      console.error('[AdminCache] Shop-managers preload error:', smErr.message);
    }

    preloadComplete = true;
    const elapsed = Date.now() - startTime;
    console.log(`[AdminCache] Preloaded ${totalCount} employees (${adminCount} admins, ${managerCount} managers, ${storeManagerCount} storeManagers) in ${elapsed}ms`);
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
  isManagerPhone,
  preloadAdminCache,
  startPeriodicRebuild,
  invalidateCache,
  clearCache,
  getCacheStats,
  normalizePhone
};
