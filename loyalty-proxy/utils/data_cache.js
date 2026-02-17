/**
 * Data Cache Utility
 * Кэширование данных employees, shops, points_settings, shift_handover_questions
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
const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;
const SHIFT_HANDOVER_QUESTIONS_DIR = `${DATA_DIR}/shift-handover-questions`;

const CACHE_TTL_MS = 5 * 60 * 1000; // 5 минут

// ============================================
// IN-MEMORY CACHES
// ============================================

let employeesCache = null;              // Array<Object> | null
let shopsCache = null;                  // Array<Object> | null
let pointsSettingsCache = null;         // Map<string, Object> | null
let shiftHandoverQuestionsCache = null; // Array<Object> | null

// ============================================
// LOAD FUNCTIONS
// ============================================

/**
 * Загрузить все JSON-файлы из директории
 * @param {string} dir - путь к директории
 * @returns {Array<Object>}
 */
async function loadJsonDir(dir) {
  try {
    await fsp.access(dir);
  } catch (e) {
    return [];
  }

  const allFiles = await fsp.readdir(dir);
  const files = allFiles.filter(f => f.endsWith('.json'));
  const items = [];

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(dir, file), 'utf8');
      items.push(JSON.parse(content));
    } catch (e) { /* skip corrupted files */ }
  }

  return items;
}

/**
 * Загрузить всех сотрудников с диска в кэш
 */
async function loadEmployees() {
  const startTime = Date.now();
  try {
    employeesCache = await loadJsonDir(EMPLOYEES_DIR);
    const elapsed = Date.now() - startTime;
    console.log(`[DataCache] Loaded ${employeesCache.length} employees in ${elapsed}ms`);
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
    shopsCache = await loadJsonDir(SHOPS_DIR);
    const elapsed = Date.now() - startTime;
    console.log(`[DataCache] Loaded ${shopsCache.length} shops in ${elapsed}ms`);
  } catch (e) {
    console.error('[DataCache] Error loading shops:', e.message);
  }
}

/**
 * Загрузить все настройки баллов в кэш (filename → settings)
 */
async function loadPointsSettings() {
  const startTime = Date.now();
  try {
    try {
      await fsp.access(POINTS_SETTINGS_DIR);
    } catch (e) {
      pointsSettingsCache = new Map();
      return;
    }

    const allFiles = await fsp.readdir(POINTS_SETTINGS_DIR);
    const files = allFiles.filter(f => f.endsWith('.json'));
    const cache = new Map();

    for (const file of files) {
      try {
        const content = await fsp.readFile(path.join(POINTS_SETTINGS_DIR, file), 'utf8');
        const key = file.replace('.json', '');
        cache.set(key, JSON.parse(content));
      } catch (e) { /* skip corrupted files */ }
    }

    pointsSettingsCache = cache;
    const elapsed = Date.now() - startTime;
    console.log(`[DataCache] Loaded ${cache.size} points_settings in ${elapsed}ms`);
  } catch (e) {
    console.error('[DataCache] Error loading points_settings:', e.message);
  }
}

/**
 * Загрузить шаблоны вопросов сдачи смены в кэш
 */
async function loadShiftHandoverQuestions() {
  const startTime = Date.now();
  try {
    shiftHandoverQuestionsCache = await loadJsonDir(SHIFT_HANDOVER_QUESTIONS_DIR);
    const elapsed = Date.now() - startTime;
    console.log(`[DataCache] Loaded ${shiftHandoverQuestionsCache.length} shift_handover_questions in ${elapsed}ms`);
  } catch (e) {
    console.error('[DataCache] Error loading shift_handover_questions:', e.message);
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
 * Получить настройки баллов по ключу
 * @param {string} key - ключ (filename без .json, напр. 'test_points_settings')
 * @returns {Object|null}
 */
function getPointsSettings(key) {
  if (!pointsSettingsCache) return null;
  const data = pointsSettingsCache.get(key);
  return data ? { ...data } : null;
}

/**
 * Получить все настройки баллов
 * @returns {Map|null}
 */
function getAllPointsSettings() {
  if (!pointsSettingsCache) return null;
  return new Map(pointsSettingsCache);
}

/**
 * Получить кэшированные вопросы сдачи смены
 * @returns {Array|null}
 */
function getShiftHandoverQuestions() {
  if (!shiftHandoverQuestionsCache) return null;
  return [...shiftHandoverQuestionsCache];
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
 * Инвалидировать кэш настроек баллов и перезагрузить
 */
function invalidatePointsSettings() {
  pointsSettingsCache = null;
  loadPointsSettings().catch(e => {
    console.error('[DataCache] Error reloading points_settings:', e.message);
  });
}

/**
 * Инвалидировать кэш вопросов сдачи смены и перезагрузить
 */
function invalidateShiftHandoverQuestions() {
  shiftHandoverQuestionsCache = null;
  loadShiftHandoverQuestions().catch(e => {
    console.error('[DataCache] Error reloading shift_handover_questions:', e.message);
  });
}

/**
 * Предзагрузка всех кэшей при старте
 */
async function preload() {
  await Promise.all([
    loadEmployees(),
    loadShops(),
    loadPointsSettings(),
    loadShiftHandoverQuestions()
  ]);
}

/**
 * Запустить периодическое обновление кэшей
 */
function startPeriodicRebuild() {
  setInterval(() => {
    Promise.all([
      loadEmployees(),
      loadShops(),
      loadPointsSettings(),
      loadShiftHandoverQuestions()
    ]).catch(e => {
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
    pointsSettings: pointsSettingsCache ? pointsSettingsCache.size : 0,
    shiftHandoverQuestions: shiftHandoverQuestionsCache ? shiftHandoverQuestionsCache.length : 0,
    employeesLoaded: employeesCache !== null,
    shopsLoaded: shopsCache !== null,
    pointsSettingsLoaded: pointsSettingsCache !== null,
    shiftHandoverQuestionsLoaded: shiftHandoverQuestionsCache !== null
  };
}

module.exports = {
  getEmployees,
  getShops,
  getPointsSettings,
  getAllPointsSettings,
  getShiftHandoverQuestions,
  invalidateEmployees,
  invalidateShops,
  invalidatePointsSettings,
  invalidateShiftHandoverQuestions,
  preload,
  startPeriodicRebuild,
  getCacheStats
};
