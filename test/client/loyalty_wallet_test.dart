import 'package:flutter_test/flutter_test.dart';

/// P2 Тесты кошелька баллов лояльности (Фаза 1)
/// Покрывает: баланс, начисление, списание, история, уровни по баллам
void main() {
  group('Loyalty Wallet Tests (Phase 1)', () {
    late MockWalletService mockWallet;

    setUp(() async {
      mockWallet = MockWalletService();
    });

    tearDown(() async {
      mockWallet.clear();
    });

    // ==================== БАЛАНС КОШЕЛЬКА ====================

    group('Wallet Balance Tests', () {
      test('CT-WALLET-001: Начальный баланс равен 0', () async {
        final balance = await mockWallet.getBalance('79001111111');

        expect(balance['loyaltyPoints'], 0);
        expect(balance['totalPointsEarned'], 0);
      });

      test('CT-WALLET-002: Баланс увеличивается при начислении', () async {
        final phone = '79001111111';

        await mockWallet.addPoints(phone, amount: 10, employeePhone: '79990001234');
        final balance = await mockWallet.getBalance(phone);

        expect(balance['loyaltyPoints'], 10);
        expect(balance['totalPointsEarned'], 10);
      });

      test('CT-WALLET-003: Множественные начисления суммируются', () async {
        final phone = '79002222222';

        await mockWallet.addPoints(phone, amount: 10, employeePhone: '79990001234');
        await mockWallet.addPoints(phone, amount: 10, employeePhone: '79990001234');
        await mockWallet.addPoints(phone, amount: 10, employeePhone: '79990001234');
        final balance = await mockWallet.getBalance(phone);

        expect(balance['loyaltyPoints'], 30);
        expect(balance['totalPointsEarned'], 30);
      });

      test('CT-WALLET-004: Баланс уменьшается при списании', () async {
        final phone = '79003333333';

        await mockWallet.addPoints(phone, amount: 50, employeePhone: '79990001234');
        await mockWallet.spendPoints(phone, amount: 20);
        final balance = await mockWallet.getBalance(phone);

        expect(balance['loyaltyPoints'], 30);
        // totalPointsEarned НЕ уменьшается при списании
        expect(balance['totalPointsEarned'], 50);
      });

      test('CT-WALLET-005: Невозможно списать больше чем есть', () async {
        final phone = '79004444444';

        await mockWallet.addPoints(phone, amount: 10, employeePhone: '79990001234');
        final result = await mockWallet.spendPoints(phone, amount: 20);

        expect(result['success'], false);
        expect(result['error'], contains('Недостаточно'));
      });

      test('CT-WALLET-006: Невозможно начислить 0 или отрицательное число', () async {
        final phone = '79005555555';

        final result1 = await mockWallet.addPoints(phone, amount: 0, employeePhone: '79990001234');
        final result2 = await mockWallet.addPoints(phone, amount: -5, employeePhone: '79990001234');

        expect(result1['success'], false);
        expect(result2['success'], false);
      });

      test('CT-WALLET-007: Невозможно списать 0 или отрицательное число', () async {
        final phone = '79006666666';

        await mockWallet.addPoints(phone, amount: 50, employeePhone: '79990001234');
        final result1 = await mockWallet.spendPoints(phone, amount: 0);
        final result2 = await mockWallet.spendPoints(phone, amount: -5);

        expect(result1['success'], false);
        expect(result2['success'], false);
      });
    });

    // ==================== ИСТОРИЯ ТРАНЗАКЦИЙ ====================

    group('Transaction History Tests', () {
      test('CT-WALLET-008: История пуста для нового клиента', () async {
        final transactions = await mockWallet.getTransactions('79007777777');

        expect(transactions, isEmpty);
      });

      test('CT-WALLET-009: Начисление создаёт запись в истории', () async {
        final phone = '79008888888';

        await mockWallet.addPoints(phone, amount: 10, employeePhone: '79990001234');
        final transactions = await mockWallet.getTransactions(phone);

        expect(transactions, hasLength(1));
        expect(transactions[0]['type'], 'earn');
        expect(transactions[0]['amount'], 10);
        expect(transactions[0]['sourceType'], 'qr_scan');
      });

      test('CT-WALLET-010: Списание создаёт запись в истории', () async {
        final phone = '79009999999';

        await mockWallet.addPoints(phone, amount: 50, employeePhone: '79990001234');
        await mockWallet.spendPoints(phone, amount: 20, sourceType: 'drink_redemption');
        final transactions = await mockWallet.getTransactions(phone);

        expect(transactions, hasLength(2));
        expect(transactions[1]['type'], 'spend');
        expect(transactions[1]['amount'], 20);
        expect(transactions[1]['sourceType'], 'drink_redemption');
      });

      test('CT-WALLET-011: Баланс после каждой транзакции корректен', () async {
        final phone = '79010000000';

        await mockWallet.addPoints(phone, amount: 30, employeePhone: '79990001234');
        await mockWallet.addPoints(phone, amount: 20, employeePhone: '79990001234');
        await mockWallet.spendPoints(phone, amount: 15);
        final transactions = await mockWallet.getTransactions(phone);

        expect(transactions[0]['balanceAfter'], 30);
        expect(transactions[1]['balanceAfter'], 50);
        expect(transactions[2]['balanceAfter'], 35);
      });
    });

    // ==================== УРОВНИ ПО БАЛЛАМ ====================

    group('Points-Based Level Tests', () {
      test('CT-WALLET-012: Новый клиент имеет уровень 1 (Новичок)', () async {
        final level = mockWallet.calculateLevel(0);

        expect(level['id'], 1);
        expect(level['name'], 'Новичок');
      });

      test('CT-WALLET-013: Уровень повышается с накоплением баллов', () async {
        // minFreeDrinks=2 → minTotalPoints=20
        final level = mockWallet.calculateLevel(25);

        expect(level['id'], 2);
        expect(level['name'], 'Любитель');
      });

      test('CT-WALLET-014: Максимальный уровень при большом количестве', () async {
        final level = mockWallet.calculateLevel(2000);

        expect(level['id'], 10);
        expect(level['name'], 'Император');
      });

      test('CT-WALLET-015: totalPointsEarned определяет уровень, не loyaltyPoints', () async {
        final phone = '79011111111';

        // Начислили 100 баллов, потратили 80 → баланс 20, но totalEarned = 100
        await mockWallet.addPoints(phone, amount: 100, employeePhone: '79990001234');
        await mockWallet.spendPoints(phone, amount: 80);

        final balance = await mockWallet.getBalance(phone);
        expect(balance['loyaltyPoints'], 20);
        expect(balance['totalPointsEarned'], 100);

        // Уровень считается по totalPointsEarned (100), а не loyaltyPoints (20)
        // minFreeDrinks=10 → minTotalPoints=100 → уровень 4 "Знаток"
        final level = mockWallet.calculateLevel(balance['totalPointsEarned'] as int);
        expect(level['id'], 4);
      });
    });

    // ==================== КОЛЕСО УДАЧИ ПО БАЛЛАМ ====================

    group('Wheel Spins by Points Tests', () {
      test('CT-WALLET-016: Прокрутки считаются по totalPointsEarned', () async {
        // freeDrinksPerSpin=5, значит pointsPerSpin=50
        final spins = mockWallet.calculateSpinsEarned(totalPointsEarned: 100, pointsPerSpin: 50);

        expect(spins, 2); // 100 / 50 = 2
      });

      test('CT-WALLET-017: Прокрутки не теряются при списании баллов', () async {
        final phone = '79012222222';

        // Начислили 100, потратили 80 → totalEarned=100
        await mockWallet.addPoints(phone, amount: 100, employeePhone: '79990001234');
        await mockWallet.spendPoints(phone, amount: 80);

        final balance = await mockWallet.getBalance(phone);
        final spins = mockWallet.calculateSpinsEarned(
          totalPointsEarned: balance['totalPointsEarned'] as int,
          pointsPerSpin: 50,
        );

        expect(spins, 2); // totalPointsEarned=100, не loyaltyPoints=20
      });

      test('CT-WALLET-018: Баллы до следующей прокрутки', () async {
        final pointsToNext = mockWallet.pointsToNextSpin(totalPointsEarned: 75, pointsPerSpin: 50);

        // 75 % 50 = 25, нужно ещё 50 - 25 = 25
        expect(pointsToNext, 25);
      });
    });

    // ==================== НАСТРОЙКА POINTSPERSCAN ====================

    group('PointsPerScan Settings Tests', () {
      test('CT-WALLET-019: По умолчанию pointsPerScan = 10', () async {
        final settings = mockWallet.getPromoSettings();

        expect(settings['pointsPerScan'], 10);
      });

      test('CT-WALLET-020: Изменение pointsPerScan влияет на начисление', () async {
        final phone = '79013333333';

        // Устанавливаем 15 баллов за сканирование
        mockWallet.updatePointsPerScan(15);

        // При сканировании добавляем pointsPerScan баллов
        final settings = mockWallet.getPromoSettings();
        await mockWallet.addPoints(
          phone,
          amount: settings['pointsPerScan'] as int,
          employeePhone: '79990001234',
        );
        final balance = await mockWallet.getBalance(phone);

        expect(balance['loyaltyPoints'], 15);
      });
    });

    // ==================== МИГРАЦИЯ ДАННЫХ ====================

    group('Data Migration Tests', () {
      test('CT-WALLET-021: Миграция freeDrinksGiven → totalPointsEarned', () async {
        // Старый клиент с freeDrinksGiven=5, pointsRequired=9
        final migrated = mockWallet.migrateClientData(
          freeDrinksGiven: 5,
          points: 3, // Текущие баллы цикла (0-8)
          pointsRequired: 9,
        );

        // totalPointsEarned = freeDrinksGiven * pointsRequired = 5 * 9 = 45
        // loyaltyPoints = points (текущие баллы цикла) = 3
        expect(migrated['totalPointsEarned'], 45);
        expect(migrated['loyaltyPoints'], 3);
      });

      test('CT-WALLET-022: Миграция клиента с 0 баллами', () async {
        final migrated = mockWallet.migrateClientData(
          freeDrinksGiven: 0,
          points: 0,
          pointsRequired: 9,
        );

        expect(migrated['totalPointsEarned'], 0);
        expect(migrated['loyaltyPoints'], 0);
      });
    });
  });
}

