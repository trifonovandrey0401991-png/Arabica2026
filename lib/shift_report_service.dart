import 'package:http/http.dart' as http;
import 'dart:convert';
import 'shift_report_model.dart';
import 'utils/logger.dart';

class ShiftReportService {
  static const String serverUrl = 'https://arabica26.ru';

  /// Сохранить отчет пересменки на сервере
  static Future<bool> saveReport(ShiftReport report) async {
    try {
      Logger.debug('📤 Сохранение отчета пересменки на сервере: ${report.id}');
      
      final url = '$serverUrl/api/shift-reports';
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(report.toJson()),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Отчет пересменки успешно сохранен на сервере');
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
      Logger.error('❌ Ошибка сохранения отчета пересменки', e);
      return false;
    }
  }

  /// Получить отчеты пересменки с сервера
  static Future<List<ShiftReport>> getReports({
    String? employeeName,
    String? shopAddress,
    DateTime? date,
  }) async {
    try {
      Logger.debug('📥 Загрузка отчетов пересменки с сервера...');
      
      final queryParams = <String, String>{};
      if (employeeName != null) queryParams['employeeName'] = employeeName;
      if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
      if (date != null) {
        queryParams['date'] = date.toIso8601String().split('T')[0];
      }
      
      final uri = Uri.parse('$serverUrl/api/shift-reports').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final reportsJson = result['reports'] as List<dynamic>;
          final reports = reportsJson
              .map((json) => ShiftReport.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено отчетов пересменки: ${reports.length}');
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
      Logger.error('❌ Ошибка загрузки отчетов пересменки', e);
      return [];
    }
  }
}



