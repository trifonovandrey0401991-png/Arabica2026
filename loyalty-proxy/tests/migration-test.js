/**
 * Migration Test - Проверяет что все endpoint'ы возвращают одинаковые ответы
 * до и после миграции inline → module
 *
 * Запуск:
 *   1. Перед миграцией: node tests/migration-test.js baseline
 *   2. После миграции:  node tests/migration-test.js verify
 *
 * Сравнивает структуру ответов (ключи JSON), статус-коды, формат данных
 */

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const BASE_URL = process.argv[3] || 'https://arabica26.ru';
const MODE = process.argv[2] || 'baseline'; // baseline | verify
const API_KEY = '58c4d46b9bb324d03c5d96781223821f3528c5efa4604090a8e95ac540173585';

const BASELINE_FILE = path.join(__dirname, 'migration-baseline.json');

// Все эндпоинты, которые затронуты миграцией
const MIGRATION_ENDPOINTS = [
  // === SHOPS (shops_api.js) ===
  { group: 'shops', method: 'GET', path: '/api/shops', expect: 200, keys: ['success', 'shops'] },

  // === MENU (menu_api.js) ===
  { group: 'menu', method: 'GET', path: '/api/menu', expect: 200, keys: ['success', 'items'] },

  // === EMPLOYEES (employees_api.js) ===
  { group: 'employees', method: 'GET', path: '/api/employees', expect: 200, keys: ['success', 'employees'] },

  // === ATTENDANCE (attendance_api.js) ===
  { group: 'attendance', method: 'GET', path: '/api/attendance', expect: 200, keys: ['success'] },
  { group: 'attendance', method: 'GET', path: '/api/attendance/pending', expect: 200, keys: ['success'] },
  { group: 'attendance', method: 'GET', path: '/api/attendance/failed', expect: 200, keys: ['success'] },

  // === RECOUNT (recount_api.js) ===
  { group: 'recount', method: 'GET', path: '/api/recount-reports', expect: 200, keys: ['success', 'reports'] },
  { group: 'recount', method: 'GET', path: '/api/recount-reports/expired', expect: 200, keys: ['success', 'reports'] },
  { group: 'recount', method: 'GET', path: '/api/pending-recount-reports', expect: 200, keys: ['success', 'reports'] },
  { group: 'recount', method: 'GET', path: '/api/recount-questions', expect: 200, keys: ['success', 'questions'] },

  // === SHIFTS (shifts_api.js) ===
  { group: 'shifts', method: 'GET', path: '/api/shift-reports', expect: 200, keys: ['success', 'reports'] },
  { group: 'shifts', method: 'GET', path: '/api/shift-questions', expect: 200, keys: ['success', 'questions'] },
  { group: 'shifts', method: 'GET', path: '/api/shift-handover-questions', expect: 200, keys: ['success', 'questions'] },
  { group: 'shifts', method: 'GET', path: '/api/shift-handover-reports', expect: 200, keys: ['success', 'reports'] },
  { group: 'shifts', method: 'GET', path: '/api/shift-handover/pending', expect: 200, keys: ['success'] },
  { group: 'shifts', method: 'GET', path: '/api/shift-handover/failed', expect: 200, keys: ['success'] },

  // === TRAINING (training_api.js) ===
  { group: 'training', method: 'GET', path: '/api/training-articles', expect: 200, keys: ['success', 'articles'] },

  // === TESTS (tests_api.js) ===
  { group: 'tests', method: 'GET', path: '/api/test-questions', expect: 200, keys: ['success', 'questions'] },
  { group: 'tests', method: 'GET', path: '/api/test-results', expect: 200, keys: ['success', 'results'] },

  // === REVIEWS (reviews_api.js) ===
  { group: 'reviews', method: 'GET', path: '/api/reviews', expect: 200, keys: ['success', 'reviews'] },

  // === RECIPES (recipes_api.js) ===
  { group: 'recipes', method: 'GET', path: '/api/recipes', expect: 200, keys: ['success', 'recipes'] },

  // === SUPPLIERS (suppliers_api.js) ===
  { group: 'suppliers', method: 'GET', path: '/api/suppliers', expect: 200, keys: ['success', 'suppliers'] },

  // === WORK SCHEDULE (work_schedule_api.js) ===
  { group: 'work_schedule', method: 'GET', path: '/api/work-schedule', expect: 200, keys: ['success'] },
  { group: 'work_schedule', method: 'GET', path: '/api/work-schedule/template', expect: 200, keys: ['success'] },

  // === WITHDRAWALS (withdrawals_api.js) ===
  { group: 'withdrawals', method: 'GET', path: '/api/withdrawals', expect: 200, keys: ['success', 'withdrawals'] },

  // === ORDERS (orders_api.js) ===
  { group: 'orders', method: 'GET', path: '/api/orders', expect: 200, keys: ['success', 'orders'] },
  { group: 'orders', method: 'GET', path: '/api/orders/unviewed-count', expect: 200, keys: ['success'] },

  // === BONUS/PENALTIES ===
  { group: 'bonus', method: 'GET', path: '/api/bonus-penalties', expect: 200, keys: ['success'] },
  { group: 'efficiency', method: 'GET', path: '/api/efficiency-penalties', expect: 200, keys: ['success'] },

  // === EFFICIENCY (manager_efficiency_api.js) ===
  { group: 'efficiency', method: 'GET', path: '/api/efficiency/reports-batch', expect: 200, keys: ['success'] },

  // === LOYALTY PROMO (loyalty_promo_api.js) ===
  { group: 'loyalty_promo', method: 'GET', path: '/api/loyalty-promo', expect: 200, keys: ['success'] },

  // === APP VERSION ===
  { group: 'app_version', method: 'GET', path: '/api/app-version', expect: 200 },

  // === SHOP SETTINGS (shop_settings_api.js) ===
  // Note: shop-settings requires :shopAddress param, tested separately

  // === HEALTH ===
  { group: 'health', method: 'GET', path: '/health', expect: 200, keys: ['status'] },
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
        let parsed = null;
        let responseKeys = [];
        try {
          parsed = JSON.parse(body);
          responseKeys = Object.keys(parsed).sort();
        } catch (e) {
          // Not JSON
        }

        resolve({
          status: res.statusCode,
          bodyLength: body.length,
          isJson: parsed !== null,
          responseKeys,
          dataTypes: parsed ? Object.fromEntries(
            Object.entries(parsed).map(([k, v]) => [k, Array.isArray(v) ? 'array' : typeof v])
          ) : {},
          arrayLengths: parsed ? Object.fromEntries(
            Object.entries(parsed)
              .filter(([k, v]) => Array.isArray(v))
              .map(([k, v]) => [k, v.length])
          ) : {},
        });
      });
    });

    req.on('error', (e) => {
      resolve({ status: 0, bodyLength: 0, isJson: false, responseKeys: [], dataTypes: {}, arrayLengths: {}, error: e.message });
    });

    req.on('timeout', () => {
      req.destroy();
      resolve({ status: 0, bodyLength: 0, isJson: false, responseKeys: [], dataTypes: {}, arrayLengths: {}, error: 'TIMEOUT' });
    });

    req.end();
  });
}

