import '../../features/employees/services/user_role_service.dart';
import '../../features/employees/models/user_role_model.dart';
import '../../features/shops/services/shop_service.dart';
import '../utils/logger.dart';

/// Сервис фильтрации данных по мультитенантности
///
/// Используется для фильтрации отчётов, сотрудников и других данных
/// в зависимости от роли пользователя и его привязки к магазинам.
class MultitenancyFilterService {
  /// Кэш разрешённых адресов магазинов для текущего пользователя
  static List<String>? _cachedAllowedShopAddresses;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 10);

  /// Очистить кэш (вызывать при смене пользователя или обновлении привязок)
  static void clearCache() {
    _cachedAllowedShopAddresses = null;
    _cacheTime = null;
    Logger.debug('🧹 Кэш мультитенантной фильтрации очищен');
  }

  /// Получить список разрешённых адресов магазинов для текущего пользователя
  ///
  /// Возвращает null если пользователь видит ВСЕ магазины (developer, client, или admin без привязок)
  static Future<List<String>?> getAllowedShopAddresses() async {
    // Проверяем кэш
    if (_cachedAllowedShopAddresses != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedAllowedShopAddresses;
    }

    final roleData = await UserRoleService.loadUserRole();

    if (roleData == null) {
      // Fail-closed: if role cannot be loaded, deny access to all shops.
      // Returning null would grant access to everything (fail-open), which is a security risk.
      Logger.warning('⚠️ Роль не загружена — доступ к магазинам закрыт (fail-closed)');
      return []; // Empty list = sees nothing
    }

    Logger.debug('🔍 Определение разрешённых магазинов для роли: ${roleData.role.name}');

    switch (roleData.role) {
      case UserRole.developer:
        Logger.debug('   Developer - без фильтрации');
        return null; // Видит всё

      case UserRole.client:
        Logger.debug('   Client - без фильтрации отчётов');
        return null; // Клиенты не видят отчёты, но если видят - видят все

      case UserRole.admin:
        if (roleData.managedShopIds.isEmpty) {
          Logger.debug('   Admin без привязанных магазинов - без фильтрации');
          return null; // Видит всё
        }
        // Admin видит только свои магазины
        // managedShopIds может содержать как ID, так и адреса - нужно получить адреса
        final addresses = await _resolveShopAddresses(roleData.managedShopIds);
        Logger.debug('   Admin - разрешены ${addresses.length} магазин(ов)');
        _cachedAllowedShopAddresses = addresses;
        _cacheTime = DateTime.now();
        return addresses;

      case UserRole.manager:
        if (roleData.canSeeAllManagerShops) {
          Logger.debug('   Manager с доступом ко всем магазинам управляющего - без фильтрации');
          return null; // Видит всё (все магазины управляющего)
        }
        if (roleData.primaryShopId != null) {
          final addresses = await _resolveShopAddresses([roleData.primaryShopId!]);
          Logger.debug('   Manager - разрешён 1 магазин');
          _cachedAllowedShopAddresses = addresses;
          _cacheTime = DateTime.now();
          return addresses;
        }
        // Fail-closed: manager without a primaryShopId and without canSeeAllManagerShops
        // should not see everything — deny access until a shop is assigned.
        Logger.warning('   Manager без primaryShopId и без canSeeAllManagerShops — доступ закрыт (fail-closed)');
        return [];

      case UserRole.employee:
        if (roleData.primaryShopId != null) {
          final addresses = await _resolveShopAddresses([roleData.primaryShopId!]);
          Logger.debug('   Employee - разрешён 1 магазин');
          _cachedAllowedShopAddresses = addresses;
          _cacheTime = DateTime.now();
          return addresses;
        }
        // Fail-closed: employee without a primaryShopId should not see all shops.
        Logger.warning('   Employee без primaryShopId — доступ к магазинам закрыт (fail-closed)');
        return [];
    }
  }

  /// Преобразовать список ID/адресов магазинов в список адресов
  ///
  /// managedShopIds может содержать как shop.id, так и shop.address
  /// Эта функция нормализует всё в адреса для фильтрации отчётов
  static Future<List<String>> _resolveShopAddresses(List<String> shopIdsOrAddresses) async {
    final allShops = await ShopService.getShops();
    final addresses = <String>{};

    for (final idOrAddress in shopIdsOrAddresses) {
      // Проверяем, является ли это ID магазина
      final shopById = allShops.where((s) => s.id == idOrAddress).firstOrNull;
      if (shopById != null) {
        addresses.add(shopById.address);
        continue;
      }

      // Проверяем, является ли это адресом магазина
      final shopByAddress = allShops.where((s) => s.address == idOrAddress).firstOrNull;
      if (shopByAddress != null) {
        addresses.add(shopByAddress.address);
        continue;
      }

      // Если не найден - добавляем как есть (может быть адресом)
      addresses.add(idOrAddress);
    }

    return addresses.toList();
  }

  /// Фильтровать список отчётов по shopAddress
  ///
  /// Универсальный метод для фильтрации любых отчётов.
  /// Возвращает отфильтрованный список или оригинал если фильтрация не нужна.
  ///
  /// Пример использования:
  /// ```dart
  /// final filteredReports = await MultitenancyFilterService.filterByShopAddress(
  ///   reports,
  ///   (report) => report.shopAddress,
  /// );
  /// ```
  static Future<List<T>> filterByShopAddress<T>(
    List<T> items,
    String Function(T item) getShopAddress,
  ) async {
    final allowedAddresses = await getAllowedShopAddresses();

    // Если null - пользователь видит всё
    if (allowedAddresses == null) {
      return items;
    }

    // Фильтруем по разрешённым адресам
    final filtered = items.where((item) {
      final address = getShopAddress(item);
      return allowedAddresses.contains(address);
    }).toList();

    Logger.debug('📊 Фильтрация отчётов: ${items.length} → ${filtered.length}');
    return filtered;
  }

  /// Проверить, имеет ли текущий пользователь доступ к магазину по адресу
  static Future<bool> hasAccessToShopAddress(String shopAddress) async {
    final allowedAddresses = await getAllowedShopAddresses();

    // Если null - пользователь видит всё
    if (allowedAddresses == null) {
      return true;
    }

    return allowedAddresses.contains(shopAddress);
  }

  /// Фильтровать список сотрудников по телефону
  ///
  /// Для admin - фильтрует по managedEmployees
  /// Для остальных - возвращает оригинал или только себя
  static Future<List<T>> filterByEmployeePhone<T>(
    List<T> items,
    String Function(T item) getEmployeePhone,
  ) async {
    final roleData = await UserRoleService.loadUserRole();

    if (roleData == null) {
      return items;
    }

    switch (roleData.role) {
      case UserRole.developer:
      case UserRole.client:
        return items; // Видит всех

      case UserRole.admin:
        if (roleData.managedEmployees.isEmpty) {
          return items; // Видит всех
        }
        // Фильтрация по управляемым сотрудникам
        final filtered = items.where((item) {
          final phone = getEmployeePhone(item).replaceAll(RegExp(r'[\s\+]'), '');
          return roleData.managedEmployees.any((managed) =>
            managed.replaceAll(RegExp(r'[\s\+]'), '') == phone
          );
        }).toList();
        Logger.debug('👥 Фильтрация сотрудников: ${items.length} → ${filtered.length}');
        return filtered;

      case UserRole.manager:
      case UserRole.employee:
        // Видит только себя в списках (или всех в зависимости от контекста)
        // Для отчётов - фильтрация по магазину важнее
        return items;
    }
  }
}
