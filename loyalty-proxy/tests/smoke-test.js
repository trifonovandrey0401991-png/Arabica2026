/**
 * API Smoke Test
 * Проверяет все GET-эндпоинты на доступность (status != 500/502/503)
 * Запуск: node tests/smoke-test.js [base_url]
 * По умолчанию: https://arabica26.ru
 */

const http = require('http');
const https = require('https');

const BASE_URL = process.argv[2] || 'https://arabica26.ru';
const API_KEY = '58c4d46b9bb324d03c5d96781223821f3528c5efa4604090a8e95ac540173585';

// Все GET-эндпоинты для проверки
const GET_ENDPOINTS = [
  // Health
  { path: '/health', expect: 200 },

  // Employees
  { path: '/api/employees', expect: 200 },

  // Shops
  { path: '/api/shops', expect: 200 },

  // Recount
  { path: '/api/recount-reports', expect: 200 },
  { path: '/api/recount-reports/expired', expect: 200 },
  { path: '/api/pending-recount-reports', expect: 200 },
  { path: '/api/recount-questions', expect: 200 },

  // Attendance
  { path: '/api/attendance', expect: 200 },
  { path: '/api/attendance/pending', expect: 200 },
  { path: '/api/attendance/failed', expect: 200 },

  // Shift Reports
  { path: '/api/shift-reports', expect: 200 },
  { path: '/api/shift-questions', expect: 200 },

  // Shift Handover
  { path: '/api/shift-handover-questions', expect: 200 },
  { path: '/api/shift-handover-reports', expect: 200 },
  { path: '/api/shift-handover/pending', expect: 200 },
  { path: '/api/shift-handover/failed', expect: 200 },

  // Envelope
  { path: '/api/envelope-questions', expect: 200 },
  { path: '/api/envelope-reports', expect: 200 },
  { path: '/api/envelope-reports/expired', expect: 200 },
  { path: '/api/envelope-pending', expect: 200 },
  { path: '/api/envelope-failed', expect: 200 },

  // RKO
  { path: '/api/rko/all', expect: 200 },
  { path: '/api/rko/pending', expect: 200 },
  { path: '/api/rko/failed', expect: 200 },

  // Work Schedule
  { path: '/api/work-schedule', expect: 200 },
  { path: '/api/work-schedule/template', expect: 200 },

  // Withdrawals
  { path: '/api/withdrawals', expect: 200 },

  // Suppliers
  { path: '/api/suppliers', expect: 200 },

  // Clients
  { path: '/api/clients', expect: 200 },

  // Training
  { path: '/api/training-articles', expect: 200 },

  // Tests
  { path: '/api/test-questions', expect: 200 },
  { path: '/api/test-results', expect: 200 },

  // Reviews
  { path: '/api/reviews', expect: 200 },

  // Recipes
  { path: '/api/recipes', expect: 200 },

  // Menu
  { path: '/api/menu', expect: 200 },

  // Orders
  { path: '/api/orders', expect: 200 },
  { path: '/api/orders/unviewed-count', expect: 200 },

  // Bonus/Penalties
  { path: '/api/bonus-penalties', expect: 200 },
  { path: '/api/efficiency-penalties', expect: 200 },

  // Efficiency
  { path: '/api/efficiency/reports-batch', expect: 200 },

  // App Version
  { path: '/api/app-version', expect: 200 },

  // Loyalty Promo
  { path: '/api/loyalty-promo', expect: 200 },

  // External modules
  { path: '/api/job-applications', expect: 200 },
  { path: '/api/referrals', expect: 200 },
  { path: '/api/tasks', expect: 200 },
  { path: '/api/recurring-tasks', expect: 200 },
  { path: '/api/shift-transfers', expect: 200 },
  { path: '/api/points-settings', expect: 200 },
  { path: '/api/task-points-settings', expect: 200 },
  { path: '/api/product-questions', expect: 200 },
  { path: '/api/master-catalog', expect: 200 },
  { path: '/api/shop-products', expect: 200 },
  { path: '/api/geofence/zones', expect: 200 },
  { path: '/api/employee-chat/chats', expect: 200 },
  { path: '/api/shop-managers', expect: 200 },
  { path: '/api/z-report/templates', expect: 200 },
  { path: '/api/cigarette-vision/stats', expect: 200 },
  { path: '/api/coffee-machine/templates', expect: 200 },
];

