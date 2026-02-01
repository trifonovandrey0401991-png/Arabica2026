import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты премий и штрафов для роли АДМИН
/// Покрывает: Создание, категории, история, баллы
void main() {
  group('Bonuses & Penalties Tests (P1)', () {
    late MockBonusesService mockBonusesService;

    setUp(() async {
      mockBonusesService = MockBonusesService();
    });

    tearDown(() async {
      mockBonusesService.clear();
    });

    // ==================== ПРЕМИИ ====================

    group('Bonus Tests', () {
      test('AT-BON-001: Создание премии сотруднику', () async {
        // Arrange
        final bonusData = {
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 5000.0,
          'reason': 'За отличную работу',
          'category': 'performance',
        };

        // Act
        final result = await mockBonusesService.createBonus(bonusData);

        // Assert
        expect(result['success'], true);
        expect(result['bonus']['amount'], 5000.0);
        expect(result['bonus']['type'], 'bonus');
      });

      test('AT-BON-002: Премия с привязкой к месяцу', () async {
        // Arrange
        final month = '2026-02';

        // Act
        final result = await mockBonusesService.createBonus({
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 3000.0,
          'reason': 'Квартальная премия',
          'month': month,
        });

        // Assert
        expect(result['bonus']['month'], month);
      });

      test('AT-BON-003: Категории премий', () async {
        // Act
        final categories = await mockBonusesService.getBonusCategories();

        // Assert
        expect(categories, isNotEmpty);
        expect(categories.any((c) => c['id'] == 'performance'), true);
        expect(categories.any((c) => c['id'] == 'holiday'), true);
      });

      test('AT-BON-004: Массовая премия (всем сотрудникам)', () async {
        // Arrange
        final employees = ['emp_001', 'emp_002', 'emp_003'];

        // Act
        final result = await mockBonusesService.createBulkBonus({
          'employeeIds': employees,
          'amount': 1000.0,
          'reason': 'Новогодняя премия',
          'category': 'holiday',
        });

        // Assert
        expect(result['success'], true);
        expect(result['created'], 3);
      });
    });

    // ==================== ШТРАФЫ ====================

    group('Penalty Tests', () {
      test('AT-BON-005: Создание штрафа', () async {
        // Arrange
        final penaltyData = {
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 500.0,
          'reason': 'Опоздание на смену',
          'category': 'discipline',
        };

        // Act
        final result = await mockBonusesService.createPenalty(penaltyData);

        // Assert
        expect(result['success'], true);
        expect(result['penalty']['amount'], -500.0); // Negative
        expect(result['penalty']['type'], 'penalty');
      });

      test('AT-BON-006: Категории штрафов', () async {
        // Act
        final categories = await mockBonusesService.getPenaltyCategories();

        // Assert
        expect(categories, isNotEmpty);
        expect(categories.any((c) => c['id'] == 'discipline'), true);
        expect(categories.any((c) => c['id'] == 'quality'), true);
      });

      test('AT-BON-007: Автоштраф за пропуск дедлайна', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final result = await mockBonusesService.createAutoPenalty({
          'employeeId': employeeId,
          'category': 'shift_missed_penalty',
          'points': -5,
          'reason': 'Не сдана пересменка',
        });

        // Assert
        expect(result['success'], true);
        expect(result['penalty']['isAuto'], true);
      });
    });

    // ==================== ИСТОРИЯ ====================

    group('History Tests', () {
      test('AT-BON-008: История сотрудника', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockBonusesService.createBonus({
          'employeeId': employeeId,
          'amount': 2000.0,
          'reason': 'Премия 1',
        });
        await mockBonusesService.createPenalty({
          'employeeId': employeeId,
          'amount': 500.0,
          'reason': 'Штраф 1',
        });
        await mockBonusesService.createBonus({
          'employeeId': employeeId,
          'amount': 1000.0,
          'reason': 'Премия 2',
        });

        // Act
        final history = await mockBonusesService.getEmployeeHistory(employeeId);

        // Assert
        expect(history.length, 3);
      });

      test('AT-BON-009: Фильтрация по типу', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockBonusesService.createBonus({
          'employeeId': employeeId,
          'amount': 2000.0,
          'reason': 'Премия',
        });
        await mockBonusesService.createPenalty({
          'employeeId': employeeId,
          'amount': 500.0,
          'reason': 'Штраф',
        });

        // Act
        final bonuses = await mockBonusesService.getEmployeeHistory(
          employeeId,
          type: 'bonus',
        );

        // Assert
        expect(bonuses.length, 1);
        expect(bonuses.first['type'], 'bonus');
      });

      test('AT-BON-010: Фильтрация по месяцу', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockBonusesService.createBonus({
          'employeeId': employeeId,
          'amount': 1000.0,
          'reason': 'Февраль',
          'month': '2026-02',
        });
        await mockBonusesService.createBonus({
          'employeeId': employeeId,
          'amount': 2000.0,
          'reason': 'Январь',
          'month': '2026-01',
        });

        // Act
        final feb = await mockBonusesService.getEmployeeHistory(
          employeeId,
          month: '2026-02',
        );

        // Assert
        expect(feb.length, 1);
      });
    });

    // ==================== БАЛАНС И РАСЧЁТЫ ====================

    group('Balance Tests', () {
      test('AT-BON-011: Итоговая сумма за месяц', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = '2026-02';

        await mockBonusesService.createBonus({
          'employeeId': employeeId,
          'amount': 5000.0,
          'month': month,
        });
        await mockBonusesService.createPenalty({
          'employeeId': employeeId,
          'amount': 1000.0,
          'month': month,
        });
        await mockBonusesService.createBonus({
          'employeeId': employeeId,
          'amount': 2000.0,
          'month': month,
        });

        // Act
        final total = await mockBonusesService.getMonthlyTotal(employeeId, month);

        // Assert
        expect(total, 6000.0); // 5000 - 1000 + 2000
      });

      test('AT-BON-012: Баллы за премии/штрафы', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        final month = DateTime.now().toIso8601String().substring(0, 7);

        await mockBonusesService.createBonus({
          'employeeId': employeeId,
          'amount': 3000.0,
          'points': 3, // 3 балла
        });
        await mockBonusesService.createPenalty({
          'employeeId': employeeId,
          'amount': 500.0,
          'points': -1, // -1 балл
        });

        // Act
        final points = await mockBonusesService.getEmployeePoints(employeeId, month);

        // Assert
        expect(points, 2); // 3 - 1
      });

      test('AT-BON-013: Сводка по магазину', () async {
        // Arrange
        final shopId = MockShopData.validShop['id'];
        final month = '2026-02';

        await mockBonusesService.createBonus({
          'employeeId': 'emp_001',
          'shopId': shopId,
          'amount': 5000.0,
          'month': month,
        });
        await mockBonusesService.createBonus({
          'employeeId': 'emp_002',
          'shopId': shopId,
          'amount': 3000.0,
          'month': month,
        });
        await mockBonusesService.createPenalty({
          'employeeId': 'emp_001',
          'shopId': shopId,
          'amount': 1000.0,
          'month': month,
        });

        // Act
        final summary = await mockBonusesService.getShopSummary(shopId, month);

        // Assert
        expect(summary['totalBonuses'], 8000.0);
        expect(summary['totalPenalties'], 1000.0);
        expect(summary['netTotal'], 7000.0);
      });
    });

    // ==================== ОТМЕНА ====================

    group('Cancellation Tests', () {
      test('AT-BON-014: Отмена премии', () async {
        // Arrange
        final bonus = await mockBonusesService.createBonus({
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 2000.0,
          'reason': 'Тестовая',
        });

        // Act
        final result = await mockBonusesService.cancel(
          bonus['bonus']['id'],
          MockEmployeeData.adminEmployee['id'],
          reason: 'Ошибка ввода',
        );

        // Assert
        expect(result['success'], true);
        expect(result['item']['status'], 'cancelled');
      });

      test('AT-BON-015: Отмена штрафа', () async {
        // Arrange
        final penalty = await mockBonusesService.createPenalty({
          'employeeId': MockEmployeeData.validEmployee['id'],
          'amount': 500.0,
          'reason': 'Тестовый',
        });

        // Act
        final result = await mockBonusesService.cancel(
          penalty['penalty']['id'],
          MockEmployeeData.adminEmployee['id'],
          reason: 'Апелляция удовлетворена',
        );

        // Assert
        expect(result['success'], true);
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockBonusesService {
  final List<Map<String, dynamic>> _items = [];
  int _counter = 0;

  final List<Map<String, dynamic>> _bonusCategories = [
    {'id': 'performance', 'name': 'За работу'},
    {'id': 'holiday', 'name': 'Праздничная'},
    {'id': 'quarterly', 'name': 'Квартальная'},
    {'id': 'other', 'name': 'Прочее'},
  ];

  final List<Map<String, dynamic>> _penaltyCategories = [
    {'id': 'discipline', 'name': 'Дисциплина'},
    {'id': 'quality', 'name': 'Качество'},
    {'id': 'shift_missed_penalty', 'name': 'Пропуск пересменки'},
    {'id': 'envelope_missed_penalty', 'name': 'Пропуск конверта'},
  ];

  Future<Map<String, dynamic>> createBonus(Map<String, dynamic> data) async {
    _counter++;
    final month = data['month'] ?? DateTime.now().toIso8601String().substring(0, 7);
    final bonus = {
      'id': 'bonus_$_counter',
      'type': 'bonus',
      'employeeId': data['employeeId'],
      'shopId': data['shopId'],
      'amount': (data['amount'] as num).toDouble(),
      'points': data['points'] ?? 0,
      'reason': data['reason'],
      'category': data['category'] ?? 'other',
      'month': month,
      'status': 'active',
      'isAuto': false,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _items.add(bonus);
    return {'success': true, 'bonus': bonus};
  }

  Future<Map<String, dynamic>> createPenalty(Map<String, dynamic> data) async {
    _counter++;
    final month = data['month'] ?? DateTime.now().toIso8601String().substring(0, 7);
    final penalty = {
      'id': 'penalty_$_counter',
      'type': 'penalty',
      'employeeId': data['employeeId'],
      'shopId': data['shopId'],
      'amount': -(data['amount'] as num).toDouble().abs(),
      'points': data['points'] ?? 0,
      'reason': data['reason'],
      'category': data['category'] ?? 'discipline',
      'month': month,
      'status': 'active',
      'isAuto': false,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _items.add(penalty);
    return {'success': true, 'penalty': penalty};
  }

  Future<Map<String, dynamic>> createAutoPenalty(Map<String, dynamic> data) async {
    _counter++;
    final month = DateTime.now().toIso8601String().substring(0, 7);
    final penalty = {
      'id': 'penalty_$_counter',
      'type': 'penalty',
      'employeeId': data['employeeId'],
      'amount': (data['points'] as num).toDouble(),
      'points': data['points'],
      'reason': data['reason'],
      'category': data['category'],
      'month': month,
      'status': 'active',
      'isAuto': true,
      'createdAt': DateTime.now().toIso8601String(),
    };
    _items.add(penalty);
    return {'success': true, 'penalty': penalty};
  }

  Future<Map<String, dynamic>> createBulkBonus(Map<String, dynamic> data) async {
    final employeeIds = data['employeeIds'] as List;
    int created = 0;
    for (final empId in employeeIds) {
      await createBonus({
        'employeeId': empId,
        'amount': data['amount'],
        'reason': data['reason'],
        'category': data['category'],
      });
      created++;
    }
    return {'success': true, 'created': created};
  }

  Future<List<Map<String, dynamic>>> getBonusCategories() async {
    return List.from(_bonusCategories);
  }

  Future<List<Map<String, dynamic>>> getPenaltyCategories() async {
    return List.from(_penaltyCategories);
  }

  Future<List<Map<String, dynamic>>> getEmployeeHistory(
    String employeeId, {
    String? type,
    String? month,
  }) async {
    return _items.where((i) {
      if (i['employeeId'] != employeeId) return false;
      if (i['status'] != 'active') return false;
      if (type != null && i['type'] != type) return false;
      if (month != null && i['month'] != month) return false;
      return true;
    }).toList();
  }

  Future<double> getMonthlyTotal(String employeeId, String month) async {
    double total = 0;
    for (final item in _items) {
      if (item['employeeId'] == employeeId &&
          item['month'] == month &&
          item['status'] == 'active') {
        total += item['amount'] as double;
      }
    }
    return total;
  }

  Future<int> getEmployeePoints(String employeeId, String month) async {
    int points = 0;
    for (final item in _items) {
      if (item['employeeId'] == employeeId &&
          item['month'] == month &&
          item['status'] == 'active') {
        points += item['points'] as int;
      }
    }
    return points;
  }

  Future<Map<String, dynamic>> getShopSummary(String shopId, String month) async {
    double bonuses = 0;
    double penalties = 0;

    for (final item in _items) {
      if (item['shopId'] == shopId &&
          item['month'] == month &&
          item['status'] == 'active') {
        final amount = item['amount'] as double;
        if (amount > 0) {
          bonuses += amount;
        } else {
          penalties += amount.abs();
        }
      }
    }

    return {
      'totalBonuses': bonuses,
      'totalPenalties': penalties,
      'netTotal': bonuses - penalties,
    };
  }

  Future<Map<String, dynamic>> cancel(
    String id,
    String adminId, {
    String? reason,
  }) async {
    final index = _items.indexWhere((i) => i['id'] == id);
    if (index < 0) {
      return {'success': false, 'error': 'Not found'};
    }

    _items[index]['status'] = 'cancelled';
    _items[index]['cancelledBy'] = adminId;
    _items[index]['cancelReason'] = reason;

    return {'success': true, 'item': _items[index]};
  }

  void clear() {
    _items.clear();
    _counter = 0;
  }
}
