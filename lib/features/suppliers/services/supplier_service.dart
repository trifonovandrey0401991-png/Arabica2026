import '../models/supplier_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class SupplierService {
  static const String baseEndpoint = ApiConstants.suppliersEndpoint;

  // In-memory cache
  static List<Supplier>? _cachedSuppliers;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  /// Получить всех поставщиков (с кэшем)
  static Future<List<Supplier>> getSuppliers() async {
    if (_cachedSuppliers != null && _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      Logger.debug('📦 Поставщики из кэша: ${_cachedSuppliers!.length}');
      return _cachedSuppliers!;
    }

    Logger.debug('📥 Загрузка поставщиков с сервера...');
    final suppliers = await BaseHttpService.getList<Supplier>(
      endpoint: baseEndpoint,
      fromJson: (json) => Supplier.fromJson(json),
      listKey: 'suppliers',
    );
    _cachedSuppliers = suppliers;
    _cacheTime = DateTime.now();
    return suppliers;
  }

  /// Сбросить кэш поставщиков
  static void invalidateCache() {
    _cachedSuppliers = null;
    _cacheTime = null;
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
    final result = await BaseHttpService.post<Supplier>(
      endpoint: baseEndpoint,
      body: supplier.toJson(),
      fromJson: (json) => Supplier.fromJson(json),
      itemKey: 'supplier',
    );
    if (result != null) invalidateCache();
    return result;
  }

  /// Обновить поставщика
  static Future<Supplier?> updateSupplier(Supplier supplier) async {
    Logger.debug('📤 Обновление поставщика: ${supplier.id}');
    final result = await BaseHttpService.put<Supplier>(
      endpoint: '$baseEndpoint/${supplier.id}',
      body: supplier.toJson(),
      fromJson: (json) => Supplier.fromJson(json),
      itemKey: 'supplier',
    );
    if (result != null) invalidateCache();
    return result;
  }

  /// Удалить поставщика
  static Future<bool> deleteSupplier(String id) async {
    Logger.debug('📤 Удаление поставщика: $id');
    final result = await BaseHttpService.delete(endpoint: '$baseEndpoint/$id');
    if (result) invalidateCache();
    return result;
  }
}
