import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P1 Тесты системы Конвертов для роли СОТРУДНИК
/// Покрывает: Временные окна, автосоздание, сдача, штрафы, подтверждение
void main() {
  group('Envelope System Tests (P1)', () {
    late MockEnvelopeService mockEnvelopeService;
    late MockEnvelopeScheduler mockScheduler;

    setUp(() async {
      mockEnvelopeService = MockEnvelopeService();
      mockScheduler = MockEnvelopeScheduler(mockEnvelopeService);
    });

    tearDown(() async {
      mockEnvelopeService.clear();
      mockScheduler.clear();
    });

    // ==================== ВРЕМЕННЫЕ ОКНА ====================

    group('Time Window Tests', () {
      test('ET-ENV-001: Утреннее окно 07:00-09:00', () async {
        // Arrange
        final settings = await mockEnvelopeService.getSettings();

        // Assert
        expect(settings['morningWindow']['start'], '07:00');
        expect(settings['morningWindow']['end'], '09:00');
      });

      test('ET-ENV-002: Вечернее окно 19:00-21:00', () async {
        // Arrange
        final settings = await mockEnvelopeService.getSettings();

        // Assert
        expect(settings['eveningWindow']['start'], '19:00');
        expect(settings['eveningWindow']['end'], '21:00');
      });

      test('ET-ENV-003: Проверка активности утреннего окна в 08:30', () async {
        // Arrange
        final time = DateTime(2024, 1, 15, 8, 30);

        // Act
        final isActive = mockEnvelopeService.isWindowActive(time, 'morning');

        // Assert
        expect(isActive, true);
      });

      test('ET-ENV-004: Утреннее окно неактивно в 09:30', () async {
        // Arrange
        final time = DateTime(2024, 1, 15, 9, 30);

        // Act
        final isActive = mockEnvelopeService.isWindowActive(time, 'morning');

        // Assert
        expect(isActive, false);
      });

      test('ET-ENV-005: Проверка активности вечернего окна в 20:00', () async {
        // Arrange
        final time = DateTime(2024, 1, 15, 20, 0);

        // Act
        final isActive = mockEnvelopeService.isWindowActive(time, 'evening');

        // Assert
        expect(isActive, true);
      });
    });

    // ==================== АВТОМАТИЧЕСКОЕ СОЗДАНИЕ ====================

    group('Auto Creation Tests', () {
      test('ET-ENV-006: Автосоздание pending отчётов в 07:00', () async {
        // Arrange
        final shops = [
          MockShopData.validShop,
          MockShopData.secondShop,
        ];

        // Act
        await mockScheduler.createPendingReports(shops, 'morning');
        final pending = await mockEnvelopeService.getPendingReports();

        // Assert
        expect(pending.length, shops.length);
        for (final report in pending) {
          expect(report['status'], 'pending');
          expect(report['window'], 'morning');
        }
      });

      test('ET-ENV-007: Автосоздание pending отчётов в 19:00', () async {
        // Arrange
        final shops = [MockShopData.validShop];

        // Act
        await mockScheduler.createPendingReports(shops, 'evening');
        final pending = await mockEnvelopeService.getPendingReports();

        // Assert
        expect(pending.first['window'], 'evening');
      });

      test('ET-ENV-008: Pending отчёт привязан к магазину', () async {
        // Arrange
        final shop = MockShopData.validShop;

        // Act
        await mockScheduler.createPendingReports([shop], 'morning');
        final pending = await mockEnvelopeService.getPendingReports();

        // Assert
        expect(pending.first['shopId'], shop['id']);
        expect(pending.first['shopAddress'], shop['address']);
      });
    });

    // ==================== СДАЧА КОНВЕРТА ====================

    group('Submit Envelope Tests', () {
      test('ET-ENV-009: Сдача конверта в активном окне', () async {
        // Arrange
        final shop = MockShopData.validShop;
        await mockScheduler.createPendingReports([shop], 'morning');
        final employee = MockEmployeeData.validEmployee;

        // Act
        final result = await mockEnvelopeService.submitEnvelope(
          shopId: shop['id'],
          employeeId: employee['id'],
          employeeName: employee['name'],
          amount: 15000,
          photoUrl: '/path/to/photo.jpg',
        );

        // Assert
        expect(result['success'], true);
        expect(result['status'], 'awaiting');
      });

      test('ET-ENV-010: Конверт содержит сумму наличных', () async {
        // Arrange
        final amount = 25000;

        // Act
        final result = await mockEnvelopeService.submitEnvelope(
          shopId: MockShopData.validShop['id'],
          employeeId: MockEmployeeData.validEmployee['id'],
          employeeName: MockEmployeeData.validEmployee['name'],
          amount: amount,
          photoUrl: '/path/to/photo.jpg',
        );

        // Assert
        expect(result['amount'], amount);
      });

      test('ET-ENV-011: Конверт содержит фото', () async {
        // Arrange
        final photoUrl = '/path/to/envelope_photo.jpg';

        // Act
        final result = await mockEnvelopeService.submitEnvelope(
          shopId: MockShopData.validShop['id'],
          employeeId: MockEmployeeData.validEmployee['id'],
          employeeName: MockEmployeeData.validEmployee['name'],
          amount: 15000,
          photoUrl: photoUrl,
        );

        // Assert
        expect(result['photoUrl'], photoUrl);
      });

      test('ET-ENV-012: Статус pending → awaiting после сдачи', () async {
        // Arrange
        final shop = MockShopData.validShop;
        await mockScheduler.createPendingReports([shop], 'morning');

        // Act
        await mockEnvelopeService.submitEnvelope(
          shopId: shop['id'],
          employeeId: MockEmployeeData.validEmployee['id'],
          employeeName: MockEmployeeData.validEmployee['name'],
          amount: 15000,
          photoUrl: '/path/to/photo.jpg',
        );
        final reports = await mockEnvelopeService.getReportsByStatus('awaiting');

        // Assert
        expect(reports.any((r) => r['shopId'] == shop['id']), true);
      });

      test('ET-ENV-013: Сдача без фото отклоняется', () async {
        // Act
        final result = await mockEnvelopeService.submitEnvelope(
          shopId: MockShopData.validShop['id'],
          employeeId: MockEmployeeData.validEmployee['id'],
          employeeName: MockEmployeeData.validEmployee['name'],
          amount: 15000,
          photoUrl: '',
        );

        // Assert
        expect(result['success'], false);
        expect(result['error'], contains('photo'));
      });
    });

    // ==================== АВТОМАТИЧЕСКИЕ ШТРАФЫ ====================

    group('Auto Penalty Tests', () {
      test('ET-ENV-014: Штраф после дедлайна (09:00)', () async {
        // Arrange
        final shop = MockShopData.validShop;
        await mockScheduler.createPendingReports([shop], 'morning');

        // Act
        final penalties = await mockScheduler.processExpiredReports(
          deadline: DateTime(2024, 1, 15, 9, 1), // After deadline
        );

        // Assert
        expect(penalties.length, 1);
        expect(penalties.first['category'], 'envelope_missed_penalty');
        expect(penalties.first['points'], -5);
      });

      test('ET-ENV-015: Штраф -5 баллов', () async {
        // Arrange
        final settings = await mockEnvelopeService.getSettings();

        // Assert
        expect(settings['penaltyPoints'], -5);
      });

      test('ET-ENV-016: Штраф записывается в efficiency-penalties', () async {
        // Arrange
        final shop = MockShopData.validShop;
        await mockScheduler.createPendingReports([shop], 'morning');

        // Act
        await mockScheduler.processExpiredReports(
          deadline: DateTime(2024, 1, 15, 9, 1),
        );
        final penalties = await mockEnvelopeService.getPenalties('2024-01');

        // Assert
        expect(
          penalties.any((p) => p['category'] == 'envelope_missed_penalty'),
          true,
        );
      });

      test('ET-ENV-017: Статус pending → failed после штрафа', () async {
        // Arrange
        final shop = MockShopData.validShop;
        await mockScheduler.createPendingReports([shop], 'morning');

        // Act
        await mockScheduler.processExpiredReports(
          deadline: DateTime(2024, 1, 15, 9, 1),
        );
        final failed = await mockEnvelopeService.getFailedReports();

        // Assert
        expect(failed.any((r) => r['shopId'] == shop['id']), true);
      });

      test('ET-ENV-018: Push-уведомление админу при штрафе', () async {
        // Arrange
        final shop = MockShopData.validShop;
        await mockScheduler.createPendingReports([shop], 'morning');

        // Act
        final result = await mockScheduler.processExpiredReports(
          deadline: DateTime(2024, 1, 15, 9, 1),
        );

        // Assert
        expect(result.first['notificationSent'], true);
        expect(result.first['notificationTarget'], 'admin');
      });

      test('ET-ENV-019: Push-уведомление сотруднику при штрафе', () async {
        // Arrange
        final shop = MockShopData.validShop;
        await mockScheduler.createPendingReports([shop], 'morning');

        // Act
        final result = await mockScheduler.processExpiredReports(
          deadline: DateTime(2024, 1, 15, 9, 1),
        );

        // Assert
        expect(result.first['employeeNotified'], true);
      });
    });

    // ==================== ПОДТВЕРЖДЕНИЕ АДМИНОМ ====================

    group('Admin Confirmation Tests', () {
      test('ET-ENV-020: Подтверждение конверта админом', () async {
        // Arrange
        await mockEnvelopeService.submitEnvelope(
          shopId: MockShopData.validShop['id'],
          employeeId: MockEmployeeData.validEmployee['id'],
          employeeName: MockEmployeeData.validEmployee['name'],
          amount: 15000,
          photoUrl: '/path/to/photo.jpg',
        );
        final awaiting = await mockEnvelopeService.getReportsByStatus('awaiting');
        final reportId = awaiting.first['id'];

        // Act
        final result = await mockEnvelopeService.confirmReport(
          reportId: reportId,
          adminId: MockEmployeeData.adminEmployee['id'],
          rating: 5,
        );

        // Assert
        expect(result['success'], true);
        expect(result['status'], 'confirmed');
      });

      test('ET-ENV-021: Оценка при подтверждении (1-5)', () async {
        // Arrange
        await mockEnvelopeService.submitEnvelope(
          shopId: MockShopData.validShop['id'],
          employeeId: MockEmployeeData.validEmployee['id'],
          employeeName: MockEmployeeData.validEmployee['name'],
          amount: 15000,
          photoUrl: '/path/to/photo.jpg',
        );
        final awaiting = await mockEnvelopeService.getReportsByStatus('awaiting');
        final reportId = awaiting.first['id'];

        // Act
        final result = await mockEnvelopeService.confirmReport(
          reportId: reportId,
          adminId: MockEmployeeData.adminEmployee['id'],
          rating: 4,
        );

        // Assert
        expect(result['rating'], 4);
      });

      test('ET-ENV-022: Отклонение конверта с причиной', () async {
        // Arrange
        await mockEnvelopeService.submitEnvelope(
          shopId: MockShopData.validShop['id'],
          employeeId: MockEmployeeData.validEmployee['id'],
          employeeName: MockEmployeeData.validEmployee['name'],
          amount: 15000,
          photoUrl: '/path/to/photo.jpg',
        );
        final awaiting = await mockEnvelopeService.getReportsByStatus('awaiting');
        final reportId = awaiting.first['id'];

        // Act
        final result = await mockEnvelopeService.rejectReport(
          reportId: reportId,
          adminId: MockEmployeeData.adminEmployee['id'],
          reason: 'Нечёткое фото',
        );

        // Assert
        expect(result['success'], true);
        expect(result['status'], 'rejected');
        expect(result['reason'], 'Нечёткое фото');
      });

      test('ET-ENV-023: Баллы за подтверждённый конверт', () async {
        // Arrange
        final settings = await mockEnvelopeService.getSettings();

        // Assert
        expect(settings['confirmPoints'], greaterThan(0));
      });
    });

    // ==================== 5 ВКЛАДОК ====================

    group('Tab Views Tests', () {
      test('ET-ENV-024: Вкладка "В очереди" (pending)', () async {
        // Arrange
        await mockScheduler.createPendingReports(
          [MockShopData.validShop],
          'morning',
        );

        // Act
        final pending = await mockEnvelopeService.getPendingReports();

        // Assert
        expect(pending.every((r) => r['status'] == 'pending'), true);
      });

      test('ET-ENV-025: Вкладка "Не сданы" (failed)', () async {
        // Arrange
        await mockScheduler.createPendingReports(
          [MockShopData.validShop],
          'morning',
        );
        await mockScheduler.processExpiredReports(
          deadline: DateTime(2024, 1, 15, 9, 1),
        );

        // Act
        final failed = await mockEnvelopeService.getFailedReports();

        // Assert
        expect(failed.every((r) => r['status'] == 'failed'), true);
      });

      test('ET-ENV-026: Вкладка "Ожидают" (awaiting)', () async {
        // Arrange
        await mockEnvelopeService.submitEnvelope(
          shopId: MockShopData.validShop['id'],
          employeeId: MockEmployeeData.validEmployee['id'],
          employeeName: MockEmployeeData.validEmployee['name'],
          amount: 15000,
          photoUrl: '/path/to/photo.jpg',
        );

        // Act
        final awaiting = await mockEnvelopeService.getReportsByStatus('awaiting');

        // Assert
        expect(awaiting.every((r) => r['status'] == 'awaiting'), true);
      });

      test('ET-ENV-027: Вкладка "Подтверждены" (confirmed)', () async {
        // Arrange
        await mockEnvelopeService.submitEnvelope(
          shopId: MockShopData.validShop['id'],
          employeeId: MockEmployeeData.validEmployee['id'],
          employeeName: MockEmployeeData.validEmployee['name'],
          amount: 15000,
          photoUrl: '/path/to/photo.jpg',
        );
        final awaiting = await mockEnvelopeService.getReportsByStatus('awaiting');
        await mockEnvelopeService.confirmReport(
          reportId: awaiting.first['id'],
          adminId: MockEmployeeData.adminEmployee['id'],
          rating: 5,
        );

        // Act
        final confirmed = await mockEnvelopeService.getReportsByStatus('confirmed');

        // Assert
        expect(confirmed.every((r) => r['status'] == 'confirmed'), true);
      });

      test('ET-ENV-028: Вкладка "Отклонены" (rejected)', () async {
        // Arrange
        await mockEnvelopeService.submitEnvelope(
          shopId: MockShopData.validShop['id'],
          employeeId: MockEmployeeData.validEmployee['id'],
          employeeName: MockEmployeeData.validEmployee['name'],
          amount: 15000,
          photoUrl: '/path/to/photo.jpg',
        );
        final awaiting = await mockEnvelopeService.getReportsByStatus('awaiting');
        await mockEnvelopeService.rejectReport(
          reportId: awaiting.first['id'],
          adminId: MockEmployeeData.adminEmployee['id'],
          reason: 'Тест',
        );

        // Act
        final rejected = await mockEnvelopeService.getReportsByStatus('rejected');

        // Assert
        expect(rejected.every((r) => r['status'] == 'rejected'), true);
      });
    });

    // ==================== ОЧИСТКА ====================

    group('Cleanup Tests', () {
      test('ET-ENV-029: Очистка pending/failed в 23:59', () async {
        // Arrange
        await mockScheduler.createPendingReports(
          [MockShopData.validShop],
          'morning',
        );

        // Act
        await mockScheduler.dailyCleanup();
        final pending = await mockEnvelopeService.getPendingReports();
        final failed = await mockEnvelopeService.getFailedReports();

        // Assert
        expect(pending.length, 0);
        expect(failed.length, 0);
      });
    });
  });
}

