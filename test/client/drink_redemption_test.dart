import 'package:flutter_test/flutter_test.dart';

/// P2 Тесты выкупа напитка за баллы (Фаза 2)
/// Покрывает: выбор напитка, создание QR, сканирование, подтверждение, списание
void main() {
  group('Drink Redemption Tests (Phase 2)', () {
    late MockRedemptionService mockService;

    setUp(() async {
      mockService = MockRedemptionService();
    });

    tearDown(() async {
      mockService.clear();
    });

    // ==================== КАТАЛОГ НАПИТКОВ ====================

    group('Drink Catalog Tests', () {
      test('CT-RDM-001: Только напитки с pointsPrice отображаются', () async {
        mockService.addRecipe(id: 'r1', name: 'Латте', pointsPrice: 100);
        mockService.addRecipe(id: 'r2', name: 'Эспрессо', pointsPrice: null);
        mockService.addRecipe(id: 'r3', name: 'Капучино', pointsPrice: 150);

        final available = mockService.getAvailableDrinks();

        expect(available, hasLength(2));
        expect(available.map((d) => d['name']), containsAll(['Латте', 'Капучино']));
      });

      test('CT-RDM-002: Поиск по названию напитка', () async {
        mockService.addRecipe(id: 'r1', name: 'Латте', pointsPrice: 100);
        mockService.addRecipe(id: 'r2', name: 'Капучино', pointsPrice: 150);
        mockService.addRecipe(id: 'r3', name: 'Латте Макиато', pointsPrice: 200);

        final results = mockService.searchDrinks('латте');

        expect(results, hasLength(2));
        expect(results[0]['name'], 'Латте');
        expect(results[1]['name'], 'Латте Макиато');
      });

      test('CT-RDM-003: Доступность напитка зависит от баланса', () async {
        mockService.setBalance(80);

        final canAfford100 = mockService.canAfford(100);
        final canAfford50 = mockService.canAfford(50);

        expect(canAfford100, false);
        expect(canAfford50, true);
      });
    });

    // ==================== СОЗДАНИЕ ЗАЯВКИ НА ВЫКУП ====================

    group('Redemption Creation Tests', () {
      test('CT-RDM-004: Успешное создание заявки', () async {
        mockService.setBalance(200);

        final result = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );

        expect(result['success'], true);
        expect(result['qrToken'], startsWith('redemption_'));
        expect(result['redemptionId'], isNotNull);
      });

      test('CT-RDM-005: Нельзя создать заявку без достаточных баллов', () async {
        mockService.setBalance(50);

        final result = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );

        expect(result['success'], false);
        expect(result['error'], contains('Недостаточно'));
      });

      test('CT-RDM-006: QR-токен уникален для каждой заявки', () async {
        mockService.setBalance(500);

        final r1 = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );
        final r2 = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );

        expect(r1['qrToken'], isNot(equals(r2['qrToken'])));
      });

      test('CT-RDM-007: Баллы НЕ списываются при создании заявки', () async {
        mockService.setBalance(200);

        await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );

        // Balance unchanged — points only deducted on confirmation
        expect(mockService.getBalance(), 200);
      });
    });

    // ==================== СКАНИРОВАНИЕ СОТРУДНИКОМ ====================

    group('Scan Redemption Tests', () {
      test('CT-RDM-008: Успешное сканирование QR выкупа', () async {
        mockService.setBalance(200);
        final created = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );
        final qrToken = created['qrToken'] as String;

        final scanResult = await mockService.scanRedemption(qrToken);

        expect(scanResult['success'], true);
        expect(scanResult['redemption']['recipeName'], 'Латте');
        expect(scanResult['redemption']['pointsPrice'], 100);
        expect(scanResult['redemption']['status'], 'scanned');
      });

      test('CT-RDM-009: Сканирование несуществующего QR → ошибка', () async {
        final scanResult = await mockService.scanRedemption('redemption_fake');

        expect(scanResult['success'], false);
        expect(scanResult['error'], contains('не найден'));
      });

      test('CT-RDM-010: Повторное сканирование подтверждённого QR → ошибка', () async {
        mockService.setBalance(200);
        final created = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );
        final qrToken = created['qrToken'] as String;
        final redemptionId = created['redemptionId'] as String;

        await mockService.scanRedemption(qrToken);
        await mockService.confirmRedemption(redemptionId, '79990001234');

        final scanAgain = await mockService.scanRedemption(qrToken);
        expect(scanAgain['success'], false);
        expect(scanAgain['error'], contains('уже'));
      });
    });

    // ==================== ПОДТВЕРЖДЕНИЕ ВЫДАЧИ ====================

    group('Confirm Redemption Tests', () {
      test('CT-RDM-011: Подтверждение списывает баллы', () async {
        mockService.setBalance(200);
        final created = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );
        final qrToken = created['qrToken'] as String;
        final redemptionId = created['redemptionId'] as String;

        await mockService.scanRedemption(qrToken);
        final confirmResult = await mockService.confirmRedemption(redemptionId, '79990001234');

        expect(confirmResult['success'], true);
        expect(confirmResult['newBalance'], 100); // 200 - 100
        expect(mockService.getBalance(), 100);
      });

      test('CT-RDM-012: Подтверждение создаёт транзакцию списания', () async {
        mockService.setBalance(200);
        final created = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );
        final qrToken = created['qrToken'] as String;
        final redemptionId = created['redemptionId'] as String;

        await mockService.scanRedemption(qrToken);
        await mockService.confirmRedemption(redemptionId, '79990001234');

        final transactions = mockService.getTransactions('79001111111');
        expect(transactions, hasLength(1));
        expect(transactions[0]['type'], 'spend');
        expect(transactions[0]['sourceType'], 'drink_redemption');
        expect(transactions[0]['amount'], 100);
      });

      test('CT-RDM-013: Повторное подтверждение невозможно', () async {
        mockService.setBalance(200);
        final created = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );
        final qrToken = created['qrToken'] as String;
        final redemptionId = created['redemptionId'] as String;

        await mockService.scanRedemption(qrToken);
        await mockService.confirmRedemption(redemptionId, '79990001234');

        // Try to confirm again
        final again = await mockService.confirmRedemption(redemptionId, '79990001234');
        expect(again['success'], false);
        expect(again['error'], contains('уже'));

        // Balance not double-deducted
        expect(mockService.getBalance(), 100);
      });

      test('CT-RDM-014: totalPointsEarned не меняется при списании за напиток', () async {
        mockService.setBalance(200);
        mockService.setTotalPointsEarned(200);
        final created = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'r1',
          recipeName: 'Латте',
          pointsPrice: 100,
        );
        final qrToken = created['qrToken'] as String;
        final redemptionId = created['redemptionId'] as String;

        await mockService.scanRedemption(qrToken);
        await mockService.confirmRedemption(redemptionId, '79990001234');

        expect(mockService.getTotalPointsEarned(), 200); // Unchanged
      });
    });

    // ==================== ПОЛНЫЙ ЦИКЛ ====================

    group('Full Cycle Tests', () {
      test('CT-RDM-015: Полный цикл выкупа напитка', () async {
        // Step 0: Client has 300 points
        mockService.setBalance(300);
        mockService.addRecipe(id: 'latte', name: 'Латте', pointsPrice: 100);

        // Step 1: Client picks Латте, creates redemption
        final created = await mockService.redeemDrink(
          clientPhone: '79001111111',
          recipeId: 'latte',
          recipeName: 'Латте',
          pointsPrice: 100,
        );
        expect(created['success'], true);
        expect(mockService.getBalance(), 300); // Not deducted yet

        // Step 2: Employee scans QR
        final scanned = await mockService.scanRedemption(created['qrToken'] as String);
        expect(scanned['success'], true);
        expect(scanned['redemption']['recipeName'], 'Латте');

        // Step 3: Employee confirms delivery
        final confirmed = await mockService.confirmRedemption(
          created['redemptionId'] as String,
          '79990001234',
        );
        expect(confirmed['success'], true);
        expect(confirmed['newBalance'], 200); // 300 - 100
        expect(mockService.getBalance(), 200);
      });
    });
  });
}

