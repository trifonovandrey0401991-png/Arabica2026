import 'package:http/http.dart' as http;
import 'dart:convert';
import 'shop_model.dart';
import 'core/utils/logger.dart';

class ShopService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/shops';

  /// Получить все магазины
  static Future<List<Shop>> getShops() async {
    try {
      Logger.debug('📥 Загрузка магазинов с сервера...');
      
      final response = await http.get(
        Uri.parse(baseUrl),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final shopsJson = result['shops'] as List<dynamic>;
          final shops = shopsJson
              .map((json) => Shop.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено магазинов: ${shops.length}');
          return shops;
        } else {
          Logger.error('❌ Ошибка загрузки магазинов: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки магазинов', e);
      return [];
    }
  }

  /// Получить магазин по ID
  static Future<Shop?> getShop(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return Shop.fromJson(result['shop'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки магазина', e);
      return null;
    }
  }

  /// Создать новый магазин
  static Future<Shop?> createShop({
    required String name,
    required String address,
    double? latitude,
    double? longitude,
  }) async {
    try {
      Logger.debug('📤 Создание магазина: $name');
      
      final requestBody = <String, dynamic>{
        'name': name,
        'address': address,
      };
      if (latitude != null) requestBody['latitude'] = latitude;
      if (longitude != null) requestBody['longitude'] = longitude;
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Магазин создан: ${result['shop']['id']}');
          return Shop.fromJson(result['shop'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка создания магазина: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания магазина', e);
      return null;
    }
  }

  /// Обновить магазин
  static Future<Shop?> updateShop({
    required String id,
    String? name,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    try {
      Logger.debug('📤 Обновление магазина: $id');
      
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (address != null) body['address'] = address;
      if (latitude != null) body['latitude'] = latitude;
      if (longitude != null) body['longitude'] = longitude;
      
      final response = await http.put(
        Uri.parse('$baseUrl/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Магазин обновлен: $id');
          return Shop.fromJson(result['shop'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка обновления магазина: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка обновления магазина', e);
      return null;
    }
  }

  /// Удалить магазин
  static Future<bool> deleteShop(String id) async {
    try {
      Logger.debug('📤 Удаление магазина: $id');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Магазин удален: $id');
          return true;
        } else {
          Logger.error('❌ Ошибка удаления магазина: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка удаления магазина', e);
      return false;
    }
  }
}


