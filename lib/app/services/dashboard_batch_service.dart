import '../../core/services/base_http_service.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/logger.dart';

/// Счётчики бейджей главного меню, загруженные одним batch-запросом.
class DashboardCounters {
  final int totalPendingReports;
  final int pendingOrders;
  final int wholesalePendingOrders;
  final int activeTaskAssignments;
  final int unreadReviews;

  const DashboardCounters({
    this.totalPendingReports = 0,
    this.pendingOrders = 0,
    this.wholesalePendingOrders = 0,
    this.activeTaskAssignments = 0,
    this.unreadReviews = 0,
  });
}

/// Сервис для получения счётчиков главного меню одним запросом.
/// Заменяет 3+ отдельных API-вызовов на один GET /api/dashboard/counters.
class DashboardBatchService {
  static Future<DashboardCounters?> getCounters({
    String? phone,
    String? employeeId,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (phone != null) queryParams['phone'] = phone;
      if (employeeId != null) queryParams['employeeId'] = employeeId;

      final result = await BaseHttpService.getRaw(
        endpoint: '/api/dashboard/counters',
        queryParams: queryParams,
        timeout: ApiConstants.shortTimeout,
      );

      if (result == null) return null;

      final counters = result['counters'] as Map<String, dynamic>?;
      if (counters == null) return null;

      return DashboardCounters(
        totalPendingReports: (counters['totalPendingReports'] as num?)?.toInt() ?? 0,
        pendingOrders: (counters['pendingOrders'] as num?)?.toInt() ?? 0,
        wholesalePendingOrders: (counters['wholesalePendingOrders'] as num?)?.toInt() ?? 0,
        activeTaskAssignments: (counters['activeTaskAssignments'] as num?)?.toInt() ?? 0,
        unreadReviews: (counters['unreadReviews'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      Logger.warning('Dashboard batch error: $e');
      return null;
    }
  }
}
