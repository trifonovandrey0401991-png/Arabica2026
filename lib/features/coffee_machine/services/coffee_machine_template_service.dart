import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../models/coffee_machine_template_model.dart';

/// Сервис для работы с шаблонами кофемашин и привязками к магазинам
class CoffeeMachineTemplateService {
  static const String _baseUrl = '${ApiConstants.serverUrl}/api/coffee-machine';

  /// Получить все шаблоны кофемашин
  static Future<List<CoffeeMachineTemplate>> getTemplates() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/templates'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['templates'] as List?)
            ?.map((e) => CoffeeMachineTemplate.fromJson(e))
            .toList() ?? [];
      }
      return [];
    } catch (e) {
      print('Ошибка получения шаблонов кофемашин: $e');
      return [];
    }
  }

  /// Получить шаблон по ID
  static Future<CoffeeMachineTemplate?> getTemplate(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/templates/$id'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return CoffeeMachineTemplate.fromJson(data['template']);
      }
      return null;
    } catch (e) {
      print('Ошибка получения шаблона кофемашины: $e');
      return null;
    }
  }

  /// Сохранить шаблон (создать или обновить)
  static Future<bool> saveTemplate({
    required CoffeeMachineTemplate template,
    Uint8List? referenceImage,
  }) async {
    try {
      final body = <String, dynamic>{
        'template': template.toJson(),
      };
      if (referenceImage != null) {
        body['referenceImage'] = base64Encode(referenceImage);
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/templates'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка сохранения шаблона кофемашины: $e');
      return false;
    }
  }

  /// Обновить шаблон
  static Future<bool> updateTemplate({
    required CoffeeMachineTemplate template,
    Uint8List? referenceImage,
  }) async {
    try {
      final body = <String, dynamic>{
        'template': template.toJson(),
      };
      if (referenceImage != null) {
        body['referenceImage'] = base64Encode(referenceImage);
      }

      final response = await http.put(
        Uri.parse('$_baseUrl/templates/${template.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка обновления шаблона кофемашины: $e');
      return false;
    }
  }

  /// Удалить шаблон
  static Future<bool> deleteTemplate(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/templates/$id'),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка удаления шаблона кофемашины: $e');
      return false;
    }
  }

  /// Получить эталонное изображение шаблона
  static Future<Uint8List?> getTemplateImage(String templateId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/templates/$templateId/image'),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      print('Ошибка получения изображения шаблона: $e');
      return null;
    }
  }

  // ===== Привязки к магазинам =====

  /// Получить все привязки (конфиги магазинов)
  static Future<List<CoffeeMachineShopConfig>> getAllShopConfigs() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/shop-config'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['configs'] as List?)
            ?.map((e) => CoffeeMachineShopConfig.fromJson(e))
            .toList() ?? [];
      }
      return [];
    } catch (e) {
      print('Ошибка получения привязок магазинов: $e');
      return [];
    }
  }

  /// Получить конфиг конкретного магазина
  static Future<CoffeeMachineShopConfig?> getShopConfig(String shopAddress) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/shop-config/${Uri.encodeComponent(shopAddress)}'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return CoffeeMachineShopConfig.fromJson(data['config']);
      }
      return null;
    } catch (e) {
      print('Ошибка получения конфига магазина: $e');
      return null;
    }
  }

  /// Обновить привязку шаблонов к магазину
  static Future<bool> updateShopConfig(CoffeeMachineShopConfig config) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/shop-config/${Uri.encodeComponent(config.shopAddress)}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config.toJson()),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка обновления привязки магазина: $e');
      return false;
    }
  }
}
