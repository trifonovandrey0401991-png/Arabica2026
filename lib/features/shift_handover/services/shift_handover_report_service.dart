import '../models/shift_handover_report_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/services/employee_push_service.dart';
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

  /// Подтвердить отчет сдачи смены и отправить push сотруднику
  ///
  /// [report] - отчёт для подтверждения (уже с обновлённым статусом)
  /// [employeePhone] - телефон сотрудника для push уведомления
  /// [rating] - оценка отчёта (1-5)
  static Future<bool> confirmReport(
    ShiftHandoverReport report, {
    required String employeePhone,
    int? rating,
  }) async {
    final success = await updateReport(report);
    if (success) {
      // Отправляем push уведомление сотруднику
      final reportDate =
          '${report.createdAt.day.toString().padLeft(2, '0')}.${report.createdAt.month.toString().padLeft(2, '0')}';
      await EmployeePushService.sendReportStatusPush(
        employeePhone: employeePhone,
        reportType: 'shift_handover',
        status: 'confirmed',
        reportDate: reportDate,
        rating: rating,
      );
      Logger.debug('✅ Пересменка подтверждена и push отправлен');
    }
    return success;
  }

  /// Отклонить отчет сдачи смены и отправить push сотруднику
  ///
  /// [report] - отчёт для отклонения
  /// [employeePhone] - телефон сотрудника для push уведомления
  /// [comment] - причина отклонения
  static Future<bool> rejectReport(
    ShiftHandoverReport report, {
    required String employeePhone,
    String? comment,
  }) async {
    final success = await updateReport(report);
    if (success) {
      final reportDate =
          '${report.createdAt.day.toString().padLeft(2, '0')}.${report.createdAt.month.toString().padLeft(2, '0')}';
      await EmployeePushService.sendReportStatusPush(
        employeePhone: employeePhone,
        reportType: 'shift_handover',
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
