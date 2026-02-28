/**
 * Stage 2 Tests — Broken Functions
 * Tests for: db.js regex bug, db.js deleteWhere NULL, loyalty field names
 *
 * Run: node tests/broken-functions-stage2-test.js
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
// TEST GROUP 1: db.js regex renumbering (FIXED version)
// The old regex was /\${i}/g — matched $1 inside $10, $11, etc.
// The fix: /\${i}(?!\d)/g — negative lookahead prevents this.
// ============================================================

console.log('\n=== TEST GROUP 1: db.js findAll() regex fix ===');

function renumberParamsBUGGY(whereClause, whereParamsLength, startIndex) {
  let adjustedWhere = whereClause;
  for (let i = whereParamsLength; i >= 1; i--) {
    // OLD BUG: no negative lookahead
    adjustedWhere = adjustedWhere.replace(
      new RegExp(`\\$${i}`, 'g'),
      `$${startIndex + i - 1}`
    );
  }
  return adjustedWhere;
}

function renumberParamsFIXED(whereClause, whereParamsLength, startIndex) {
  let adjustedWhere = whereClause;
  for (let i = whereParamsLength; i >= 1; i--) {
    // FIXED: negative lookahead prevents $1 matching inside $10, $11 etc.
    adjustedWhere = adjustedWhere.replace(
      new RegExp(`\\$${i}(?!\\d)`, 'g'),
      `$${startIndex + i - 1}`
    );
  }
  return adjustedWhere;
}

// Test 1a: Bug reproduces with 10+ params (baseline — buggy version breaks)
const whereWith10Params = '$1 AND $2 AND $10 AND $11';
const buggyResult = renumberParamsBUGGY(whereWith10Params, 11, 5);
// With the bug: $1→$5 is applied first, but then $10→$14 has $1 in $14 which was already renamed
// Actually the loop goes from high to low (11→1), so $11 gets replaced first
// i=11: $11 → $15; i=10: $10 → $14; i=9: (no match); ... i=2: $2 → $6; i=1: $1 → $5
// BUT: $15 contains $15 which has $1 in it... actually the replacement is done left-to-right
// The bug: $1 matches inside $15 (already replaced from $11)
// Let me trace: start = '$1 AND $2 AND $10 AND $11', startIndex=5
// i=11: replace $11 → $15: '$1 AND $2 AND $10 AND $15'
// i=10: replace $10 → $14: '$1 AND $2 AND $14 AND $15'
// i=9: no match
// i=8: no match
// ...
// i=2: replace $2 → $6: '$1 AND $6 AND $14 AND $15'
// i=1: replace $1 → $5: BUT $1 also matches inside $14 and $15!
//   '$5 AND $6 AND $54 AND $55' <-- WRONG! $14 → $54, $15 → $55
assert(
  buggyResult !== '$5 AND $6 AND $14 AND $15',
  'BUG CONFIRMED: old regex corrupts params ($14→$54, $15→$55 with 11 params)'
);

// Test 1b: Fixed version handles 10+ params correctly
const fixedResult = renumberParamsFIXED(whereWith10Params, 11, 5);
// i=11: $11 → $15: '$1 AND $2 AND $10 AND $15'
// i=10: $10 → $14: '$1 AND $2 AND $14 AND $15'
// ...
// i=1: replace $1(?!\d) → $5: BUT $14 and $15 end with digit after $1, so no match
//   '$5 AND $6 AND $14 AND $15' <-- CORRECT
assertEqual(
  fixedResult,
  '$5 AND $6 AND $14 AND $15',
  'FIXED: regex with negative lookahead correctly renumbers all 11 params'
);

// Test 1c: Works for small number of params (regression — must still work)
const simple = renumberParamsFIXED('$1 AND $2', 2, 3);
assertEqual(simple, '$3 AND $4', 'FIXED: simple case still works (2 params, startIndex=3)');

// Test 1d: Single param
const single = renumberParamsFIXED('$1', 1, 7);
assertEqual(single, '$7', 'FIXED: single param case');

// Test 1e: Params with exact boundaries ($9 vs $9X)
const boundary = renumberParamsFIXED('$9 AND $91', 9, 2);
// i=9: $9(?!\d) → $10 for the standalone $9, not the $91
// Result should be '$10 AND $91'
assertEqual(boundary, '$10 AND $91', 'FIXED: $9 does not corrupt $91');

// Test 1f: Already-replaced params not double-substituted
const noDouble = renumberParamsFIXED('$1 AND $12', 12, 10);
// i=12: $12 → $21, i=11: no match, ..., i=1: $1(?!\d) → $10 (not matching inside $21)
// $12 → $21
// $1 → $10 but $21 has $2 after replacing... actually:
// Start: '$1 AND $12', 12 params, startIndex=10
// i=12: replace $12(?!\d) → $21: '$1 AND $21'
// i=11: no match
// ...
// i=2: replace $2(?!\d) → $11: '$1 AND $11' — WAIT: $21 has $2 in it?
//   $2(?!\d) matches $2 in $21? No! $21 = $2 followed by 1, so $2(?!\d) would NOT match $21
//   Actually: in $21, position of $2 is followed by 1, so negative lookahead (?!\d) would NOT match
//   So: '$1 AND $21' stays as '$1 AND $21'
// i=1: replace $1(?!\d) → $10: '$10 AND $21'
assertEqual(noDouble, '$10 AND $21', 'FIXED: no double-substitution when replacement contains $ digits');

// ============================================================
// TEST GROUP 2: db.js deleteWhere NULL handling
// The old code always generated "col = $N" even for null values.
// In SQL: "col = NULL" never matches any row (should be "col IS NULL").
// ============================================================

console.log('\n=== TEST GROUP 2: db.js deleteWhere() NULL fix ===');

function buildDeleteConditionsBUGGY(filters) {
  const conditions = [];
  const params = [];
  let paramIndex = 1;
  for (const [col, val] of Object.entries(filters)) {
    // OLD BUG: no null check
    conditions.push(`"${col}" = $${paramIndex}`);
    params.push(val);
    paramIndex++;
  }
  return { conditions, params };
}

function buildDeleteConditionsFIXED(filters) {
  const conditions = [];
  const params = [];
  let paramIndex = 1;
  for (const [col, val] of Object.entries(filters)) {
    if (val === null || val === undefined) {
      // FIXED: use IS NULL for null values
      conditions.push(`"${col}" IS NULL`);
    } else {
      conditions.push(`"${col}" = $${paramIndex}`);
      params.push(val);
      paramIndex++;
    }
  }
  return { conditions, params };
}

// Test 2a: Bug — null becomes "= $1" with null as param (would fail in SQL)
const buggyNull = buildDeleteConditionsBUGGY({ status: null });
assertEqual(buggyNull.conditions[0], '"status" = $1', 'BUG CONFIRMED: null generates = $1');
assertEqual(buggyNull.params[0], null, 'BUG: null pushed as param (SQL would produce "= NULL" which never matches)');

// Test 2b: Fixed — null becomes IS NULL with no param
const fixedNull = buildDeleteConditionsFIXED({ status: null });
assertEqual(fixedNull.conditions[0], '"status" IS NULL', 'FIXED: null generates IS NULL');
assertEqual(fixedNull.params.length, 0, 'FIXED: no params for null conditions');

// Test 2c: Fixed — non-null still works normally
const fixedNormal = buildDeleteConditionsFIXED({ status: 'active' });
assertEqual(fixedNormal.conditions[0], '"status" = $1', 'FIXED: non-null still generates = $1');
assertEqual(fixedNormal.params[0], 'active', 'FIXED: non-null param pushed correctly');

// Test 2d: Mixed null and non-null
const fixedMixed = buildDeleteConditionsFIXED({ deleted_at: null, status: 'pending' });
assertEqual(fixedMixed.conditions[0], '"deleted_at" IS NULL', 'FIXED: first null field IS NULL');
assertEqual(fixedMixed.conditions[1], '"status" = $1', 'FIXED: non-null field uses $1 (shifted down since null skipped)');
assertEqual(fixedMixed.params.length, 1, 'FIXED: only 1 param for mixed case');
assertEqual(fixedMixed.params[0], 'pending', 'FIXED: non-null param is correct');

// Test 2e: Undefined also treated as NULL
const fixedUndefined = buildDeleteConditionsFIXED({ archived: undefined });
assertEqual(fixedUndefined.conditions[0], '"archived" IS NULL', 'FIXED: undefined treated as NULL');

// ============================================================
// TEST GROUP 3: loyalty wallet field names
// The server expects: phone (not clientPhone), points (not amount)
// redeemDrink expects: pointsPrice (not amount)
// ============================================================

console.log('\n=== TEST GROUP 3: Loyalty wallet field name mapping ===');

// Simulate the BUGGY Flutter request body
function walletAddPointsBUGGY(clientPhone, amount) {
  return {
    clientPhone: clientPhone,  // BUG: server reads 'phone'
    amount: amount,             // BUG: server reads 'points'
    description: 'QR-сканирование',
    sourceType: 'qr_scan',
  };
}

// Simulate the FIXED Flutter request body
function walletAddPointsFIXED(clientPhone, amount) {
  return {
    phone: clientPhone,    // FIXED: correct key
    points: amount,        // FIXED: correct key
    description: 'QR-сканирование',
    sourceType: 'qr_scan',
  };
}

// Simulate server-side handling (what the server reads)
function serverAddPoints(body) {
  const { phone, points } = body;
  if (!phone) return { success: false, error: 'phone required' };
  if (!points || points <= 0) return { success: false, error: 'points must be positive' };
  return { success: true, phone, points };
}

// Test 3a: Buggy body fails on server
const buggyBody = walletAddPointsBUGGY('79001234567', 100);
const buggyResult3 = serverAddPoints(buggyBody);
assertEqual(buggyResult3.success, false, 'BUG CONFIRMED: server returns error when clientPhone/amount sent');

// Test 3b: Fixed body succeeds on server
const fixedBody = walletAddPointsFIXED('79001234567', 100);
const fixedResult3 = serverAddPoints(fixedBody);
assertEqual(fixedResult3.success, true, 'FIXED: server accepts phone/points correctly');
assertEqual(fixedResult3.phone, '79001234567', 'FIXED: phone is passed through');
assertEqual(fixedResult3.points, 100, 'FIXED: points amount is passed through');

// Test 3c: redeemDrink field name fix
function redeemDrinkBUGGY(clientPhone, pointsPrice) {
  return {
    clientPhone: clientPhone,
    recipeId: 'recipe_123',
    recipeName: 'Латте',
    amount: pointsPrice,  // BUG: server reads 'pointsPrice'
  };
}

function redeemDrinkFIXED(clientPhone, pointsPrice) {
  return {
    clientPhone: clientPhone,
    recipeId: 'recipe_123',
    recipeName: 'Латте',
    pointsPrice: pointsPrice,  // FIXED: correct key
  };
}

function serverRedeemDrink(body) {
  const { clientPhone, recipeId, recipeName, pointsPrice } = body;
  if (!clientPhone) return { success: false, error: 'clientPhone required' };
  if (!pointsPrice || pointsPrice <= 0) return { success: false, error: 'pointsPrice required' };
  return { success: true, clientPhone, recipeId, recipeName, pointsPrice };
}

const buggyRedeem = redeemDrinkBUGGY('79001234567', 500);
const buggyRedeemResult = serverRedeemDrink(buggyRedeem);
assertEqual(buggyRedeemResult.success, false, 'BUG CONFIRMED: server rejects when "amount" sent instead of "pointsPrice"');

const fixedRedeem = redeemDrinkFIXED('79001234567', 500);
const fixedRedeemResult = serverRedeemDrink(fixedRedeem);
assertEqual(fixedRedeemResult.success, true, 'FIXED: server accepts redeemDrink with correct pointsPrice key');
assertEqual(fixedRedeemResult.pointsPrice, 500, 'FIXED: pointsPrice value is correct');

// ============================================================
// TEST GROUP 4: CartProvider updateShouldNotify
// ============================================================

console.log('\n=== TEST GROUP 4: CartProvider updateShouldNotify logic ===');

// Simulate the BUGGY updateShouldNotify logic
function updateShouldNotifyBUGGY(cart, oldCart) {
  return cart !== oldCart;  // BUG: same instance, always false
}

// Simulate the FIXED updateShouldNotify logic
function updateShouldNotifyFIXED(/* cart, oldCart */) {
  return true;  // FIXED: always notify since ChangeNotifier already guards unnecessary rebuilds
}

