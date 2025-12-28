import '../models/shop_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ShopService {
  /// Получить все магазины
  static Future<List<Shop>> getShops() async {
    Logger.debug('📥 Загрузка магазинов с сервера...');

    return await BaseHttpService.getList<Shop>(
      endpoint: ApiConstants.shopsEndpoint,
      fromJson: (json) => Shop.fromJson(json),
      listKey: 'shops',
    );
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

    return await BaseHttpService.post<Shop>(
      endpoint: ApiConstants.shopsEndpoint,
      body: requestBody,
      fromJson: (json) => Shop.fromJson(json),
      itemKey: 'shop',
    );
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

    return await BaseHttpService.put<Shop>(
      endpoint: '${ApiConstants.shopsEndpoint}/$id',
      body: body,
      fromJson: (json) => Shop.fromJson(json),
      itemKey: 'shop',
    );
  }

  /// Удалить магазин
  static Future<bool> deleteShop(String id) async {
    Logger.debug('📤 Удаление магазина: $id');

    return await BaseHttpService.delete(
      endpoint: '${ApiConstants.shopsEndpoint}/$id',
    );
  }
}


