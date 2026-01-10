import '../models/shift_report_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ShiftReportService {
  static const String baseEndpoint = ApiConstants.shiftReportsEndpoint;

  /// Сохранить отчет пересменки на сервере
  static Future<bool> saveReport(ShiftReport report) async {
    Logger.debug('📤 Сохранение отчета пересменки на сервере: ${report.id}');
    return await BaseHttpService.simplePost(
      endpoint: baseEndpoint,
      body: report.toJson(),
    );
  }

  /// Обновить отчет пересменки на сервере (например, подтвердить)
  static Future<bool> updateReport(ShiftReport report) async {
    Logger.debug('📤 Обновление отчета пересменки на сервере: ${report.id}');
    return await BaseHttpService.simplePut(
      endpoint: '$baseEndpoint/${Uri.encodeComponent(report.id)}',
      body: report.toJson(),
    );
  }

  /// Получить отчеты пересменки с сервера
  static Future<List<ShiftReport>> getReports({
    String? employeeName,
    String? shopAddress,
    DateTime? date,
  }) async {
    Logger.debug('📥 Загрузка отчетов пересменки с сервера...');

    final queryParams = <String, String>{};
    if (employeeName != null) queryParams['employeeName'] = employeeName;
    if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
    if (date != null) {
      queryParams['date'] = date.toIso8601String().split('T')[0];
    }

    return await BaseHttpService.getList<ShiftReport>(
      endpoint: baseEndpoint,
      fromJson: (json) => ShiftReport.fromJson(json),
      listKey: 'reports',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
  }

  /// Получить просроченные отчеты пересменки с сервера
  static Future<List<ShiftReport>> getExpiredReports() async {
    Logger.debug('📥 Загрузка просроченных отчетов пересменки...');
    return await BaseHttpService.getList<ShiftReport>(
      endpoint: '$baseEndpoint/expired',
      fromJson: (json) => ShiftReport.fromJson(json),
      listKey: 'reports',
    );
  }
}



