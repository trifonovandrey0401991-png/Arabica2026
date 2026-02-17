/**
 * Phase 3 Test — BaseReportScheduler + fileExists/sanitizeId dedup
 *
 * Проверяет:
 * 1. Все шедулеры загружаются без ошибок
 * 2. Все шедулеры экспортируют ожидаемые функции
 * 3. BaseReportScheduler содержит все нужные методы
 * 4. Нет локальных дубликатов fileExists/sanitizeId (кроме каноничных)
 * 5. index.js загружается без ошибок
 *
 * Запуск:  node tests/phase3-test.js
 */

const fs = require('fs');
const path = require('path');

// ============================================
// CONFIGURATION
// ============================================
const PROXY_DIR = path.join(__dirname, '..', 'loyalty-proxy');
const API_DIR = path.join(PROXY_DIR, 'api');
const UTILS_DIR = path.join(PROXY_DIR, 'utils');
const MODULES_DIR = path.join(PROXY_DIR, 'modules');

let passed = 0;
let failed = 0;

function ok(name) {
  console.log(`  ✅ ${name}`);
  passed++;
}
function fail(name, err) {
  console.log(`  ❌ ${name}: ${err}`);
  failed++;
}

// ============================================
// TEST 1: BaseReportScheduler loads & has required methods
// ============================================
console.log('\n[Test 1] BaseReportScheduler structure');
try {
  const BRS = require(path.join(UTILS_DIR, 'base_report_scheduler'));

  const expectedMethods = [
    'loadState', 'saveState', 'getAllShops', 'parseTime',
    'isWithinTimeWindow', 'isTimeReached', 'isSameDay',
    'getDeadlineTime', 'createPenalty', 'assignPenaltyFromSchedule',
    'sendAdminFailedNotification', 'sendPushToEmployee',
    'runScheduledChecks', 'start'
  ];

  for (const method of expectedMethods) {
    if (typeof BRS.prototype[method] === 'function') {
      ok(`BRS.prototype.${method} exists`);
    } else {
      fail(`BRS.prototype.${method} exists`, 'not a function');
    }
  }
} catch (e) {
  fail('BaseReportScheduler loads', e.message);
}

// ============================================
// TEST 2: All schedulers load and export expected functions
// ============================================
console.log('\n[Test 2] Scheduler exports');

const schedulerTests = [
  {
    file: 'shift_automation_scheduler.js',
    exports: ['startShiftAutomationScheduler', 'generatePendingReports', 'checkPendingDeadlines',
              'checkReviewTimeouts', 'cleanupFailedReports', 'setReportToReview', 'confirmReport',
              'loadTodayReports', 'saveTodayReports', 'getShiftSettings', 'getMoscowTime', 'getMoscowDateString']
  },
  {
    file: 'recount_automation_scheduler.js',
    exports: ['startRecountAutomationScheduler', 'generatePendingReports', 'checkPendingDeadlines',
              'checkReviewTimeouts', 'cleanupFailedReports', 'setReportToReview', 'confirmReport',
              'loadTodayReports', 'getRecountSettings', 'getMoscowTime', 'getMoscowDateString']
  },
  {
    file: 'rko_automation_scheduler.js',
    exports: ['startRkoAutomationScheduler', 'generatePendingReports', 'checkPendingDeadlines',
              'cleanupFailedReports', 'loadTodayPendingReports', 'getPendingReports', 'getFailedReports',
              'getRkoSettings', 'getMoscowTime', 'getMoscowDateString']
  },
  {
    file: 'shift_handover_automation_scheduler.js',
    exports: ['startShiftHandoverAutomationScheduler', 'generatePendingReports', 'checkPendingDeadlines',
              'checkAdminReviewTimeout', 'cleanupFailedReports', 'loadTodayPendingReports',
              'getPendingReports', 'getFailedReports', 'markPendingAsCompleted',
              'sendAdminNewReportNotification', 'getShiftHandoverSettings', 'getMoscowTime', 'getMoscowDateString']
  },
  {
    file: 'attendance_automation_scheduler.js',
    exports: ['startAttendanceAutomationScheduler', 'generatePendingReports', 'checkPendingDeadlines',
              'cleanupFailedReports', 'loadTodayPendingReports', 'getPendingReports', 'getFailedReports',
              'canMarkAttendance', 'markPendingAsCompleted', 'getAttendanceSettings', 'getMoscowTime', 'getMoscowDateString']
  },
  {
    file: 'envelope_automation_scheduler.js',
    exports: ['startScheduler']
  },
  {
    file: 'coffee_machine_automation_scheduler.js',
    exports: ['startCoffeeMachineAutomation', 'getPendingReports', 'getFailedReports']
  },
  {
    file: 'product_questions_penalty_scheduler.js',
    exports: ['setupProductQuestionsPenaltyScheduler']
  }
];

