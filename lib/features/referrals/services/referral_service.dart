import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/referral_stats_model.dart';

/// Сервис для работы с реферальной системой.
///
/// Каждый сотрудник имеет уникальный код (1-1000).
/// Клиент вводит код при регистрации - сотрудник получает баллы.
///
/// Основные операции:
/// - [getNextReferralCode] - получить свободный код для сотрудника
/// - [validateReferralCode] - проверить код при регистрации клиента
/// - [registerReferral] - зарегистрировать приглашение
/// - [getReferralStats] - статистика приглашений сотрудника
/// - [getReferralReport] - отчёт для админа
///
/// Интеграция:
/// - Баллы добавляются к рейтингу сотрудника
/// - Отчёт "Приглашения" в админ-панели
class ReferralService {
  static const String _baseEndpoint = ApiConstants.referralsEndpoint;
  static const String _pointsSettingsEndpoint = '${ApiConstants.pointsSettingsEndpoint}/referrals';

  /// Получить следующий свободный код приглашения
  static Future<int?> getNextReferralCode() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/next-code',
      );
      return result?['nextCode'] as int?;
    } catch (e) {
      Logger.error('Ошибка получения следующего кода', e);
      return null;
    }
  }

  /// Проверить валидность кода приглашения
  static Future<Map<String, dynamic>?> validateReferralCode(int code) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/validate-code/$code',
      );

      if (result != null) {
        return {
          'valid': result['valid'] ?? false,
          'message': result['message'],
          'employee': result['employee'],
        };
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка валидации кода', e);
      return null;
    }
  }

  /// Получить статистику всех сотрудников
  static Future<Map<String, dynamic>?> getAllStats() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/stats',
      );

      if (result != null) {
        final stats = (result['employeeStats'] as List?)
            ?.map((e) => EmployeeReferralStats.fromJson(e))
            .toList() ?? [];

        return {
          'totalClients': result['totalClients'] ?? 0,
          'unassignedCount': result['unassignedCount'] ?? 0,
          'employeeStats': stats,
        };
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка получения статистики', e);
      return null;
    }
  }

  /// Получить статистику одного сотрудника
  static Future<Map<String, dynamic>?> getEmployeeStats(String employeeId) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/stats/$employeeId',
      );

      if (result != null) {
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
      return null;
    } catch (e) {
      Logger.error('Ошибка получения статистики сотрудника', e);
      return null;
    }
  }

  /// Получить список клиентов по коду приглашения
  static Future<List<ReferredClient>> getClientsByCode(int referralCode) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/clients/$referralCode',
      );

      if (result != null) {
        return (result['clients'] as List?)
            ?.map((e) => ReferredClient.fromJson(e))
            .toList() ?? [];
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка получения клиентов', e);
      return [];
    }
  }

  /// Получить количество неучтённых клиентов
  static Future<int> getUnassignedCount() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/unassigned',
      );
      return result?['count'] as int? ?? 0;
    } catch (e) {
      Logger.error('Ошибка получения неучтённых', e);
      return 0;
    }
  }

  /// Получить настройки баллов за приглашения
  static Future<ReferralSettings> getSettings() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: _pointsSettingsEndpoint,
      );

      if (result != null && result['settings'] != null) {
        return ReferralSettings.fromJson(result['settings']);
      }
      return ReferralSettings(pointsPerReferral: 1);
    } catch (e) {
      Logger.error('Ошибка получения настроек', e);
      return ReferralSettings(pointsPerReferral: 1);
    }
  }

  /// Обновить настройки баллов за приглашения
  static Future<bool> updateSettings(ReferralSettings settings) async {
    try {
      return await BaseHttpService.simplePost(
        endpoint: _pointsSettingsEndpoint,
        body: settings.toJson(),
      );
    } catch (e) {
      Logger.error('Ошибка обновления настроек', e);
      return false;
    }
  }

  /// Получить баллы сотрудника за приглашения
  static Future<EmployeeReferralPoints?> getEmployeePoints(String employeeId) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/employee-points/$employeeId',
      );

      if (result != null) {
        return EmployeeReferralPoints.fromJson(result);
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка получения баллов', e);
      return null;
    }
  }

  /// Получить количество непросмотренных приглашений
  static Future<int> getUnviewedCount() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/unviewed-count',
      );
      return result?['count'] as int? ?? 0;
    } catch (e) {
      Logger.error('Ошибка получения непросмотренных приглашений', e);
      return 0;
    }
  }

  /// Получить непросмотренные приглашения по сотрудникам
  static Future<Map<String, int>> getUnviewedByEmployee() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/unviewed-count',
      );
      final byEmployee = result?['byEmployee'] as Map<String, dynamic>? ?? {};
      return byEmployee.map((k, v) => MapEntry(k, v as int));
    } catch (e) {
      Logger.error('Ошибка получения непросмотренных по сотрудникам', e);
      return {};
    }
  }

  /// Отметить приглашения как просмотренные
  static Future<void> markAsViewed() async {
    try {
      await BaseHttpService.simplePost(
        endpoint: '$_baseEndpoint/mark-as-viewed',
        body: {},
      );
    } catch (e) {
      Logger.error('Ошибка отметки как просмотренные', e);
    }
  }
}
