import '../models/shop_model.dart';
import '../models/shop_settings_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/disk_cache.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/models/user_role_model.dart';

class ShopService {
  // In-memory cache for shops (instant access within session)
  static List<Shop>? _cachedShops;

  /// Получить все магазины (с кэшем: диск → память → сервер)
  static Future<List<Shop>> getShops() async {
    // 1. Memory cache — мгновенно
    if (_cachedShops != null && _cachedShops!.isNotEmpty) {
      Logger.debug('🏪 Магазины из памяти: ${_cachedShops!.length}');
      // Обновляем с сервера в фоне (не блокируем)
      _refreshShopsInBackground();
      return _cachedShops!;
    }

    // 2. Disk cache — быстро, переживает перезапуск
    try {
      final diskData = await DiskCache.read('shops_list');
      if (diskData != null && diskData['shops'] != null) {
        final shops = (diskData['shops'] as List<dynamic>)
            .map((s) => Shop.fromJson(s as Map<String, dynamic>))
            .toList();
        if (shops.isNotEmpty) {
          _cachedShops = shops;
          Logger.debug('🏪 Магазины с диска: ${shops.length}');
          // Обновляем с сервера в фоне
          _refreshShopsInBackground();
          return shops;
        }
      }
    } catch (e) {
      Logger.error('Ошибка чтения кэша магазинов', e);
    }

    // 3. Server — первая загрузка или кэш пуст
    return await _fetchShopsFromServer();
  }

  /// Загрузить магазины с сервера и обновить кэш
  static Future<List<Shop>> _fetchShopsFromServer() async {
    Logger.debug('📥 Загрузка магазинов с сервера...');
    final shops = await BaseHttpService.getList<Shop>(
      endpoint: ApiConstants.shopsEndpoint,
      fromJson: (json) => Shop.fromJson(json),
      listKey: 'shops',
    );
    if (shops.isNotEmpty) {
      _cachedShops = shops;
      DiskCache.write('shops_list', {
        'shops': shops.map((s) => s.toJson()).toList(),
      });
    }
    return shops;
  }

