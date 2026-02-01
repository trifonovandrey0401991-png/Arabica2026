import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты РКО (расходные кассовые ордера) для роли АДМИН
/// Покрывает: Создание, категории, подтверждение, отчёты
void main() {
  group('RKO Tests (P1)', () {
    late MockRkoService mockRkoService;

    setUp(() async {
      mockRkoService = MockRkoService();
    });

    tearDown(() async {
      mockRkoService.clear();
    });

    // ==================== СОЗДАНИЕ РКО ====================

    group('RKO Creation Tests', () {
      test('AT-RKO-001: Создание РКО', () async {
        // Arrange
        final rkoData = {
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 5000.0,
          'category': 'supplies',
          'description': 'Закупка расходников',
        };

        // Act
        final result = await mockRkoService.createRko(rkoData);

        // Assert
        expect(result['success'], true);
        expect(result['rko']['status'], 'pending');
        expect(result['rko']['amount'], 5000.0);
      });

      test('AT-RKO-002: Валидация суммы (> 0)', () async {
        // Act
        final result = await mockRkoService.createRko({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': -100.0,
          'category': 'supplies',
        });

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('amount'));
      });

      test('AT-RKO-003: Обязательная категория', () async {
        // Act
        final result = await mockRkoService.createRko({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 1000.0,
          // No category
        });

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('Category'));
      });

      test('AT-RKO-004: Прикрепление чека (фото)', () async {
        // Arrange
        final rko = await mockRkoService.createRko({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 2000.0,
          'category': 'food',
        });
        final rkoId = rko['rko']['id'];

        // Act
        final result = await mockRkoService.attachReceipt(rkoId, 'receipt_photo_base64');

        // Assert
        expect(result['success'], true);
        expect(result['receiptUrl'], isNotEmpty);
      });
    });

    // ==================== КАТЕГОРИИ ====================

    group('Category Tests', () {
      test('AT-RKO-005: Список категорий расходов', () async {
        // Act
        final categories = await mockRkoService.getCategories();

        // Assert
        expect(categories, isNotEmpty);
        expect(categories.any((c) => c['id'] == 'supplies'), true);
        expect(categories.any((c) => c['id'] == 'food'), true);
      });

      test('AT-RKO-006: Фильтрация РКО по категории', () async {
        // Arrange
        await mockRkoService.createRko({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 1000.0,
          'category': 'supplies',
        });
        await mockRkoService.createRko({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 2000.0,
          'category': 'food',
        });
        await mockRkoService.createRko({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 3000.0,
          'category': 'supplies',
        });

        // Act
        final supplies = await mockRkoService.getByCategory('supplies');

        // Assert
        expect(supplies.length, 2);
      });
    });

    // ==================== ПОДТВЕРЖДЕНИЕ ====================

    group('Approval Tests', () {
      test('AT-RKO-007: Подтверждение РКО админом', () async {
        // Arrange
        final rko = await mockRkoService.createRko({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 5000.0,
          'category': 'supplies',
        });

        // Act
        final result = await mockRkoService.approve(
          rko['rko']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['success'], true);
        expect(result['rko']['status'], 'approved');
      });

      test('AT-RKO-008: Отклонение РКО с причиной', () async {
        // Arrange
        final rko = await mockRkoService.createRko({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 50000.0,
          'category': 'other',
        });

        // Act
        final result = await mockRkoService.reject(
          rko['rko']['id'],
          MockEmployeeData.adminEmployee['id'],
          reason: 'Слишком большая сумма, нужно согласование',
        );

        // Assert
        expect(result['success'], true);
        expect(result['rko']['status'], 'rejected');
        expect(result['rko']['rejectionReason'], contains('сумма'));
      });

      test('AT-RKO-009: Нельзя подтвердить уже обработанный РКО', () async {
        // Arrange
        final rko = await mockRkoService.createRko({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 1000.0,
          'category': 'supplies',
        });
        await mockRkoService.approve(rko['rko']['id'], MockEmployeeData.adminEmployee['id']);

        // Act
        final result = await mockRkoService.reject(
          rko['rko']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['success'], false);
      });
    });

    // ==================== ОТЧЁТЫ ====================

    group('Reports Tests', () {
      test('AT-RKO-010: Сумма расходов за месяц по магазину', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        final month = DateTime.now().toIso8601String().substring(0, 7);

        for (var i = 0; i < 5; i++) {
          final rko = await mockRkoService.createRko({
            'shopId': shopId,
            'employeeId': MockEmployeeData.validEmployee['id'],
            'amount': 1000.0 * (i + 1),
            'category': 'supplies',
          });
          await mockRkoService.approve(rko['rko']['id'], MockEmployeeData.adminEmployee['id']);
        }

        // Act
        final total = await mockRkoService.getMonthlyTotal(shopId, month);

        // Assert
        expect(total, 15000.0); // 1000+2000+3000+4000+5000
      });

      test('AT-RKO-011: Разбивка по категориям', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        final month = DateTime.now().toIso8601String().substring(0, 7);

        final rko1 = await mockRkoService.createRko({
          'shopId': shopId,
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 5000.0,
          'category': 'supplies',
        });
        await mockRkoService.approve(rko1['rko']['id'], MockEmployeeData.adminEmployee['id']);

        final rko2 = await mockRkoService.createRko({
          'shopId': shopId,
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 3000.0,
          'category': 'food',
        });
        await mockRkoService.approve(rko2['rko']['id'], MockEmployeeData.adminEmployee['id']);

        // Act
        final breakdown = await mockRkoService.getCategoryBreakdown(shopId, month);

        // Assert
        expect(breakdown['supplies'], 5000.0);
        expect(breakdown['food'], 3000.0);
      });

      test('AT-RKO-012: Список РКО с пагинацией', () async {
        // Arrange
        for (var i = 0; i < 25; i++) {
          await mockRkoService.createRko({
            'shopId': MockShopData.validShop['id'],
            'employeeId': MockEmployeeData.validEmployee['id'],
            'amount': 100.0,
            'category': 'supplies',
          });
        }

        // Act
        final page1 = await mockRkoService.list(page: 1, perPage: 10);
        final page2 = await mockRkoService.list(page: 2, perPage: 10);
        final page3 = await mockRkoService.list(page: 3, perPage: 10);

        // Assert
        expect(page1['items'].length, 10);
        expect(page2['items'].length, 10);
        expect(page3['items'].length, 5);
      });
    });

    // ==================== ШТРАФЫ ====================

    group('Penalty Tests', () {
      test('AT-RKO-013: Штраф за пропущенный РКО', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = DateTime.now().toIso8601String().substring(0, 7);

        // Act
        final result = await mockRkoService.applyPenalty(
          employeeId,
          month,
          reason: 'Не сдан РКО за смену',
        );

        // Assert
        expect(result['success'], true);
        expect(result['penalty']['points'], -3);
      });

      test('AT-RKO-014: Баллы за качественный РКО', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final rko = await mockRkoService.createRko({
          'shopId': MockShopData.validShop['id'],
          'employeeId': employeeId,
          'amount': 1000.0,
          'category': 'supplies',
        });
        await mockRkoService.attachReceipt(rko['rko']['id'], 'receipt');

        // Act
        final result = await mockRkoService.approve(
          rko['rko']['id'],
          MockEmployeeData.adminEmployee['id'],
        );

        // Assert
        expect(result['pointsAwarded'], greaterThan(0));
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockRkoService {
  final List<Map<String, dynamic>> _rkos = [];
  final List<Map<String, dynamic>> _penalties = [];
  int _rkoCounter = 0;

  final List<Map<String, dynamic>> _categories = [
    {'id': 'supplies', 'name': 'Расходники'},
    {'id': 'food', 'name': 'Продукты'},
    {'id': 'repair', 'name': 'Ремонт'},
    {'id': 'utilities', 'name': 'Коммунальные'},
    {'id': 'other', 'name': 'Прочее'},
  ];

  Future<Map<String, dynamic>> createRko(Map<String, dynamic> data) async {
    final amount = data['amount'] as double? ?? 0;
    if (amount <= 0) {
      return {'success': false, 'error': 'Invalid amount'};
    }

    final category = data['category'] as String?;
    if (category == null || category.isEmpty) {
      return {'success': false, 'error': 'Category required'};
    }

    _rkoCounter++;
    final rko = {
      'id': 'rko_$_rkoCounter',
      'shopId': data['shopId'],
      'employeeId': data['employeeId'],
      'amount': amount,
      'category': category,
      'description': data['description'],
      'status': 'pending',
      'receiptUrl': null,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _rkos.add(rko);
    return {'success': true, 'rko': rko};
  }

  Future<Map<String, dynamic>> attachReceipt(String rkoId, String photoData) async {
    final index = _rkos.indexWhere((r) => r['id'] == rkoId);
    if (index < 0) {
      return {'success': false, 'error': 'RKO not found'};
    }

    final receiptUrl = 'https://storage.example.com/rko/$rkoId/receipt.jpg';
    _rkos[index]['receiptUrl'] = receiptUrl;

    return {'success': true, 'receiptUrl': receiptUrl};
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    return List.from(_categories);
  }

  Future<List<Map<String, dynamic>>> getByCategory(String category) async {
    return _rkos.where((r) => r['category'] == category).toList();
  }

  Future<Map<String, dynamic>> approve(String rkoId, String adminId) async {
    final index = _rkos.indexWhere((r) => r['id'] == rkoId);
    if (index < 0) {
      return {'success': false, 'error': 'RKO not found'};
    }

    if (_rkos[index]['status'] != 'pending') {
      return {'success': false, 'error': 'RKO already processed'};
    }

    _rkos[index]['status'] = 'approved';
    _rkos[index]['approvedBy'] = adminId;
    _rkos[index]['approvedAt'] = DateTime.now().toIso8601String();

    final hasReceipt = _rkos[index]['receiptUrl'] != null;
    final points = hasReceipt ? 2.0 : 1.0;

    return {
      'success': true,
      'rko': _rkos[index],
      'pointsAwarded': points,
    };
  }

  Future<Map<String, dynamic>> reject(String rkoId, String adminId, {String? reason}) async {
    final index = _rkos.indexWhere((r) => r['id'] == rkoId);
    if (index < 0) {
      return {'success': false, 'error': 'RKO not found'};
    }

    if (_rkos[index]['status'] != 'pending') {
      return {'success': false, 'error': 'RKO already processed'};
    }

    _rkos[index]['status'] = 'rejected';
    _rkos[index]['rejectedBy'] = adminId;
    _rkos[index]['rejectionReason'] = reason;

    return {'success': true, 'rko': _rkos[index]};
  }

  Future<double> getMonthlyTotal(String shopId, String month) async {
    double total = 0;
    for (final rko in _rkos) {
      if (rko['shopId'] == shopId &&
          rko['status'] == 'approved' &&
          (rko['createdAt'] as String).startsWith(month)) {
        total += rko['amount'] as double;
      }
    }
    return total;
  }

  Future<Map<String, double>> getCategoryBreakdown(String shopId, String month) async {
    final breakdown = <String, double>{};
    for (final rko in _rkos) {
      if (rko['shopId'] == shopId &&
          rko['status'] == 'approved' &&
          (rko['createdAt'] as String).startsWith(month)) {
        final cat = rko['category'] as String;
        breakdown[cat] = (breakdown[cat] ?? 0) + (rko['amount'] as double);
      }
    }
    return breakdown;
  }

  Future<Map<String, dynamic>> list({int page = 1, int perPage = 10}) async {
    final start = (page - 1) * perPage;
    final end = start + perPage;
    final items = _rkos.skip(start).take(perPage).toList();

    return {
      'items': items,
      'total': _rkos.length,
      'page': page,
      'perPage': perPage,
    };
  }

  Future<Map<String, dynamic>> applyPenalty(
    String employeeId,
    String month, {
    String? reason,
  }) async {
    final penalty = {
      'id': 'penalty_${_penalties.length + 1}',
      'employeeId': employeeId,
      'month': month,
      'category': 'rko_missed_penalty',
      'points': -3,
      'reason': reason,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _penalties.add(penalty);
    return {'success': true, 'penalty': penalty};
  }

  void clear() {
    _rkos.clear();
    _penalties.clear();
    _rkoCounter = 0;
  }
}