async function runBaseline() {
  console.log(`\n========================================`);
  console.log(`  MIGRATION BASELINE CAPTURE`);
  console.log(`  Server: ${BASE_URL}`);
  console.log(`  Date: ${new Date().toISOString()}`);
  console.log(`========================================\n`);

  const results = {};

  for (const ep of MIGRATION_ENDPOINTS) {
    const res = await makeRequest(ep.method, ep.path);
    const key = `${ep.method} ${ep.path}`;

    results[key] = {
      group: ep.group,
      status: res.status,
      isJson: res.isJson,
      responseKeys: res.responseKeys,
      dataTypes: res.dataTypes,
      arrayLengths: res.arrayLengths,
      error: res.error || null,
    };

    const icon = res.status >= 500 || res.status === 0 ? '❌' : '✅';
    console.log(`  ${icon} ${key} → ${res.status} [keys: ${res.responseKeys.join(',')}]`);
  }

  fs.writeFileSync(BASELINE_FILE, JSON.stringify({
    date: new Date().toISOString(),
    baseUrl: BASE_URL,
    results,
  }, null, 2));

  console.log(`\n✅ Baseline saved to ${BASELINE_FILE}`);
  console.log(`   ${Object.keys(results).length} endpoints captured\n`);
}

async function runVerify() {
  console.log(`\n========================================`);
  console.log(`  MIGRATION VERIFICATION`);
  console.log(`  Server: ${BASE_URL}`);
  console.log(`  Date: ${new Date().toISOString()}`);
  console.log(`========================================\n`);

  if (!fs.existsSync(BASELINE_FILE)) {
    console.error('❌ Baseline file not found! Run: node migration-test.js baseline');
    process.exit(1);
  }

  const baseline = JSON.parse(fs.readFileSync(BASELINE_FILE, 'utf8'));
  console.log(`  Baseline from: ${baseline.date}\n`);

  let passed = 0;
  let failed = 0;
  const failures = [];

  for (const ep of MIGRATION_ENDPOINTS) {
    const res = await makeRequest(ep.method, ep.path);
    const key = `${ep.method} ${ep.path}`;
    const base = baseline.results[key];

    if (!base) {
      console.log(`  ⚠️  ${key} → No baseline (NEW endpoint)`);
      continue;
    }

    const issues = [];

    // Check status code
    if (res.status !== base.status) {
      issues.push(`status: ${base.status} → ${res.status}`);
    }

    // Check JSON structure
    if (res.isJson !== base.isJson) {
      issues.push(`isJson: ${base.isJson} → ${res.isJson}`);
    }

    // Check response keys
    if (res.responseKeys.join(',') !== base.responseKeys.join(',')) {
      issues.push(`keys: [${base.responseKeys}] → [${res.responseKeys}]`);
    }

    // Check data types
    for (const k of base.responseKeys) {
      if (base.dataTypes[k] && res.dataTypes[k] && base.dataTypes[k] !== res.dataTypes[k]) {
        issues.push(`type(${k}): ${base.dataTypes[k]} → ${res.dataTypes[k]}`);
      }
    }

    if (issues.length === 0) {
      passed++;
      console.log(`  ✅ ${key} → ${res.status} OK`);
    } else {
      failed++;
      failures.push({ key, issues });
      console.log(`  ❌ ${key} → CHANGED: ${issues.join(', ')}`);
    }
  }

  // Summary
  console.log(`\n========================================`);
  console.log(`  RESULTS: ${passed} passed, ${failed} failed`);
  console.log(`  Total: ${passed + failed} endpoints verified`);
  console.log(`========================================\n`);

  if (failures.length > 0) {
    console.log('FAILURES:');
    for (const f of failures) {
      console.log(`  ${f.key}:`);
      for (const issue of f.issues) {
        console.log(`    - ${issue}`);
      }
    }
    console.log('');
  }

  // Save verification results
  const resultFile = `tests/migration-verify-${Date.now()}.json`;
  fs.writeFileSync(resultFile, JSON.stringify({
    date: new Date().toISOString(),
    baseUrl: BASE_URL,
    baselineDate: baseline.date,
    passed,
    failed,
    failures,
  }, null, 2));

  console.log(`Results saved to: ${resultFile}`);

  return failed === 0;
}

async function main() {
  if (MODE === 'baseline') {
    await runBaseline();
  } else if (MODE === 'verify') {
    const success = await runVerify();
    process.exit(success ? 0 : 1);
  } else {
    console.log('Usage:');
    console.log('  node migration-test.js baseline [url]  - capture baseline');
    console.log('  node migration-test.js verify [url]    - verify after migration');
    process.exit(1);
  }
}

main();
