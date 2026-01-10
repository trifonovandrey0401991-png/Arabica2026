import '../models/supplier_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class SupplierService {
  static const String baseEndpoint = ApiConstants.suppliersEndpoint;

  /// Получить всех поставщиков
  static Future<List<Supplier>> getSuppliers() async {
    Logger.debug('📥 Загрузка поставщиков с сервера...');
    return await BaseHttpService.getList<Supplier>(
      endpoint: baseEndpoint,
      fromJson: (json) => Supplier.fromJson(json),
      listKey: 'suppliers',
    );
  }

  /// Получить поставщика по ID
  static Future<Supplier?> getSupplier(String id) async {
    Logger.debug('📥 Загрузка поставщика: $id');
    return await BaseHttpService.get<Supplier>(
      endpoint: '$baseEndpoint/$id',
      fromJson: (json) => Supplier.fromJson(json),
      itemKey: 'supplier',
    );
  }

  /// Создать нового поставщика
  static Future<Supplier?> createSupplier(Supplier supplier) async {
    Logger.debug('📤 Создание поставщика: ${supplier.name}');
    return await BaseHttpService.post<Supplier>(
      endpoint: baseEndpoint,
      body: supplier.toJson(),
      fromJson: (json) => Supplier.fromJson(json),
      itemKey: 'supplier',
    );
  }

  /// Обновить поставщика
  static Future<Supplier?> updateSupplier(Supplier supplier) async {
    Logger.debug('📤 Обновление поставщика: ${supplier.id}');
    return await BaseHttpService.put<Supplier>(
      endpoint: '$baseEndpoint/${supplier.id}',
      body: supplier.toJson(),
      fromJson: (json) => Supplier.fromJson(json),
      itemKey: 'supplier',
    );
  }

  /// Удалить поставщика
  static Future<bool> deleteSupplier(String id) async {
    Logger.debug('📤 Удаление поставщика: $id');
    return await BaseHttpService.delete(endpoint: '$baseEndpoint/$id');
  }
}
