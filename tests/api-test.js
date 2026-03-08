/**
 * API Smoke & Structure Test — Arabica
 *
 * Уровень 1 (Smoke):     Каждый GET эндпоинт отвечает 200
 * Уровень 2 (Structure):  Ответ содержит ожидаемые поля
 *
 * Запуск:  node tests/api-test.js
 * С ключом: API_KEY=xxx node tests/api-test.js
 */

const https = require('https');
const http = require('http');

// ============================================
// КОНФИГУРАЦИЯ
// ============================================
const SERVER_URL = process.env.SERVER_URL || 'https://arabica26.ru';
const API_KEY = process.env.API_KEY || '58c4d46b9bb324d03c5d96781223821f3528c5efa4604090a8e95ac540173585';
const AUTH_TOKEN = process.env.AUTH_TOKEN || 'b20781bfd2837fc2b71941e7138dec26100db899afa1d6cbbfa907962810e812';
const TIMEOUT_MS = 20000; // 20s — сервер 2GB RAM, большие JSON
const CONCURRENT_LIMIT = 5; // Максимум параллельных запросов

// ============================================
// ОПРЕДЕЛЕНИЯ ТЕСТОВ
// ============================================
// Формат: { path, name, expectedFields?, expectedType? }
//   expectedFields: массив ключей которые должны быть в ответе (Level 2)
//   expectedType: 'array' | 'object' — тип верхнего уровня
const TESTS = [
  // =============================================
  // CORE — Системные
  // =============================================
  // auth/check-session — НЕ тестируем, эндпоинт не существует (см. ISSUES_FOUND C-01)
  { path: '/api/auth/device-approval-requests', name: 'Device approval requests (dev)', expectedType: 'object' },
  { path: '/api/auth/device-approval-status/0000000000', name: 'Device approval status (test)', expectedType: 'object' },

  // =============================================
  // EMPLOYEES — Сотрудники
  // =============================================
  { path: '/api/employees', name: 'Employees list', expectedFields: ['employees'], expectedType: 'object' },
  { path: '/api/employee-registrations', name: 'Employee registrations', expectedType: 'object' },
  { path: '/api/shop-managers/role/0000000000', name: 'Shop manager role (test)', expectedType: 'object' },

  // =============================================
  // SHOPS — Магазины
  // =============================================
  { path: '/api/shops', name: 'Shops list', expectedFields: ['shops'], expectedType: 'object' },
  { path: '/api/shop-settings/%D0%9B%D0%B5%D1%80%D0%BC%D0%BE%D0%BD%D1%82%D0%BE%D0%B2', name: 'Shop settings', expectedType: 'object' },
  { path: '/api/shop-coordinates', name: 'Shop coordinates', expectedType: 'object' },

  // =============================================
  // SHIFTS — Пересменки
  // =============================================
  { path: '/api/shift-reports', name: 'Shift reports', expectedFields: ['reports'], expectedType: 'object' },
  { path: '/api/shift-questions', name: 'Shift questions', expectedFields: ['questions'], expectedType: 'object' },
  { path: '/api/pending-shift-reports', name: 'Pending shift reports', expectedType: 'object' },

  // =============================================
  // ATTENDANCE — Посещаемость
  // =============================================
  { path: '/api/attendance', name: 'Attendance records', expectedType: 'object' },

  // =============================================
  // WORK SCHEDULE — Рабочий график
  // =============================================
  { path: '/api/work-schedule?month=2026-02', name: 'Work schedule (2026-02)', expectedType: 'object' },

  // =============================================
  // SHIFT HANDOVER — Передача смены
  // =============================================
  { path: '/api/shift-handover-reports', name: 'Shift handover reports', expectedFields: ['reports'], expectedType: 'object' },
  { path: '/api/shift-handover-questions', name: 'Shift handover questions', expectedType: 'object' },
  { path: '/api/pending-shift-handover-reports', name: 'Pending shift handover', expectedType: 'object' },

  // =============================================
  // RECOUNT — Пересчёт
  // =============================================
  { path: '/api/recount-reports', name: 'Recount reports', expectedFields: ['reports'], expectedType: 'object' },
  { path: '/api/recount-questions', name: 'Recount questions', expectedType: 'object' },
  { path: '/api/pending-recount-reports', name: 'Pending recount reports', expectedType: 'object' },

  // =============================================
  // ENVELOPE — Конверты
  // =============================================
  { path: '/api/envelope-reports', name: 'Envelope reports', expectedFields: ['reports'], expectedType: 'object' },
  { path: '/api/envelope-questions', name: 'Envelope questions', expectedType: 'object' },

  // =============================================
  // RKO — Расходно-кассовые ордера
  // =============================================
  { path: '/api/rko/all?month=2026-02', name: 'RKO all (2026-02)', expectedFields: ['success'], expectedType: 'object' },

  // =============================================
  // ORDERS — Заказы
  // =============================================
  { path: '/api/orders', name: 'Orders list', expectedFields: ['orders'], expectedType: 'object' },
  { path: '/api/orders/unviewed-count', name: 'Orders unviewed count', expectedType: 'object' },

  // =============================================
  // MENU — Меню
  // =============================================
  { path: '/api/menu', name: 'Menu items', expectedType: 'object' },

  // =============================================
  // RECIPES — Рецепты
  // =============================================
  { path: '/api/recipes', name: 'Recipes list', expectedType: 'object' },

  // =============================================
  // REVIEWS — Отзывы
  // =============================================
  { path: '/api/reviews', name: 'Reviews list', expectedType: 'object' },

  // =============================================
  // CLIENTS — Клиенты
  // =============================================
  { path: '/api/clients', name: 'Clients list', expectedType: 'object' },

  // =============================================
  // TRAINING — Обучение
  // =============================================
  { path: '/api/training-articles', name: 'Training articles', expectedType: 'object' },

  // =============================================
  // TESTS — Тестирование
  // =============================================
  { path: '/api/test-questions', name: 'Test questions', expectedType: 'object' },
  { path: '/api/test-results', name: 'Test results', expectedType: 'object' },
  { path: '/api/test-settings', name: 'Test settings', expectedType: 'object' },

  // =============================================
  // PRODUCT QUESTIONS — Вопросы по товарам
  // =============================================
  { path: '/api/product-questions', name: 'Product questions', expectedType: 'object' },

  // =============================================
  // TASKS — Задачи
  // =============================================
  { path: '/api/tasks', name: 'Tasks list', expectedFields: ['tasks'], expectedType: 'object' },
  { path: '/api/task-assignments', name: 'Task assignments', expectedType: 'object' },
  { path: '/api/recurring-tasks', name: 'Recurring tasks', expectedFields: ['tasks'], expectedType: 'object' },

  // =============================================
  // EFFICIENCY — Эффективность
  // =============================================
  { path: '/api/efficiency/reports-batch?month=2026-01', name: 'Efficiency batch', expectedType: 'object' },
  { path: '/api/efficiency-penalties?month=2026-01', name: 'Efficiency penalties', expectedType: 'object' },
  { path: '/api/points-settings/shift', name: 'Points settings (shift)', expectedType: 'object' },
  { path: '/api/points-settings/recount', name: 'Points settings (recount)', expectedType: 'object' },
  { path: '/api/points-settings/attendance', name: 'Points settings (attendance)', expectedType: 'object' },

  // =============================================
  // RATING & FORTUNE WHEEL
  // =============================================
  { path: '/api/ratings', name: 'Ratings', expectedType: 'object' },
  { path: '/api/fortune-wheel/settings', name: 'Fortune wheel settings', expectedType: 'object' },

  // =============================================
  // REFERRALS — Рефералы
  // =============================================
  { path: '/api/referrals/stats', name: 'Referral stats', expectedType: 'object' },

  // =============================================
  // JOB APPLICATIONS — Заявки на работу
  // =============================================
  { path: '/api/job-applications', name: 'Job applications', expectedType: 'object' },

  // =============================================
  // COFFEE MACHINE — Кофемашины
  // =============================================
  { path: '/api/coffee-machine/reports', name: 'Coffee machine reports', expectedFields: ['reports'], expectedType: 'object' },
  { path: '/api/coffee-machine/templates', name: 'Coffee machine templates', expectedType: 'object' },
  { path: '/api/coffee-machine/pending', name: 'Coffee machine pending', expectedType: 'array' },

  // =============================================
  // SUPPLIERS — Поставщики
  // =============================================
  { path: '/api/suppliers', name: 'Suppliers list', expectedType: 'object' },

  // =============================================
  // BONUS & WITHDRAWALS
  // =============================================
  { path: '/api/bonus-penalties', name: 'Bonus penalties', expectedType: 'object' },
  { path: '/api/withdrawals', name: 'Withdrawals list', expectedType: 'object' },

  // =============================================
  // LOYALTY & PROMO
  // =============================================
  { path: '/api/loyalty-promo', name: 'Loyalty promo', expectedType: 'object' },

  // =============================================
  // DASHBOARD
  // =============================================
  { path: '/api/dashboard/counters', name: 'Dashboard counters', expectedType: 'object' },

  // =============================================
  // GEOFENCE
  // =============================================
  { path: '/api/geofence-settings', name: 'Geofence settings', expectedType: 'object' },

  // =============================================
  // MASTER CATALOG
  // =============================================
  { path: '/api/master-catalog/for-training', name: 'Master catalog', expectedType: 'object' },

  // =============================================
  // Z-REPORT
  // =============================================
  { path: '/api/z-report/templates', name: 'Z-report templates', expectedType: 'object' },

  // =============================================
  // EXECUTION CHAIN
  // =============================================
  { path: '/api/execution-chain/config', name: 'Execution chain config', expectedType: 'object' },

  // =============================================================================
  // ==================== РАСШИРЕННЫЕ ТЕСТЫ (75+ эндпоинтов) ====================
  // =============================================================================

  // =============================================
  // HEALTH & SYSTEM — Здоровье сервера
  // =============================================
  // /health — доступен только внутри сервера (nginx не проксирует)
  { path: '/api/app-version', name: 'App version', expectedType: 'object' },
  { path: '/api/admin/data-stats', name: 'Admin data stats', expectedType: 'object' },
  { path: '/api/admin/disk-info', name: 'Admin disk info', expectedType: 'object' },

  // =============================================
  // SHOP MANAGERS — Управление магазинами
  // =============================================
  // /api/shop-managers/store-managers — требует роль developer (403 с тестовым токеном)

  // =============================================
  // MESSENGER — Мессенджер
  // =============================================
  { path: '/api/messenger/conversations?phone=79001234567', name: 'Messenger conversations', expectedType: 'object' },
  { path: '/api/messenger/contacts/search?query=test', name: 'Messenger contact search', expectedType: 'object' },
  { path: '/api/messenger/unread?phone=79001234567', name: 'Messenger unread count', expectedType: 'object' },
  { path: '/api/messenger/ice-config', name: 'Messenger ICE config (TURN/STUN)', expectedType: 'object' },
  // /api/messenger/profile — возвращает 404 если профиль не существует (ожидаемо для тестового телефона)

  // =============================================
  // EMPLOYEE CHAT — Чат сотрудников
  // =============================================
  { path: '/api/employee-chats?phone=79001234567', name: 'Employee chats list', expectedType: 'object' },
  { path: '/api/clients/list', name: 'Clients list (for chats)', expectedType: 'object' },

  // =============================================
  // SHIFT TRANSFERS — Подмена смен
  // =============================================
  { path: '/api/shift-transfers', name: 'Shift transfers all', expectedType: 'object' },
  { path: '/api/shift-transfers/admin', name: 'Shift transfers admin', expectedType: 'object' },
  { path: '/api/shift-transfers/admin/unread-count', name: 'Shift transfers admin unread', expectedType: 'object' },
  { path: '/api/shift-transfers/employee/test-emp', name: 'Shift transfers employee', expectedType: 'object' },
  { path: '/api/shift-transfers/employee/test-emp/outgoing', name: 'Shift transfers outgoing', expectedType: 'object' },
  { path: '/api/shift-transfers/employee/test-emp/unread-count', name: 'Shift transfers emp unread', expectedType: 'object' },

  // =============================================
  // PRODUCT QUESTIONS — Вопросы по товарам (доп.)
  // =============================================
  { path: '/api/product-questions/unanswered-count', name: 'Product questions unanswered', expectedType: 'object' },
  { path: '/api/product-question-dialogs/all', name: 'Product question dialogs all', expectedType: 'object' },
  { path: '/api/product-question-dialogs/unviewed-counts', name: 'Product question unviewed', expectedType: 'object' },

  // =============================================
  // SHOP PRODUCTS — Товары в магазинах
  // =============================================
  { path: '/api/shop-products/shops/list', name: 'Shop products shops list', expectedType: 'object' },
  { path: '/api/shop-products/stats', name: 'Shop products stats', expectedType: 'object' },
  { path: '/api/shop-products/api-keys', name: 'Shop products API keys', expectedType: 'object' },
  { path: '/api/shop-products-search?q=%D0%BA%D0%BE%D1%84%D0%B5', name: 'Shop products search', expectedType: 'object' },

  // =============================================
  // CIGARETTE VISION / AI — Распознавание товаров
  // =============================================
  { path: '/api/cigarette-vision/products', name: 'CV products list', expectedType: 'object' },
  { path: '/api/cigarette-vision/products/groups', name: 'CV product groups', expectedType: 'object' },
  { path: '/api/cigarette-vision/stats', name: 'CV training stats', expectedType: 'object' },
  { path: '/api/cigarette-vision/typed-stats', name: 'CV typed stats', expectedType: 'object' },
  { path: '/api/cigarette-vision/typed-stats/counting', name: 'CV typed stats counting', expectedType: 'object' },
  { path: '/api/cigarette-vision/model-status', name: 'CV model status', expectedType: 'object' },
  { path: '/api/cigarette-vision/settings', name: 'CV settings', expectedType: 'object' },
  { path: '/api/cigarette-vision/dataset-version', name: 'CV dataset version', expectedType: 'object' },
  { path: '/api/cigarette-vision/embedding-catalog/stats', name: 'CV embedding catalog stats', expectedType: 'object' },

  // =============================================
  // AI DASHBOARD — Панель AI
  // =============================================
  { path: '/api/ai-dashboard/metrics', name: 'AI dashboard metrics', expectedType: 'object' },
  { path: '/api/ai-dashboard/retrain-status', name: 'AI retrain status', expectedType: 'object' },
  { path: '/api/ai-dashboard/recount-train-status', name: 'AI recount train status', expectedType: 'object' },
  { path: '/api/ai-dashboard/recount-train-schedule', name: 'AI recount train schedule', expectedType: 'object' },

  // =============================================
  // SHIFT AI — AI верификация пересменок
  // =============================================
  { path: '/api/shift-ai/products', name: 'Shift AI products', expectedType: 'object' },
  { path: '/api/shift-ai/product-groups', name: 'Shift AI product groups', expectedType: 'object' },
  { path: '/api/shift-ai/model-status', name: 'Shift AI model status', expectedType: 'object' },
  { path: '/api/shift-ai/stats', name: 'Shift AI stats', expectedType: 'object' },

  // =============================================
  // REPORT NOTIFICATIONS — Уведомления об отчётах
  // =============================================
  { path: '/api/report-notifications', name: 'Report notifications', expectedType: 'object' },
  { path: '/api/report-notifications/unviewed-counts', name: 'Report notif unviewed', expectedType: 'object' },

  // =============================================
  // CLIENT DIALOGS — Диалоги с клиентами
  // =============================================
  { path: '/api/management-dialogs', name: 'Management dialogs', expectedType: 'object' },

  // =============================================
  // LOYALTY GAMIFICATION — Программа лояльности
  // =============================================
  { path: '/api/loyalty-gamification/settings', name: 'Loyalty gamification settings', expectedType: 'object' },
  { path: '/api/loyalty-gamification/wheel-history', name: 'Loyalty wheel history', expectedType: 'object' },
  { path: '/api/loyalty-gamification/client-prizes-report', name: 'Loyalty prizes report', expectedType: 'object' },

  // =============================================
  // LOYALTY WALLET — Кошелёк баллов (Фаза 1)
  // =============================================
  { path: '/api/loyalty/balance/79001234567', name: 'Loyalty wallet balance', expectedType: 'object' },
  { path: '/api/loyalty/transactions/79001234567', name: 'Loyalty wallet transactions', expectedType: 'object' },

  // =============================================
  // SHOP CATALOG — Каталог товаров магазина
  // =============================================
  { path: '/api/shop-catalog/groups', name: 'Shop catalog groups', expectedType: 'object' },
  { path: '/api/shop-catalog/products', name: 'Shop catalog products', expectedType: 'object' },
  { path: '/api/shop-catalog/authorized-employees', name: 'Shop catalog authorized employees', expectedType: 'object' },

  // =============================================
  // COFFEE MACHINE — Кофемашины (доп.)
  // =============================================
  { path: '/api/coffee-machine/failed', name: 'Coffee machine failed', expectedType: 'array' },
  { path: '/api/coffee-machine/intelligence', name: 'Coffee machine intelligence', expectedType: 'object' },
  { path: '/api/coffee-machine/training', name: 'Coffee machine training', expectedType: 'object' },
  { path: '/api/coffee-machine/training/stats', name: 'Coffee machine train stats', expectedType: 'object' },

  // =============================================
  // RECOUNT POINTS & SETTINGS — Баллы за пересчёт
  // =============================================
  { path: '/api/recount-points', name: 'Recount points', expectedType: 'object' },
  { path: '/api/recount-settings', name: 'Recount settings', expectedType: 'object' },

  // =============================================
  // MANAGER EFFICIENCY — Эффективность менеджера
  // =============================================
  // /api/manager-efficiency — требует реальный телефон менеджера (404 с тестовым)
  // /api/manager-efficiency/team-task-penalties — требует сессию менеджера (401 без неё)

  // =============================================
  // POINTS SETTINGS — Настройки баллов (доп.)
  // =============================================
  { path: '/api/points-settings/envelope', name: 'Points settings (envelope)', expectedType: 'object' },
  { path: '/api/points-settings/coffee-machine', name: 'Points settings (coffee)', expectedType: 'object' },
  { path: '/api/points-settings/orders', name: 'Points settings (orders)', expectedType: 'object' },
  { path: '/api/points-settings/product-search', name: 'Points settings (product-search)', expectedType: 'object' },
  { path: '/api/points-settings/recurring-tasks', name: 'Points settings (recurring)', expectedType: 'object' },
  { path: '/api/points-settings/referrals', name: 'Points settings (referrals)', expectedType: 'object' },
  { path: '/api/points-settings/regular-tasks', name: 'Points settings (regular)', expectedType: 'object' },
  { path: '/api/points-settings/reviews', name: 'Points settings (reviews)', expectedType: 'object' },
  { path: '/api/points-settings/rko', name: 'Points settings (rko)', expectedType: 'object' },
  { path: '/api/points-settings/shift-handover', name: 'Points settings (handover)', expectedType: 'object' },
  { path: '/api/points-settings/test', name: 'Points settings (test)', expectedType: 'object' },
  { path: '/api/points-settings/manager', name: 'Points settings (manager)', expectedType: 'object' },
  { path: '/api/points-settings/tasks', name: 'Points settings (tasks)', expectedType: 'object' },

  // =============================================
  // Z-REPORT — Z-отчёты (доп.)
  // =============================================
  { path: '/api/z-report/training-samples', name: 'Z-report training samples', expectedType: 'object' },
  { path: '/api/z-report/training-stats', name: 'Z-report training stats', expectedType: 'object' },
  { path: '/api/z-report/intelligence', name: 'Z-report intelligence', expectedType: 'object' },

  // =============================================
  // REFERRALS — Рефералы (доп.)
  // =============================================
  { path: '/api/referrals/unviewed-count', name: 'Referrals unviewed count', expectedType: 'object' },
  { path: '/api/referrals/unassigned', name: 'Referrals unassigned', expectedType: 'object' },

  // =============================================
  // MASTER CATALOG — Каталог товаров (доп.)
  // =============================================
  { path: '/api/master-catalog', name: 'Master catalog full', expectedType: 'object' },
  { path: '/api/master-catalog/groups/list', name: 'Master catalog groups', expectedType: 'object' },
  { path: '/api/master-catalog/stats', name: 'Master catalog stats', expectedType: 'object' },
  { path: '/api/master-catalog/pending-codes', name: 'Master catalog pending', expectedType: 'object' },

  // =============================================
  // RKO — РКО (доп.)
  // =============================================
  { path: '/api/rko/pending', name: 'RKO pending', expectedType: 'object' },
  { path: '/api/rko/failed', name: 'RKO failed', expectedType: 'object' },

  // =============================================
  // ENVELOPE — Конверты (доп.)
  // =============================================
  { path: '/api/envelope-pending', name: 'Envelope pending', expectedType: 'array' },
  { path: '/api/envelope-failed', name: 'Envelope failed', expectedType: 'array' },

  // =============================================
  // ATTENDANCE — Посещаемость (доп.)
  // =============================================
  { path: '/api/attendance/pending', name: 'Attendance pending', expectedType: 'object' },
  { path: '/api/attendance/failed', name: 'Attendance failed', expectedType: 'object' },

  // =============================================
  // SHIFT HANDOVER — Передача смены (доп.)
  // =============================================
  { path: '/api/shift-handover/pending', name: 'Shift handover pending', expectedType: 'object' },
  { path: '/api/shift-handover/failed', name: 'Shift handover failed', expectedType: 'object' },

  // =============================================
  // JOB APPLICATIONS — Заявки (доп.)
  // =============================================
  { path: '/api/job-applications/unviewed-count', name: 'Job apps unviewed count', expectedType: 'object' },
];


