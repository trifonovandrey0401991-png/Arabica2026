import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../models/referral_stats_model.dart';

/// Сервис для работы с реферальной системой
class ReferralService {
  static const String _baseUrl = '${ApiConstants.serverUrl}/api/referrals';
  static const String _pointsSettingsUrl = '${ApiConstants.serverUrl}/api/points-settings/referrals';

  /// Получить следующий свободный код приглашения
  static Future<int?> getNextReferralCode() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/next-code'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result['nextCode'];
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка получения следующего кода: $e');
      return null;
    }
  }

  /// Проверить валидность кода приглашения
  static Future<Map<String, dynamic>?> validateReferralCode(int code) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/validate-code/$code'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return {
            'valid': result['valid'] ?? false,
            'message': result['message'],
            'employee': result['employee'],
          };
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка валидации кода: $e');
      return null;
    }
  }

  /// Получить статистику всех сотрудников
  static Future<Map<String, dynamic>?> getAllStats() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/stats'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final stats = (result['employeeStats'] as List?)
              ?.map((e) => EmployeeReferralStats.fromJson(e))
              .toList() ?? [];

          return {
            'totalClients': result['totalClients'] ?? 0,
            'unassignedCount': result['unassignedCount'] ?? 0,
            'employeeStats': stats,
          };
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка получения статистики: $e');
      return null;
    }
  }

  /// Получить статистику одного сотрудника
  static Future<Map<String, dynamic>?> getEmployeeStats(String employeeId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/stats/$employeeId'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final clients = (result['stats']?['clients'] as List?)
              ?.map((e) => ReferredClient.fromJson(e))
              .toList() ?? [];

          return {
            'employeeId': result['employeeId'],
            'employeeName': result['employeeName'],
            'referralCode': result['referralCode'],
            'today': result['stats']?['today'] ?? 0,
            'currentMonth': result['stats']?['currentMonth'] ?? 0,
            'previousMonth': result['stats']?['previousMonth'] ?? 0,
            'total': result['stats']?['total'] ?? 0,
            'clients': clients,
          };
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка получения статистики сотрудника: $e');
      return null;
    }
  }

  /// Получить список клиентов по коду приглашения
  static Future<List<ReferredClient>> getClientsByCode(int referralCode) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/clients/$referralCode'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return (result['clients'] as List?)
              ?.map((e) => ReferredClient.fromJson(e))
              .toList() ?? [];
        }
      }
      return [];
    } catch (e) {
      print('❌ Ошибка получения клиентов: $e');
      return [];
    }
  }

  /// Получить количество неучтённых клиентов
  static Future<int> getUnassignedCount() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/unassigned'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result['count'] ?? 0;
        }
      }
      return 0;
    } catch (e) {
      print('❌ Ошибка получения неучтённых: $e');
      return 0;
    }
  }

  /// Получить настройки баллов за приглашения
  static Future<ReferralSettings> getSettings() async {
    try {
      final response = await http.get(
        Uri.parse(_pointsSettingsUrl),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true && result['settings'] != null) {
          return ReferralSettings.fromJson(result['settings']);
        }
      }
      return ReferralSettings(pointsPerReferral: 1);
    } catch (e) {
      print('❌ Ошибка получения настроек: $e');
      return ReferralSettings(pointsPerReferral: 1);
    }
  }

  /// Обновить настройки баллов за приглашения
  static Future<bool> updateSettings(ReferralSettings settings) async {
    try {
      final response = await http.post(
        Uri.parse(_pointsSettingsUrl),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(settings.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Ошибка обновления настроек: $e');
      return false;
    }
  }

  /// Получить баллы сотрудника за приглашения
  static Future<EmployeeReferralPoints?> getEmployeePoints(String employeeId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/employee-points/$employeeId'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return EmployeeReferralPoints.fromJson(result);
        }
      }
      return null;
    } catch (e) {
      print('❌ Ошибка получения баллов: $e');
      return null;
    }
  }
}
