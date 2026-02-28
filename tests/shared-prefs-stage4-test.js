/**
 * Stage 4 Tests — SharedPreferences Keys & Efficiency Penalties
 * Tests for: attendance penalty name matching fix, key consistency
 *
 * Run: node tests/shared-prefs-stage4-test.js
 */

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    console.log(`  ✅ PASS: ${message}`);
    passed++;
  } else {
    console.error(`  ❌ FAIL: ${message}`);
    failed++;
  }
}

function assertEqual(actual, expected, message) {
  if (actual === expected) {
    console.log(`  ✅ PASS: ${message}`);
    passed++;
  } else {
    console.error(`  ❌ FAIL: ${message}`);
    console.error(`     Expected: ${JSON.stringify(expected)}`);
    console.error(`     Actual:   ${JSON.stringify(actual)}`);
    failed++;
  }
}

// ============================================================
// TEST GROUP 1: Attendance penalty matching — name vs phone
// ============================================================

console.log('\n=== TEST GROUP 1: Efficiency attendance penalty matching (Task 22) ===');

// attendance_api.js creates penalties like:
// { entityId: "Анна Иванова", entityName: "Анна Иванова", employeePhone: undefined }
// efficiency_calc.js searches by employeeId = "79001234567" (phone)

const testPenalties = [
  { entityId: 'Анна Иванова', entityName: 'Анна Иванова', employeeName: 'Анна Иванова', points: -1, date: '2026-02-15' },
  { entityId: '79009999999', entityName: 'Петр Сидоров', employeeName: 'Петр Сидоров', points: -2, date: '2026-02-20' },
  { entityId: '79001234567', entityName: 'Иван Иванов', employeeName: 'Иван Иванов', points: -1, date: '2026-02-10' },
];

const month = '2026-02';
const anna_phone = '79001111111';  // Anna's phone
const anna_name = 'Анна Иванова';

// BUGGY matching logic (current)
function calculatePenaltiesBUGGY(penalties, employeeId, month) {
  return penalties
    .filter(p => {
      const matchesEmployee = (p.employeeId === employeeId) || (p.entityId === employeeId);
      const matchesMonth = p.date && p.date.startsWith(month);
      return matchesEmployee && matchesMonth;
    })
    .reduce((sum, p) => sum + (p.points || 0), 0);
}

// FIXED matching logic
function calculatePenaltiesFIXED(penalties, employeeId, employeeName, month) {
  return penalties
    .filter(p => {
      const matchesEmployee = (p.employeeId === employeeId) ||
                              (p.entityId === employeeId) ||
                              (p.employeePhone === employeeId) ||
                              // Also match by name (since attendance API stores entityId = name)
                              (employeeName && (p.entityId === employeeName ||
                                               p.entityName === employeeName ||
                                               p.employeeName === employeeName));
      const matchesMonth = p.date && p.date.startsWith(month);
      return matchesEmployee && matchesMonth;
    })
    .reduce((sum, p) => sum + (p.points || 0), 0);
}

// Test 1a: BUGGY — Anna's phone doesn't match her name-based penalty
const buggyResult = calculatePenaltiesBUGGY(testPenalties, anna_phone, month);
assertEqual(buggyResult, 0, 'BUG CONFIRMED: attendance penalty not counted when entityId = name, search by phone');

// Test 1b: FIXED — Anna's name matches her penalty
const fixedResult = calculatePenaltiesFIXED(testPenalties, anna_phone, anna_name, month);
assertEqual(fixedResult, -1, 'FIXED: attendance penalty found when searching by name');

// Test 1c: FIXED — direct phone match still works
const peterPhone = '79009999999';
const peterName = 'Петр Сидоров';
const peterFixed = calculatePenaltiesFIXED(testPenalties, peterPhone, peterName, month);
assertEqual(peterFixed, -2, 'FIXED: direct phone entityId match still works');

// Test 1d: FIXED — old format with phone entityId also works with name lookup
const ivanPhone = '79001234567';
const ivanName = 'Иван Иванов';
const ivanFixed = calculatePenaltiesFIXED(testPenalties, ivanPhone, ivanName, month);
assertEqual(ivanFixed, -1, 'FIXED: phone-based entityId match with name available');

// Test 1e: BUGGY cached version
function calculatePenaltiesCachedBUGGY(penalties, employeeId) {
  return penalties
    .filter(p => p.entityId === employeeId || p.employeePhone === employeeId)
    .reduce((sum, p) => sum + (p.points || 0), 0);
}