// ============================================
// HTTP КЛИЕНТ
// ============================================
function makeRequest(urlPath) {
  return new Promise((resolve, reject) => {
    const fullUrl = SERVER_URL + urlPath;
    const parsed = new URL(fullUrl);
    const client = parsed.protocol === 'https:' ? https : http;

    const options = {
      hostname: parsed.hostname,
      port: parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
      path: parsed.pathname + parsed.search,
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-API-Key': API_KEY,
        'Authorization': `Bearer ${AUTH_TOKEN}`,
      },
      timeout: TIMEOUT_MS,
    };

    const req = client.request(options, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        resolve({
          status: res.statusCode,
          headers: res.headers,
          body: data,
        });
      });
    });

    req.on('timeout', () => {
      req.destroy();
      reject(new Error('TIMEOUT'));
    });

    req.on('error', (err) => {
      reject(err);
    });

    req.end();
  });
}


// ============================================
// ТЕСТОВЫЙ RUNNER
// ============================================
async function runTest(test) {
  const result = {
    name: test.name,
    path: test.path,
    smokePass: false,
    structurePass: false,
    status: null,
    error: null,
    responseType: null,
    missingFields: [],
  };

  try {
    const response = await makeRequest(test.path);
    result.status = response.status;

    // ---- Level 1: Smoke (status 200) ----
    if (response.status === 200) {
      result.smokePass = true;
    } else {
      result.error = `HTTP ${response.status}`;
      return result;
    }

    // ---- Level 2: Structure ----
    let parsed;
    try {
      parsed = JSON.parse(response.body);
    } catch (e) {
      result.error = 'Invalid JSON';
      return result;
    }

    // Проверяем тип ответа
    const actualType = Array.isArray(parsed) ? 'array' : typeof parsed;
    result.responseType = actualType;

    if (test.expectedType) {
      if (test.expectedType === 'array' && !Array.isArray(parsed)) {
        result.error = `Expected array, got ${actualType}`;
        return result;
      }
      if (test.expectedType === 'object' && (Array.isArray(parsed) || typeof parsed !== 'object')) {
        result.error = `Expected object, got ${actualType}`;
        return result;
      }
    }

    // Проверяем обязательные поля
    if (test.expectedFields && !Array.isArray(parsed)) {
      const missing = test.expectedFields.filter(f => !(f in parsed));
      result.missingFields = missing;
      if (missing.length > 0) {
        result.error = `Missing fields: ${missing.join(', ')}`;
        return result;
      }
    }

    result.structurePass = true;

  } catch (err) {
    result.error = err.message || String(err);
  }

  return result;
}

