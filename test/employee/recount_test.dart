import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты пересчётов для роли СОТРУДНИК
/// Покрывает: Создание, фото, статусы, подтверждение
void main() {
  group('Recount Tests (P1)', () {
    late MockRecountService mockRecountService;

    setUp(() async {
      mockRecountService = MockRecountService();
    });

    tearDown(() async {
      mockRecountService.clear();
    });

    // ==================== СОЗДАНИЕ ПЕРЕСЧЁТА ====================

    group('Recount Creation Tests', () {
      test('ET-REC-001: Создание пересчёта для магазина', () async {
        // Arrange
        final recountData = {
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full', // full / partial
        };

        // Act
        final result = await mockRecountService.createRecount(recountData);

        // Assert
        expect(result['success'], true);
        expect(result['recount']['status'], 'in_progress');
      });

      test('ET-REC-002: Нельзя создать второй активный пересчёт', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        await mockRecountService.createRecount({
          'shopId': shopId,
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });

        // Act
        final result = await mockRecountService.createRecount({
          'shopId': shopId,
          'employeeId': MockEmployeeData.secondEmployee['id'],
          'type': 'partial',
        });

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('active'));
      });

      test('ET-REC-003: Выбор типа пересчёта (full/partial)', () async {
        // Arrange & Act
        final fullRecount = await mockRecountService.createRecount({
          'shopId': 'shop_001',
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });

        final partialRecount = await mockRecountService.createRecount({
          'shopId': 'shop_002',
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'partial',
        });

        // Assert
        expect(fullRecount['recount']['type'], 'full');
        expect(partialRecount['recount']['type'], 'partial');
      });
    });

    // ==================== ДОБАВЛЕНИЕ ПОЗИЦИЙ ====================

    group('Item Entry Tests', () {
      test('ET-REC-004: Добавление позиции в пересчёт', () async {
        // Arrange
        final recount = await mockRecountService.createRecount({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });
        final recountId = recount['recount']['id'];

        // Act
        final result = await mockRecountService.addItem(recountId, {
          'productId': 'prod_001',
          'productName': 'Кофе Арабика',
          'expectedQuantity': 100,
          'actualQuantity': 98,
        });

        // Assert
        expect(result['success'], true);
        expect(result['item']['difference'], -2);
      });

      test('ET-REC-005: Фото для позиции с расхождением', () async {
        // Arrange
        final recount = await mockRecountService.createRecount({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });
        final recountId = recount['recount']['id'];
        final item = await mockRecountService.addItem(recountId, {
          'productId': 'prod_001',
          'productName': 'Товар',
          'expectedQuantity': 50,
          'actualQuantity': 45,
        });

        // Act
        final result = await mockRecountService.attachPhoto(
          recountId,
          item['item']['id'],
          'photo_base64_data',
        );

        // Assert
        expect(result['success'], true);
        expect(result['photoUrl'], isNotEmpty);
      });

      test('ET-REC-006: Расчёт разницы (положительный/отрицательный)', () async {
        // Arrange
        final recount = await mockRecountService.createRecount({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });
        final recountId = recount['recount']['id'];

        // Act
        final shortage = await mockRecountService.addItem(recountId, {
          'productId': 'prod_001',
          'productName': 'Недостача',
          'expectedQuantity': 100,
          'actualQuantity': 90, // -10
        });

        final surplus = await mockRecountService.addItem(recountId, {
          'productId': 'prod_002',
          'productName': 'Излишек',
          'expectedQuantity': 50,
          'actualQuantity': 55, // +5
        });

        // Assert
        expect(shortage['item']['difference'], -10);
        expect(surplus['item']['difference'], 5);
      });
    });

    // ==================== ЗАВЕРШЕНИЕ ====================

    group('Completion Tests', () {
      test('ET-REC-007: Завершение пересчёта', () async {
        // Arrange
        final recount = await mockRecountService.createRecount({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });
        final recountId = recount['recount']['id'];
        await mockRecountService.addItem(recountId, {
          'productId': 'prod_001',
          'productName': 'Товар',
          'expectedQuantity': 100,
          'actualQuantity': 100,
        });

        // Act
        final result = await mockRecountService.complete(recountId);

        // Assert
        expect(result['success'], true);
        expect(result['recount']['status'], 'pending_review');
      });

      test('ET-REC-008: Нельзя завершить пустой пересчёт', () async {
        // Arrange
        final recount = await mockRecountService.createRecount({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });

        // Act
        final result = await mockRecountService.complete(recount['recount']['id']);

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('empty'));
      });

      test('ET-REC-009: Итоговая статистика при завершении', () async {
        // Arrange
        final recount = await mockRecountService.createRecount({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });
        final recountId = recount['recount']['id'];
        await mockRecountService.addItem(recountId, {
          'productId': 'prod_001',
          'expectedQuantity': 100,
          'actualQuantity': 95,
        });
        await mockRecountService.addItem(recountId, {
          'productId': 'prod_002',
          'expectedQuantity': 50,
          'actualQuantity': 55,
        });

        // Act
        final result = await mockRecountService.complete(recountId);

        // Assert
        expect(result['recount']['totalItems'], 2);
        expect(result['recount']['itemsWithDifference'], 2);
        expect(result['recount']['totalShortage'], -5);
        expect(result['recount']['totalSurplus'], 5);
      });
    });

    // ==================== ПРОВЕРКА АДМИНОМ ====================

    group('Admin Review Tests', () {
      test('ET-REC-010: Подтверждение пересчёта админом', () async {
        // Arrange
        final recount = await mockRecountService.createRecount({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });
        final recountId = recount['recount']['id'];
        await mockRecountService.addItem(recountId, {
          'productId': 'prod_001',
          'expectedQuantity': 100,
          'actualQuantity': 100,
        });
        await mockRecountService.complete(recountId);

        // Act
        final result = await mockRecountService.approve(
          recountId,
          MockEmployeeData.adminEmployee['id'],
          rating: 10,
        );

        // Assert
        expect(result['success'], true);
        expect(result['recount']['status'], 'approved');
        expect(result['pointsAwarded'], greaterThan(0));
      });

      test('ET-REC-011: Отклонение пересчёта с комментарием', () async {
        // Arrange
        final recount = await mockRecountService.createRecount({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });
        final recountId = recount['recount']['id'];
        await mockRecountService.addItem(recountId, {
          'productId': 'prod_001',
          'expectedQuantity': 100,
          'actualQuantity': 50,
        });
        await mockRecountService.complete(recountId);

        // Act
        final result = await mockRecountService.reject(
          recountId,
          MockEmployeeData.adminEmployee['id'],
          comment: 'Нужно пересчитать заново',
        );

        // Assert
        expect(result['success'], true);
        expect(result['recount']['status'], 'rejected');
      });

      test('ET-REC-012: Баллы за качественный пересчёт', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = DateTime.now().toIso8601String().substring(0, 7);

        final recount = await mockRecountService.createRecount({
          'shopId': MockShopData.validShop['id'],
          'employeeId': employeeId,
          'type': 'full',
        });
        final recountId = recount['recount']['id'];
        await mockRecountService.addItem(recountId, {
          'productId': 'prod_001',
          'expectedQuantity': 100,
          'actualQuantity': 100,
        });
        await mockRecountService.complete(recountId);
        await mockRecountService.approve(
          recountId,
          MockEmployeeData.adminEmployee['id'],
          rating: 10,
        );

        // Act
        final points = await mockRecountService.getEmployeePoints(employeeId, month);

        // Assert
        expect(points, greaterThan(0));
      });
    });

    // ==================== ИСТОРИЯ ====================

    group('History Tests', () {
      test('ET-REC-013: Список пересчётов магазина', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        for (var i = 0; i < 3; i++) {
          final r = await mockRecountService.createRecount({
            'shopId': shopId,
            'employeeId': MockEmployeeData.validEmployee['id'],
            'type': 'full',
          });
          await mockRecountService.addItem(r['recount']['id'], {
            'productId': 'prod_00$i',
            'expectedQuantity': 100,
            'actualQuantity': 100,
          });
          await mockRecountService.complete(r['recount']['id']);
        }

        // Act
        final history = await mockRecountService.getShopHistory(shopId);

        // Assert
        expect(history.length, 3);
      });

      test('ET-REC-014: Детали пересчёта', () async {
        // Arrange
        final recount = await mockRecountService.createRecount({
          'shopId': MockShopData.validShop['id'],
          'employeeId': MockEmployeeData.validEmployee['id'],
          'type': 'full',
        });
        final recountId = recount['recount']['id'];
        await mockRecountService.addItem(recountId, {
          'productId': 'prod_001',
          'productName': 'Кофе',
          'expectedQuantity': 100,
          'actualQuantity': 95,
        });

        // Act
        final details = await mockRecountService.getDetails(recountId);

        // Assert
        expect(details['items'].length, 1);
        expect(details['items'][0]['productName'], 'Кофе');
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockRecountService {
  final List<Map<String, dynamic>> _recounts = [];
  final Map<String, List<Map<String, dynamic>>> _items = {};
  final Map<String, double> _employeePoints = {};
  int _recountCounter = 0;
  int _itemCounter = 0;

  Future<Map<String, dynamic>> createRecount(Map<String, dynamic> data) async {
    final shopId = data['shopId'] as String;

    // Check for active recount
    final hasActive = _recounts.any((r) =>
      r['shopId'] == shopId &&
      r['status'] == 'in_progress'
    );

    if (hasActive) {
      return {'success': false, 'error': 'Shop already has active recount'};
    }

    _recountCounter++;
    final recount = {
      'id': 'recount_$_recountCounter',
      'shopId': shopId,
      'employeeId': data['employeeId'],
      'type': data['type'] ?? 'full',
      'status': 'in_progress',
      'createdAt': DateTime.now().toIso8601String(),
    };

    _recounts.add(recount);
    _items['recount_$_recountCounter'] = [];

    return {'success': true, 'recount': recount};
  }

  Future<Map<String, dynamic>> addItem(String recountId, Map<String, dynamic> data) async {
    final items = _items[recountId];
    if (items == null) {
      return {'success': false, 'error': 'Recount not found'};
    }

    _itemCounter++;
    final expected = data['expectedQuantity'] as int;
    final actual = data['actualQuantity'] as int;
    final item = {
      'id': 'item_$_itemCounter',
      'productId': data['productId'],
      'productName': data['productName'] ?? 'Товар',
      'expectedQuantity': expected,
      'actualQuantity': actual,
      'difference': actual - expected,
      'photoUrl': null,
    };

    items.add(item);
    return {'success': true, 'item': item};
  }

  Future<Map<String, dynamic>> attachPhoto(
    String recountId,
    String itemId,
    String photoData,
  ) async {
    final items = _items[recountId];
    if (items == null) {
      return {'success': false, 'error': 'Recount not found'};
    }

    final index = items.indexWhere((i) => i['id'] == itemId);
    if (index < 0) {
      return {'success': false, 'error': 'Item not found'};
    }

    final photoUrl = 'https://storage.example.com/recount/$recountId/$itemId.jpg';
    items[index]['photoUrl'] = photoUrl;

    return {'success': true, 'photoUrl': photoUrl};
  }

  Future<Map<String, dynamic>> complete(String recountId) async {
    final index = _recounts.indexWhere((r) => r['id'] == recountId);
    if (index < 0) {
      return {'success': false, 'error': 'Recount not found'};
    }

    final items = _items[recountId] ?? [];
    if (items.isEmpty) {
      return {'success': false, 'error': 'Cannot complete empty recount'};
    }

    int totalShortage = 0;
    int totalSurplus = 0;
    int itemsWithDiff = 0;

    for (final item in items) {
      final diff = item['difference'] as int;
      if (diff < 0) {
        totalShortage += diff;
        itemsWithDiff++;
      } else if (diff > 0) {
        totalSurplus += diff;
        itemsWithDiff++;
      }
    }

    _recounts[index]['status'] = 'pending_review';
    _recounts[index]['totalItems'] = items.length;
    _recounts[index]['itemsWithDifference'] = itemsWithDiff;
    _recounts[index]['totalShortage'] = totalShortage;
    _recounts[index]['totalSurplus'] = totalSurplus;
    _recounts[index]['completedAt'] = DateTime.now().toIso8601String();

    return {'success': true, 'recount': _recounts[index]};
  }

  Future<Map<String, dynamic>> approve(
    String recountId,
    String adminId, {
    int rating = 10,
  }) async {
    final index = _recounts.indexWhere((r) => r['id'] == recountId);
    if (index < 0) {
      return {'success': false, 'error': 'Recount not found'};
    }

    _recounts[index]['status'] = 'approved';
    _recounts[index]['approvedBy'] = adminId;
    _recounts[index]['rating'] = rating;

    final points = rating.toDouble();
    final employeeId = _recounts[index]['employeeId'] as String;
    final month = DateTime.now().toIso8601String().substring(0, 7);
    final key = '${employeeId}_$month';
    _employeePoints[key] = (_employeePoints[key] ?? 0) + points;

    return {
      'success': true,
      'recount': _recounts[index],
      'pointsAwarded': points,
    };
  }

  Future<Map<String, dynamic>> reject(
    String recountId,
    String adminId, {
    String? comment,
  }) async {
    final index = _recounts.indexWhere((r) => r['id'] == recountId);
    if (index < 0) {
      return {'success': false, 'error': 'Recount not found'};
    }

    _recounts[index]['status'] = 'rejected';
    _recounts[index]['rejectedBy'] = adminId;
    _recounts[index]['rejectionComment'] = comment;

    return {'success': true, 'recount': _recounts[index]};
  }

  Future<double> getEmployeePoints(String employeeId, String month) async {
    final key = '${employeeId}_$month';
    return _employeePoints[key] ?? 0;
  }

  Future<List<Map<String, dynamic>>> getShopHistory(String shopId) async {
    return _recounts.where((r) => r['shopId'] == shopId).toList();
  }

  Future<Map<String, dynamic>> getDetails(String recountId) async {
    final recount = _recounts.firstWhere(
      (r) => r['id'] == recountId,
      orElse: () => <String, dynamic>{},
    );
    final items = _items[recountId] ?? [];
    return {...recount, 'items': items};
  }

  void clear() {
    _recounts.clear();
    _items.clear();
    _employeePoints.clear();
    _recountCounter = 0;
    _itemCounter = 0;
  }
}
