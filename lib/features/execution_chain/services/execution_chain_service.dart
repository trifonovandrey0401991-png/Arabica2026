import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/execution_chain_model.dart';

class ExecutionChainService {
  static const String _endpoint = ApiConstants.executionChainEndpoint;

  /// Получить конфиг цепочки
  static Future<ExecutionChainConfig?> getConfig() async {
    try {
      Logger.debug('📥 GET $_endpoint/config');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/config'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return ExecutionChainConfig.fromJson(result);
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки конфига цепочки', e);
    }
    return null;
  }

  /// Сохранить конфиг цепочки
  static Future<bool> saveConfig({
    required bool enabled,
    required List<ExecutionChainStep> steps,
  }) async {
    try {
      Logger.debug('📤 PUT $_endpoint/config');

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/config'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'enabled': enabled,
          'steps': steps.map((s) => s.toJson()).toList(),
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
    } catch (e) {
      Logger.error('Ошибка сохранения конфига цепочки', e);
    }
    return false;
  }

  /// Получить статус выполнения цепочки для сотрудника
  static Future<ExecutionChainStatus?> getStatus({
    required String employeeName,
    required String shopAddress,
  }) async {
    try {
      Logger.debug('📥 GET $_endpoint/status (employee=$employeeName)');

      final uri = Uri.parse('${ApiConstants.serverUrl}$_endpoint/status')
          .replace(queryParameters: {
        'employeeName': employeeName,
        'shopAddress': shopAddress,
      });

      final response = await http.get(
        uri,
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      Logger.debug('📥 Chain status response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final status = ExecutionChainStatus.fromJson(result);
          Logger.debug('📥 Chain: enabled=${status.enabled}, steps=${status.steps.length}');
          return status;
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки статуса цепочки', e);
    }
    return null;
  }
}
