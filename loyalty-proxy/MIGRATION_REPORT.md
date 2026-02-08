# Migration Report: Inline Routes → Module Files

## Executive Summary

**18 module files** exist in `api/` but were NOT connected in `index.js`.
After detailed comparison, most modules were INCOMPATIBLE with the inline code.
The modules were created as simplified versions during async refactoring and lacked critical business logic.

**Strategy Applied: Rewrite modules from inline code (exact copy into module pattern)**

## Current Status (2026-02-08)

### Phase 1: COMPLETED - Wired Up (2 modules)

| Module | Status | Lines Removed from index.js |
|--------|--------|----------------------------|
| shops_api.js | WIRED UP | ~150 lines (DEFAULT_SHOPS, init, 5 routes) |
| menu_api.js | WIRED UP | ~148 lines (MENU_DIR, init, 5 routes) |

**Note:** `SHOPS_DIR` constant kept in index.js for GPS check dependency.

### Phase 2: REWRITTEN - Ready to Wire Up (5 modules)

| Module | Dependencies | Wire-up Call |
|--------|-------------|-------------|
| suppliers_api.js | getNextReferralCode (from employees section) | `setupSuppliersAPI(app, { getNextReferralCode })` |
| recipes_api.js | sanitizeId, isPathSafe (from file_helpers) | `setupRecipesAPI(app)` |
| reviews_api.js | sendPushNotification, sendPushToPhone | `setupReviewsAPI(app, { sendPushNotification, sendPushToPhone })` |
| tests_api.js | sanitizeId, isPathSafe + assignTestPoints (self-contained) | `setupTestsAPI(app)` |
| training_api.js | multer (self-contained), sanitizeId, isPathSafe | `setupTrainingAPI(app)` |

### Phase 3: NOT YET REWRITTEN (11 modules - need inline extraction)

| Module | Complexity | Key Dependencies |
|--------|-----------|-----------------|
| employees_api.js | HIGH | getNextReferralCode, invalidateCache, search, pagination |
| attendance_api.js | VERY HIGH | canMarkAttendance, loadShopSettings, checkShiftTime, bonus/penalty, sendPushToPhone |
| recount_api.js | VERY HIGH | calculateRecountPoints, sendPushToPhone, TIME_EXPIRED, reviewDeadline |
| shifts_api.js | HIGH | getShiftSettings, loadTodayReports, saveTodayReports |
| withdrawals_api.js | MEDIUM | firebase push, loadAllEmployeesForWithdrawals |
| work_schedule_api.js | MEDIUM | loadSchedule, saveSchedule, sendPushToPhone |
| shop_settings_api.js | MEDIUM | document number generation |
| pending_api.js | HIGH | penalty processing, automation state |
| efficiency_penalties_api.js | MEDIUM | report loading helpers |
| loyalty_promo_api.js | LOW | inline is simple settings (2 routes) |
| shop_coordinates_api.js | NEW | No inline counterpart |

### Bonus inline sections (not separate modules):
- bonus_penalties (4 routes)
- orders (7 routes, uses ordersModule)
- app_version (2 routes)
- envelope questions/reports (14 routes)
- shift-handover questions (6 routes)
- shift-handover reports (7 routes)
- recount questions (7 routes)
- shift questions (6 routes)

## Dependency Map

```
index.js exports used by modules:
├── sendPushToPhone() ─── reviews, attendance, recount, work_schedule, withdrawals
├── sendPushNotification() ─── reviews
├── getNextReferralCode() ─── suppliers, employees
├── invalidateCache() ─── employees
├── canMarkAttendance() ─── attendance
├── loadShopSettings() ─── attendance
├── calculateRecountPoints() ─── recount
├── calculateShiftPoints() ─── shifts
├── sanitizeId() ─── ALL (available from file_helpers.js)
├── isPathSafe() ─── ALL (available from file_helpers.js)
└── fileExists() ─── ALL (available from file_helpers.js)
```

## Migration Test

`tests/migration-test.js` — baseline/verify tool for zero-regression testing:
```bash
# Before migration (on live server):
node tests/migration-test.js baseline

# After migration:
node tests/migration-test.js verify
```
Tests 33 endpoints, compares status codes, JSON keys, data types.

## Next Steps for Full Migration

1. **Run baseline** on live server before deploying Phase 1
2. **Deploy Phase 1** (shops + menu already wired)
3. **Verify** with migration test
4. **Wire up Phase 2** modules one at a time with testing
5. **Extract Phase 3** modules from inline code (major effort)
6. **Remove** all inline routes after full verification

## Files Changed

| File | Change |
|------|--------|
| index.js | Added requires for shops/menu, removed inline routes (~300 lines), added setupXxxAPI calls |
| api/shops_api.js | Rewritten to match inline exactly |
| api/menu_api.js | Rewritten to match inline exactly |
| api/suppliers_api.js | Rewritten with getNextReferralCode dependency injection |
| api/recipes_api.js | Rewritten with sanitizeId/isPathSafe + photo routes |
| api/reviews_api.js | Rewritten with push notification dependency injection |
| api/tests_api.js | Rewritten with full assignTestPoints logic |
| api/training_api.js | Rewritten with multer image upload/delete |
| tests/migration-test.js | NEW: baseline/verify testing tool |
