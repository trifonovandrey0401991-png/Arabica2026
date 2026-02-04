import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/shift_report_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/multitenancy_filter_service.dart';

/// Результат отправки отчёта пересменки
class ShiftSubmitResult {
  final bool success;
  final String? errorType; // 'TIME_EXPIRED' или другие
  final String? message;
  final ShiftReport? report;

  ShiftSubmitResult({
    required this.success,
    this.errorType,
    this.message,
    this.report,
  });

  bool get isTimeExpired => errorType == 'TIME_EXPIRED';
}

class ShiftReportService {
  static const String baseEndpoint = ApiConstants.shiftReportsEndpoint;

  /// Отправить отчет пересменки на сервер с обработкой TIME_EXPIRED
  static Future<ShiftSubmitResult> submitReport(ShiftReport report) async {
    Logger.debug('📤 Отправка отчета пересменки: ${report.id}');

    try {
      final response = await http
          .post(
            Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
            headers: ApiConstants.jsonHeaders,
            body: jsonEncode(report.toJson()),
          )
          .timeout(ApiConstants.defaultTimeout);

      final result = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (result['success'] == true) {
          Logger.debug('✅ Отчёт успешно отправлен');
          return ShiftSubmitResult(
            success: true,
            report: result['report'] != null
                ? ShiftReport.fromJson(result['report'])
                : null,
          );
        }
      }

      // Обработка ошибок
      final errorType = result['error']?.toString();
      final message = result['message']?.toString();

      Logger.warning('⚠️ Ошибка отправки: $errorType - $message');
      return ShiftSubmitResult(
        success: false,
        errorType: errorType,
        message: message ?? 'Ошибка сохранения отчёта',
      );
    } catch (e) {
      Logger.error('❌ Ошибка сети при отправке отчёта', e);
      return ShiftSubmitResult(
        success: false,
        errorType: 'NETWORK_ERROR',
        message: 'Ошибка сети: $e',
      );
    }
  }

  /// Сохранить отчет пересменки на сервере (устаревший метод для обратной совместимости)
  static Future<bool> saveReport(ShiftReport report) async {
    final result = await submitReport(report);
    return result.success;
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

  /// Получить отчеты пересменки с фильтрацией по мультитенантности
  ///
  /// Developer видит все, Admin видит только свои магазины
  static Future<List<ShiftReport>> getReportsForCurrentUser({
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

  /// Получить просроченные отчеты пересменки с сервера
  static Future<List<ShiftReport>> getExpiredReports() async {
    Logger.debug('📥 Загрузка просроченных отчетов пересменки...');
    return await BaseHttpService.getList<ShiftReport>(
      endpoint: '$baseEndpoint/expired',
      fromJson: (json) => ShiftReport.fromJson(json),
      listKey: 'reports',
    );
  }

  /// Получить pending отчёты для текущего дня
  static Future<List<ShiftReport>> getPendingReports({
    String? shopAddress,
    String? shiftType,
  }) async {
    Logger.debug('📥 Загрузка pending отчетов...');

    final queryParams = <String, String>{
      'status': 'pending',
      'date': DateTime.now().toIso8601String().split('T')[0],
    };
    if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
    if (shiftType != null) queryParams['shiftType'] = shiftType;

    return await BaseHttpService.getList<ShiftReport>(
      endpoint: baseEndpoint,
      fromJson: (json) => ShiftReport.fromJson(json),
      listKey: 'reports',
      queryParams: queryParams,
    );
  }

  /// Проверить есть ли pending отчёт для магазина/смены
  static Future<ShiftReport?> findPendingReport({
    required String shopAddress,
    required String shiftType,
  }) async {
    final reports = await getPendingReports(
      shopAddress: shopAddress,
      shiftType: shiftType,
    );
    return reports.isNotEmpty ? reports.first : null;
  }
}