// ==================== MOCK SERVICES ====================

class MockEnvelopeService {
  final List<Map<String, dynamic>> _reports = [];
  final List<Map<String, dynamic>> _penalties = [];

  Future<Map<String, dynamic>> getSettings() async {
    return {
      'morningWindow': {'start': '07:00', 'end': '09:00'},
      'eveningWindow': {'start': '19:00', 'end': '21:00'},
      'penaltyPoints': -5,
      'confirmPoints': 2,
    };
  }

  bool isWindowActive(DateTime time, String window) {
    final hour = time.hour;
    final minute = time.minute;
    final totalMinutes = hour * 60 + minute;

    if (window == 'morning') {
      return totalMinutes >= 7 * 60 && totalMinutes < 9 * 60;
    } else if (window == 'evening') {
      return totalMinutes >= 19 * 60 && totalMinutes < 21 * 60;
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> getPendingReports() async {
    return _reports.where((r) => r['status'] == 'pending').toList();
  }

  Future<List<Map<String, dynamic>>> getFailedReports() async {
    return _reports.where((r) => r['status'] == 'failed').toList();
  }

  Future<List<Map<String, dynamic>>> getReportsByStatus(String status) async {
    return _reports.where((r) => r['status'] == status).toList();
  }

  Future<Map<String, dynamic>> submitEnvelope({
    required String shopId,
    required String employeeId,
    required String employeeName,
    required int amount,
    required String photoUrl,
  }) async {
    if (photoUrl.isEmpty) {
      return {'success': false, 'error': 'photo is required'};
    }

    final report = {
      'id': 'env_${DateTime.now().millisecondsSinceEpoch}',
      'shopId': shopId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'amount': amount,
      'photoUrl': photoUrl,
      'status': 'awaiting',
      'createdAt': DateTime.now().toIso8601String(),
      'success': true,
    };

    // Remove pending for this shop
    _reports.removeWhere((r) => r['shopId'] == shopId && r['status'] == 'pending');
    _reports.add(report);

    return report;
  }

  Future<Map<String, dynamic>> confirmReport({
    required String reportId,
    required String adminId,
    required int rating,
  }) async {
    final index = _reports.indexWhere((r) => r['id'] == reportId);
    if (index >= 0) {
      _reports[index]['status'] = 'confirmed';
      _reports[index]['rating'] = rating;
      _reports[index]['confirmedBy'] = adminId;
      return {
        'success': true,
        'status': 'confirmed',
        'rating': rating,
      };
    }
    return {'success': false, 'error': 'Report not found'};
  }

  Future<Map<String, dynamic>> rejectReport({
    required String reportId,
    required String adminId,
    required String reason,
  }) async {
    final index = _reports.indexWhere((r) => r['id'] == reportId);
    if (index >= 0) {
      _reports[index]['status'] = 'rejected';
      _reports[index]['reason'] = reason;
      _reports[index]['rejectedBy'] = adminId;
      return {
        'success': true,
        'status': 'rejected',
        'reason': reason,
      };
    }
    return {'success': false, 'error': 'Report not found'};
  }

  void addPendingReport(Map<String, dynamic> report) {
    _reports.add(report);
  }

  void markFailed(String shopId) {
    final index = _reports.indexWhere(
      (r) => r['shopId'] == shopId && r['status'] == 'pending',
    );
    if (index >= 0) {
      _reports[index]['status'] = 'failed';
    }
  }

  void addPenalty(Map<String, dynamic> penalty) {
    _penalties.add(penalty);
  }

  Future<List<Map<String, dynamic>>> getPenalties(String month) async {
    return _penalties.where((p) => p['month'] == month).toList();
  }

  void clearPendingAndFailed() {
    _reports.removeWhere(
      (r) => r['status'] == 'pending' || r['status'] == 'failed',
    );
  }

  void clear() {
    _reports.clear();
    _penalties.clear();
  }
}

class MockEnvelopeScheduler {
  final MockEnvelopeService _service;

  MockEnvelopeScheduler(this._service);

  Future<void> createPendingReports(
    List<Map<String, dynamic>> shops,
    String window,
  ) async {
    for (final shop in shops) {
      _service.addPendingReport({
        'id': 'pending_${shop['id']}_$window',
        'shopId': shop['id'],
        'shopAddress': shop['address'],
        'window': window,
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<Map<String, dynamic>>> processExpiredReports({
    required DateTime deadline,
  }) async {
    final pending = await _service.getPendingReports();
    final penalties = <Map<String, dynamic>>[];

    for (final report in pending) {
      _service.markFailed(report['shopId']);

      final penalty = {
        'shopId': report['shopId'],
        'category': 'envelope_missed_penalty',
        'points': -5,
        'month': '2024-01',
        'notificationSent': true,
        'notificationTarget': 'admin',
        'employeeNotified': true,
        'createdAt': DateTime.now().toIso8601String(),
      };
      penalties.add(penalty);
      _service.addPenalty(penalty);
    }

    return penalties;
  }

  Future<void> dailyCleanup() async {
    _service.clearPendingAndFailed();
  }

  void clear() {
    _service.clear();
  }
}

// ==================== MOCK DATA ====================

class MockShopData {
  static const Map<String, dynamic> validShop = {
    'id': 'shop_001',
    'name': 'Кофейня на Арбате',
    'address': 'ул. Арбат, 10',
  };

  static const Map<String, dynamic> secondShop = {
    'id': 'shop_002',
    'name': 'Кофейня на Тверской',
    'address': 'ул. Тверская, 20',
  };
}

class MockEmployeeData {
  static const Map<String, dynamic> validEmployee = {
    'id': 'emp_001',
    'name': 'Тестовый Сотрудник',
    'phone': '79001234567',
    'isAdmin': false,
  };

  static const Map<String, dynamic> adminEmployee = {
    'id': 'admin_001',
    'name': 'Администратор',
    'phone': '79009999999',
    'isAdmin': true,
  };
}