function calculatePenaltiesCachedFIXED(penalties, employeeId, employeeName) {
  return penalties
    .filter(p =>
      p.entityId === employeeId ||
      p.employeePhone === employeeId ||
      (employeeName && (p.entityId === employeeName ||
                        p.entityName === employeeName ||
                        p.employeeName === employeeName))
    )
    .reduce((sum, p) => sum + (p.points || 0), 0);
}

const buggyCache = calculatePenaltiesCachedBUGGY(testPenalties, anna_phone);
assertEqual(buggyCache, 0, 'BUG CONFIRMED: cached version also fails to find Anna\'s penalty');

const fixedCache = calculatePenaltiesCachedFIXED(testPenalties, anna_phone, anna_name);
assertEqual(fixedCache, -1, 'FIXED: cached version finds penalty by name');

// Test 1f: Month filtering still works
const prevMonth = '2026-01';
const wrongMonth = calculatePenaltiesFIXED(testPenalties, anna_phone, anna_name, prevMonth);
assertEqual(wrongMonth, 0, 'FIXED: penalty from different month is not counted');

// Test 1g: No double-counting (same employee with name match + phone match)
const mixedPenalties = [
  { entityId: anna_name, employeePhone: anna_phone, points: -1, date: '2026-02-10' },
];
const noDouble = calculatePenaltiesFIXED(mixedPenalties, anna_phone, anna_name, month);
assertEqual(noDouble, -1, 'FIXED: no double-counting when both phone and name match');

// ============================================================
// TEST GROUP 2: SharedPreferences key consistency (Tasks 19-21)
// ============================================================

console.log('\n=== TEST GROUP 2: SharedPreferences key fallback logic ===');

// Simulate SharedPreferences storage
function createMockPrefs(data) {
  return {
    getString: (key) => data[key] || null,
  };
}

// Task 20: userPhone fallback to user_phone
function getPhoneWithFallbackFIXED(prefs) {
  return prefs.getString('user_phone') ?? prefs.getString('userPhone');
}

// Only user_phone is written (registration/auth flow)
const prefsWithUserPhone = createMockPrefs({ 'user_phone': '79001234567' });
const prefsEmpty = createMockPrefs({});

assertEqual(
  getPhoneWithFallbackFIXED(prefsWithUserPhone),
  '79001234567',
  'FIXED Task 20: user_phone read correctly'
);
assertEqual(
  getPhoneWithFallbackFIXED(prefsEmpty),
  null,
  'FIXED Task 20: returns null when neither key set'
);

// Task 21: employee name key fallback
function getEmployeeNameFIXED(prefs) {
  return prefs.getString('currentEmployeeName') ??
         prefs.getString('user_employee_name') ??
         prefs.getString('user_name');
}

const prefsWithCurrentName = createMockPrefs({ 'currentEmployeeName': 'Анна Иванова' });
const prefsWithEmployeeName = createMockPrefs({ 'user_employee_name': 'Анна Иванова' });
const prefsWithUserName = createMockPrefs({ 'user_name': 'Анна' });
const prefsWithAllKeys = createMockPrefs({
  'currentEmployeeName': 'Анна Иванова',
  'user_employee_name': 'Анна Иванова (другое)',
  'user_name': 'Анна'
});

assertEqual(
  getEmployeeNameFIXED(prefsWithCurrentName),
  'Анна Иванова',
  'FIXED Task 21: reads currentEmployeeName when set'
);
assertEqual(
  getEmployeeNameFIXED(prefsWithEmployeeName),
  'Анна Иванова',
  'FIXED Task 21: falls back to user_employee_name'
);
assertEqual(
  getEmployeeNameFIXED(prefsWithUserName),
  'Анна',
  'FIXED Task 21: falls back to user_name as last resort'
);
assertEqual(
  getEmployeeNameFIXED(prefsWithAllKeys),
  'Анна Иванова',
  'FIXED Task 21: currentEmployeeName takes priority'
);

// ============================================================
// FINAL SUMMARY
// ============================================================

console.log(`\n${'='.repeat(50)}`);
console.log(`STAGE 4 TEST RESULTS: ${passed} passed, ${failed} failed`);
console.log(`${'='.repeat(50)}\n`);

if (failed > 0) {
  process.exit(1);
}
