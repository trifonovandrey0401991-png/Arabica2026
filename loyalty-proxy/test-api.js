/**
 * API Health Check Script
 *
 * Тестирует все основные API endpoints.
 * Запуск: node test-api.js [base_url]
 *
 * Примеры:
 *   node test-api.js                          # localhost:3000
 *   node test-api.js http://arabica26.ru:3000 # production
 */

const http = require('http');
const https = require('https');

const BASE_URL = process.argv[2] || 'http://localhost:3000';

// Список endpoints для тестирования
const ENDPOINTS = [
  // Магазины
  { method: 'GET', path: '/api/shops', name: 'Shops list' },

  // Сотрудники
  { method: 'GET', path: '/api/employees', name: 'Employees list' },

  // Меню
  { method: 'GET', path: '/api/menu', name: 'Menu items' },

  // Рецепты
  { method: 'GET', path: '/api/recipes', name: 'Recipes' },

  // Настройки баллов
  { method: 'GET', path: '/api/points-settings/shift', name: 'Shift points settings' },
  { method: 'GET', path: '/api/points-settings/recount', name: 'Recount points settings' },
  { method: 'GET', path: '/api/points-settings/envelope', name: 'Envelope points settings' },

  // Заказы
  { method: 'GET', path: '/api/orders', name: 'Orders list' },

  // Задачи
  { method: 'GET', path: '/api/tasks', name: 'Tasks list' },

  // Рейтинг
  { method: 'GET', path: '/api/ratings?month=2026-01', name: 'Ratings' },

  // Колесо удачи
  { method: 'GET', path: '/api/fortune-wheel/settings', name: 'Fortune wheel settings' },

  // Геофенсинг
  { method: 'GET', path: '/api/geofence-settings', name: 'Geofence settings' },

  // Лояльность
  { method: 'GET', path: '/api/loyalty-promo', name: 'Loyalty promo' },

  // Обучение
  { method: 'GET', path: '/api/training-articles', name: 'Training articles' },

  // Тесты
  { method: 'GET', path: '/api/test-questions', name: 'Test questions' },

  // Поставщики
  { method: 'GET', path: '/api/suppliers', name: 'Suppliers' },

  // Чат сотрудников
  { method: 'GET', path: '/api/employee-chat-groups', name: 'Chat groups' },

  // Рефералы
  { method: 'GET', path: '/api/referral-stats', name: 'Referral stats' },

  // Заявки на работу
  { method: 'GET', path: '/api/job-applications', name: 'Job applications' },

  // Посещаемость
  { method: 'GET', path: '/api/attendance', name: 'Attendance' },

  // Пересменки
  { method: 'GET', path: '/api/shift-reports', name: 'Shift reports' },

  // Пересчёты
  { method: 'GET', path: '/api/recount-reports', name: 'Recount reports' },

  // Конверты
  { method: 'GET', path: '/api/envelope-reports', name: 'Envelope reports' },

  // РКО
  { method: 'GET', path: '/api/rko-reports', name: 'RKO reports' },

  // Мастер-каталог
  { method: 'GET', path: '/api/master-catalog', name: 'Master catalog' },
];

// Статистика
let stats = {
  total: ENDPOINTS.length,
  passed: 0,
  failed: 0,
  errors: []
};

function makeRequest(endpoint) {
  return new Promise((resolve) => {
    const url = new URL(endpoint.path, BASE_URL);
    const protocol = url.protocol === 'https:' ? https : http;

    const startTime = Date.now();

    const req = protocol.request(url, {
      method: endpoint.method,
      timeout: 10000
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const duration = Date.now() - startTime;
        const success = res.statusCode >= 200 && res.statusCode < 400;

        if (success) {
          // Проверяем что ответ - валидный JSON
          try {
            JSON.parse(data);
            resolve({ success: true, status: res.statusCode, duration, name: endpoint.name });
          } catch (e) {
            resolve({ success: false, status: res.statusCode, duration, name: endpoint.name, error: 'Invalid JSON' });
          }
        } else {
          resolve({ success: false, status: res.statusCode, duration, name: endpoint.name, error: `HTTP ${res.statusCode}` });
        }
      });
    });

    req.on('error', (err) => {
      resolve({ success: false, status: 0, duration: Date.now() - startTime, name: endpoint.name, error: err.message });
    });

    req.on('timeout', () => {
      req.destroy();
      resolve({ success: false, status: 0, duration: 10000, name: endpoint.name, error: 'Timeout' });
    });

    req.end();
  });
}

async function runTests() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('  API Health Check');
  console.log(`  Base URL: ${BASE_URL}`);
  console.log(`  Endpoints: ${ENDPOINTS.length}`);
  console.log('═══════════════════════════════════════════════════════════\n');

  for (const endpoint of ENDPOINTS) {
    const result = await makeRequest(endpoint);

    if (result.success) {
      stats.passed++;
      console.log(`  ✅ ${result.name} (${result.duration}ms)`);
    } else {
      stats.failed++;
      stats.errors.push(result);
      console.log(`  ❌ ${result.name} - ${result.error}`);
    }
  }

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('  Summary');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(`  Total:  ${stats.total}`);
  console.log(`  Passed: ${stats.passed} ✅`);
  console.log(`  Failed: ${stats.failed} ${stats.failed > 0 ? '❌' : ''}`);

  if (stats.errors.length > 0) {
    console.log('\n  Failed endpoints:');
    for (const err of stats.errors) {
      console.log(`    - ${err.name}: ${err.error}`);
    }
  }

  console.log('\n═══════════════════════════════════════════════════════════');

  // Exit code для CI/CD
  process.exit(stats.failed > 0 ? 1 : 0);
}

runTests();
