import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/pending_code_model.dart';
import '../models/master_product_model.dart';

/// Сервис для работы с мастер-каталогом товаров
class MasterCatalogService {
  static const String _endpoint = '/api/master-catalog';

  // ============ ПРОДУКТЫ МАСТЕР-КАТАЛОГА ============

  /// Получить все продукты мастер-каталога
  static Future<List<MasterProduct>> getProducts({
    String? group,
    String? search,
    int? limit,
    int? offset,
  }) async {
    try {
      var url = '${ApiConstants.serverUrl}$_endpoint?';
      final params = <String>[];
      if (group != null) params.add('group=${Uri.encodeComponent(group)}');
      if (search != null) params.add('search=${Uri.encodeComponent(search)}');
      if (limit != null) params.add('limit=$limit');
      if (offset != null) params.add('offset=$offset');
      url += params.join('&');

      Logger.debug('GET $url');

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['products'] as List? ?? [];
        Logger.debug('Loaded ${list.length} master products');
        return list.map((json) => MasterProduct.fromJson(json)).toList();
      } else {
        Logger.error('Error getting master products: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('Error getting master products', e);
      return [];
    }
  }

  /// Получить список групп товаров
  static Future<List<String>> getGroups() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/groups/list'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<String>.from(data['groups'] ?? []);
      }
      return [];
    } catch (e) {
      Logger.error('Error getting groups', e);
      return [];
    }
  }

  /// Получить статистику мастер-каталога
  static Future<MasterCatalogStats?> getStats() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/stats'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return MasterCatalogStats.fromJson(data['stats']);
      }
      return null;
    } catch (e) {
      Logger.error('Error getting stats', e);
      return null;
    }
  }

  /// Создать новый продукт в мастер-каталоге
  static Future<MasterProduct?> createProduct({
    required String name,
    required String barcode,
    String? group,
    Map<String, String>? shopCodes,
  }) async {
    try {
      final body = {
        'name': name,
        'barcode': barcode,
        if (group != null) 'group': group,
        if (shopCodes != null) 'shopCodes': shopCodes,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(body),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        Logger.info('Product created: $name');
        return MasterProduct.fromJson(data['product']);
      } else {
        Logger.error('Error creating product: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('Error creating product', e);
      return null;
    }
  }

  /// Обновить продукт
  static Future<MasterProduct?> updateProduct({
    required String id,
    String? name,
    String? group,
    String? barcode,
    Map<String, String>? shopCodes,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (group != null) body['group'] = group;
      if (barcode != null) body['barcode'] = barcode;
      if (shopCodes != null) body['shopCodes'] = shopCodes;

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/$id'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(body),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return MasterProduct.fromJson(data['product']);
      }
      return null;
    } catch (e) {
      Logger.error('Error updating product', e);
      return null;
    }
  }

  /// Удалить продукт
  static Future<bool> deleteProduct(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/$id'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      return response.statusCode == 200;
    } catch (e) {
      Logger.error('Error deleting product', e);
      return false;
    }
  }

  // ============ PENDING CODES (новые коды) ============

  /// Получить список кодов ожидающих подтверждения
  static Future<List<PendingCode>> getPendingCodes() async {
    try {
      Logger.debug('GET $_endpoint/pending-codes');

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/pending-codes'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['codes'] as List? ?? [];
        Logger.debug('Loaded ${list.length} pending codes');
        return list.map((json) => PendingCode.fromJson(json)).toList();
      } else {
        Logger.error('Error getting pending codes: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('Error getting pending codes', e);
      return [];
    }
  }

  /// Подтвердить код и добавить в мастер-каталог
  static Future<MasterProduct?> approveCode({
    required String kod,
    required String name,
    String? group,
  }) async {
    try {
      final body = {
        'kod': kod,
        'name': name,
        if (group != null) 'group': group,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/approve-code'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(body),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        Logger.info('Code approved: $kod -> $name');
        return MasterProduct.fromJson(data['product']);
      } else {
        Logger.error('Error approving code: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('Error approving code', e);
      return null;
    }
  }

  /// Отклонить код (удалить из pending)
  static Future<bool> rejectCode(String kod) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/pending-codes/$kod'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        Logger.info('Code rejected: $kod');
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('Error rejecting code', e);
      return false;
    }
  }

  // ============ BULK IMPORT ============

  /// Массовый импорт товаров
  static Future<BulkImportResult?> bulkImport({
    required List<Map<String, dynamic>> products,
    bool skipExisting = true,
  }) async {
    try {
      final body = {
        'products': products,
        'skipExisting': skipExisting,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$_endpoint/bulk-import'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(body),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return BulkImportResult.fromJson(data);
      } else {
        Logger.error('Error bulk import: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      Logger.error('Error bulk import', e);
      return null;
    }
  }

  // ============ ДЛЯ AI TRAINING ============

  /// Получить товары для обучения (формат для AI Training)
  static Future<List<MasterProduct>> getProductsForTraining({String? group}) async {
    try {
      var url = '${ApiConstants.serverUrl}$_endpoint/for-training';
      if (group != null) {
        url += '?productGroup=${Uri.encodeComponent(group)}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['products'] as List? ?? [];
        return list.map((json) => MasterProduct.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      Logger.error('Error getting products for training', e);
      return [];
    }
  }

  // ============ ПРИВЯЗКА КОДОВ К СУЩЕСТВУЮЩИМ ТОВАРАМ ============

  /// Поиск товаров для привязки pending-кода (лёгкий, с фото и баркодами)
  static Future<List<AssignSearchProduct>> searchForAssign(String query) async {
    try {
      if (query.length < 2) return [];

      final url = '${ApiConstants.serverUrl}$_endpoint/search-for-assign?search=${Uri.encodeComponent(query)}';
      Logger.debug('GET $url');

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['products'] as List? ?? [];
        return list.map((json) => AssignSearchProduct.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      Logger.error('Error searching for assign', e);
      return [];
    }
  }

  /// Привязать pending-код к существующему товару
  static Future<bool> assignCodeToProduct({
    required String kod,
    required String targetProductId,
  }) async {
    try {
      final url = '${ApiConstants.serverUrl}$_endpoint/assign-code-to-product';
      Logger.debug('POST $url (kod: $kod, target: $targetProductId)');

      final response = await http.post(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'kod': kod,
          'targetProductId': targetProductId,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      Logger.error('Error assigning code: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('Error assigning code to product', e);
      return false;
    }
  }
}

/// Продукт из лёгкого поиска для привязки кода
class AssignSearchProduct {
  final String id;
  final String name;
  final String group;
  final String? barcode;
  final List<String> barcodes;
  final List<String> ids;
  final int barcodesCount;
  final String? productPhotoUrl;

  AssignSearchProduct({
    required this.id,
    required this.name,
    this.group = '',
    this.barcode,
    this.barcodes = const [],
    this.ids = const [],
    this.barcodesCount = 1,
    this.productPhotoUrl,
  });

  factory AssignSearchProduct.fromJson(Map<String, dynamic> json) {
    return AssignSearchProduct(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      group: json['group'] ?? '',
      barcode: json['barcode'],
      barcodes: (json['barcodes'] as List?)?.map((e) => e.toString()).toList() ?? [],
      ids: (json['ids'] as List?)?.map((e) => e.toString()).toList() ?? [],
      barcodesCount: json['barcodesCount'] ?? 1,
      productPhotoUrl: json['productPhotoUrl'] as String?,
    );
  }
}

/// Статистика мастер-каталога
class MasterCatalogStats {
  final int totalProducts;
  final int productsWithMappings;
  final int productsWithoutMappings;
  final int totalGroups;
  final int totalMappings;
  final int linkedShops;

  MasterCatalogStats({
    required this.totalProducts,
    required this.productsWithMappings,
    required this.productsWithoutMappings,
    required this.totalGroups,
    required this.totalMappings,
    required this.linkedShops,
  });

  factory MasterCatalogStats.fromJson(Map<String, dynamic> json) {
    return MasterCatalogStats(
      totalProducts: json['totalProducts'] ?? 0,
      productsWithMappings: json['productsWithMappings'] ?? 0,
      productsWithoutMappings: json['productsWithoutMappings'] ?? 0,
      totalGroups: json['totalGroups'] ?? 0,
      totalMappings: json['totalMappings'] ?? 0,
      linkedShops: json['linkedShops'] ?? 0,
    );
  }
}

/// Результат bulk import
class BulkImportResult {
  final int added;
  final int skipped;
  final int errors;
  final int total;

  BulkImportResult({
    required this.added,
    required this.skipped,
    required this.errors,
    required this.total,
  });

  factory BulkImportResult.fromJson(Map<String, dynamic> json) {
    return BulkImportResult(
      added: json['added'] ?? 0,
      skipped: json['skipped'] ?? 0,
      errors: json['errors'] ?? 0,
      total: json['total'] ?? 0,
    );
  }
}
