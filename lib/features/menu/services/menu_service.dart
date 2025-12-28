import '../pages/menu_page.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class MenuService {
  /// Получить все позиции меню
  static Future<List<MenuItem>> getMenuItems() async {
    Logger.debug('📥 Загрузка меню с сервера...');

    return await BaseHttpService.getList<MenuItem>(
      endpoint: ApiConstants.menuEndpoint,
      fromJson: (json) => MenuItem.fromJson(json),
      listKey: 'items',
    );
  }

  /// Получить позицию меню по ID
  static Future<MenuItem?> getMenuItem(String id) async {
    return await BaseHttpService.get<MenuItem>(
      endpoint: '${ApiConstants.menuEndpoint}/$id',
      fromJson: (json) => MenuItem.fromJson(json),
      itemKey: 'item',
    );
  }

  /// Создать новую позицию меню
  static Future<MenuItem?> createMenuItem({
    required String name,
    String? price,
    String? category,
    String? shop,
    String? photoId,
  }) async {
    Logger.debug('📤 Создание позиции меню: $name');

    final requestBody = <String, dynamic>{
      'name': name,
    };
    if (price != null) requestBody['price'] = price;
    if (category != null) requestBody['category'] = category;
    if (shop != null) requestBody['shop'] = shop;
    if (photoId != null) requestBody['photo_id'] = photoId;

    return await BaseHttpService.post<MenuItem>(
      endpoint: ApiConstants.menuEndpoint,
      body: requestBody,
      fromJson: (json) => MenuItem.fromJson(json),
      itemKey: 'item',
    );
  }

  /// Обновить позицию меню
  static Future<MenuItem?> updateMenuItem({
    required String id,
    String? name,
    String? price,
    String? category,
    String? shop,
    String? photoId,
  }) async {
    Logger.debug('📤 Обновление позиции меню: $id');

    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (price != null) body['price'] = price;
    if (category != null) body['category'] = category;
    if (shop != null) body['shop'] = shop;
    if (photoId != null) body['photo_id'] = photoId;

    return await BaseHttpService.put<MenuItem>(
      endpoint: '${ApiConstants.menuEndpoint}/$id',
      body: body,
      fromJson: (json) => MenuItem.fromJson(json),
      itemKey: 'item',
    );
  }

  /// Удалить позицию меню
  static Future<bool> deleteMenuItem(String id) async {
    Logger.debug('📤 Удаление позиции меню: $id');

    return await BaseHttpService.delete(
      endpoint: '${ApiConstants.menuEndpoint}/$id',
    );
  }
}


