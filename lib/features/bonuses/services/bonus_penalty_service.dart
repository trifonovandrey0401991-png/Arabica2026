import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/bonus_penalty_model.dart';

class BonusPenaltyService {
  static const String baseEndpoint = '/api/bonus-penalties';

  /// Получить все премии/штрафы за месяц
  static Future<List<BonusPenalty>> getRecords({String? month, String? employeeId}) async {
    try {
      final queryParams = <String, String>{};
      if (month != null) queryParams['month'] = month;
      if (employeeId != null) queryParams['employeeId'] = employeeId;

      final uri = Uri.parse('${ApiConstants.serverUrl}$baseEndpoint')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      Logger.debug('GET $uri');

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final records = (data['records'] as List<dynamic>? ?? [])
              .map((r) => BonusPenalty.fromJson(r))
              .toList();
          Logger.debug('Получено ${records.length} записей');
          return records;
        }
      }
      Logger.error('Ошибка получения записей: ${response.statusCode}');
      return [];
    } catch (e) {
      Logger.error('Ошибка получения премий/штрафов', e);
      return [];
    }
  }

  /// Создать премию или штраф
  static Future<BonusPenalty?> create({
    required String employeeId,
    required String employeeName,
    required String type,
    required double amount,
    required String comment,
    required String adminName,
  }) async {
    try {
      Logger.debug('POST $baseEndpoint: $type $amount для $employeeName');

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'employeeId': employeeId,
          'employeeName': employeeName,
          'type': type,
          'amount': amount,
          'comment': comment,
          'adminName': adminName,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['record'] != null) {
          Logger.debug('Создана запись: ${data['record']['id']}');
          return BonusPenalty.fromJson(data['record']);
        }
      }
      Logger.error('Ошибка создания записи: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Ошибка создания премии/штрафа', e);
      return null;
    }
  }

  /// Удалить премию/штраф
  static Future<bool> delete(String id, {String? month}) async {
    try {
      final queryParams = <String, String>{};
      if (month != null) queryParams['month'] = month;

      final uri = Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$id')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      Logger.debug('DELETE $uri');

      final response = await http.delete(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('Запись удалена: $id');
          return true;
        }
      }
      Logger.error('Ошибка удаления записи: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('Ошибка удаления премии/штрафа', e);
      return false;
    }
  }

  /// Получить сводку для сотрудника (текущий и прошлый месяц)
  static Future<BonusPenaltySummary> getSummary(String employeeId) async {
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/summary/$employeeId');

      Logger.debug('GET $uri');

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('Получена сводка для $employeeId');
          return BonusPenaltySummary.fromJson(data);
        }
      }
      Logger.error('Ошибка получения сводки: ${response.statusCode}');
      return BonusPenaltySummary.empty();
    } catch (e) {
      Logger.error('Ошибка получения сводки', e);
      return BonusPenaltySummary.empty();
    }
  }
}
