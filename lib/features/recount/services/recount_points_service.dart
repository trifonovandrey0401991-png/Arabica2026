import '../models/recount_points_model.dart';
import '../models/recount_settings_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Сервис для работы с баллами пересчёта
class RecountPointsService {
  static const String _baseEndpoint = ApiConstants.recountPointsEndpoint;
  static const String _settingsEndpoint = ApiConstants.recountSettingsEndpoint;
  static const String _reportsEndpoint = ApiConstants.recountReportsEndpoint;

  /// Получить баллы всех сотрудников
  static Future<List<RecountPoints>> getAllPoints() async {
    try {
      Logger.debug('Загружаем баллы всех сотрудников...');

      return await BaseHttpService.getList<RecountPoints>(
        endpoint: _baseEndpoint,
        fromJson: (json) => RecountPoints.fromJson(json),
        listKey: 'points',
      );
    } catch (e) {
      Logger.error('Ошибка загрузки баллов', e);
      return [];
    }
  }

  /// Получить баллы конкретного сотрудника по телефону
  static Future<RecountPoints?> getPointsByPhone(String phone) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
      Logger.debug('Загружаем баллы сотрудника: $normalizedPhone');

      return await BaseHttpService.get<RecountPoints>(
        endpoint: '$_baseEndpoint/$normalizedPhone',
        fromJson: (json) => RecountPoints.fromJson(json),
        itemKey: 'points',
      );
    } catch (e) {
      Logger.error('Ошибка загрузки баллов сотрудника', e);
      return null;
    }
  }

  /// Обновить баллы сотрудника (ручная установка админом)
  static Future<bool> updatePoints({
    required String phone,
    required double points,
    required String adminName,
    String? employeeName,
  }) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
      Logger.debug('Обновляем баллы сотрудника: $normalizedPhone -> $points');

      final body = <String, dynamic>{
        'points': points,
        'adminName': adminName,
      };
      if (employeeName != null) body['employeeName'] = employeeName;

      final result = await BaseHttpService.postRaw(
        endpoint: '$_baseEndpoint/$normalizedPhone',
        body: body,
      );

      if (result != null) {
        Logger.success('Баллы обновлены');
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка обновления баллов', e);
      return false;
    }
  }

  /// Инициализировать баллы всем сотрудникам (85 по умолчанию)
  static Future<int> initializeAllPoints() async {
    try {
      Logger.debug('Инициализируем баллы для всех сотрудников...');

      final result = await BaseHttpService.postRaw(
        endpoint: '$_baseEndpoint/init',
        body: {},
        timeout: const Duration(seconds: 60),
      );

      if (result != null) {
        final count = result['count'] as int? ?? 0;
        Logger.success('Инициализировано: $count сотрудников');
        return count;
      }
      return 0;
    } catch (e) {
      Logger.error('Ошибка инициализации баллов', e);
      return 0;
    }
  }

  /// Получить общие настройки пересчёта
  static Future<RecountSettings> getSettings() async {
    try {
      Logger.debug('Загружаем настройки пересчёта...');

      final result = await BaseHttpService.get<RecountSettings>(
        endpoint: _settingsEndpoint,
        fromJson: (json) => RecountSettings.fromJson(json),
        itemKey: 'settings',
      );

      return result ?? RecountSettings();
    } catch (e) {
      Logger.error('Ошибка загрузки настроек', e);
      return RecountSettings();
    }
  }

  /// Обновить общие настройки пересчёта
  static Future<bool> updateSettings(RecountSettings settings) async {
    try {
      Logger.debug('Обновляем настройки пересчёта...');

      final result = await BaseHttpService.postRaw(
        endpoint: _settingsEndpoint,
        body: settings.toJson(),
      );

      if (result != null) {
        Logger.success('Настройки обновлены');
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка обновления настроек', e);
      return false;
    }
  }

  /// Верифицировать фото в отчёте (принять/отклонить)
  static Future<bool> verifyPhoto({
    required String reportId,
    required int photoIndex,
    required String status, // 'approved' или 'rejected'
    required String adminName,
    required String employeePhone,
  }) async {
    try {
      Logger.debug('Верификация фото: $reportId, индекс $photoIndex -> $status');

      return await BaseHttpService.simplePatch(
        endpoint: '$_reportsEndpoint/$reportId/verify-photo',
        body: {
          'photoIndex': photoIndex,
          'status': status,
          'adminName': adminName,
          'employeePhone': employeePhone,
        },
      );
    } catch (e) {
      Logger.error('Ошибка верификации фото', e);
      return false;
    }
  }

  /// Добавить баллы сотруднику (после верификации фото)
  static Future<bool> addPointsChange({
    required String phone,
    required double change,
    required String reason,
  }) async {
    try {
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
      Logger.debug('Изменение баллов: $normalizedPhone, ${change > 0 ? '+' : ''}$change');

      // Получаем текущие баллы
      final current = await getPointsByPhone(normalizedPhone);
      if (current == null) {
        Logger.warning('Сотрудник не найден: $normalizedPhone');
        return false;
      }

      // Вычисляем новые баллы (не меньше 0, не больше 100)
      final newPoints = (current.points + change).clamp(0.0, 100.0);

      final result = await BaseHttpService.postRaw(
        endpoint: '$_baseEndpoint/$normalizedPhone',
        body: {
          'points': newPoints,
          'adminName': 'Система',
          'reason': reason,
        },
      );

      if (result != null) {
        Logger.success('Баллы изменены: $newPoints');
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка изменения баллов', e);
      return false;
    }
  }
}