// ==================== MOCK REDEMPTION SERVICE ====================

class MockRedemptionService {
  int _balance = 0;
  int _totalPointsEarned = 0;
  final List<Map<String, dynamic>> _recipes = [];
  final Map<String, Map<String, dynamic>> _redemptions = {};
  final Map<String, List<Map<String, dynamic>>> _transactions = {};
  int _counter = 0;

  void setBalance(int b) => _balance = b;
  int getBalance() => _balance;
  void setTotalPointsEarned(int t) => _totalPointsEarned = t;
  int getTotalPointsEarned() => _totalPointsEarned;

  void addRecipe({required String id, required String name, int? pointsPrice}) {
    _recipes.add({'id': id, 'name': name, 'pointsPrice': pointsPrice, 'category': 'Кофе'});
  }

  List<Map<String, dynamic>> getAvailableDrinks() {
    return _recipes.where((r) => r['pointsPrice'] != null && (r['pointsPrice'] as int) > 0).toList();
  }

  List<Map<String, dynamic>> searchDrinks(String query) {
    final q = query.toLowerCase();
    return getAvailableDrinks().where((r) => (r['name'] as String).toLowerCase().contains(q)).toList();
  }

  bool canAfford(int pointsPrice) => _balance >= pointsPrice;

  Future<Map<String, dynamic>> redeemDrink({
    required String clientPhone,
    required String recipeId,
    required String recipeName,
    required int pointsPrice,
  }) async {
    if (_balance < pointsPrice) {
      return {'success': false, 'error': 'Недостаточно баллов'};
    }

    _counter++;
    final redemptionId = 'rdm_$_counter';
    final qrToken = 'redemption_mock_$_counter';

    _redemptions[redemptionId] = {
      'id': redemptionId,
      'clientPhone': clientPhone,
      'recipeId': recipeId,
      'recipeName': recipeName,
      'pointsPrice': pointsPrice,
      'qrToken': qrToken,
      'status': 'pending',
    };

    return {'success': true, 'qrToken': qrToken, 'redemptionId': redemptionId};
  }

