import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты Главной Кассы для роли АДМИН
/// Покрывает: Балансы, выемки, пополнения, аналитика
void main() {
  group('Main Cash Tests (P1)', () {
    late MockMainCashService mockMainCashService;

    setUp(() async {
      mockMainCashService = MockMainCashService();
    });

    tearDown(() async {
      mockMainCashService.clear();
    });

    // ==================== БАЛАНСЫ ====================

    group('Balance Tests', () {
      test('AT-MCH-001: Получение текущего баланса магазина', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 50000.0);

        // Act
        final balance = await mockMainCashService.getBalance(shopId);

        // Assert
        expect(balance['amount'], 50000.0);
      });

      test('AT-MCH-002: Баланс всех магазинов', () async {
        // Arrange
        await mockMainCashService.setBalance('shop_001', 30000.0);
        await mockMainCashService.setBalance('shop_002', 45000.0);
        await mockMainCashService.setBalance('shop_003', 25000.0);

        // Act
        final balances = await mockMainCashService.getAllBalances();

        // Assert
        expect(balances.length, 3);
        final total = balances.fold<double>(0, (sum, b) => sum + (b['amount'] as double));
        expect(total, 100000.0);
      });

      test('AT-MCH-003: История изменений баланса', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.addTransaction(shopId, 10000.0, 'deposit');
        await mockMainCashService.addTransaction(shopId, -5000.0, 'withdrawal');
        await mockMainCashService.addTransaction(shopId, 3000.0, 'deposit');

        // Act
        final history = await mockMainCashService.getHistory(shopId);

        // Assert
        expect(history.length, 3);
      });
    });

    // ==================== ВЫЕМКИ ====================

    group('Withdrawal Tests', () {
      test('AT-MCH-004: Создание выемки', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 50000.0);

        // Act
        final result = await mockMainCashService.createWithdrawal({
          'shopId': shopId,
          'amount': 20000.0,
          'employeeId': MockEmployeeData.validEmployee['id'],
          'reason': 'Инкассация',
        });

        // Assert
        expect(result['success'], true);
        expect(result['withdrawal']['amount'], 20000.0);
        expect(result['newBalance'], 30000.0);
      });

      test('AT-MCH-005: Нельзя выемку больше баланса', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 10000.0);

        // Act
        final result = await mockMainCashService.createWithdrawal({
          'shopId': shopId,
          'amount': 15000.0,
          'employeeId': MockEmployeeData.validEmployee['id'],
        });

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('Insufficient'));
      });

      test('AT-MCH-006: Подтверждение выемки админом', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 50000.0);
        final withdrawal = await mockMainCashService.createWithdrawal({
          'shopId': shopId,
          'amount': 20000.0,
          'employeeId': MockEmployeeData.validEmployee['id'],
        });

        // Act
        final result = await mockMainCashService.confirmWithdrawal(
          withdrawal['withdrawal']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['success'], true);
        expect(result['withdrawal']['status'], 'confirmed');
      });

      test('AT-MCH-007: Фото подтверждения выемки', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 50000.0);
        final withdrawal = await mockMainCashService.createWithdrawal({
          'shopId': shopId,
          'amount': 20000.0,
          'employeeId': MockEmployeeData.validEmployee['id'],
        });

        // Act
        final result = await mockMainCashService.attachWithdrawalPhoto(
          withdrawal['withdrawal']['id'],
          'photo_base64',
        );

        // Assert
        expect(result['success'], true);
        expect(result['photoUrl'], isNotEmpty);
      });
    });

    // ==================== ПОПОЛНЕНИЯ ====================

    group('Deposit Tests', () {
      test('AT-MCH-008: Пополнение кассы', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 10000.0);

        // Act
        final result = await mockMainCashService.createDeposit({
          'shopId': shopId,
          'amount': 5000.0,
          'employeeId': MockEmployeeData.validEmployee['id'],
          'source': 'Сдача за смену',
        });

        // Assert
        expect(result['success'], true);
        expect(result['newBalance'], 15000.0);
      });

      test('AT-MCH-009: Автопополнение из конвертов', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 20000.0);

        // Act
        final result = await mockMainCashService.autoDepositFromEnvelope({
          'shopId': shopId,
          'envelopeId': 'env_123',
          'amount': 8000.0,
        });

        // Assert
        expect(result['success'], true);
        expect(result['source'], 'envelope');
        expect(result['newBalance'], 28000.0);
      });
    });

    // ==================== АНАЛИТИКА ====================

    group('Analytics Tests', () {
      test('AT-MCH-010: Статистика выемок за период', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 100000.0);

        for (var i = 0; i < 5; i++) {
          final w = await mockMainCashService.createWithdrawal({
            'shopId': shopId,
            'amount': 5000.0,
            'employeeId': MockEmployeeData.validEmployee['id'],
          });
          await mockMainCashService.confirmWithdrawal(
            w['withdrawal']['id'],
            MockEmployeeData.adminEmployee['id'],
          );
        }

        // Act
        final stats = await mockMainCashService.getWithdrawalStats(
          shopId,
          DateTime.now().toIso8601String().substring(0, 7),
        );

        // Assert
        expect(stats['count'], 5);
        expect(stats['total'], 25000.0);
      });

      test('AT-MCH-011: Сводка по всем магазинам', () async {
        // Arrange
        await mockMainCashService.setBalance('shop_001', 50000.0);
        await mockMainCashService.setBalance('shop_002', 30000.0);
        await mockMainCashService.addTransaction('shop_001', -10000.0, 'withdrawal');
        await mockMainCashService.addTransaction('shop_002', 5000.0, 'deposit');

        // Act
        final summary = await mockMainCashService.getSummary();

        // Assert
        expect(summary['totalBalance'], greaterThan(0));
        expect(summary['shopsCount'], 2);
      });

      test('AT-MCH-012: Экспорт отчёта', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 50000.0);
        await mockMainCashService.addTransaction(shopId, -5000.0, 'withdrawal');

        // Act
        final report = await mockMainCashService.exportReport(
          shopId,
          '2026-02-01',
          '2026-02-28',
        );

        // Assert
        expect(report['success'], true);
        expect(report['data'], isNotEmpty);
      });
    });

    // ==================== ЛИМИТЫ ====================

    group('Limit Tests', () {
      test('AT-MCH-013: Предупреждение при низком балансе', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 3000.0);
        await mockMainCashService.setMinBalanceAlert(shopId, 5000.0);

        // Act
        final alerts = await mockMainCashService.checkAlerts();

        // Assert
        expect(alerts.any((a) => a['shopId'] == shopId && a['type'] == 'low_balance'), true);
      });

      test('AT-MCH-014: Лимит на выемку за день', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockMainCashService.setBalance(shopId, 100000.0);
        await mockMainCashService.setDailyWithdrawalLimit(shopId, 30000.0);

        // Make withdrawals
        await mockMainCashService.createWithdrawal({
          'shopId': shopId,
          'amount': 20000.0,
          'employeeId': MockEmployeeData.validEmployee['id'],
        });

        // Act - try to exceed limit
        final result = await mockMainCashService.createWithdrawal({
          'shopId': shopId,
          'amount': 15000.0,
          'employeeId': MockEmployeeData.validEmployee['id'],
        });

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('limit'));
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockMainCashService {
  final Map<String, double> _balances = {};
  final List<Map<String, dynamic>> _transactions = [];
  final List<Map<String, dynamic>> _withdrawals = [];
  final Map<String, double> _minBalanceAlerts = {};
  final Map<String, double> _dailyLimits = {};
  final Map<String, double> _dailyWithdrawn = {};
  int _transactionCounter = 0;
  int _withdrawalCounter = 0;

  Future<void> setBalance(String shopId, double amount) async {
    _balances[shopId] = amount;
  }

  Future<Map<String, dynamic>> getBalance(String shopId) async {
    return {
      'shopId': shopId,
      'amount': _balances[shopId] ?? 0,
    };
  }

  Future<List<Map<String, dynamic>>> getAllBalances() async {
    return _balances.entries.map((e) => {
      'shopId': e.key,
      'amount': e.value,
    }).toList();
  }

  Future<void> addTransaction(String shopId, double amount, String type) async {
    _transactionCounter++;
    _transactions.add({
      'id': 'txn_$_transactionCounter',
      'shopId': shopId,
      'amount': amount,
      'type': type,
      'createdAt': DateTime.now().toIso8601String(),
    });
    _balances[shopId] = (_balances[shopId] ?? 0) + amount;
  }

  Future<List<Map<String, dynamic>>> getHistory(String shopId) async {
    return _transactions.where((t) => t['shopId'] == shopId).toList();
  }

  Future<Map<String, dynamic>> createWithdrawal(Map<String, dynamic> data) async {
    final shopId = data['shopId'] as String;
    final amount = data['amount'] as double;
    final currentBalance = _balances[shopId] ?? 0;

    if (amount > currentBalance) {
      return {'success': false, 'error': 'Insufficient balance'};
    }

    // Check daily limit
    final limit = _dailyLimits[shopId];
    if (limit != null) {
      final todayWithdrawn = _dailyWithdrawn[shopId] ?? 0;
      if (todayWithdrawn + amount > limit) {
        return {'success': false, 'error': 'Daily withdrawal limit exceeded'};
      }
      _dailyWithdrawn[shopId] = todayWithdrawn + amount;
    }

    _withdrawalCounter++;
    final withdrawal = {
      'id': 'withdrawal_$_withdrawalCounter',
      'shopId': shopId,
      'amount': amount,
      'employeeId': data['employeeId'],
      'reason': data['reason'],
      'status': 'pending',
      'photoUrl': null,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _withdrawals.add(withdrawal);
    _balances[shopId] = currentBalance - amount;

    return {
      'success': true,
      'withdrawal': withdrawal,
      'newBalance': _balances[shopId],
    };
  }

  Future<Map<String, dynamic>> confirmWithdrawal(String withdrawalId, String adminId) async {
    final index = _withdrawals.indexWhere((w) => w['id'] == withdrawalId);
    if (index < 0) {
      return {'success': false, 'error': 'Withdrawal not found'};
    }

    _withdrawals[index]['status'] = 'confirmed';
    _withdrawals[index]['confirmedBy'] = adminId;
    _withdrawals[index]['confirmedAt'] = DateTime.now().toIso8601String();

    return {'success': true, 'withdrawal': _withdrawals[index]};
  }

  Future<Map<String, dynamic>> attachWithdrawalPhoto(String withdrawalId, String photoData) async {
    final index = _withdrawals.indexWhere((w) => w['id'] == withdrawalId);
    if (index < 0) {
      return {'success': false, 'error': 'Withdrawal not found'};
    }

    final photoUrl = 'https://storage.example.com/withdrawals/$withdrawalId.jpg';
    _withdrawals[index]['photoUrl'] = photoUrl;

    return {'success': true, 'photoUrl': photoUrl};
  }

  Future<Map<String, dynamic>> createDeposit(Map<String, dynamic> data) async {
    final shopId = data['shopId'] as String;
    final amount = data['amount'] as double;

    await addTransaction(shopId, amount, 'deposit');

    return {
      'success': true,
      'newBalance': _balances[shopId],
    };
  }

  Future<Map<String, dynamic>> autoDepositFromEnvelope(Map<String, dynamic> data) async {
    final shopId = data['shopId'] as String;
    final amount = data['amount'] as double;

    await addTransaction(shopId, amount, 'envelope_deposit');

    return {
      'success': true,
      'source': 'envelope',
      'newBalance': _balances[shopId],
    };
  }

  Future<Map<String, dynamic>> getWithdrawalStats(String shopId, String month) async {
    final confirmed = _withdrawals.where((w) =>
      w['shopId'] == shopId &&
      w['status'] == 'confirmed' &&
      (w['createdAt'] as String).startsWith(month)
    ).toList();

    double total = 0;
    for (final w in confirmed) {
      total += w['amount'] as double;
    }

    return {
      'count': confirmed.length,
      'total': total,
    };
  }

  Future<Map<String, dynamic>> getSummary() async {
    double totalBalance = 0;
    for (final balance in _balances.values) {
      totalBalance += balance;
    }

    return {
      'totalBalance': totalBalance,
      'shopsCount': _balances.length,
    };
  }

  Future<Map<String, dynamic>> exportReport(String shopId, String startDate, String endDate) async {
    final transactions = _transactions.where((t) => t['shopId'] == shopId).toList();
    return {
      'success': true,
      'data': transactions,
    };
  }

  Future<void> setMinBalanceAlert(String shopId, double minBalance) async {
    _minBalanceAlerts[shopId] = minBalance;
  }

  Future<void> setDailyWithdrawalLimit(String shopId, double limit) async {
    _dailyLimits[shopId] = limit;
  }

  Future<List<Map<String, dynamic>>> checkAlerts() async {
    final alerts = <Map<String, dynamic>>[];
    for (final entry in _minBalanceAlerts.entries) {
      final balance = _balances[entry.key] ?? 0;
      if (balance < entry.value) {
        alerts.add({
          'shopId': entry.key,
          'type': 'low_balance',
          'currentBalance': balance,
          'threshold': entry.value,
        });
      }
    }
    return alerts;
  }

  void clear() {
    _balances.clear();
    _transactions.clear();
    _withdrawals.clear();
    _minBalanceAlerts.clear();
    _dailyLimits.clear();
    _dailyWithdrawn.clear();
    _transactionCounter = 0;
    _withdrawalCounter = 0;
  }
}
