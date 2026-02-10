import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Сервис для управления сетью магазинов (мультитенантность)
/// Доступен только для developer
class NetworkManagementService {
  /// Получить полную конфигурацию shop-managers
  static Future<Map<String, dynamic>?> getShopManagersConfig(String adminPhone) async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/shop-managers?phone=${Uri.encodeQueryComponent(adminPhone)}',
        timeout: ApiConstants.defaultTimeout,
      );

      if (result == null || result['success'] != true) {
        Logger.debug('⚠️ Не удалось получить конфигурацию shop-managers');
        return null;
      }

      return result['data'] as Map<String, dynamic>?;
    } catch (e) {
      Logger.debug('❌ Ошибка получения конфигурации: $e');
      return null;
    }
  }

  // ==================== DEVELOPERS ====================

  /// Получить список разработчиков
  static Future<List<String>> getDevelopers(String adminPhone) async {
    final config = await getShopManagersConfig(adminPhone);
    if (config == null) return [];
    return (config['developers'] as List?)?.map((e) => e.toString()).toList() ?? [];
  }

  /// Добавить разработчика
  static Future<bool> addDeveloper(String adminPhone, String developerPhone) async {
    try {
      final normalizedPhone = developerPhone.replaceAll(RegExp(r'[\s\+]'), '');

      final result = await BaseHttpService.postRaw(
        endpoint: '/api/shop-managers/developers',
        body: {
          'adminPhone': adminPhone,
          'developerPhone': normalizedPhone,
        },
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        Logger.debug('✅ Разработчик добавлен: ${Logger.maskPhone(normalizedPhone)}');
        return true;
      }

      Logger.debug('⚠️ Не удалось добавить разработчика');
      return false;
    } catch (e) {
      Logger.debug('❌ Ошибка добавления разработчика: $e');
      return false;
    }
  }

  /// Удалить разработчика
  static Future<bool> removeDeveloper(String adminPhone, String developerPhone) async {
    try {
      final normalizedPhone = developerPhone.replaceAll(RegExp(r'[\s\+]'), '');

      final result = await BaseHttpService.deleteRaw(
        endpoint: '/api/shop-managers/developers/$normalizedPhone?adminPhone=${Uri.encodeQueryComponent(adminPhone)}',
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        Logger.debug('✅ Разработчик удалён: ${Logger.maskPhone(normalizedPhone)}');
        return true;
      }

      Logger.debug('⚠️ Не удалось удалить разработчика');
      return false;
    } catch (e) {
      Logger.debug('❌ Ошибка удаления разработчика: $e');
      return false;
    }
  }

  // ==================== MANAGERS (Управляющие) ====================

  /// Получить список управляющих
  static Future<List<Map<String, dynamic>>> getManagers(String adminPhone) async {
    final config = await getShopManagersConfig(adminPhone);
    if (config == null) return [];
    return (config['managers'] as List?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList() ?? [];
  }

  /// Добавить/обновить управляющего
  static Future<bool> saveManager(String adminPhone, Map<String, dynamic> manager) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '/api/shop-managers/managers',
        body: {
          'adminPhone': adminPhone,
          'manager': manager,
        },
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        Logger.debug('✅ Управляющий сохранён: ${Logger.maskPhone(manager['phone']?.toString())}');
        return true;
      }

      Logger.debug('⚠️ Не удалось сохранить управляющего');
      return false;
    } catch (e) {
      Logger.debug('❌ Ошибка сохранения управляющего: $e');
      return false;
    }
  }

  /// Удалить управляющего
  static Future<bool> removeManager(String adminPhone, String managerPhone) async {
    try {
      final normalizedPhone = managerPhone.replaceAll(RegExp(r'[\s\+]'), '');

      final result = await BaseHttpService.deleteRaw(
        endpoint: '/api/shop-managers/managers/$normalizedPhone?adminPhone=${Uri.encodeQueryComponent(adminPhone)}',
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        Logger.debug('✅ Управляющий удалён: ${Logger.maskPhone(normalizedPhone)}');
        return true;
      }

      Logger.debug('⚠️ Не удалось удалить управляющего');
      return false;
    } catch (e) {
      Logger.debug('❌ Ошибка удаления управляющего: $e');
      return false;
    }
  }

  /// Обновить магазины управляющего
  static Future<bool> updateManagerShops(String adminPhone, String managerPhone, List<String> shopIds) async {
    try {
      final normalizedPhone = managerPhone.replaceAll(RegExp(r'[\s\+]'), '');

      final result = await BaseHttpService.putRaw(
        endpoint: '/api/shop-managers/managers/$normalizedPhone/shops',
        body: {
          'adminPhone': adminPhone,
          'shopIds': shopIds,
        },
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        Logger.debug('✅ Магазины управляющего обновлены');
        return true;
      }

      Logger.debug('⚠️ Не удалось обновить магазины');
      return false;
    } catch (e) {
      Logger.debug('❌ Ошибка обновления магазинов: $e');
      return false;
    }
  }

  /// Обновить сотрудников управляющего
  static Future<bool> updateManagerEmployees(String adminPhone, String managerPhone, List<String> employeePhones) async {
    try {
      final normalizedPhone = managerPhone.replaceAll(RegExp(r'[\s\+]'), '');

      final result = await BaseHttpService.putRaw(
        endpoint: '/api/shop-managers/managers/$normalizedPhone/employees',
        body: {
          'adminPhone': adminPhone,
          'employeePhones': employeePhones,
        },
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        Logger.debug('✅ Сотрудники управляющего обновлены');
        return true;
      }

      Logger.debug('⚠️ Не удалось обновить сотрудников');
      return false;
    } catch (e) {
      Logger.debug('❌ Ошибка обновления сотрудников: $e');
      return false;
    }
  }

  // ==================== STORE MANAGERS (Заведующие) ====================

  /// Получить список заведующих
  static Future<List<Map<String, dynamic>>> getStoreManagers(String adminPhone) async {
    final config = await getShopManagersConfig(adminPhone);
    if (config == null) return [];
    return (config['storeManagers'] as List?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList() ?? [];
  }

  /// Добавить/обновить заведующую
  static Future<bool> saveStoreManager(String adminPhone, Map<String, dynamic> storeManager) async {
    try {
      final result = await BaseHttpService.postRaw(
        endpoint: '/api/shop-managers/store-managers',
        body: {
          'adminPhone': adminPhone,
          'storeManager': storeManager,
        },
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        Logger.debug('✅ Заведующая сохранена: ${Logger.maskPhone(storeManager['phone']?.toString())}');
        return true;
      }

      Logger.debug('⚠️ Не удалось сохранить заведующую');
      return false;
    } catch (e) {
      Logger.debug('❌ Ошибка сохранения заведующей: $e');
      return false;
    }
  }

  /// Удалить заведующую
  static Future<bool> removeStoreManager(String adminPhone, String storeManagerPhone) async {
    try {
      final normalizedPhone = storeManagerPhone.replaceAll(RegExp(r'[\s\+]'), '');

      final result = await BaseHttpService.deleteRaw(
        endpoint: '/api/shop-managers/store-managers/$normalizedPhone?adminPhone=${Uri.encodeQueryComponent(adminPhone)}',
        timeout: ApiConstants.defaultTimeout,
      );

      if (result != null && result['success'] == true) {
        Logger.debug('✅ Заведующая удалена: ${Logger.maskPhone(normalizedPhone)}');
        return true;
      }

      Logger.debug('⚠️ Не удалось удалить заведующую');
      return false;
    } catch (e) {
      Logger.debug('❌ Ошибка удаления заведующей: $e');
      return false;
    }
  }
}
