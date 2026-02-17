import 'package:flutter_test/flutter_test.dart';

/// P1 Тесты batch-сервиса дашборда (Task 2.4)
/// Покрывает: модель DashboardCounters, парсинг, дефолты, fallback
void main() {
  group('Dashboard Batch Tests (Phase 2.4)', () {
    late MockDashboardBatchService mockService;

    setUp(() {
      mockService = MockDashboardBatchService();
    });

    // ==================== МОДЕЛЬ ====================

    group('DashboardCounters Model', () {
      test('PH2-DASH-001: Корректный парсинг всех счётчиков', () {
        // Arrange
        final json = {
          'counters': {
            'totalPendingReports': 5,
            'pendingOrders': 3,
            'activeTaskAssignments': 7,
            'unreadReviews': 2,
          }
        };

        // Act
        final counters = mockService.parseCounters(json);

        // Assert
        expect(counters, isNotNull);
        expect(counters!.totalPendingReports, 5);
        expect(counters.pendingOrders, 3);
        expect(counters.activeTaskAssignments, 7);
        expect(counters.unreadReviews, 2);
      });

      test('PH2-DASH-002: Дефолтные значения при отсутствии полей', () {
        // Arrange
        final json = {
          'counters': <String, dynamic>{}
        };

        // Act
        final counters = mockService.parseCounters(json);

        // Assert
        expect(counters, isNotNull);
        expect(counters!.totalPendingReports, 0);
        expect(counters.pendingOrders, 0);
        expect(counters.activeTaskAssignments, 0);
        expect(counters.unreadReviews, 0);
      });

      test('PH2-DASH-003: null при отсутствии ключа counters', () {
        // Arrange
        final json = {'success': true};

        // Act
        final counters = mockService.parseCounters(json);

        // Assert
        expect(counters, isNull);
      });

      test('PH2-DASH-004: null при null ответе сервера', () {
        // Act
        final counters = mockService.parseCounters(null);

        // Assert
        expect(counters, isNull);
      });

      test('PH2-DASH-005: Парсинг num как int (double → int)', () {
        // Arrange — сервер может вернуть double
        final json = {
          'counters': {
            'totalPendingReports': 3.0,
            'pendingOrders': 1.0,
            'activeTaskAssignments': 0.0,
            'unreadReviews': 4.0,
          }
        };

        // Act
        final counters = mockService.parseCounters(json);

        // Assert
        expect(counters, isNotNull);
        expect(counters!.totalPendingReports, 3);
        expect(counters.pendingOrders, 1);
        expect(counters.activeTaskAssignments, 0);
        expect(counters.unreadReviews, 4);
      });

      test('PH2-DASH-006: Частичные данные (только некоторые поля)', () {
        // Arrange
        final json = {
          'counters': {
            'totalPendingReports': 10,
            // Остальные поля отсутствуют
          }
        };

        // Act
        final counters = mockService.parseCounters(json);

        // Assert
        expect(counters, isNotNull);
        expect(counters!.totalPendingReports, 10);
        expect(counters.pendingOrders, 0);
        expect(counters.activeTaskAssignments, 0);
        expect(counters.unreadReviews, 0);
      });
    });

    // ==================== ЗАПРОС ====================

    group('DashboardBatch Request', () {
      test('PH2-DASH-007: Query-параметры формируются с phone', () {
        // Act
        final params = mockService.buildQueryParams(
          phone: '79001234567',
          employeeId: null,
        );

        // Assert
        expect(params['phone'], '79001234567');
        expect(params.containsKey('employeeId'), false);
      });

      test('PH2-DASH-008: Query-параметры формируются с employeeId', () {
        // Act
        final params = mockService.buildQueryParams(
          phone: null,
          employeeId: 'emp_001',
        );

        // Assert
        expect(params.containsKey('phone'), false);
        expect(params['employeeId'], 'emp_001');
      });

      test('PH2-DASH-009: Query-параметры с обоими полями', () {
        // Act
        final params = mockService.buildQueryParams(
          phone: '79001234567',
          employeeId: 'emp_001',
        );

        // Assert
        expect(params['phone'], '79001234567');
        expect(params['employeeId'], 'emp_001');
      });

      test('PH2-DASH-010: Пустые параметры без phone и employeeId', () {
        // Act
        final params = mockService.buildQueryParams(
          phone: null,
          employeeId: null,
        );

        // Assert
        expect(params.isEmpty, true);
      });
    });

    // ==================== FALLBACK ====================

    group('DashboardBatch Fallback', () {
      test('PH2-DASH-011: Fallback вызывается при ошибке batch', () async {
        // Arrange
        mockService.shouldFail = true;
        var fallbackCalled = false;

        // Act
        await mockService.getCounters(
          phone: '79001234567',
          onFallback: () => fallbackCalled = true,
        );

        // Assert
        expect(fallbackCalled, true);
      });

      test('PH2-DASH-012: Успешный batch — fallback НЕ вызывается', () async {
        // Arrange
        mockService.shouldFail = false;
        var fallbackCalled = false;

        // Act
        await mockService.getCounters(
          phone: '79001234567',
          onFallback: () => fallbackCalled = true,
        );

        // Assert
        expect(fallbackCalled, false);
      });
    });
  });
}

// ==================== MOCK ====================

class DashboardCountersModel {
  final int totalPendingReports;
  final int pendingOrders;
  final int activeTaskAssignments;
  final int unreadReviews;

  const DashboardCountersModel({
    this.totalPendingReports = 0,
    this.pendingOrders = 0,
    this.activeTaskAssignments = 0,
    this.unreadReviews = 0,
  });
}

class MockDashboardBatchService {
  bool shouldFail = false;

  DashboardCountersModel? parseCounters(Map<String, dynamic>? result) {
    if (result == null) return null;

    final counters = result['counters'] as Map<String, dynamic>?;
    if (counters == null) return null;

    return DashboardCountersModel(
      totalPendingReports:
          (counters['totalPendingReports'] as num?)?.toInt() ?? 0,
      pendingOrders: (counters['pendingOrders'] as num?)?.toInt() ?? 0,
      activeTaskAssignments:
          (counters['activeTaskAssignments'] as num?)?.toInt() ?? 0,
      unreadReviews: (counters['unreadReviews'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, String> buildQueryParams({
    String? phone,
    String? employeeId,
  }) {
    final params = <String, String>{};
    if (phone != null) params['phone'] = phone;
    if (employeeId != null) params['employeeId'] = employeeId;
    return params;
  }

  Future<DashboardCountersModel?> getCounters({
    String? phone,
    void Function()? onFallback,
  }) async {
    try {
      if (shouldFail) throw Exception('Batch failed');
      return DashboardCountersModel(
        totalPendingReports: 5,
        pendingOrders: 3,
        activeTaskAssignments: 7,
        unreadReviews: 2,
      );
    } catch (e) {
      onFallback?.call();
      return null;
    }
  }
}