// POST-эндпоинты, которые можно проверить без тела (ожидаем 400, не 500)
const POST_SAFE_CHECK = [
  { path: '/api/auth/request-otp', expect: 400 },
  { path: '/api/auth/verify-otp', expect: 400 },
  { path: '/api/auth/login', expect: 400 },
];

function makeRequest(method, urlPath) {
  return new Promise((resolve) => {
    const fullUrl = `${BASE_URL}${urlPath}`;
    const urlObj = new URL(fullUrl);
    const lib = urlObj.protocol === 'https:' ? https : http;

    const options = {
      hostname: urlObj.hostname,
      port: urlObj.port,
      path: urlObj.pathname + urlObj.search,
      method: method,
      headers: {
        'X-API-Key': API_KEY,
        'Accept': 'application/json',
      },
      timeout: 15000,
      rejectUnauthorized: false,
    };

    const req = lib.request(options, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        resolve({
          status: res.statusCode,
          body: body.substring(0, 200),
          ok: true,
        });
      });
    });

    req.on('error', (e) => {
      resolve({ status: 0, body: e.message, ok: false });
    });

    req.on('timeout', () => {
      req.destroy();
      resolve({ status: 0, body: 'TIMEOUT', ok: false });
    });

    req.end();
  });
}

async function runTests() {
  console.log(`\n========================================`);
  console.log(`  API SMOKE TEST`);
  console.log(`  Server: ${BASE_URL}`);
  console.log(`  Date: ${new Date().toISOString()}`);
  console.log(`========================================\n`);

  let passed = 0;
  let failed = 0;
  let errors = [];
  const results = [];

  // GET tests
  console.log('--- GET Endpoints ---\n');
  for (const ep of GET_ENDPOINTS) {
    const res = await makeRequest('GET', ep.path);
    const isServerError = res.status >= 500 || res.status === 0;
    const icon = isServerError ? '❌' : '✅';

    if (isServerError) {
      failed++;
      errors.push({ method: 'GET', path: ep.path, status: res.status, body: res.body });
    } else {
      passed++;
    }

    results.push({ method: 'GET', path: ep.path, status: res.status, expected: ep.expect });
    console.log(`  ${icon} GET ${ep.path} → ${res.status}`);
  }

  // POST safe-check tests
  console.log('\n--- POST Safe-Check (expect 400, not 500) ---\n');
  for (const ep of POST_SAFE_CHECK) {
    const res = await makeRequest('POST', ep.path);
    const isServerError = res.status >= 500 || res.status === 0;
    const icon = isServerError ? '❌' : '✅';

    if (isServerError) {
      failed++;
      errors.push({ method: 'POST', path: ep.path, status: res.status, body: res.body });
    } else {
      passed++;
    }

    results.push({ method: 'POST', path: ep.path, status: res.status, expected: ep.expect });
    console.log(`  ${icon} POST ${ep.path} → ${res.status}`);
  }

  // Summary
  console.log(`\n========================================`);
  console.log(`  RESULTS: ${passed} passed, ${failed} failed`);
  console.log(`  Total: ${passed + failed} endpoints tested`);
  console.log(`========================================\n`);

  if (errors.length > 0) {
    console.log('FAILURES:');
    for (const err of errors) {
      console.log(`  ${err.method} ${err.path} → ${err.status}: ${err.body}`);
    }
    console.log('');
  }

  // Save results to file
  const fs = require('fs');
  const resultFile = `tests/smoke-results-${Date.now()}.json`;
  fs.writeFileSync(resultFile, JSON.stringify({ date: new Date().toISOString(), base_url: BASE_URL, passed, failed, results, errors }, null, 2));
  console.log(`Results saved to: ${resultFile}`);

  return failed === 0;
}

runTests().then(success => {
  process.exit(success ? 0 : 1);
});
