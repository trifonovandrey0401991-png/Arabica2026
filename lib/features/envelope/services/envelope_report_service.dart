import '../models/envelope_report_model.dart';
import '../models/pending_envelope_report_model.dart';
import '../../../core/services/base_report_service.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EnvelopeReportService {
  static const String baseEndpoint = ApiConstants.envelopeReportsEndpoint;

  static final _base = BaseReportService<EnvelopeReport>(
    endpoint: baseEndpoint,
    fromJson: (json) => EnvelopeReport.fromJson(json),
    getShopAddress: (r) => r.shopAddress,
    reportType: 'envelope',
  );

  /// Получить все отчеты конвертов
  static Future<List<EnvelopeReport>> getReports({
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

  /// Получить отчеты конвертов с фильтрацией по мультитенантности
  ///
  /// Developer видит все, Admin видит только свои магазины
  static Future<List<EnvelopeReport>> getReportsForCurrentUser({
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

  /// Получить отчет по ID
  static Future<EnvelopeReport?> getReport(String id) => _base.getReport(id);

  /// Создать новый отчет конверта
  static Future<EnvelopeReport?> createReport(EnvelopeReport report) async {
    Logger.debug('Создание отчета конверта: ${report.employeeName}');
    return await BaseHttpService.post<EnvelopeReport>(
      endpoint: baseEndpoint,
      body: report.toJson(),
      fromJson: (json) => EnvelopeReport.fromJson(json),
      itemKey: 'report',
    );
  }

  /// Обновить отчет (подтверждение, рейтинг)
  static Future<EnvelopeReport?> updateReport(EnvelopeReport report) async {
    Logger.debug('Обновление отчета конверта: ${report.id}');
    return await BaseHttpService.put<EnvelopeReport>(
      endpoint: '$baseEndpoint/${report.id}',
      body: report.toJson(),
      fromJson: (json) => EnvelopeReport.fromJson(json),
      itemKey: 'report',
    );
  }

  /// Удалить отчет
  static Future<bool> deleteReport(String id) => _base.deleteReport(id);

  /// Получить просроченные отчеты (более 24 часов без подтверждения)
  static Future<List<EnvelopeReport>> getExpiredReports() => _base.getExpiredReports();

  /// Подтвердить отчет с оценкой
  static Future<EnvelopeReport?> confirmReport(String id, String adminName, int rating) =>
    _base.confirmViaEndpoint(id, adminName, rating);

  /// Подтвердить отчет конверта с push уведомлением сотруднику
  static Future<EnvelopeReport?> confirmReportWithPush({
    required String id,
    required String adminName,
    required int rating,
    required String employeePhone,
    String? reportDate,
  }) async {
    final report = await confirmReport(id, adminName, rating);
    if (report != null) {
      Logger.debug('Конверт подтверждён, отправка push сотруднику');
      await _base.sendStatusPush(
        employeePhone: employeePhone,
        status: 'confirmed',
        reportDate: reportDate,
        rating: rating,
      );
    }
    return report;
  }

  /// Отклонить отчет конверта с push уведомлением сотруднику
  static Future<bool> rejectReportWithPush({
    required String id,
    required String adminName,
    required String employeePhone,
    String? comment,
    String? reportDate,
  }) async {
    final result = await _base.rejectViaEndpoint(id, adminName, comment);
    if (result != null) {
      Logger.debug('Конверт отклонён, отправка push сотруднику');
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

  /// Получить pending отчеты (ожидающие сдачи)
  static Future<List<PendingEnvelopeReport>> getPendingReports() async {
    Logger.debug('Загрузка pending отчетов...');
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}/api/envelope-pending');
      final response = await http.get(uri, headers: ApiConstants.headersWithApiKey).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => PendingEnvelopeReport.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        Logger.error('Ошибка загрузки pending отчетов: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка загрузки pending отчетов', e);
      return [];
    }
  }

  /// Получить pending отчеты с фильтрацией по мультитенантности
  static Future<List<PendingEnvelopeReport>> getPendingReportsForCurrentUser() async {
    final reports = await getPendingReports();
    return await MultitenancyFilterService.filterByShopAddress(
      reports,
      (r) => r.shopAddress,
    );
  }

  /// Получить failed отчеты (не сданные)
  static Future<List<PendingEnvelopeReport>> getFailedReports() async {
    Logger.debug('Загрузка failed отчетов...');
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}/api/envelope-failed');
      final response = await http.get(uri, headers: ApiConstants.headersWithApiKey).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => PendingEnvelopeReport.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        Logger.error('Ошибка загрузки failed отчетов: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка загрузки failed отчетов', e);
      return [];
    }
  }

  /// Получить failed отчеты с фильтрацией по мультитенантности
  static Future<List<PendingEnvelopeReport>> getFailedReportsForCurrentUser() async {
    final reports = await getFailedReports();
    return await MultitenancyFilterService.filterByShopAddress(
      reports,
      (r) => r.shopAddress,
    );
  }
}