// ==================== MOCK WALLET SERVICE ====================

class MockWalletService {
  final Map<String, int> _loyaltyPoints = {};
  final Map<String, int> _totalPointsEarned = {};
  final Map<String, List<Map<String, dynamic>>> _transactions = {};
  int _pointsPerScan = 10;

  // Default levels (same as server defaults)
  final List<Map<String, dynamic>> _levels = [
    {'id': 1, 'name': 'Новичок', 'minFreeDrinks': 0},
    {'id': 2, 'name': 'Любитель', 'minFreeDrinks': 2},
    {'id': 3, 'name': 'Ценитель', 'minFreeDrinks': 5},
    {'id': 4, 'name': 'Знаток', 'minFreeDrinks': 10},
    {'id': 5, 'name': 'Гурман', 'minFreeDrinks': 20},
    {'id': 6, 'name': 'Эксперт', 'minFreeDrinks': 35},
    {'id': 7, 'name': 'Мастер', 'minFreeDrinks': 50},
    {'id': 8, 'name': 'Легенда', 'minFreeDrinks': 75},
    {'id': 9, 'name': 'Чемпион', 'minFreeDrinks': 100},
    {'id': 10, 'name': 'Император', 'minFreeDrinks': 150},
  ];

  Future<Map<String, dynamic>> getBalance(String phone) async {
    return {
      'success': true,
      'loyaltyPoints': _loyaltyPoints[phone] ?? 0,
      'totalPointsEarned': _totalPointsEarned[phone] ?? 0,
    };
  }

