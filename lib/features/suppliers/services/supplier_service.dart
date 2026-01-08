import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/supplier_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class SupplierService {
  static const String baseEndpoint = '/api/suppliers';

  /// Получить всех поставщиков
  static Future<List<Supplier>> getSuppliers() async {
    try {
      Logger.debug('📥 Загрузка поставщиков с сервера...');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final suppliersJson = result['suppliers'] as List<dynamic>;
          final suppliers = suppliersJson
              .map((json) => Supplier.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено поставщиков: ${suppliers.length}');
          return suppliers;
        } else {
          Logger.error('❌ Ошибка загрузки поставщиков: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки поставщиков', e);
      return [];
    }
  }

  /// Получить поставщика по ID
  static Future<Supplier?> getSupplier(String id) async {
    try {
      Logger.debug('📥 Загрузка поставщика: $id');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$id'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Поставщик загружен');
          return Supplier.fromJson(result['supplier']);
        } else {
          Logger.error('❌ Ошибка загрузки поставщика: ${result['error']}');
          return null;
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки поставщика', e);
      return null;
    }
  }

  /// Создать нового поставщика
  static Future<Supplier?> createSupplier(Supplier supplier) async {
    try {
      Logger.debug('📤 Создание поставщика: ${supplier.name}');

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(supplier.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Поставщик создан');
          return Supplier.fromJson(result['supplier']);
        } else {
          Logger.error('❌ Ошибка создания поставщика: ${result['error']}');
          return null;
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('❌ Ошибка создания поставщика', e);
      return null;
    }
  }

  /// Обновить поставщика
  static Future<Supplier?> updateSupplier(Supplier supplier) async {
    try {
      Logger.debug('📤 Обновление поставщика: ${supplier.id}');

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/${supplier.id}'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(supplier.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Поставщик обновлен');
          return Supplier.fromJson(result['supplier']);
        } else {
          Logger.error('❌ Ошибка обновления поставщика: ${result['error']}');
          return null;
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('❌ Ошибка обновления поставщика', e);
      return null;
    }
  }

  /// Удалить поставщика
  static Future<bool> deleteSupplier(String id) async {
    try {
      Logger.debug('📤 Удаление поставщика: $id');

      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/$id'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Поставщик удален');
          return true;
        } else {
          Logger.error('❌ Ошибка удаления поставщика: ${result['error']}');
          return false;
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return false;
      }
    } catch (e) {
      Logger.error('❌ Ошибка удаления поставщика', e);
      return false;
    }
  }
}