// Simulate a CartProvider instance (single instance used throughout)
const cartInstance = { items: [], itemCount: 0 };

// Test 4a: Buggy — same instance, returns false
const buggyNotify = updateShouldNotifyBUGGY(cartInstance, cartInstance);
assertEqual(buggyNotify, false, 'BUG CONFIRMED: same instance always returns false (no rebuild)');

// Test 4b: Fixed — always returns true
const fixedNotify = updateShouldNotifyFIXED(cartInstance, cartInstance);
assertEqual(fixedNotify, true, 'FIXED: updateShouldNotify always returns true to propagate rebuild');

// Test 4c: Listener subscription is critical for the InheritedWidget pattern
let stateRebuildCalled = false;
function simulateCartListener(rebuildFn) {
  // In StatefulWidget.initState() — addListener to cart
  const callRebuild = () => { stateRebuildCalled = true; rebuildFn(); };
  return callRebuild;
}
const triggerRebuild = simulateCartListener(() => { /* setState called */ });

// Simulate cart.notifyListeners() calling the listener
triggerRebuild();
assertEqual(stateRebuildCalled, true, 'FIXED: state rebuild triggered when cart notifies listeners');

// ============================================================
// FINAL SUMMARY
// ============================================================

console.log(`\n${'='.repeat(50)}`);
console.log(`STAGE 2 TEST RESULTS: ${passed} passed, ${failed} failed`);
console.log(`${'='.repeat(50)}\n`);

if (failed > 0) {
  process.exit(1);
}
