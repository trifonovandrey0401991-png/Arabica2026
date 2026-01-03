import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/pending_shift_report_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class PendingShiftService {
  static const String baseEndpoint = '/api/pending-shift-reports';

  /// Получить список непройденных пересменок за сегодня
  static Future<List<PendingShiftReport>> getPendingReports() async {
    try {
      Logger.debug('📥 Загрузка непройденных пересменок...');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final reportsJson = result['reports'] as List<dynamic>;
          final reports = reportsJson
              .map((json) => PendingShiftReport.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено непройденных пересменок: ${reports.length}');
          return reports;
        } else {
          Logger.error('❌ Ошибка загрузки: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки непройденных пересменок', e);
      return [];
    }
  }

  /// Сгенерировать пересменки на сегодня (ручной вызов)
  static Future<bool> generateDailyReports() async {
    try {
      Logger.debug('📤 Генерация пересменок на сегодня...');

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/generate'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Пересменки сгенерированы');
          return true;
        }
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка генерации пересменок', e);
      return false;
    }
  }
}
