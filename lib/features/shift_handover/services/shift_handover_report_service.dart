import '../models/shift_handover_report_model.dart';
import '../../../core/services/base_report_service.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ShiftHandoverReportService {
  static const String baseEndpoint = ApiConstants.shiftHandoverReportsEndpoint;

  static final _base = BaseReportService<ShiftHandoverReport>(
    endpoint: baseEndpoint,
    fromJson: (json) => ShiftHandoverReport.fromJson(json),
    getShopAddress: (r) => r.shopAddress,
    reportType: 'shift_handover',
  );

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

  /// Подтвердить отчет сдачи смены и отправить push сотруднику
  static Future<bool> confirmReport(
    ShiftHandoverReport report, {
    required String employeePhone,
    int? rating,
  }) async {
    final success = await updateReport(report);
    if (success) {
      final reportDate =
          '${report.createdAt.day.toString().padLeft(2, '0')}.${report.createdAt.month.toString().padLeft(2, '0')}';
      await _base.sendStatusPush(
        employeePhone: employeePhone,
        status: 'confirmed',
        reportDate: reportDate,
        rating: rating,
      );
      Logger.debug('✅ Пересменка подтверждена и push отправлен');
    }
    return success;
  }

  /// Отклонить отчет сдачи смены и отправить push сотруднику
  static Future<bool> rejectReport(
    ShiftHandoverReport report, {
    required String employeePhone,
    String? comment,
  }) async {
    final success = await updateReport(report);
    if (success) {
      final reportDate =
          '${report.createdAt.day.toString().padLeft(2, '0')}.${report.createdAt.month.toString().padLeft(2, '0')}';
      await _base.sendStatusPush(
        employeePhone: employeePhone,
        status: 'rejected',
        reportDate: reportDate,
        comment: comment,
      );
      Logger.debug('✅ Пересменка отклонена и push отправлен');
    }
    return success;
  }

  /// Получить отчеты сдачи смены с сервера
  static Future<List<ShiftHandoverReport>> getReports({
    String? employeeName,
    String? shopAddress,
    DateTime? date,
  }) => _base.getReports(
    queryParams: BaseReportService.buildQueryParams({
      'employeeName': employeeName,
      'shopAddress': shopAddress,
      'date': date?.toIso8601String().split('T')[0],
    }),
  );

  /// Получить отчеты сдачи смены с фильтрацией по мультитенантности
  ///
  /// Developer видит все, Admin видит только свои магазины
  static Future<List<ShiftHandoverReport>> getReportsForCurrentUser({
    String? employeeName,
    String? shopAddress,
    DateTime? date,
  }) => _base.getReportsForCurrentUser(
    queryParams: BaseReportService.buildQueryParams({
      'employeeName': employeeName,
      'shopAddress': shopAddress,
      'date': date?.toIso8601String().split('T')[0],
    }),
  );

  /// Получить отчет по ID
  static Future<ShiftHandoverReport?> getReport(String reportId) => _base.getReport(reportId);

  /// Получить просроченные отчеты сдачи смены с сервера
  static Future<List<ShiftHandoverReport>> getExpiredReports() => _base.getExpiredReports();

  /// Удалить отчет с сервера
  static Future<bool> deleteReport(String reportId) => _base.deleteReport(reportId);
}
