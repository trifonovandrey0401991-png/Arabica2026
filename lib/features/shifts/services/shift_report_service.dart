import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/shift_report_model.dart';
import '../../../core/services/base_report_service.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

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

  static final _base = BaseReportService<ShiftReport>(
    endpoint: baseEndpoint,
    fromJson: (json) => ShiftReport.fromJson(json),
    getShopAddress: (r) => r.shopAddress,
    reportType: 'shift',
  );

  /// Отправить отчет пересменки на сервер с обработкой TIME_EXPIRED
  static Future<ShiftSubmitResult> submitReport(ShiftReport report) async {
    Logger.debug('📤 Отправка отчета пересменки: ${report.id}');

    // Две попытки: если первая не удалась из-за сети — пробуем ещё раз
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        Logger.debug('📤 Попытка $attempt/2...');
        final response = await http
            .post(
              Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
              headers: ApiConstants.jsonHeaders,
              body: jsonEncode(report.toJson()),
            )
            .timeout(ApiConstants.longTimeout);

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

        // Обработка ошибок сервера (не сетевых — повтор не поможет)
        final errorType = result['error']?.toString();
        final message = result['message']?.toString();

        Logger.warning('⚠️ Ошибка отправки: $errorType - $message');
        return ShiftSubmitResult(
          success: false,
          errorType: errorType,
          message: message ?? 'Ошибка сохранения отчёта',
        );
      } catch (e) {
        Logger.error('❌ Ошибка сети при отправке отчёта (попытка $attempt)', e);
        if (attempt < 2) {
          Logger.debug('🔄 Повторная попытка через 2 секунды...');
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        return ShiftSubmitResult(
          success: false,
          errorType: 'NETWORK_ERROR',
          message: 'Ошибка сети: $e',
        );
      }
    }

    // Не должны сюда попасть, но на всякий случай
    return ShiftSubmitResult(success: false, errorType: 'UNKNOWN', message: 'Неизвестная ошибка');
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
  }) => _base.getReports(
    queryParams: BaseReportService.buildQueryParams({
      'employeeName': employeeName,
      'shopAddress': shopAddress,
      'date': date?.toIso8601String().split('T')[0],
    }),
  );

  /// Получить отчеты пересменки с фильтрацией по мультитенантности
  ///
  /// Developer видит все, Admin видит только свои магазины
  static Future<List<ShiftReport>> getReportsForCurrentUser({
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

  /// Получить просроченные отчеты пересменки с сервера
  static Future<List<ShiftReport>> getExpiredReports() => _base.getExpiredReports();

  /// Получить просроченные отчеты с фильтрацией по мультитенантности
  static Future<List<ShiftReport>> getExpiredReportsForCurrentUser() => _base.getExpiredReportsForCurrentUser();

  /// Получить pending отчёты для текущего дня
  static Future<List<ShiftReport>> getPendingReports({
    String? shopAddress,
    String? shiftType,
  }) async {
    Logger.debug('📥 Загрузка pending отчетов...');

    // FIX: Не фильтруем по дате — для midnight-crossing окон (23:01-13:00)
    // pending отчёты могут быть на завтрашнюю дату. Pending всегда актуальны
    // (старые автоматически переходят в failed).
    final queryParams = <String, String>{
      'status': 'pending',
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

  /// Получить pending отчёты с фильтрацией по мультитенантности
  static Future<List<ShiftReport>> getPendingReportsForCurrentUser({
    String? shopAddress,
    String? shiftType,
  }) async {
    final reports = await getPendingReports(
      shopAddress: shopAddress,
      shiftType: shiftType,
    );
    return await MultitenancyFilterService.filterByShopAddress(
      reports,
      (r) => r.shopAddress,
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
