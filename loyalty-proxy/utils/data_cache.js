/**
 * Data Cache Utility
 * Кэширование полных данных employees и shops в памяти
 *
 * SCALABILITY: Без кэша каждый GET /api/employees сканирует ВСЕ файлы.
 * При 100 сотрудниках и 50 запросах/мин = 5000 file reads/мин
 * С кэшем = 0 file reads (между ребилдами)
 *
 * Стратегия:
 * - Preload при старте сервера
 * - Periodic rebuild каждые 5 минут (safety net)
 * - Invalidation при CRUD операциях (мгновенное обновление)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const SHOPS_DIR = `${DATA_DIR}/shops`;

const CACHE_TTL_MS = 5 * 60 * 1000; // 5 минут

// ============================================
// IN-MEMORY CACHES
// ============================================

let employeesCache = null; // Array<Object> | null
let shopsCache = null;     // Array<Object> | null

// ============================================
// LOAD FUNCTIONS
// ============================================

/**
 * Загрузить всех сотрудников с диска в кэш
 */
async function loadEmployees() {
  const startTime = Date.now();
  try {
    try {
      await fsp.access(EMPLOYEES_DIR);
    } catch (e) {
      employeesCache = [];
      return;
    }

    const allFiles = await fsp.readdir(EMPLOYEES_DIR);
    const files = allFiles.filter(f => f.endsWith('.json'));
    const employees = [];

    for (const file of files) {
      try {
        const content = await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
        employees.push(JSON.parse(content));
      } catch (e) { /* skip corrupted files */ }
    }

    employeesCache = employees;
    const elapsed = Date.now() - startTime;
    console.log(`[DataCache] Loaded ${employees.length} employees in ${elapsed}ms`);
  } catch (e) {
    console.error('[DataCache] Error loading employees:', e.message);
  }
}

/**
 * Загрузить все магазины с диска в кэш
 */
async function loadShops() {
  const startTime = Date.now();
  try {
    try {
      await fsp.access(SHOPS_DIR);
    } catch (e) {
      shopsCache = [];
      return;
    }

    const allFiles = await fsp.readdir(SHOPS_DIR);
    const files = allFiles.filter(f => f.endsWith('.json'));
    const shops = [];

    for (const file of files) {
      try {
        const content = await fsp.readFile(path.join(SHOPS_DIR, file), 'utf8');
        shops.push(JSON.parse(content));
      } catch (e) { /* skip corrupted files */ }
    }

    shopsCache = shops;
    const elapsed = Date.now() - startTime;
    console.log(`[DataCache] Loaded ${shops.length} shops in ${elapsed}ms`);
  } catch (e) {
    console.error('[DataCache] Error loading shops:', e.message);
  }
}

// ============================================
// PUBLIC API
// ============================================

/**
 * Получить кэшированных сотрудников (копия массива для безопасности)
 * @returns {Array} - массив сотрудников
 */
function getEmployees() {
  if (!employeesCache) return null;
  return [...employeesCache];
}

/**
 * Получить кэшированные магазины (копия массива для безопасности)
 * @returns {Array} - массив магазинов
 */
function getShops() {
  if (!shopsCache) return null;
  return [...shopsCache];
}

/**
 * Инвалидировать кэш сотрудников и перезагрузить
 */
function invalidateEmployees() {
  employeesCache = null;
  loadEmployees().catch(e => {
    console.error('[DataCache] Error reloading employees:', e.message);
  });
}

/**
 * Инвалидировать кэш магазинов и перезагрузить
 */
function invalidateShops() {
  shopsCache = null;
  loadShops().catch(e => {
    console.error('[DataCache] Error reloading shops:', e.message);
  });
}

/**
 * Предзагрузка обоих кэшей при старте
 */
async function preload() {
  await Promise.all([loadEmployees(), loadShops()]);
}

/**
 * Запустить периодическое обновление кэшей
 */
function startPeriodicRebuild() {
  setInterval(() => {
    Promise.all([loadEmployees(), loadShops()]).catch(e => {
      console.error('[DataCache] Periodic rebuild error:', e.message);
    });
  }, CACHE_TTL_MS);
}

/**
 * Статистика кэша
 */
function getCacheStats() {
  return {
    employees: employeesCache ? employeesCache.length : 0,
    shops: shopsCache ? shopsCache.length : 0,
    employeesLoaded: employeesCache !== null,
    shopsLoaded: shopsCache !== null
  };
}

module.exports = {
  getEmployees,
  getShops,
  invalidateEmployees,
  invalidateShops,
  preload,
  startPeriodicRebuild,
  getCacheStats
};
