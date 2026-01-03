import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/pending_recount_report_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class PendingRecountService {
  static const String baseEndpoint = '/api/pending-recount-reports';

  /// Получить список непройденных пересчётов за сегодня
  static Future<List<PendingRecountReport>> getPendingReports() async {
    try {
      Logger.debug('📥 Загрузка непройденных пересчётов...');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final reportsJson = result['reports'] as List<dynamic>;
          final reports = reportsJson
              .map((json) => PendingRecountReport.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено непройденных пересчётов: ${reports.length}');
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
      Logger.error('❌ Ошибка загрузки непройденных пересчётов', e);
      return [];
    }
  }

  /// Сгенерировать пересчёты на сегодня (ручной вызов)
  static Future<bool> generateDailyReports() async {
    try {
      Logger.debug('📤 Генерация пересчётов на сегодня...');

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/generate'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Пересчёты сгенерированы');
          return true;
        }
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка генерации пересчётов', e);
      return false;
    }
  }
}