// Запуск с ограничением параллельности
async function runWithConcurrency(tests, limit) {
  const results = [];
  let index = 0;

  async function worker() {
    while (index < tests.length) {
      const i = index++;
      results[i] = await runTest(tests[i]);
    }
  }

  const workers = Array.from({ length: Math.min(limit, tests.length) }, () => worker());
  await Promise.all(workers);
  return results;
}


// ============================================
// ОТЧЁТ
// ============================================
function printReport(results) {
  const total = results.length;
  const smokePass = results.filter(r => r.smokePass).length;
  const smokeFail = total - smokePass;
  const structPass = results.filter(r => r.structurePass).length;
  const structFail = results.filter(r => r.smokePass && !r.structurePass).length;

  console.log('\n' + '='.repeat(70));
  console.log('  API TEST REPORT — Arabica');
  console.log('  ' + new Date().toISOString());
  console.log('='.repeat(70));

  // Smoke results
  console.log(`\n--- Level 1: SMOKE (HTTP 200) ---`);
  console.log(`  PASS: ${smokePass}/${total}   FAIL: ${smokeFail}/${total}`);

  if (smokeFail > 0) {
    console.log('\n  FAILED:');
    results.filter(r => !r.smokePass).forEach(r => {
      console.log(`  [FAIL] ${r.name}`);
      console.log(`         ${r.path} -> ${r.error}`);
    });
  }

  // Structure results
  console.log(`\n--- Level 2: STRUCTURE (correct fields) ---`);
  console.log(`  PASS: ${structPass}/${total}   FAIL: ${structFail}/${total}   SKIP: ${smokeFail}/${total}`);

  if (structFail > 0) {
    console.log('\n  FAILED:');
    results.filter(r => r.smokePass && !r.structurePass).forEach(r => {
      console.log(`  [FAIL] ${r.name}`);
      console.log(`         ${r.path} -> ${r.error}`);
    });
  }

  // Summary
  console.log('\n' + '='.repeat(70));
  const allPass = smokeFail === 0 && structFail === 0;
  if (allPass) {
    console.log('  RESULT: ALL TESTS PASSED');
  } else {
    console.log(`  RESULT: ${smokeFail + structFail} FAILURES`);
  }
  console.log('='.repeat(70) + '\n');

  // Full table
  console.log('--- Full Results ---');
  console.log(`${'Endpoint'.padEnd(45)} ${'Smoke'.padEnd(7)} ${'Struct'.padEnd(7)} ${'Status'.padEnd(7)} Error`);
  console.log('-'.repeat(90));
  results.forEach(r => {
    const smoke = r.smokePass ? 'OK' : 'FAIL';
    const struct = r.structurePass ? 'OK' : (r.smokePass ? 'FAIL' : 'SKIP');
    const status = r.status || '-';
    const error = r.error || '';
    console.log(`${r.name.padEnd(45)} ${smoke.padEnd(7)} ${struct.padEnd(7)} ${String(status).padEnd(7)} ${error}`);
  });

  return allPass;
}


// ============================================
// MAIN
// ============================================
async function main() {
  console.log(`Testing ${TESTS.length} endpoints on ${SERVER_URL}...`);
  console.log(`API Key: ${API_KEY.substring(0, 8)}...`);
  console.log(`Concurrency: ${CONCURRENT_LIMIT}\n`);

  const startTime = Date.now();
  const results = await runWithConcurrency(TESTS, CONCURRENT_LIMIT);
  const duration = ((Date.now() - startTime) / 1000).toFixed(1);

  console.log(`\nCompleted in ${duration}s`);

  const allPass = printReport(results);
  process.exit(allPass ? 0 : 1);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(2);
});
