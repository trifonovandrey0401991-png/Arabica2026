import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/fortune_wheel_model.dart';

/// Сервис для работы с Колесом Удачи.
///
/// Колесо - награда для топ-3 сотрудников по рейтингу.
/// 15 секторов с настраиваемыми призами и вероятностями.
///
/// Основные операции:
/// - [getSettings] / [updateSettings] - настройки секторов (админ)
/// - [getAvailableSpins] - доступные прокрутки сотрудника
/// - [spinWheel] - прокрутить колесо
/// - [getSpinHistory] - история прокруток
/// - [markPrizeProcessed] - отметить приз выданным
///
/// Связанные сервисы:
/// - [RatingService] - определяет кто получает прокрутки
class FortuneWheelService {
  static const String _baseEndpoint = ApiConstants.fortuneWheelEndpoint;

  /// Получить настройки секторов колеса
  static Future<FortuneWheelSettings?> getSettings() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/settings',
      );

      if (result != null) {
        return FortuneWheelSettings(
          sectors: (result['sectors'] as List?)
              ?.map((e) => FortuneWheelSector.fromJson(e))
              .toList() ?? [],
        );
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка получения настроек колеса', e);
      return null;
    }
  }

  /// Обновить настройки секторов
  static Future<bool> updateSettings(List<FortuneWheelSector> sectors) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '$_baseEndpoint/settings',
        body: {
          'sectors': sectors.map((s) => s.toJson()).toList(),
        },
      );
      return result != null;
    } catch (e) {
      Logger.error('Ошибка обновления настроек колеса', e);
      return false;
    }
  }

  /// Получить доступные прокрутки сотрудника
  static Future<EmployeeWheelSpins> getAvailableSpins(String employeeId) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/spins/$employeeId',
      );

      if (result != null) {
        return EmployeeWheelSpins.fromJson(result);
      }
      return EmployeeWheelSpins(availableSpins: 0);
    } catch (e) {
      Logger.error('Ошибка получения прокруток', e);
      return EmployeeWheelSpins(availableSpins: 0);
    }
  }

  /// Прокрутить колесо
  static Future<WheelSpinResult?> spin({
    required String employeeId,
    required String employeeName,
  }) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '$_baseEndpoint/spin',
        body: {
          'employeeId': employeeId,
          'employeeName': employeeName,
        },
      );

      if (result != null) {
        return WheelSpinResult.fromJson(result);
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка прокрутки колеса', e);
      return null;
    }
  }

  /// Получить историю прокруток
  static Future<List<WheelSpinRecord>> getHistory({String? month}) async {
    try {
      final queryParams = <String, String>{};
      if (month != null) queryParams['month'] = month;

      return await BaseHttpService.getList<WheelSpinRecord>(
        endpoint: '$_baseEndpoint/history',
        fromJson: (json) => WheelSpinRecord.fromJson(json),
        listKey: 'records',
        queryParams: queryParams.isNotEmpty ? queryParams : null,
      );
    } catch (e) {
      Logger.error('Ошибка получения истории', e);
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
      final body = <String, dynamic>{
        'adminName': adminName,
      };
      if (month != null) body['month'] = month;

      return await BaseHttpService.simplePatch(
        endpoint: '$_baseEndpoint/history/$recordId/process',
        body: body,
      );
    } catch (e) {
      Logger.error('Ошибка обработки приза', e);
      return false;
    }
  }
}
