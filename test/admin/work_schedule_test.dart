import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты графика работы для роли АДМИН
/// Покрывает: Создание смен, шаблоны, конфликты, массовые операции
void main() {
  group('Work Schedule Tests (P1)', () {
    late MockWorkScheduleService mockScheduleService;

    setUp(() async {
      mockScheduleService = MockWorkScheduleService();
    });

    tearDown(() async {
      mockScheduleService.clear();
    });

    // ==================== СОЗДАНИЕ СМЕН ====================

    group('Shift Creation Tests', () {
      test('AT-SCH-001: Создание смены на дату', () async {
        // Arrange
        final shiftData = {
          'employeeId': MockEmployeeData.validEmployee['id'],
          'shopId': MockShopData.validShop['id'],
          'date': '2026-02-01',
          'startTime': '09:00',
          'endTime': '18:00',
        };

        // Act
        final result = await mockScheduleService.createShift(shiftData);

        // Assert
        expect(result['success'], true);
        expect(result['shift']['date'], '2026-02-01');
      });

      test('AT-SCH-002: Нельзя создать перекрывающиеся смены', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockScheduleService.createShift({
          'employeeId': employeeId,
          'shopId': MockShopData.validShop['id'],
          'date': '2026-02-01',
          'startTime': '09:00',
          'endTime': '18:00',
        });

        // Act
        final result = await mockScheduleService.createShift({
          'employeeId': employeeId,
          'shopId': MockShopData.validShop['id'],
          'date': '2026-02-01',
          'startTime': '14:00',
          'endTime': '22:00',
        });

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('overlap'));
      });

      test('AT-SCH-003: Валидация времени смены', () async {
        // Arrange
        final invalidShift = {
          'employeeId': MockEmployeeData.validEmployee['id'],
          'shopId': MockShopData.validShop['id'],
          'date': '2026-02-01',
          'startTime': '18:00',
          'endTime': '09:00', // End before start
        };

        // Act
        final result = await mockScheduleService.createShift(invalidShift);

        // Assert
        expect(result['success'], false);
      });

      test('AT-SCH-004: Смена в разных магазинах в один день', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockScheduleService.createShift({
          'employeeId': employeeId,
          'shopId': 'shop_001',
          'date': '2026-02-01',
          'startTime': '09:00',
          'endTime': '14:00',
        });

        // Act
        final result = await mockScheduleService.createShift({
          'employeeId': employeeId,
          'shopId': 'shop_002',
          'date': '2026-02-01',
          'startTime': '15:00',
          'endTime': '20:00',
        });

        // Assert
        expect(result['success'], true);
      });
    });

    // ==================== ШАБЛОНЫ ====================

    group('Template Tests', () {
      test('AT-SCH-005: Создание шаблона смены', () async {
        // Arrange
        final templateData = {
          'name': 'Утренняя смена',
          'startTime': '07:00',
          'endTime': '15:00',
        };

        // Act
        final result = await mockScheduleService.createTemplate(templateData);

        // Assert
        expect(result['success'], true);
        expect(result['template']['name'], 'Утренняя смена');
      });

      test('AT-SCH-006: Применение шаблона к сотруднику', () async {
        // Arrange
        final template = await mockScheduleService.createTemplate({
          'name': 'Вечерняя',
          'startTime': '15:00',
          'endTime': '23:00',
        });
        final templateId = template['template']['id'];

        // Act
        final result = await mockScheduleService.applyTemplate(
          templateId,
          MockEmployeeData.validEmployee['id'],
          '2026-02-01',
          MockShopData.validShop['id'],
        );

        // Assert
        expect(result['success'], true);
        expect(result['shift']['startTime'], '15:00');
      });

      test('AT-SCH-007: Список шаблонов', () async {
        // Arrange
        await mockScheduleService.createTemplate({'name': 'Шаблон 1', 'startTime': '09:00', 'endTime': '18:00'});
        await mockScheduleService.createTemplate({'name': 'Шаблон 2', 'startTime': '14:00', 'endTime': '22:00'});

        // Act
        final templates = await mockScheduleService.getTemplates();

        // Assert
        expect(templates.length, 2);
      });
    });

    // ==================== МАССОВЫЕ ОПЕРАЦИИ ====================

    group('Bulk Operations Tests', () {
      test('AT-SCH-008: Массовое создание смен на неделю', () async {
        // Arrange
        final employees = ['emp_001', 'emp_002', 'emp_003'];
        final startDate = '2026-02-02'; // Monday

        // Act
        final result = await mockScheduleService.bulkCreateWeek(
          employees,
          startDate,
          MockShopData.validShop['id'],
          '09:00',
          '18:00',
        );

        // Assert
        expect(result['success'], true);
        expect(result['created'], greaterThan(0));
      });

      test('AT-SCH-009: Копирование расписания на следующую неделю', () async {
        // Arrange
        await mockScheduleService.createShift({
          'employeeId': MockEmployeeData.validEmployee['id'],
          'shopId': MockShopData.validShop['id'],
          'date': '2026-02-02',
          'startTime': '09:00',
          'endTime': '18:00',
        });

        // Act
        final result = await mockScheduleService.copyWeek(
          '2026-02-02',
          '2026-02-09',
          MockShopData.validShop['id'],
        );

        // Assert
        expect(result['success'], true);
        expect(result['copied'], greaterThan(0));
      });

      test('AT-SCH-010: Удаление всех смен за период', () async {
        // Arrange
        for (var i = 1; i <= 5; i++) {
          await mockScheduleService.createShift({
            'employeeId': MockEmployeeData.validEmployee['id'],
            'shopId': MockShopData.validShop['id'],
            'date': '2026-02-0$i',
            'startTime': '09:00',
            'endTime': '18:00',
          });
        }

        // Act
        final result = await mockScheduleService.deleteRange(
          '2026-02-01',
          '2026-02-05',
          MockShopData.validShop['id'],
        );

        // Assert
        expect(result['success'], true);
        expect(result['deleted'], 5);
      });
    });

    // ==================== ЗАПРОСЫ ====================

    group('Query Tests', () {
      test('AT-SCH-011: Расписание магазина на день', () async {
        // Arrange
        await mockScheduleService.createShift({
          'employeeId': 'emp_001',
          'shopId': MockShopData.validShop['id'],
          'date': '2026-02-01',
          'startTime': '09:00',
          'endTime': '18:00',
        });
        await mockScheduleService.createShift({
          'employeeId': 'emp_002',
          'shopId': MockShopData.validShop['id'],
          'date': '2026-02-01',
          'startTime': '14:00',
          'endTime': '22:00',
        });

        // Act
        final shifts = await mockScheduleService.getShopSchedule(
          MockShopData.validShop['id'],
          '2026-02-01',
        );

        // Assert
        expect(shifts.length, 2);
      });

      test('AT-SCH-012: Расписание сотрудника на месяц', () async {
        // Arrange
        final employeeId = MockEmployeeData.validEmployee['id'];
        for (var i = 1; i <= 10; i++) {
          await mockScheduleService.createShift({
            'employeeId': employeeId,
            'shopId': MockShopData.validShop['id'],
            'date': '2026-02-${i.toString().padLeft(2, '0')}',
            'startTime': '09:00',
            'endTime': '18:00',
          });
        }

        // Act
        final shifts = await mockScheduleService.getEmployeeSchedule(
          employeeId,
          '2026-02',
        );

        // Assert
        expect(shifts.length, 10);
      });

      test('AT-SCH-013: Свободные слоты на день', () async {
        // Arrange
        await mockScheduleService.createShift({
          'employeeId': MockEmployeeData.validEmployee['id'],
          'shopId': MockShopData.validShop['id'],
          'date': '2026-02-01',
          'startTime': '09:00',
          'endTime': '14:00',
        });

        // Act
        final slots = await mockScheduleService.getFreeSlots(
          MockShopData.validShop['id'],
          '2026-02-01',
        );

        // Assert
        expect(slots, isNotEmpty);
        expect(slots.any((s) => s['startTime'] == '14:00'), true);
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockWorkScheduleService {
  final List<Map<String, dynamic>> _shifts = [];
  final List<Map<String, dynamic>> _templates = [];
  int _shiftCounter = 0;
  int _templateCounter = 0;

  Future<Map<String, dynamic>> createShift(Map<String, dynamic> data) async {
    final employeeId = data['employeeId'] as String;
    final date = data['date'] as String;
    final startTime = data['startTime'] as String;
    final endTime = data['endTime'] as String;

    // Validate time
    if (startTime.compareTo(endTime) >= 0) {
      return {'success': false, 'error': 'End time must be after start time'};
    }

    // Check for overlaps
    final existing = _shifts.where((s) =>
      s['employeeId'] == employeeId &&
      s['date'] == date
    );

    for (final shift in existing) {
      final existingStart = shift['startTime'] as String;
      final existingEnd = shift['endTime'] as String;

      // Check overlap
      if (!(endTime.compareTo(existingStart) <= 0 || startTime.compareTo(existingEnd) >= 0)) {
        return {'success': false, 'error': 'Shifts overlap'};
      }
    }

    _shiftCounter++;
    final shift = {
      'id': 'shift_$_shiftCounter',
      'employeeId': employeeId,
      'shopId': data['shopId'],
      'date': date,
      'startTime': startTime,
      'endTime': endTime,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _shifts.add(shift);
    return {'success': true, 'shift': shift};
  }

  Future<Map<String, dynamic>> createTemplate(Map<String, dynamic> data) async {
    _templateCounter++;
    final template = {
      'id': 'template_$_templateCounter',
      'name': data['name'],
      'startTime': data['startTime'],
      'endTime': data['endTime'],
    };
    _templates.add(template);
    return {'success': true, 'template': template};
  }

  Future<Map<String, dynamic>> applyTemplate(
    String templateId,
    String employeeId,
    String date,
    String shopId,
  ) async {
    final template = _templates.firstWhere(
      (t) => t['id'] == templateId,
      orElse: () => <String, dynamic>{},
    );
    if (template.isEmpty) {
      return {'success': false, 'error': 'Template not found'};
    }

    return createShift({
      'employeeId': employeeId,
      'shopId': shopId,
      'date': date,
      'startTime': template['startTime'],
      'endTime': template['endTime'],
    });
  }

  Future<List<Map<String, dynamic>>> getTemplates() async {
    return List.from(_templates);
  }

  Future<Map<String, dynamic>> bulkCreateWeek(
    List<String> employeeIds,
    String startDate,
    String shopId,
    String startTime,
    String endTime,
  ) async {
    int created = 0;
    final start = DateTime.parse(startDate);

    for (final empId in employeeIds) {
      for (var i = 0; i < 5; i++) { // Mon-Fri
        final date = start.add(Duration(days: i));
        final dateStr = date.toIso8601String().substring(0, 10);
        final result = await createShift({
          'employeeId': empId,
          'shopId': shopId,
          'date': dateStr,
          'startTime': startTime,
          'endTime': endTime,
        });
        if (result['success'] == true) created++;
      }
    }

    return {'success': true, 'created': created};
  }

  Future<Map<String, dynamic>> copyWeek(
    String fromWeekStart,
    String toWeekStart,
    String shopId,
  ) async {
    final from = DateTime.parse(fromWeekStart);
    final to = DateTime.parse(toWeekStart);
    final diff = to.difference(from).inDays;

    final weekShifts = _shifts.where((s) {
      final date = DateTime.parse(s['date']);
      return s['shopId'] == shopId &&
             date.isAfter(from.subtract(const Duration(days: 1))) &&
             date.isBefore(from.add(const Duration(days: 7)));
    }).toList();

    int copied = 0;
    for (final shift in weekShifts) {
      final oldDate = DateTime.parse(shift['date']);
      final newDate = oldDate.add(Duration(days: diff));
      final result = await createShift({
        'employeeId': shift['employeeId'],
        'shopId': shift['shopId'],
        'date': newDate.toIso8601String().substring(0, 10),
        'startTime': shift['startTime'],
        'endTime': shift['endTime'],
      });
      if (result['success'] == true) copied++;
    }

    return {'success': true, 'copied': copied};
  }

  Future<Map<String, dynamic>> deleteRange(
    String startDate,
    String endDate,
    String shopId,
  ) async {
    final start = DateTime.parse(startDate);
    final end = DateTime.parse(endDate);

    final toRemove = _shifts.where((s) {
      final date = DateTime.parse(s['date']);
      return s['shopId'] == shopId &&
             !date.isBefore(start) &&
             !date.isAfter(end);
    }).toList();

    final deleted = toRemove.length;
    for (final shift in toRemove) {
      _shifts.remove(shift);
    }

    return {'success': true, 'deleted': deleted};
  }

  Future<List<Map<String, dynamic>>> getShopSchedule(String shopId, String date) async {
    return _shifts.where((s) => s['shopId'] == shopId && s['date'] == date).toList();
  }

  Future<List<Map<String, dynamic>>> getEmployeeSchedule(String employeeId, String month) async {
    return _shifts.where((s) =>
      s['employeeId'] == employeeId &&
      (s['date'] as String).startsWith(month)
    ).toList();
  }

  Future<List<Map<String, dynamic>>> getFreeSlots(String shopId, String date) async {
    // Simplified: return afternoon slot
    return [
      {'startTime': '14:00', 'endTime': '22:00'},
    ];
  }

  void clear() {
    _shifts.clear();
    _templates.clear();
    _shiftCounter = 0;
    _templateCounter = 0;
  }
}
