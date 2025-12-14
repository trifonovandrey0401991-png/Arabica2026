import 'package:http/http.dart' as http;
import 'dart:convert';
import 'menu_page.dart';
import 'utils/logger.dart';

class MenuService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/menu';

  /// Получить все позиции меню
  static Future<List<MenuItem>> getMenuItems() async {
    try {
      Logger.debug('📥 Загрузка меню с сервера...');
      
      final response = await http.get(
        Uri.parse(baseUrl),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final itemsJson = result['items'] as List<dynamic>;
          final items = itemsJson
              .map((json) => MenuItem.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено позиций меню: ${items.length}');
          return items;
        } else {
          Logger.error('❌ Ошибка загрузки меню: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки меню', e);
      return [];
    }
  }

  /// Получить позицию меню по ID
  static Future<MenuItem?> getMenuItem(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return MenuItem.fromJson(result['item'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки позиции меню', e);
      return null;
    }
  }

  /// Создать новую позицию меню
  static Future<MenuItem?> createMenuItem({
    required String name,
    String? price,
    String? category,
    String? shop,
    String? photoId,
  }) async {
    try {
      Logger.debug('📤 Создание позиции меню: $name');
      
      final requestBody = <String, dynamic>{
        'name': name,
      };
      if (price != null) requestBody['price'] = price;
      if (category != null) requestBody['category'] = category;
      if (shop != null) requestBody['shop'] = shop;
      if (photoId != null) requestBody['photo_id'] = photoId;
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Позиция меню создана: ${result['item']['id']}');
          return MenuItem.fromJson(result['item'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка создания позиции меню: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания позиции меню', e);
      return null;
    }
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
    try {
      Logger.debug('📤 Обновление позиции меню: $id');
      
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (price != null) body['price'] = price;
      if (category != null) body['category'] = category;
      if (shop != null) body['shop'] = shop;
      if (photoId != null) body['photo_id'] = photoId;
      
      final response = await http.put(
        Uri.parse('$baseUrl/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Позиция меню обновлена: $id');
          return MenuItem.fromJson(result['item'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка обновления позиции меню: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка обновления позиции меню', e);
      return null;
    }
  }

  /// Удалить позицию меню
  static Future<bool> deleteMenuItem(String id) async {
    try {
      Logger.debug('📤 Удаление позиции меню: $id');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Позиция меню удалена: $id');
          return true;
        } else {
          Logger.error('❌ Ошибка удаления позиции меню: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка удаления позиции меню', e);
      return false;
    }
  }
}

