import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';

/// Модель данных заведующей магазина
class StoreManagerInfo {
  final String phone;
  final String? name;
  final String? shopId;
  final List<String> managedShopIds;
  final bool canSeeAllManagerShops;

  StoreManagerInfo({
    required this.phone,
    this.name,
    this.shopId,
    this.managedShopIds = const [],
    this.canSeeAllManagerShops = false,
  });

  factory StoreManagerInfo.fromJson(Map<String, dynamic> json) {
    return StoreManagerInfo(
      phone: json['phone']?.toString() ?? '',
      name: json['name']?.toString(),
      shopId: json['shopId']?.toString(),
      managedShopIds: (json['managedShopIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          (json['shopId'] != null ? [json['shopId'].toString()] : []),
      canSeeAllManagerShops: json['canSeeAllManagerShops'] == true,
    );
  }
}

/// Сервис для управления привязками заведующих к магазинам
class StoreManagerService {
  static Future<String> _getPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_phone') ?? '';
  }

  /// Получить список всех заведующих
  static Future<List<StoreManagerInfo>> getStoreManagers() async {
    try {
      final phone = await _getPhone();
      if (phone.isEmpty) {
        Logger.warning('Нет телефона пользователя для запроса заведующих');
        return [];
      }

      final result = await BaseHttpService.getRaw(
        endpoint: '/api/shop-managers/store-managers?phone=$phone',
      );

      if (result == null || result['success'] != true) {
        Logger.warning('Не удалось загрузить заведующих');
        return [];
      }

      final list = result['storeManagers'] as List? ?? [];
      return list
          .map((e) => StoreManagerInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Logger.error('Ошибка загрузки заведующих', e);
      return [];
    }
  }

  /// Обновить привязку магазинов для заведующей
  static Future<bool> updateShopAssignments(
    String storeManagerPhone,
    List<String> shopIds,
  ) async {
    try {
      final adminPhone = await _getPhone();

      final result = await BaseHttpService.putRaw(
        endpoint: '/api/shop-managers/store-managers/$storeManagerPhone/shops',
        body: {
          'adminPhone': adminPhone,
          'managedShopIds': shopIds,
        },
      );

      if (result != null && result['success'] == true) {
        Logger.debug('Магазины заведующей ${Logger.maskPhone(storeManagerPhone)} обновлены: ${shopIds.length}');
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка обновления магазинов заведующей', e);
      return false;
    }
  }
}