  Future<Map<String, dynamic>> scanRedemption(String qrToken) async {
    final entry = _redemptions.values.where((r) => r['qrToken'] == qrToken).firstOrNull;
    if (entry == null) return {'success': false, 'error': 'Заявка не найдена'};
    if (entry['status'] == 'confirmed') return {'success': false, 'error': 'Заявка уже подтверждена'};

    entry['status'] = 'scanned';
    return {
      'success': true,
      'redemption': {
        'id': entry['id'],
        'clientPhone': entry['clientPhone'],
        'recipeName': entry['recipeName'],
        'pointsPrice': entry['pointsPrice'],
        'status': 'scanned',
      },
    };
  }

  Future<Map<String, dynamic>> confirmRedemption(String redemptionId, String employeePhone) async {
    final entry = _redemptions[redemptionId];
    if (entry == null) return {'success': false, 'error': 'Заявка не найдена'};
    if (entry['status'] == 'confirmed') return {'success': false, 'error': 'Заявка уже подтверждена'};

    final pointsPrice = entry['pointsPrice'] as int;
    if (_balance < pointsPrice) return {'success': false, 'error': 'Недостаточно баллов'};

    _balance -= pointsPrice;
    entry['status'] = 'confirmed';

    final phone = entry['clientPhone'] as String;
    _transactions.putIfAbsent(phone, () => []);
    _transactions[phone]!.add({
      'type': 'spend',
      'amount': pointsPrice,
      'sourceType': 'drink_redemption',
      'sourceId': redemptionId,
      'balanceAfter': _balance,
    });

    return {'success': true, 'newBalance': _balance};
  }

  List<Map<String, dynamic>> getTransactions(String phone) {
    return _transactions[phone] ?? [];
  }

  void clear() {
    _balance = 0;
    _totalPointsEarned = 0;
    _recipes.clear();
    _redemptions.clear();
    _transactions.clear();
    _counter = 0;
  }
}
