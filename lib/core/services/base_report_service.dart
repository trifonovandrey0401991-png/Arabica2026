import 'base_http_service.dart';
import 'multitenancy_filter_service.dart';
import 'employee_push_service.dart';
import '../utils/logger.dart';

/// Базовый сервис для работы с отчётами.
///
/// Инкапсулирует общие CRUD-операции, multitenancy фильтрацию
/// и push-уведомления о статусе отчётов.
///
/// Используется через композицию: каждый конкретный сервис
/// создаёт `static final _base = BaseReportService<T>(...)`.
class BaseReportService<T> {
  final String endpoint;
  final T Function(Map<String, dynamic>) fromJson;
  final String Function(T) getShopAddress;
  final String listKey;
  final String reportType;

  const BaseReportService({
    required this.endpoint,
    required this.fromJson,
    required this.getShopAddress,
    this.listKey = 'reports',
    required this.reportType,
  });

  /// Получить список отчётов с фильтрами
  Future<List<T>> getReports({
    Map<String, String>? queryParams,
    Duration? timeout,
  }) async {
    Logger.debug('📥 Загрузка отчётов ($reportType)...');
    return await BaseHttpService.getList<T>(
      endpoint: endpoint,
      fromJson: fromJson,
      listKey: listKey,
      queryParams: queryParams,
      timeout: timeout,
    );
  }

  /// Получить отчёты с фильтрацией по мультитенантности
  ///
  /// Developer видит все, Admin видит только свои магазины
  Future<List<T>> getReportsForCurrentUser({
    Map<String, String>? queryParams,
    Duration? timeout,
  }) async {
    final reports = await getReports(
      queryParams: queryParams,
      timeout: timeout,
    );
    return await MultitenancyFilterService.filterByShopAddress(
      reports,
      getShopAddress,
    );
  }

  /// Получить просроченные отчёты
  Future<List<T>> getExpiredReports() async {
    Logger.debug('📥 Загрузка просроченных отчётов ($reportType)...');
    return await BaseHttpService.getList<T>(
      endpoint: '$endpoint/expired',
      fromJson: fromJson,
      listKey: listKey,
    );
  }

  /// Получить отчёт по ID
  Future<T?> getReport(String id) async {
    Logger.debug('📥 Загрузка отчёта $reportType: $id');
    return await BaseHttpService.get<T>(
      endpoint: '$endpoint/$id',
      fromJson: fromJson,
      itemKey: 'report',
    );
  }

  /// Удалить отчёт
  Future<bool> deleteReport(String id) async {
    Logger.debug('🗑️ Удаление отчёта $reportType: $id');
    return await BaseHttpService.delete(endpoint: '$endpoint/$id');
  }

  /// Подтвердить отчёт через PUT /$id/confirm
  ///
  /// Используется Envelope и CoffeeMachine сервисами
  Future<T?> confirmViaEndpoint(
    String id,
    String adminName,
    int rating,
  ) async {
    Logger.debug('Подтверждение отчёта $reportType: $id, оценка: $rating');
    return await BaseHttpService.put<T>(
      endpoint: '$endpoint/$id/confirm',
      body: {
        'confirmedByAdmin': adminName,
        'rating': rating,
      },
      fromJson: fromJson,
      itemKey: 'report',
    );
  }

  /// Отклонить отчёт через PUT /$id/reject
  ///
  /// Используется Envelope и CoffeeMachine сервисами
  Future<T?> rejectViaEndpoint(
    String id,
    String adminName,
    String? reason,
  ) async {
    Logger.debug('Отклонение отчёта $reportType: $id');
    return await BaseHttpService.put<T>(
      endpoint: '$endpoint/$id/reject',
      body: {
        'rejectedByAdmin': adminName,
        'rejectReason': reason,
      },
      fromJson: fromJson,
      itemKey: 'report',
    );
  }

  /// Отправить push-уведомление о статусе отчёта
  Future<bool> sendStatusPush({
    required String employeePhone,
    required String status,
    String? reportDate,
    int? rating,
    String? comment,
  }) async {
    return await EmployeePushService.sendReportStatusPush(
      employeePhone: employeePhone,
      reportType: reportType,
      status: status,
      reportDate: reportDate,
      rating: rating,
      comment: comment,
    );
  }

  /// Построить Map query-параметров, отбросив null значения
  static Map<String, String>? buildQueryParams(Map<String, String?> params) {
    final result = <String, String>{};
    for (final entry in params.entries) {
      if (entry.value != null) result[entry.key] = entry.value!;
    }
    return result.isNotEmpty ? result : null;
  }
}
