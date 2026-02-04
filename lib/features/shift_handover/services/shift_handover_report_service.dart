import '../models/shift_handover_report_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/multitenancy_filter_service.dart';

class ShiftHandoverReportService {
  static const String baseEndpoint = ApiConstants.shiftHandoverReportsEndpoint;

  /// Сохранить отчет сдачи смены на сервере
  static Future<bool> saveReport(ShiftHandoverReport report) async {
    Logger.debug('📤 Сохранение отчета сдачи смены на сервере: ${report.id}');
    return await BaseHttpService.simplePost(
      endpoint: baseEndpoint,
      body: report.toJson(),
    );
  }

  /// Обновить отчет сдачи смены на сервере (например, подтвердить)
  static Future<bool> updateReport(ShiftHandoverReport report) async {
    Logger.debug('📤 Обновление отчета сдачи смены на сервере: ${report.id}');
    return await BaseHttpService.simplePut(
      endpoint: '$baseEndpoint/${Uri.encodeComponent(report.id)}',
      body: report.toJson(),
    );
  }

  /// Получить отчеты сдачи смены с сервера
  static Future<List<ShiftHandoverReport>> getReports({
    String? employeeName,
    String? shopAddress,
    DateTime? date,
  }) async {
    Logger.debug('📥 Загрузка отчетов сдачи смены с сервера...');

    final queryParams = <String, String>{};
    if (employeeName != null) queryParams['employeeName'] = employeeName;
    if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
    if (date != null) {
      queryParams['date'] = date.toIso8601String().split('T')[0];
    }

    return await BaseHttpService.getList<ShiftHandoverReport>(
      endpoint: baseEndpoint,
      fromJson: (json) => ShiftHandoverReport.fromJson(json),
      listKey: 'reports',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
  }

  /// Получить отчеты сдачи смены с фильтрацией по мультитенантности
  ///
  /// Developer видит все, Admin видит только свои магазины
  static Future<List<ShiftHandoverReport>> getReportsForCurrentUser({
    String? employeeName,
    String? shopAddress,
    DateTime? date,
  }) async {
    final reports = await getReports(
      employeeName: employeeName,
      shopAddress: shopAddress,
      date: date,
    );

    return await MultitenancyFilterService.filterByShopAddress(
      reports,
      (report) => report.shopAddress,
    );
  }

  /// Получить отчет по ID
  static Future<ShiftHandoverReport?> getReport(String reportId) async {
    Logger.debug('📥 Загрузка отчета сдачи смены: $reportId');
    return await BaseHttpService.get<ShiftHandoverReport>(
      endpoint: '$baseEndpoint/$reportId',
      fromJson: (json) => ShiftHandoverReport.fromJson(json),
      itemKey: 'report',
    );
  }

  /// Получить просроченные отчеты сдачи смены с сервера
  static Future<List<ShiftHandoverReport>> getExpiredReports() async {
    Logger.debug('📥 Загрузка просроченных отчетов сдачи смены...');
    return await BaseHttpService.getList<ShiftHandoverReport>(
      endpoint: '$baseEndpoint/expired',
      fromJson: (json) => ShiftHandoverReport.fromJson(json),
      listKey: 'reports',
    );
  }

  /// Удалить отчет с сервера
  static Future<bool> deleteReport(String reportId) async {
    Logger.debug('📤 Удаление отчета сдачи смены: $reportId');
    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/$reportId',
    );
  }
}
