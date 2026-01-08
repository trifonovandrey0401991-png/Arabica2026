import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/envelope_report_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class EnvelopeReportService {
  static const String baseEndpoint = '/api/envelope-reports';

  /// Получить все отчеты конвертов
  static Future<List<EnvelopeReport>> getReports({
    String? shopAddress,
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      Logger.debug('Загрузка отчетов конвертов...');

      final queryParams = <String, String>{};
      if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
      if (status != null) queryParams['status'] = status;
      if (fromDate != null) queryParams['fromDate'] = fromDate.toIso8601String();
      if (toDate != null) queryParams['toDate'] = toDate.toIso8601String();

      final uri = Uri.parse('${ApiConstants.serverUrl}$baseEndpoint')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final reportsJson = result['reports'] as List<dynamic>;
          final reports = reportsJson
              .map((json) => EnvelopeReport.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('Загружено отчетов конвертов: ${reports.length}');
          return reports;
        } else {
          Logger.error('Ошибка загрузки отчетов: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка загрузки отчетов конвертов', e);
      return [];
    }
  }

  /// Получить отчет по ID
  static Future<EnvelopeReport?> getReport(String id) async {
    try {
      Logger.debug('Загрузка отчета конверта: $id');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$id'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('Отчет конверта загружен');
          return EnvelopeReport.fromJson(result['report']);
        } else {
          Logger.error('Ошибка загрузки отчета: ${result['error']}');
          return null;
        }
      } else {
        Logger.error('Ошибка API: statusCode=${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('Ошибка загрузки отчета конверта', e);
      return null;
    }
  }

  /// Создать новый отчет конверта
  static Future<EnvelopeReport?> createReport(EnvelopeReport report) async {
    try {
      Logger.debug('Создание отчета конверта: ${report.employeeName}');

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(report.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('Отчет конверта создан');
          return EnvelopeReport.fromJson(result['report']);
        } else {
          Logger.error('Ошибка создания отчета: ${result['error']}');
          return null;
        }
      } else {
        Logger.error('Ошибка API: statusCode=${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('Ошибка создания отчета конверта', e);
      return null;
    }
  }

  /// Обновить отчет (подтверждение, рейтинг)
  static Future<EnvelopeReport?> updateReport(EnvelopeReport report) async {
    try {
      Logger.debug('Обновление отчета конверта: ${report.id}');

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/${report.id}'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(report.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('Отчет конверта обновлен');
          return EnvelopeReport.fromJson(result['report']);
        } else {
          Logger.error('Ошибка обновления отчета: ${result['error']}');
          return null;
        }
      } else {
        Logger.error('Ошибка API: statusCode=${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('Ошибка обновления отчета конверта', e);
      return null;
    }
  }

  /// Удалить отчет
  static Future<bool> deleteReport(String id) async {
    try {
      Logger.debug('Удаление отчета конверта: $id');

      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$id'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('Отчет конверта удален');
          return true;
        } else {
          Logger.error('Ошибка удаления отчета: ${result['error']}');
          return false;
        }
      } else {
        Logger.error('Ошибка API: statusCode=${response.statusCode}');
        return false;
      }
    } catch (e) {
      Logger.error('Ошибка удаления отчета конверта', e);
      return false;
    }
  }

  /// Получить просроченные отчеты (более 24 часов без подтверждения)
  static Future<List<EnvelopeReport>> getExpiredReports() async {
    try {
      Logger.debug('Загрузка просроченных отчетов конвертов...');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/expired'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final reportsJson = result['reports'] as List<dynamic>;
          final reports = reportsJson
              .map((json) => EnvelopeReport.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('Просроченных отчетов: ${reports.length}');
          return reports;
        } else {
          Logger.error('Ошибка загрузки просроченных: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка загрузки просроченных отчетов', e);
      return [];
    }
  }

  /// Подтвердить отчет с оценкой
  static Future<EnvelopeReport?> confirmReport(String id, String adminName, int rating) async {
    try {
      Logger.debug('Подтверждение отчета: $id, оценка: $rating');

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$id/confirm'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'confirmedByAdmin': adminName,
          'rating': rating,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('Отчет подтвержден');
          return EnvelopeReport.fromJson(result['report']);
        } else {
          Logger.error('Ошибка подтверждения: ${result['error']}');
          return null;
        }
      } else {
        Logger.error('Ошибка API: statusCode=${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('Ошибка подтверждения отчета', e);
      return null;
    }
  }
}