  /// Фоновое обновление с сервера (не блокирует вызывающий код)
  static bool _isRefreshing = false;
  static Future<void> _refreshShopsInBackground() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      await _fetchShopsFromServer();
    } catch (_) {} finally {
      _isRefreshing = false;
    }
  }

  /// Сбросить кэш магазинов (вызывать при создании/удалении магазина)
  static void invalidateCache() {
    _cachedShops = null;
  }

  /// Получить магазин по ID
  static Future<Shop?> getShop(String id) async {
    return await BaseHttpService.get<Shop>(
      endpoint: '${ApiConstants.shopsEndpoint}/$id',
      fromJson: (json) => Shop.fromJson(json),
      itemKey: 'shop',
    );
  }

  /// Создать новый магазин
  static Future<Shop?> createShop({
    required String name,
    required String address,
    double? latitude,
    double? longitude,
  }) async {
    Logger.debug('📤 Создание магазина: $name');

    final requestBody = <String, dynamic>{
      'name': name,
      'address': address,
    };
    if (latitude != null) requestBody['latitude'] = latitude;
    if (longitude != null) requestBody['longitude'] = longitude;

    final result = await BaseHttpService.post<Shop>(
      endpoint: ApiConstants.shopsEndpoint,
      body: requestBody,
      fromJson: (json) => Shop.fromJson(json),
      itemKey: 'shop',
    );
    if (result != null) invalidateCache();
    return result;
  }

  /// Обновить магазин
  static Future<Shop?> updateShop({
    required String id,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    Logger.debug('📤 Обновление магазина: $id');

    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (address != null) body['address'] = address;
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;

    final result = await BaseHttpService.put<Shop>(
      endpoint: '${ApiConstants.shopsEndpoint}/$id',
      body: body,
      fromJson: (json) => Shop.fromJson(json),
      itemKey: 'shop',
    );
    if (result != null) invalidateCache();
    return result;
  }

  /// Удалить магазин
  static Future<bool> deleteShop(String id) async {
    Logger.debug('📤 Удаление магазина: $id');

    final result = await BaseHttpService.delete(
      endpoint: '${ApiConstants.shopsEndpoint}/$id',
    );
    if (result) invalidateCache();
    return result;
  }

  /// Найти магазин по адресу
  /// Возвращает null если магазин не найден
  static Future<Shop?> findShopByAddress(String address) async {
    try {
      final shops = await getShops();
      return shops.firstWhere(
        (shop) => shop.address == address,
        orElse: () => throw Exception('Shop not found'),
      );
    } catch (e) {
      Logger.warning('Магазин не найден по адресу: $address');
      return null;
    }
  }

  /// Найти ID магазина по адресу
  /// Возвращает null если магазин не найден
  static Future<String?> findShopIdByAddress(String address) async {
    final shop = await findShopByAddress(address);
    return shop?.id;
  }

  // ============================================
  // Shop Settings API
  // ============================================

  /// Получить настройки магазина по адресу
  static Future<ShopSettings?> getShopSettings(String shopAddress) async {
    Logger.debug('📥 Загрузка настроек магазина: $shopAddress');

    return await BaseHttpService.get<ShopSettings>(
      endpoint: '/api/shop-settings/${Uri.encodeComponent(shopAddress)}',
      fromJson: (json) => ShopSettings.fromJson(json),
      itemKey: 'settings',
    );
  }

  /// Сохранить настройки магазина
  static Future<bool> saveShopSettings(ShopSettings settings) async {
    Logger.debug('📤 Сохранение настроек магазина: ${settings.shopAddress}');

    final result = await BaseHttpService.post<ShopSettings>(
      endpoint: '/api/shop-settings',
      body: settings.toJson(),
      fromJson: (json) => ShopSettings.fromJson(json),
      itemKey: 'settings',
    );

    return result != null;
  }

  // ============================================
  // Multitenancy Filtering
  // ============================================

  /// Получить магазины с учётом мультитенантности
  /// Developer - все магазины
  /// Admin - только managedShopIds
  /// Manager - зависит от canSeeAllManagerShops
  /// Employee - только primaryShopId
  /// Client - все магазины
  static Future<List<Shop>> getShopsForCurrentUser() async {
    final allShops = await getShops();
    final roleData = await UserRoleService.loadUserRole();

    if (roleData == null) {
      Logger.debug('⚠️ Роль не загружена, возвращаем пустой список (fail-secure)');
      return [];
    }

    Logger.debug('🏪 Фильтрация магазинов для роли: ${roleData.role.name}');

    switch (roleData.role) {
      case UserRole.developer:
        Logger.debug('   Developer - все ${allShops.length} магазинов');
        return allShops;

      case UserRole.admin:
        if (roleData.managedShopIds.isEmpty) {
          // Fail-secure: if managedShopIds not loaded yet (network timeout, race condition),
          // return empty list instead of ALL shops to prevent data leakage
          Logger.debug('   Admin без привязанных магазинов - пустой список (fail-secure)');
          return [];
        }
        final filtered = allShops.where((shop) =>
          roleData.managedShopIds.contains(shop.id) ||
          roleData.managedShopIds.contains(shop.address)
        ).toList();
        Logger.debug('   Admin - ${filtered.length} из ${allShops.length} магазинов');
        return filtered;

      case UserRole.manager:
        if (roleData.canSeeAllManagerShops) {
          Logger.debug('   Manager с доступом ко всем магазинам управляющего');
          return allShops;
        }
        // Поддержка множественных магазинов (managedShopIds)
        if (roleData.managedShopIds.isNotEmpty) {
          final filtered = allShops.where((shop) =>
            roleData.managedShopIds.contains(shop.id) ||
            roleData.managedShopIds.contains(shop.address)
          ).toList();
          Logger.debug('   Manager - ${filtered.length} из ${allShops.length} магазинов (по managedShopIds)');
          return filtered;
        }
        // Обратная совместимость — один primaryShopId
        if (roleData.primaryShopId != null) {
          final filtered = allShops.where((shop) =>
            shop.id == roleData.primaryShopId ||
            shop.address == roleData.primaryShopId
          ).toList();
          Logger.debug('   Manager - ${filtered.length} магазин(ов)');
          return filtered;
        }
        return allShops;

      case UserRole.employee:
        if (roleData.primaryShopId != null) {
          final filtered = allShops.where((shop) =>
            shop.id == roleData.primaryShopId ||
            shop.address == roleData.primaryShopId
          ).toList();
          Logger.debug('   Employee - ${filtered.length} магазин(ов)');
          return filtered;
        }
        return allShops;

      case UserRole.client:
        Logger.debug('   Client - все ${allShops.length} магазинов');
        return allShops;
    }
  }

  /// Проверить, имеет ли текущий пользователь доступ к магазину
  static Future<bool> hasAccessToShop(String shopIdOrAddress) async {
    final roleData = await UserRoleService.loadUserRole();

    if (roleData == null) return false;

    switch (roleData.role) {
      case UserRole.developer:
      case UserRole.client:
        return true;

      case UserRole.admin:
        if (roleData.managedShopIds.isEmpty) return true;
        return roleData.managedShopIds.contains(shopIdOrAddress);

      case UserRole.manager:
        if (roleData.canSeeAllManagerShops) return true;
        if (roleData.primaryShopId == null) return true;
        return roleData.primaryShopId == shopIdOrAddress;

      case UserRole.employee:
        if (roleData.primaryShopId == null) return true;
        return roleData.primaryShopId == shopIdOrAddress;
    }
  }
}