  Future<Map<String, dynamic>> addPoints(String phone, {
    required int amount,
    required String employeePhone,
    String sourceType = 'qr_scan',
  }) async {
    if (amount <= 0) {
      return {'success': false, 'error': 'Amount must be positive'};
    }

    _loyaltyPoints[phone] = (_loyaltyPoints[phone] ?? 0) + amount;
    _totalPointsEarned[phone] = (_totalPointsEarned[phone] ?? 0) + amount;

    final tx = {
      'type': 'earn',
      'amount': amount,
      'balanceAfter': _loyaltyPoints[phone],
      'sourceType': sourceType,
      'employeePhone': employeePhone,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _transactions.putIfAbsent(phone, () => []);
    _transactions[phone]!.add(tx);

    return {
      'success': true,
      'balance': _loyaltyPoints[phone],
      'totalPointsEarned': _totalPointsEarned[phone],
    };
  }

  Future<Map<String, dynamic>> spendPoints(String phone, {
    required int amount,
    String sourceType = 'drink_redemption',
  }) async {
    if (amount <= 0) {
      return {'success': false, 'error': 'Amount must be positive'};
    }

    final current = _loyaltyPoints[phone] ?? 0;
    if (current < amount) {
      return {'success': false, 'error': 'Недостаточно баллов'};
    }

    _loyaltyPoints[phone] = current - amount;

    final tx = {
      'type': 'spend',
      'amount': amount,
      'balanceAfter': _loyaltyPoints[phone],
      'sourceType': sourceType,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _transactions.putIfAbsent(phone, () => []);
    _transactions[phone]!.add(tx);

    return {
      'success': true,
      'balance': _loyaltyPoints[phone],
    };
  }

  Future<List<Map<String, dynamic>>> getTransactions(String phone) async {
    return _transactions[phone] ?? [];
  }

  Map<String, dynamic> calculateLevel(int totalPointsEarned) {
    Map<String, dynamic> current = _levels[0];
    for (final level in _levels) {
      final threshold = (level['minFreeDrinks'] as int) * 10;
      if (totalPointsEarned >= threshold) {
        current = level;
      }
    }
    return current;
  }

  int calculateSpinsEarned({required int totalPointsEarned, required int pointsPerSpin}) {
    return totalPointsEarned ~/ pointsPerSpin;
  }

  int pointsToNextSpin({required int totalPointsEarned, required int pointsPerSpin}) {
    return pointsPerSpin - (totalPointsEarned % pointsPerSpin);
  }

  Map<String, dynamic> getPromoSettings() {
    return {
      'pointsRequired': 9,
      'drinksToGive': 1,
      'pointsPerScan': _pointsPerScan,
      'promoText': 'Копите баллы и обменивайте на напитки и товары!',
    };
  }

  void updatePointsPerScan(int value) {
    _pointsPerScan = value;
  }

  Map<String, dynamic> migrateClientData({
    required int freeDrinksGiven,
    required int points,
    required int pointsRequired,
  }) {
    return {
      'totalPointsEarned': freeDrinksGiven * pointsRequired,
      'loyaltyPoints': points,
    };
  }

  void clear() {
    _loyaltyPoints.clear();
    _totalPointsEarned.clear();
    _transactions.clear();
    _pointsPerScan = 10;
  }
}
