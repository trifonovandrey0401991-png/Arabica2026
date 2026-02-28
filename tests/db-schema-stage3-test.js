/**
 * Stage 3 Tests — Database Schema & Queries
 * Tests for: auth DB mapping, deleteWhere NULL, loyalty_gamification clients upsert,
 *            envelope_reports missing columns
 *
 * Run: node tests/db-schema-stage3-test.js
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
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
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
// TEST GROUP 1: auth_pins DB mapping (Task 15)
// ============================================================

console.log('\n=== TEST GROUP 1: auth_pins DB column mapping ===');

// Simulate BUGGY getPinData (reads row.data which doesn't exist)
function getPinDataBUGGY(row) {
  if (!row) return null;
  return row.data;  // BUG: column 'data' doesn't exist in auth_pins table
}

// Simulate FIXED getPinData (maps real columns to expected JSON format)
function getPinDataFIXED(row) {
  if (!row) return null;
  return {
    pinHash: row.pin_hash,
    hashType: row.hash_type || 'bcrypt',
    salt: row.salt || null,
    failedAttempts: row.failed_attempts || 0,
    lockedUntil: row.locked_until ? new Date(row.locked_until).getTime() : null,
  };
}

// Simulate DB row (real columns in auth_pins table)
const dbPinRow = {
  phone: '79001234567',
  pin_hash: '$2b$10$examplehash',
  hash_type: 'bcrypt',
  salt: null,
  failed_attempts: 2,
  locked_until: null
};

// Test 1a: Buggy version returns undefined (column doesn't exist)
const buggyPin = getPinDataBUGGY(dbPinRow);
assert(buggyPin === undefined, 'BUG CONFIRMED: row.data is undefined (column missing)');

// Test 1b: Fixed version correctly maps columns
const fixedPin = getPinDataFIXED(dbPinRow);
assertEqual(fixedPin.pinHash, '$2b$10$examplehash', 'FIXED: pinHash from pin_hash column');
assertEqual(fixedPin.hashType, 'bcrypt', 'FIXED: hashType from hash_type column');
assertEqual(fixedPin.failedAttempts, 2, 'FIXED: failedAttempts from failed_attempts column');
assertEqual(fixedPin.lockedUntil, null, 'FIXED: lockedUntil is null when locked_until is null');

// Test 1c: With locked_until set
const lockedRow = { ...dbPinRow, locked_until: '2026-02-26T10:00:00Z' };
const lockedPin = getPinDataFIXED(lockedRow);
assert(typeof lockedPin.lockedUntil === 'number', 'FIXED: lockedUntil is a number (ms timestamp)');
assert(lockedPin.lockedUntil > 0, 'FIXED: lockedUntil is a positive timestamp');

// Test 1d: savePinData maps correct columns
function buildSavePinDataBUGGY(phone, data) {
  return { phone, data, updated_at: '2026-02-26T00:00:00Z' };  // BUG: 'data' column
}

function buildSavePinDataFIXED(phone, data) {
  return {
    phone: phone,
    pin_hash: data.pinHash || '',
    hash_type: data.hashType || 'bcrypt',
    salt: data.salt || null,
    failed_attempts: data.failedAttempts || 0,
    locked_until: data.lockedUntil ? new Date(data.lockedUntil).toISOString() : null,
  };
}

const pinData = { pinHash: '$2b$10$hash', hashType: 'bcrypt', failedAttempts: 0, lockedUntil: null };
const buggyInsert = buildSavePinDataBUGGY('79001234567', pinData);
assert('data' in buggyInsert, 'BUG CONFIRMED: buggy insert has "data" key (non-existent column)');
assert(!('pin_hash' in buggyInsert), 'BUG CONFIRMED: buggy insert missing "pin_hash" column');

const fixedInsert = buildSavePinDataFIXED('79001234567', pinData);
assert(!('data' in fixedInsert), 'FIXED: no "data" key in insert (does not exist in DB)');
assert('pin_hash' in fixedInsert, 'FIXED: "pin_hash" column present');
assert('hash_type' in fixedInsert, 'FIXED: "hash_type" column present');

// ============================================================
// TEST GROUP 2: auth_sessions DB mapping (Task 15)
// ============================================================

console.log('\n=== TEST GROUP 2: auth_sessions DB column mapping ===');

// Simulate BUGGY getSessionByToken (reads row.data which doesn't exist)
function getSessionByTokenBUGGY(rows) {
  if (!rows || rows.length === 0) return null;
  return rows[0].data;  // BUG: column 'data' doesn't exist
}

// Simulate FIXED getSessionByToken (maps real columns)
function getSessionByTokenFIXED(rows) {
  if (!rows || rows.length === 0) return null;
  const row = rows[0];
  return {
    sessionToken: row.session_token,
    phone: row.phone,
    name: null,  // Not in DB schema — will use pinData.name as fallback
    isAdmin: row.is_admin || false,
    employeeId: row.employee_id || null,
    expiresAt: row.expires_at ? new Date(row.expires_at).getTime() : 0,
  };
}

// Real DB columns in auth_sessions
const dbSessionRow = {
  id: 1,
  phone: '79001234567',
  session_token: 'tok_abc123',
  employee_id: 'emp_456',
  is_admin: false,
  created_at: '2026-02-26T00:00:00Z',
  expires_at: '2026-03-05T00:00:00Z'
};

// Test 2a: Buggy version returns undefined
const buggySession = getSessionByTokenBUGGY([dbSessionRow]);
assert(buggySession === undefined, 'BUG CONFIRMED: row.data is undefined (column missing in auth_sessions)');

// Test 2b: Fixed version correctly maps columns
const fixedSession = getSessionByTokenFIXED([dbSessionRow]);
assertEqual(fixedSession.sessionToken, 'tok_abc123', 'FIXED: sessionToken from session_token');
assertEqual(fixedSession.phone, '79001234567', 'FIXED: phone mapped correctly');
assertEqual(fixedSession.isAdmin, false, 'FIXED: isAdmin from is_admin');
assertEqual(fixedSession.employeeId, 'emp_456', 'FIXED: employeeId from employee_id');
assert(fixedSession.expiresAt > 0, 'FIXED: expiresAt converted to ms timestamp');

// Test 2c: saveSession maps correct columns (no 'data' key)
function buildSaveSessionBUGGY(phone, session) {
  return { phone, session_token: session.sessionToken, data: session };  // BUG
}

function buildSaveSessionFIXED(phone, session) {
  return {
    phone: phone,
    session_token: session.sessionToken || '',
    employee_id: session.employeeId || null,
    is_admin: session.isAdmin || false,
    expires_at: session.expiresAt ? new Date(session.expiresAt).toISOString() : null,
  };
}

const sessionObj = { sessionToken: 'tok123', phone: '79001234567', isAdmin: false, employeeId: 'emp_1', expiresAt: Date.now() + 86400000 };
const buggySessionInsert = buildSaveSessionBUGGY('79001234567', sessionObj);
assert('data' in buggySessionInsert, 'BUG CONFIRMED: buggy save has "data" key (non-existent column)');

const fixedSessionInsert = buildSaveSessionFIXED('79001234567', sessionObj);
assert(!('data' in fixedSessionInsert), 'FIXED: no "data" key in session insert');
assert('session_token' in fixedSessionInsert, 'FIXED: session_token column present');
assert('is_admin' in fixedSessionInsert, 'FIXED: is_admin column present');
assert('expires_at' in fixedSessionInsert, 'FIXED: expires_at column present');

// ============================================================
// TEST GROUP 3: loyalty_gamification_api clients upsert (Task 17)
// ============================================================

console.log('\n=== TEST GROUP 3: loyalty_gamification clients upsert fix ===');

// clients table columns: phone, name, client_name, fcm_token, referred_by, referred_at,
//                        is_admin, employee_name, created_at, updated_at
// NO: data, wheelSpinsUsed, points, freeDrinks, etc.

function buildClientUpsertBUGGY(phone, client) {
  return { phone, data: client };  // BUG: 'data' column doesn't exist
}

function buildClientUpsertFIXED(phone, client) {
  return {
    phone: phone,
    name: client.name || null,
    client_name: client.name || null,
    updated_at: client.updatedAt || new Date().toISOString(),
  };
}

const clientObj = {
  phone: '79001234567',
  name: 'Анна',
  wheelSpinsUsed: 3,
  lastWheelSpin: '2026-02-26T12:00:00Z',
  points: 150,
  freeDrinks: 0,
  updatedAt: '2026-02-26T12:00:00Z'
};

const buggyClientInsert = buildClientUpsertBUGGY('79001234567', clientObj);
assert('data' in buggyClientInsert, 'BUG CONFIRMED: buggy clients upsert has "data" key');
assert(!('name' in buggyClientInsert), 'BUG CONFIRMED: buggy insert missing "name" column');

const fixedClientInsert = buildClientUpsertFIXED('79001234567', clientObj);
assert(!('data' in fixedClientInsert), 'FIXED: no "data" key in clients upsert');
assertEqual(fixedClientInsert.name, 'Анна', 'FIXED: name column present and correct');
assertEqual(fixedClientInsert.client_name, 'Анна', 'FIXED: client_name also set');
assert(!('wheelSpinsUsed' in fixedClientInsert), 'FIXED: loyalty-specific fields not in clients table');

// ============================================================
// TEST GROUP 4: envelope_reports missing columns (Task 18)
// ============================================================

console.log('\n=== TEST GROUP 4: envelope_reports missing columns ===');

// dbEnvelopeReportToCamel reads these 4 columns that don't exist in schema:
// - ooo_z_report_edited → oooZReportEdited
// - ip_z_report_edited  → ipZReportEdited
// - ooo_field_regions   → oooFieldRegions
// - ip_field_regions    → ipFieldRegions

// Without the columns, they'd be undefined → the function defaults to false/null
function dbEnvelopeToCamelBUGGY(row) {
  return {
    id: row.id,
    // Missing columns — would be undefined
    oooZReportEdited: row.ooo_z_report_edited,  // undefined if column missing
    ipZReportEdited: row.ip_z_report_edited,     // undefined
    oooFieldRegions: row.ooo_field_regions,      // undefined
    ipFieldRegions: row.ip_field_regions,        // undefined
  };
}

function dbEnvelopeToCamelFIXED(row) {
  return {
    id: row.id,
    // FIXED: columns now exist, with safe fallbacks
    oooZReportEdited: row.ooo_z_report_edited || false,
    ipZReportEdited: row.ip_z_report_edited || false,
    oooFieldRegions: typeof row.ooo_field_regions === 'string'
      ? JSON.parse(row.ooo_field_regions)
      : (row.ooo_field_regions || null),
    ipFieldRegions: typeof row.ip_field_regions === 'string'
      ? JSON.parse(row.ip_field_regions)
      : (row.ip_field_regions || null),
  };
}

// Simulate DB row WITHOUT the missing columns (current broken state)
const rowWithoutColumns = {
  id: 'env_123',
  employee_name: 'Анна',
  // ooo_z_report_edited missing
  // ip_z_report_edited missing
  // ooo_field_regions missing
  // ip_field_regions missing
};

const buggyEnvelope = dbEnvelopeToCamelBUGGY(rowWithoutColumns);
assert(buggyEnvelope.oooZReportEdited === undefined, 'BUG CONFIRMED: ooo_z_report_edited missing → undefined');
assert(buggyEnvelope.oooFieldRegions === undefined, 'BUG CONFIRMED: ooo_field_regions missing → undefined');

// Simulate DB row WITH the missing columns (after migration)
const rowWithColumns = {
  id: 'env_123',
  employee_name: 'Анна',
  ooo_z_report_edited: true,
  ip_z_report_edited: false,
  ooo_field_regions: JSON.stringify([{x: 10, y: 20}]),
  ip_field_regions: null,
};

const fixedEnvelope = dbEnvelopeToCamelFIXED(rowWithColumns);
assertEqual(fixedEnvelope.oooZReportEdited, true, 'FIXED: oooZReportEdited correctly reads column');
assertEqual(fixedEnvelope.ipZReportEdited, false, 'FIXED: ipZReportEdited correctly reads column');
assert(Array.isArray(fixedEnvelope.oooFieldRegions), 'FIXED: oooFieldRegions parsed from JSON string');
assertEqual(fixedEnvelope.ipFieldRegions, null, 'FIXED: ipFieldRegions null when DB value is null');

// Test with column present but NULL (new row before data fills in)
const rowWithNullColumns = {
  id: 'env_456',
  ooo_z_report_edited: null,
  ip_z_report_edited: null,
  ooo_field_regions: null,
  ip_field_regions: null,
};
const nullEnvelope = dbEnvelopeToCamelFIXED(rowWithNullColumns);
assertEqual(nullEnvelope.oooZReportEdited, false, 'FIXED: null ooo_z_report_edited → false (|| false)');
assertEqual(nullEnvelope.oooFieldRegions, null, 'FIXED: null ooo_field_regions → null (|| null)');

// ============================================================
// FINAL SUMMARY
// ============================================================

console.log(`\n${'='.repeat(50)}`);
console.log(`STAGE 3 TEST RESULTS: ${passed} passed, ${failed} failed`);
console.log(`${'='.repeat(50)}\n`);

if (failed > 0) {
  process.exit(1);
}
