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
  // 5 counters that were previously missing from the batch (showed 0 on startup)
  final int coffeeMachineReports;
  final int unreadProductQuestions;
  final int shiftTransferRequests;
  final int jobApplications;
  final int reportNotifications;

  const DashboardCounters({
    this.totalPendingReports = 0,
    this.pendingOrders = 0,
    this.wholesalePendingOrders = 0,
    this.activeTaskAssignments = 0,
    this.unreadReviews = 0,
    this.coffeeMachineReports = 0,
    this.unreadProductQuestions = 0,
    this.shiftTransferRequests = 0,
    this.jobApplications = 0,
    this.reportNotifications = 0,
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
        coffeeMachineReports: (counters['coffeeMachineReports'] as num?)?.toInt() ?? 0,
        unreadProductQuestions: (counters['unreadProductQuestions'] as num?)?.toInt() ?? 0,
        shiftTransferRequests: (counters['shiftTransferRequests'] as num?)?.toInt() ?? 0,
        jobApplications: (counters['jobApplications'] as num?)?.toInt() ?? 0,
        reportNotifications: (counters['reportNotifications'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      Logger.warning('Dashboard batch error: $e');
      return null;
    }
  }
}
