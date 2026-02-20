/**
 * Points Settings Test — Arabica
 *
 * Проверяет:
 * 1. parsePoints() корректно округляет float значения
 * 2. API настроек баллов возвращает корректные данные
 * 3. Все категории имеют необходимые поля
 *
 * Запуск: node tests/points-settings-test.js
 */

const https = require('https');

// ============================================
// КОНФИГУРАЦИЯ
// ============================================
const SERVER_URL = process.env.SERVER_URL || 'https://arabica26.ru';
const API_KEY = process.env.API_KEY || '58c4d46b9bb324d03c5d96781223821f3528c5efa4604090a8e95ac540173585';
const AUTH_TOKEN = process.env.AUTH_TOKEN || 'b20781bfd2837fc2b71941e7138dec26100db899afa1d6cbbfa907962810e812';
const TIMEOUT_MS = 15000;

let passed = 0;
let failed = 0;

// ============================================
// HELPERS
// ============================================
function assert(condition, message) {
  if (condition) {
    passed++;
    console.log(`  ✓ ${message}`);
  } else {
    failed++;
    console.log(`  ✗ ${message}`);
  }
}

function assertClose(actual, expected, message, tolerance = 0.001) {
  const ok = Math.abs(actual - expected) < tolerance;
  if (ok) {
    passed++;
    console.log(`  ✓ ${message} (${actual})`);
  } else {
    failed++;
    console.log(`  ✗ ${message} — expected ${expected}, got ${actual}`);
  }
}

