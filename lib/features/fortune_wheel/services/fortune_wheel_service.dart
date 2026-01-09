import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../models/fortune_wheel_model.dart';

/// Сервис для работы с Колесом Удачи
class FortuneWheelService {
  static const String _baseUrl = '${ApiConstants.serverUrl}/api/fortune-wheel';

  /// Получить настройки секторов колеса
  static Future<FortuneWheelSettings?> getSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/settings'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return FortuneWheelSettings(
            sectors: (result['sectors'] as List?)
                ?.map((e) => FortuneWheelSector.fromJson(e))
                .toList() ?? [],
          );
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка получения настроек колеса: $e');
      return null;
    }
  }

  /// Обновить настройки секторов
  static Future<bool> updateSettings(List<FortuneWheelSector> sectors) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/settings'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'sectors': sectors.map((s) => s.toJson()).toList(),
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Ошибка обновления настроек колеса: $e');
      return false;
    }
  }

  /// Получить доступные прокрутки сотрудника
  static Future<EmployeeWheelSpins> getAvailableSpins(String employeeId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/spins/$employeeId'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return EmployeeWheelSpins.fromJson(result);
        }
      }
      return EmployeeWheelSpins(availableSpins: 0);
    } catch (e) {
      print('❌ Ошибка получения прокруток: $e');
      return EmployeeWheelSpins(availableSpins: 0);
    }
  }

  /// Прокрутить колесо
  static Future<WheelSpinResult?> spin({
    required String employeeId,
    required String employeeName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/spin'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'employeeId': employeeId,
          'employeeName': employeeName,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return WheelSpinResult.fromJson(result);
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка прокрутки колеса: $e');
      return null;
    }
  }

  /// Получить историю прокруток
  static Future<List<WheelSpinRecord>> getHistory({String? month}) async {
    try {
      final url = month != null
          ? '$_baseUrl/history?month=$month'
          : '$_baseUrl/history';

      final response = await http.get(
        Uri.parse(url),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return (result['records'] as List?)
              ?.map((e) => WheelSpinRecord.fromJson(e))
              .toList() ?? [];
        }
      }
      return [];
    } catch (e) {
      print('❌ Ошибка получения истории: $e');
      return [];
    }
  }

  /// Отметить приз как обработанный
  static Future<bool> markProcessed({
    required String recordId,
    required String adminName,
    String? month,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/history/$recordId/process'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'adminName': adminName,
          if (month != null) 'month': month,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Ошибка обработки приза: $e');
      return false;
    }
  }
}
