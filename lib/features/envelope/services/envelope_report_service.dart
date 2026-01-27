import '../models/envelope_report_model.dart';
import '../models/pending_envelope_report_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EnvelopeReportService {
  static const String baseEndpoint = ApiConstants.envelopeReportsEndpoint;

  /// Получить все отчеты конвертов
  static Future<List<EnvelopeReport>> getReports({
    String? shopAddress,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    Logger.debug('Загрузка отчетов конвертов...');

    final queryParams = <String, String>{};
    if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
    if (status != null) queryParams['status'] = status;
    if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String();
    if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();

    return await BaseHttpService.getList<EnvelopeReport>(
      endpoint: baseEndpoint,
      fromJson: (json) => EnvelopeReport.fromJson(json),
      listKey: 'reports',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );
  }

  /// Получить отчет по ID
  static Future<EnvelopeReport?> getReport(String id) async {
    Logger.debug('Загрузка отчета конверта: $id');
    return await BaseHttpService.get<EnvelopeReport>(
      endpoint: '$baseEndpoint/$id',
      fromJson: (json) => EnvelopeReport.fromJson(json),
      itemKey: 'report',
    );
  }

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
  static Future<bool> deleteReport(String id) async {
    Logger.debug('Удаление отчета конверта: $id');
    return await BaseHttpService.delete(endpoint: '$baseEndpoint/$id');
  }

  /// Получить просроченные отчеты (более 24 часов без подтверждения)
  static Future<List<EnvelopeReport>> getExpiredReports() async {
    Logger.debug('Загрузка просроченных отчетов конвертов...');
    return await BaseHttpService.getList<EnvelopeReport>(
      endpoint: '$baseEndpoint/expired',
      fromJson: (json) => EnvelopeReport.fromJson(json),
      listKey: 'reports',
    );
  }

  /// Подтвердить отчет с оценкой
  static Future<EnvelopeReport?> confirmReport(String id, String adminName, int rating) async {
    Logger.debug('Подтверждение отчета: $id, оценка: $rating');
    return await BaseHttpService.put<EnvelopeReport>(
      endpoint: '$baseEndpoint/$id/confirm',
      body: {
        'confirmedByAdmin': adminName,
        'rating': rating,
      },
      fromJson: (json) => EnvelopeReport.fromJson(json),
      itemKey: 'report',
    );
  }

  /// Получить pending отчеты (ожидающие сдачи)
  static Future<List<PendingEnvelopeReport>> getPendingReports() async {
    Logger.debug('Загрузка pending отчетов...');
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}/api/envelope-pending');
      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

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

  /// Получить failed отчеты (не сданные)
  static Future<List<PendingEnvelopeReport>> getFailedReports() async {
    Logger.debug('Загрузка failed отчетов...');
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}/api/envelope-failed');
      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

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
}
