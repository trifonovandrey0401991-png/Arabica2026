import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/services/base_report_service.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';
import '../models/coffee_machine_report_model.dart';
import '../models/pending_coffee_machine_report_model.dart';

/// Сервис для работы с отчётами по счётчикам кофемашин
class CoffeeMachineReportService {
  static const String baseEndpoint = '/api/coffee-machine/reports';

  static final _base = BaseReportService<CoffeeMachineReport>(
    endpoint: baseEndpoint,
    fromJson: (json) => CoffeeMachineReport.fromJson(json),
    getShopAddress: (r) => r.shopAddress,
    reportType: 'coffee_machine',
  );

  /// Получить все отчёты
  static Future<List<CoffeeMachineReport>> getReports({
    String? shopAddress,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) => _base.getReports(
    queryParams: BaseReportService.buildQueryParams({
      'shopAddress': shopAddress,
      'status': status,
      'fromDate': fromDate?.toIso8601String(),
      'toDate': toDate?.toIso8601String(),
    }),
  );

  /// Получить отчёты с фильтрацией по мультитенантности
  static Future<List<CoffeeMachineReport>> getReportsForCurrentUser({
    String? shopAddress,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) => _base.getReportsForCurrentUser(
    queryParams: BaseReportService.buildQueryParams({
      'shopAddress': shopAddress,
      'status': status,
      'fromDate': fromDate?.toIso8601String(),
      'toDate': toDate?.toIso8601String(),
    }),
  );

  /// Получить отчёт по ID
  static Future<CoffeeMachineReport?> getReport(String id) => _base.getReport(id);

  /// Создать новый отчёт
  static Future<CoffeeMachineReport?> createReport(CoffeeMachineReport report) async {
    Logger.debug('Создание отчёта кофемашины: ${report.employeeName}');
    return await BaseHttpService.post<CoffeeMachineReport>(
      endpoint: baseEndpoint,
      body: report.toJson(),
      fromJson: (json) => CoffeeMachineReport.fromJson(json),
      itemKey: 'report',
    );
  }

  /// Удалить отчёт
  static Future<bool> deleteReport(String id) => _base.deleteReport(id);

  /// Подтвердить отчёт с оценкой
  static Future<CoffeeMachineReport?> confirmReport(String id, String adminName, int rating) =>
    _base.confirmViaEndpoint(id, adminName, rating);

  /// Подтвердить отчёт с push уведомлением сотруднику
  static Future<CoffeeMachineReport?> confirmReportWithPush({
    required String id,
    required String adminName,
    required int rating,
    required String employeePhone,
    String? reportDate,
  }) async {
    final report = await confirmReport(id, adminName, rating);
    if (report != null) {
      Logger.debug('Счётчик подтверждён, отправка push сотруднику');
      await _base.sendStatusPush(
        employeePhone: employeePhone,
        status: 'confirmed',
        reportDate: reportDate,
        rating: rating,
      );
    }
    return report;
  }

  /// Отклонить отчёт с push уведомлением сотруднику
  static Future<bool> rejectReportWithPush({
    required String id,
    required String adminName,
    required String employeePhone,
    String? comment,
    String? reportDate,
  }) async {
    final result = await _base.rejectViaEndpoint(id, adminName, comment);
    if (result != null) {
      Logger.debug('Счётчик отклонён, отправка push сотруднику');
      await _base.sendStatusPush(
        employeePhone: employeePhone,
        status: 'rejected',
        reportDate: reportDate,
        comment: comment,
      );
      return true;
    }
    return false;
  }

  /// Получить pending отчёты (ожидающие сдачи)
  static Future<List<PendingCoffeeMachineReport>> getPendingReports() async {
    Logger.debug('Загрузка pending отчётов кофемашин...');
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}/api/coffee-machine/pending');
      final response = await http.get(uri, headers: ApiConstants.headersWithApiKey).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => PendingCoffeeMachineReport.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        Logger.error('Ошибка загрузки pending отчётов: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка загрузки pending отчётов', e);
      return [];
    }
  }

  /// Получить failed отчёты (не сданные)
  static Future<List<PendingCoffeeMachineReport>> getFailedReports() async {
    Logger.debug('Загрузка failed отчётов кофемашин...');
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}/api/coffee-machine/failed');
      final response = await http.get(uri, headers: ApiConstants.headersWithApiKey).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => PendingCoffeeMachineReport.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        Logger.error('Ошибка загрузки failed отчётов: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка загрузки failed отчётов', e);
      return [];
    }
  }

  /// Получить количество неподтверждённых отчётов
  static Future<int> getUnconfirmedCount() async {
    try {
      final reports = await getReports(status: 'pending');
      return reports.length;
    } catch (e) {
      Logger.error('Ошибка получения количества неподтверждённых', e);
      return 0;
    }
  }
}
