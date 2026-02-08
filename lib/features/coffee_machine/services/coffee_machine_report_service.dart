import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import '../../../core/services/employee_push_service.dart';
import '../models/coffee_machine_report_model.dart';
import '../models/pending_coffee_machine_report_model.dart';

/// Сервис для работы с отчётами по счётчикам кофемашин
class CoffeeMachineReportService {
  static const String baseEndpoint = '/api/coffee-machine/reports';

  /// Получить все отчёты
  static Future<List<CoffeeMachineReport>> getReports({
    String? shopAddress,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    Logger.debug('Загрузка отчётов кофемашин...');

    final queryParams = <String, String>{};
    if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
    if (status != null) queryParams['status'] = status;
    if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String();
    if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();

    return await BaseHttpService.getList<CoffeeMachineReport>(
      endpoint: baseEndpoint,
      fromJson: (json) => CoffeeMachineReport.fromJson(json),
      listKey: 'reports',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
  }

  /// Получить отчёты с фильтрацией по мультитенантности
  static Future<List<CoffeeMachineReport>> getReportsForCurrentUser({
    String? shopAddress,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final reports = await getReports(
      shopAddress: shopAddress,
      status: status,
      fromDate: fromDate,
      toDate: toDate,
    );

    return await MultitenancyFilterService.filterByShopAddress(
      reports,
      (report) => report.shopAddress,
    );
  }

  /// Получить отчёт по ID
  static Future<CoffeeMachineReport?> getReport(String id) async {
    Logger.debug('Загрузка отчёта кофемашины: $id');
    return await BaseHttpService.get<CoffeeMachineReport>(
      endpoint: '$baseEndpoint/$id',
      fromJson: (json) => CoffeeMachineReport.fromJson(json),
      itemKey: 'report',
    );
  }

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
  static Future<bool> deleteReport(String id) async {
    Logger.debug('Удаление отчёта кофемашины: $id');
    return await BaseHttpService.delete(endpoint: '$baseEndpoint/$id');
  }

  /// Подтвердить отчёт с оценкой
  static Future<CoffeeMachineReport?> confirmReport(String id, String adminName, int rating) async {
    Logger.debug('Подтверждение отчёта: $id, оценка: $rating');
    return await BaseHttpService.put<CoffeeMachineReport>(
      endpoint: '$baseEndpoint/$id/confirm',
      body: {
        'confirmedByAdmin': adminName,
        'rating': rating,
      },
      fromJson: (json) => CoffeeMachineReport.fromJson(json),
      itemKey: 'report',
    );
  }

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
      await EmployeePushService.sendReportStatusPush(
        employeePhone: employeePhone,
        reportType: 'coffee_machine',
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
    Logger.debug('Отклонение отчёта кофемашины: $id');

    final result = await BaseHttpService.put<CoffeeMachineReport>(
      endpoint: '$baseEndpoint/$id/reject',
      body: {
        'rejectedByAdmin': adminName,
        'rejectReason': comment,
      },
      fromJson: (json) => CoffeeMachineReport.fromJson(json),
      itemKey: 'report',
    );

    if (result != null) {
      Logger.debug('Счётчик отклонён, отправка push сотруднику');
      await EmployeePushService.sendReportStatusPush(
        employeePhone: employeePhone,
        reportType: 'coffee_machine',
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