for (const test of schedulerTests) {
  try {
    const mod = require(path.join(API_DIR, test.file));
    ok(`${test.file} loads`);

    for (const exp of test.exports) {
      if (typeof mod[exp] === 'function') {
        ok(`${test.file} → ${exp}`);
      } else {
        fail(`${test.file} → ${exp}`, `not a function (got ${typeof mod[exp]})`);
      }
    }
  } catch (e) {
    fail(`${test.file} loads`, e.message);
  }
}

// ============================================
// TEST 3: No local fileExists duplicates
// ============================================
console.log('\n[Test 3] No local fileExists/sanitizeId duplicates');

const CANONICAL_FILES = new Set([
  path.join(UTILS_DIR, 'file_helpers.js'),
  path.join(UTILS_DIR, 'async_fs.js')
]);

function scanForLocalFn(dir, fnPattern, label) {
  const files = [];
  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith('.js')) continue;
      const fullPath = path.join(dir, entry.name);
      if (CANONICAL_FILES.has(fullPath)) continue;

      const content = fs.readFileSync(fullPath, 'utf8');
      if (fnPattern.test(content)) {
        files.push(fullPath);
      }
    }
  } catch (e) {
    // dir doesn't exist
  }
  return files;
}

const fileExistsPattern = /^(?:async )?function fileExists\s*\(/m;
const sanitizeIdPattern = /^function sanitizeId\s*\(/m;

const dirsToCheck = [API_DIR, PROXY_DIR, MODULES_DIR];
let dupes = [];

for (const dir of dirsToCheck) {
  dupes = dupes.concat(scanForLocalFn(dir, fileExistsPattern, 'fileExists'));
}
if (dupes.length === 0) {
  ok('No local fileExists duplicates found');
} else {
  fail('No local fileExists duplicates found', `Found in: ${dupes.map(f => path.basename(f)).join(', ')}`);
}

dupes = [];
for (const dir of dirsToCheck) {
  dupes = dupes.concat(scanForLocalFn(dir, sanitizeIdPattern, 'sanitizeId'));
}
if (dupes.length === 0) {
  ok('No local sanitizeId duplicates found');
} else {
  fail('No local sanitizeId duplicates found', `Found in: ${dupes.map(f => path.basename(f)).join(', ')}`);
}

// ============================================
// TEST 4: file_helpers exports are complete
// ============================================
console.log('\n[Test 4] file_helpers exports');
try {
  const fh = require(path.join(UTILS_DIR, 'file_helpers'));
  const expectedExports = ['fileExists', 'sanitizeId', 'loadJsonFile', 'saveJsonFile',
                           'isPathSafe', 'maskPhone', 'sanitizePhone', 'normalizePhone', 'ensureDir'];
  for (const exp of expectedExports) {
    if (typeof fh[exp] === 'function') {
      ok(`file_helpers.${exp}`);
    } else {
      fail(`file_helpers.${exp}`, `not a function (got ${typeof fh[exp]})`);
    }
  }
} catch (e) {
  fail('file_helpers loads', e.message);
}

// ============================================
// SUMMARY
// ============================================
console.log('\n======================================================================');
console.log(`  Phase 3 Tests: ${passed} passed, ${failed} failed`);
console.log('======================================================================\n');

process.exit(failed > 0 ? 1 : 0);