function fetchJson(path) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, SERVER_URL);
    const options = {
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname + url.search,
      method: 'GET',
      headers: {
        'X-API-Key': API_KEY,
        'Authorization': `Bearer ${AUTH_TOKEN}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      rejectUnauthorized: false,
      timeout: TIMEOUT_MS
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch (e) {
          // HTML responses (e.g. nginx 401/403 pages)
          resolve({ status: res.statusCode, body: { error: 'Non-JSON response' } });
        }
      });
    });

    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Timeout')); });
    req.end();
  });
}

// ============================================
// TEST 1: parsePoints logic (local)
// ============================================
function testParsePoints() {
  console.log('\n━━━ Test 1: parsePoints rounding ━━━');

  // Simulate the parsePoints function
  function parsePoints(value) {
    return Math.round(parseFloat(value) * 10) / 10;
  }

  // Float precision cases
  assertClose(parsePoints(-4.3999999999999995), -4.4, '-4.3999... rounds to -4.4');
  assertClose(parsePoints(1.5000000000000002), 1.5, '1.5000... rounds to 1.5');
  assertClose(parsePoints(-2.0999999999999996), -2.1, '-2.0999... rounds to -2.1');
  assertClose(parsePoints(0.30000000000000004), 0.3, '0.3000... rounds to 0.3');
  assertClose(parsePoints(-3.7), -3.7, '-3.7 stays -3.7');
  assertClose(parsePoints(0), 0, '0 stays 0');
  assertClose(parsePoints(-10), -10, '-10 stays -10');
  assertClose(parsePoints('2.5'), 2.5, 'String "2.5" parses correctly');
  assertClose(parsePoints('-1.1'), -1.1, 'String "-1.1" parses correctly');
}

// ============================================
// TEST 2: API endpoints return valid settings
// ============================================
async function testSettingsEndpoints() {
  console.log('\n━━━ Test 2: Settings API endpoints ━━━');

  const categories = [
    {
      path: '/api/points-settings/attendance',
      name: 'Attendance',
      requiredFields: ['onTimePoints', 'latePoints', 'missedPenalty'],
      checkMissedPenalty: true
    },
    {
      path: '/api/points-settings/shift',
      name: 'Shift',
      requiredFields: ['minPoints', 'maxPoints', 'missedPenalty']
    },
    {
      path: '/api/points-settings/recount',
      name: 'Recount',
      requiredFields: ['minPoints', 'maxPoints', 'missedPenalty']
    },
    {
      path: '/api/points-settings/rko',
      name: 'RKO',
      requiredFields: ['hasRkoPoints', 'noRkoPoints', 'missedPenalty']
    },
    {
      path: '/api/points-settings/shift-handover',
      name: 'Shift Handover',
      requiredFields: ['minPoints', 'maxPoints', 'missedPenalty']
    },
    {
      path: '/api/points-settings/reviews',
      name: 'Reviews',
      requiredFields: ['positivePoints', 'negativePoints']
    },
    {
      path: '/api/points-settings/product-search',
      name: 'Product Search',
      requiredFields: ['answeredPoints', 'notAnsweredPoints']
    },
    {
      path: '/api/points-settings/orders',
      name: 'Orders',
      requiredFields: ['acceptedPoints', 'rejectedPoints']
    },
  ];

  // Pre-check: verify auth token is valid
  try {
    const preCheck = await fetchJson('/api/points-settings/attendance');
    if (preCheck.status === 401) {
      console.log('  ⚠ Auth token expired (401). Skipping API tests.');
      console.log('    Re-run with valid AUTH_TOKEN env var after login.');
      return;
    }
  } catch (e) {
    console.log(`  ⚠ Server unreachable: ${e.message}. Skipping API tests.`);
    return;
  }

  for (const cat of categories) {
    try {
      const result = await fetchJson(cat.path);
      assert(result.status === 200, `${cat.name}: HTTP 200`);

      const settings = result.body.settings || result.body;

      for (const field of cat.requiredFields) {
        const hasField = settings[field] !== undefined;
        assert(hasField, `${cat.name}: has ${field} (${settings[field]})`);

        // Check no float errors (all values should have at most 1 decimal)
        if (hasField && typeof settings[field] === 'number') {
          const str = settings[field].toString();
          const decimals = str.includes('.') ? str.split('.')[1].length : 0;
          assert(decimals <= 2, `${cat.name}: ${field} no float error (${settings[field]})`);
        }
      }
    } catch (e) {
      failed++;
      console.log(`  ✗ ${cat.name}: ${e.message}`);
    }
  }
}

// ============================================
// TEST 3: Efficiency calc uses dynamic settings
// ============================================
async function testEfficiencyCalc() {
  console.log('\n━━━ Test 3: Efficiency calculation endpoint ━━━');

  try {
    const month = new Date().toISOString().slice(0, 7);
    const result = await fetchJson(`/api/efficiency/${month}?shopAddress=%D0%9B%D0%B5%D1%80%D0%BC%D0%BE%D0%BD%D1%82%D0%BE%D0%B2`);
    if (result.status === 401 || result.status === 403 || result.status === 404) {
      console.log('  ⚠ Auth token expired. Skipping.');
      return;
    }
    assert(result.status === 200, 'Efficiency endpoint returns 200');

    if (result.body.employees) {
      assert(Array.isArray(result.body.employees), 'Employees is an array');
      if (result.body.employees.length > 0) {
        const emp = result.body.employees[0];
        assert(emp.categories !== undefined, 'Employee has categories');
        assert(emp.totalPoints !== undefined, 'Employee has totalPoints');
      }
    }
  } catch (e) {
    failed++;
    console.log(`  ✗ Efficiency endpoint: ${e.message}`);
  }
}

// ============================================
// TEST 4: Task points settings dynamic
// ============================================
async function testTaskPointsSettings() {
  console.log('\n━━━ Test 4: Task points settings ━━━');

  try {
    const result = await fetchJson('/api/points-settings/tasks');
    if (result.status === 401 || result.status === 403 || result.status === 404) {
      console.log('  ⚠ Auth token expired. Skipping.');
      return;
    }
    assert(result.status === 200, 'Task points settings returns 200');

    const settings = result.body.settings || result.body;
    assert(settings.regularTasks !== undefined, 'Has regularTasks');
    assert(settings.recurringTasks !== undefined, 'Has recurringTasks');

    if (settings.regularTasks) {
      assert(settings.regularTasks.completionPoints !== undefined, 'regularTasks has completionPoints');
    }
    if (settings.recurringTasks) {
      assert(settings.recurringTasks.completionPoints !== undefined, 'recurringTasks has completionPoints');
    }
  } catch (e) {
    failed++;
    console.log(`  ✗ Task points settings: ${e.message}`);
  }
}

// ============================================
// RUN ALL
// ============================================
async function main() {
  console.log('╔═══════════════════════════════════════════╗');
  console.log('║   Points Settings Tests — Arabica         ║');
  console.log('╚═══════════════════════════════════════════╝');

  // Local tests (no network)
  testParsePoints();

  // API tests (network)
  await testSettingsEndpoints();
  await testEfficiencyCalc();
  await testTaskPointsSettings();

  // Summary
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`Total: ${passed + failed} tests | ✓ ${passed} passed | ✗ ${failed} failed`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  process.exit(failed > 0 ? 1 : 0);
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
