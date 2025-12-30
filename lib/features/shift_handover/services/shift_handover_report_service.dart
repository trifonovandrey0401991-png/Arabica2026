import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/shift_handover_report_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ShiftHandoverReportService {
  static const String baseEndpoint = '/api/shift-handover-reports';

  /// Сохранить отчет сдачи смены на сервере
  static Future<bool> saveReport(ShiftHandoverReport report) async {
    try {
      Logger.debug('📤 Сохранение отчета сдачи смены на сервере: ${report.id}');

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(report.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Отчет сдачи смены успешно сохранен на сервере');
          return true;
        } else {
          Logger.error('❌ Ошибка сохранения отчета: ${result['error']}');
          return false;
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return false;
      }
    } catch (e) {
      Logger.error('❌ Ошибка сохранения отчета сдачи смены', e);
      return false;
    }
  }

  /// Получить отчеты сдачи смены с сервера
  static Future<List<ShiftHandoverReport>> getReports({
    String? employeeName,
    String? shopAddress,
    DateTime? date,
  }) async {
    try {
      Logger.debug('📥 Загрузка отчетов сдачи смены с сервера...');

      final queryParams = <String, String>{};
      if (employeeName != null) queryParams['employeeName'] = employeeName;
      if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
      if (date != null) {
        queryParams['date'] = date.toIso8601String().split('T')[0];
      }

      final uri = Uri.parse('${ApiConstants.serverUrl}$baseEndpoint')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final reportsJson = result['reports'] as List<dynamic>;
          final reports = reportsJson
              .map((json) => ShiftHandoverReport.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено отчетов сдачи смены: ${reports.length}');
          return reports;
        } else {
          Logger.error('❌ Ошибка загрузки отчетов: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки отчетов сдачи смены', e);
      return [];
    }
  }

  /// Получить отчет по ID
  static Future<ShiftHandoverReport?> getReport(String reportId) async {
    try {
      Logger.debug('📥 Загрузка отчета сдачи смены: $reportId');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$reportId'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Отчет сдачи смены загружен');
          return ShiftHandoverReport.fromJson(result['report']);
        } else {
          Logger.error('❌ Ошибка загрузки отчета: ${result['error']}');
          return null;
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки отчета сдачи смены', e);
      return null;
    }
  }

  /// Удалить отчет с сервера
  static Future<bool> deleteReport(String reportId) async {
    try {
      Logger.debug('📤 Удаление отчета сдачи смены: $reportId');

      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$reportId'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Отчет сдачи смены успешно удален');
          return true;
        } else {
          Logger.error('❌ Ошибка удаления отчета: ${result['error']}');
          return false;
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return false;
      }
    } catch (e) {
      Logger.error('❌ Ошибка удаления отчета сдачи смены', e);
      return false;
    }
  }
}
