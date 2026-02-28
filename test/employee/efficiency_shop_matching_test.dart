import 'package:flutter_test/flutter_test.dart';
import 'package:arabica_app/features/efficiency/models/efficiency_data_model.dart';
import 'package:arabica_app/features/efficiency/models/manager_efficiency_model.dart';

/// Tests for efficiency shop matching — H-1 and C-2
///
/// H-1: Shop search in my_efficiency_page is case-sensitive.
///      entityId in byShop is lowercase (from efficiency_data_service normalization),
///      but shopAddress in ShopEfficiencyItem is original case from server.
///      Result: shop cards open empty detail page instead of real data.
///
/// C-2: Empty shopId ('') causes false match when two shops both have empty shopId.
///      After fix: shopId is never used for matching, only address and name.

// Helper: simulate OLD case-sensitive matching logic (current broken code)
EfficiencySummary? _findSummaryOLD(
    List<EfficiencySummary> byShop, ShopEfficiencyItem shop) {
  try {
    return byShop.firstWhere(
      (s) =>
          s.entityId == shop.shopAddress ||
          s.entityName == shop.shopName ||
          s.entityId == shop.shopId, // Bug: shopId can be ''
    );
  } catch (_) {
    return null;
  }
}

// Helper: simulate NEW case-insensitive matching logic (fixed code)
EfficiencySummary? _findSummaryNEW(
    List<EfficiencySummary> byShop, ShopEfficiencyItem shop) {
  final normalizedAddress = shop.shopAddress.trim().toLowerCase();
  final normalizedName = shop.shopName.trim().toLowerCase();
  try {
    return byShop.firstWhere(
      (s) =>
          s.entityId.trim().toLowerCase() == normalizedAddress ||
          s.entityName.trim().toLowerCase() == normalizedName,
    );
  } catch (_) {
    return null;
  }
}

// Factory helpers
EfficiencySummary _makeSummary(String entityId, String entityName) {
  return EfficiencySummary(
    entityId: entityId,
    entityName: entityName,
    earnedPoints: 100,
    lostPoints: 10,
    totalPoints: 90,
    recordsCount: 5,
    records: [],
    categorySummaries: [],
  );
}

ShopEfficiencyItem _makeShop({
  String shopId = '',
  required String shopName,
  required String shopAddress,
}) {
  return ShopEfficiencyItem(
    shopId: shopId,
    shopName: shopName,
    shopAddress: shopAddress,
    totalPoints: 90,
    earnedPoints: 100,
    lostPoints: 10,
    recordsCount: 5,
    percentage: 90.0,
  );
}

void main() {
  group('Efficiency Shop Matching', () {
    // ══════════════════════════════════════════════════════
    // H-1: Case-insensitive shop address matching
    // ══════════════════════════════════════════════════════
    group('H-1: Case-insensitive matching', () {
      test('BEFORE FIX: case mismatch causes shop to NOT be found', () {
        // efficiency_data_service normalizes both entityId AND entityName to lowercase
        final byShop = [
          _makeSummary('москва, ул. пушкина, 10', 'кофейня центр'),
        ];
        // server returns ShopEfficiencyItem with original case
        final shop = _makeShop(
          shopName: 'Кофейня Центр', // original case — won't match 'кофейня центр'
          shopAddress: 'Москва, ул. Пушкина, 10', // original case — won't match 'москва...'
        );

        final result = _findSummaryOLD(byShop, shop);

        // Bug confirmed: not found because both address and name have case mismatch
        expect(result, isNull);
      });

      test('AFTER FIX: case mismatch is handled — shop IS found', () {
        // Normalized (lowercase) in byShop, original case from server
        final byShop = [
          _makeSummary('москва, ул. пушкина, 10', 'кофейня центр'),
        ];
        final shop = _makeShop(
          shopName: 'Кофейня Центр', // original case
          shopAddress: 'Москва, ул. Пушкина, 10', // original case
        );

        final result = _findSummaryNEW(byShop, shop);

        expect(result, isNotNull);
        expect(result!.entityId, equals('москва, ул. пушкина, 10'));
      });

      test('AFTER FIX: match works when entityId already lowercase', () {
        final byShop = [
          _makeSummary('ст. ленина, 5', 'Кофейня Восток'),
        ];
        final shop = _makeShop(
          shopName: 'Кофейня Восток',
          shopAddress: 'ст. Ленина, 5',
        );

        final result = _findSummaryNEW(byShop, shop);
        expect(result, isNotNull);
      });

      test('AFTER FIX: match by name when addresses differ', () {
        final byShop = [
          _makeSummary('адрес 1', 'кофейня север'), // lowercase name
        ];
        final shop = _makeShop(
          shopName: 'Кофейня Север', // uppercase name
          shopAddress: 'Адрес 2', // different address
        );

        final result = _findSummaryNEW(byShop, shop);
        expect(result, isNotNull);
      });

      test('AFTER FIX: returns null when neither address nor name match', () {
        final byShop = [
          _makeSummary('ул. пушкина, 10', 'Кофейня Центр'),
        ];
        final shop = _makeShop(
          shopName: 'Кофейня Запад',
          shopAddress: 'ул. Гагарина, 5',
        );

        final result = _findSummaryNEW(byShop, shop);
        expect(result, isNull);
      });

      test('AFTER FIX: extra spaces are trimmed before comparison', () {
        final byShop = [
          _makeSummary('  ул. пушкина, 10  ', 'Кофейня Центр'),
        ];
        final shop = _makeShop(
          shopName: 'Кофейня Центр',
          shopAddress: 'Ул. Пушкина, 10',
        );

        final result = _findSummaryNEW(byShop, shop);
        expect(result, isNotNull);
      });
    });

    // ══════════════════════════════════════════════════════
    // C-2: Empty shopId false match
    // ══════════════════════════════════════════════════════
    group('C-2: Empty shopId false match', () {
      test('BEFORE FIX: two shops with empty shopId cause false match', () {
        final byShop = [
          _makeSummary('', 'Кофейня А'), // entityId = '' (from empty shopId)
        ];
        final shop = _makeShop(
          shopId: '', // server returned empty shopId
          shopName: 'Совсем другой магазин',
          shopAddress: 'Другой адрес',
        );

        final result = _findSummaryOLD(byShop, shop);

        // Bug: '' == '' causes wrong match
        expect(result, isNotNull);
        expect(result!.entityName, equals('Кофейня А')); // wrong shop!
      });

      test('AFTER FIX: empty shopId does NOT cause false match', () {
        final byShop = [
          _makeSummary('', 'Кофейня А'),
        ];
        final shop = _makeShop(
          shopId: '',
          shopName: 'Совсем другой магазин',
          shopAddress: 'Другой адрес',
        );

        final result = _findSummaryNEW(byShop, shop);

        // Fixed: no false match via empty shopId
        expect(result, isNull);
      });
    });
  });
}
