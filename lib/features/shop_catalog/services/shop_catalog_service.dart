import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/shop_product.dart';
import '../models/shop_product_group.dart';

/// HTTP-сервис для каталога товаров магазина
class ShopCatalogService {
  // ==================== CACHE ====================

  static const _cacheKeyProducts = 'shop_catalog_products';
  static const _cacheKeyGroups = 'shop_catalog_groups';
  static const _cacheKeyTimestamp = 'shop_catalog_cache_ts';
  static const _cacheDuration = Duration(hours: 1);

  /// Read cached catalog (products + groups). Returns null if no cache or expired.
  static Future<({List<ShopProduct> products, List<ShopProductGroup> groups})?> readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_cacheKeyTimestamp);
      if (ts == null) return null;

      final age = DateTime.now().millisecondsSinceEpoch - ts;
      if (age > _cacheDuration.inMilliseconds) return null;

      final productsJson = prefs.getString(_cacheKeyProducts);
      final groupsJson = prefs.getString(_cacheKeyGroups);
      if (productsJson == null || groupsJson == null) return null;

      final products = (jsonDecode(productsJson) as List)
          .map((j) => ShopProduct.fromJson(Map<String, dynamic>.from(j)))
          .toList();
      final groups = (jsonDecode(groupsJson) as List)
          .map((j) => ShopProductGroup.fromJson(Map<String, dynamic>.from(j)))
          .toList();

      return (products: products, groups: groups);
    } catch (e) {
      Logger.error('Shop catalog cache read error', e);
      return null;
    }
  }

  /// Save catalog to cache
  static Future<void> writeCache(List<ShopProduct> products, List<ShopProductGroup> groups) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyProducts, jsonEncode(products.map((p) => p.toJson()).toList()));
      await prefs.setString(_cacheKeyGroups, jsonEncode(groups.map((g) => g.toJson()).toList()));
      await prefs.setInt(_cacheKeyTimestamp, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      Logger.error('Shop catalog cache write error', e);
    }
  }

  /// Invalidate cache (call after admin edits)
  static Future<void> invalidateCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKeyTimestamp);
    } catch (e) {
      Logger.error('Shop catalog cache invalidate error', e);
    }
  }

  // ==================== GROUPS ====================

  static Future<List<ShopProductGroup>> getGroups() async {
    final result = await BaseHttpService.getRaw(endpoint: '/api/shop-catalog/groups');
    if (result == null || result['success'] != true) return [];
    final list = result['groups'] as List? ?? [];
    return list.map((j) => ShopProductGroup.fromJson(Map<String, dynamic>.from(j))).toList();
  }

  static Future<ShopProductGroup?> createGroup({required String name, String visibility = 'all', int sortOrder = 0}) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '/api/shop-catalog/groups',
      body: {'name': name, 'visibility': visibility, 'sortOrder': sortOrder},
    );
    if (result == null || result['success'] != true) return null;
    return ShopProductGroup.fromJson(Map<String, dynamic>.from(result['group']));
  }

  static Future<ShopProductGroup?> updateGroup({required String id, String? name, String? visibility, int? sortOrder, bool? isActive}) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (visibility != null) body['visibility'] = visibility;
    if (sortOrder != null) body['sortOrder'] = sortOrder;
    if (isActive != null) body['isActive'] = isActive;

    final result = await BaseHttpService.putRaw(endpoint: '/api/shop-catalog/groups/$id', body: body);
    if (result == null || result['success'] != true) return null;
    return ShopProductGroup.fromJson(Map<String, dynamic>.from(result['group']));
  }

  static Future<bool> deleteGroup(String id) async {
    final result = await BaseHttpService.deleteRaw(endpoint: '/api/shop-catalog/groups/$id');
    return result != null && result['success'] == true;
  }

  // ==================== PRODUCTS ====================

  static Future<List<ShopProduct>> getProducts({String? groupId, bool? active}) async {
    var endpoint = '/api/shop-catalog/products';
    final params = <String>[];
    if (groupId != null) params.add('groupId=$groupId');
    if (active != null) params.add('active=$active');
    if (params.isNotEmpty) endpoint += '?${params.join('&')}';

    final result = await BaseHttpService.getRaw(endpoint: endpoint);
    if (result == null || result['success'] != true) return [];
    final list = result['products'] as List? ?? [];
    return list.map((j) => ShopProduct.fromJson(Map<String, dynamic>.from(j))).toList();
  }

  static Future<ShopProduct?> getProduct(String id) async {
    final result = await BaseHttpService.getRaw(endpoint: '/api/shop-catalog/products/$id');
    if (result == null || result['success'] != true) return null;
    return ShopProduct.fromJson(Map<String, dynamic>.from(result['product']));
  }

  static Future<ShopProduct?> createProduct({
    required String name,
    String? description,
    String? groupId,
    double? priceRetail,
    double? priceWholesale,
    int? pricePoints,
    bool isWholesale = false,
    int sortOrder = 0,
  }) async {
    final body = <String, dynamic>{'name': name, 'sortOrder': sortOrder, 'isWholesale': isWholesale};
    if (description != null) body['description'] = description;
    if (groupId != null) body['groupId'] = groupId;
    if (priceRetail != null) body['priceRetail'] = priceRetail;
    if (priceWholesale != null) body['priceWholesale'] = priceWholesale;
    if (pricePoints != null) body['pricePoints'] = pricePoints;

    final result = await BaseHttpService.postRaw(endpoint: '/api/shop-catalog/products', body: body);
    if (result == null || result['success'] != true) return null;
    return ShopProduct.fromJson(Map<String, dynamic>.from(result['product']));
  }

  static Future<ShopProduct?> updateProduct({
    required String id,
    String? name,
    String? description,
    String? groupId,
    double? priceRetail,
    double? priceWholesale,
    int? pricePoints,
    bool? isActive,
    bool? isWholesale,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (groupId != null) body['groupId'] = groupId;
    if (priceRetail != null) body['priceRetail'] = priceRetail;
    if (priceWholesale != null) body['priceWholesale'] = priceWholesale;
    if (pricePoints != null) body['pricePoints'] = pricePoints;
    if (isActive != null) body['isActive'] = isActive;
    if (isWholesale != null) body['isWholesale'] = isWholesale;
    if (sortOrder != null) body['sortOrder'] = sortOrder;

    final result = await BaseHttpService.putRaw(endpoint: '/api/shop-catalog/products/$id', body: body);
    if (result == null || result['success'] != true) return null;
    return ShopProduct.fromJson(Map<String, dynamic>.from(result['product']));
  }

  static Future<bool> deleteProduct(String id) async {
    final result = await BaseHttpService.deleteRaw(endpoint: '/api/shop-catalog/products/$id');
    return result != null && result['success'] == true;
  }

  static Future<List<String>?> uploadPhoto({required String productId, required File photoFile}) async {
    try {
      Logger.debug('📤 Загрузка фото товара: $productId');
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.serverUrl}/api/shop-catalog/products/$productId/upload-photo'),
      );
      if (ApiConstants.apiKey != null && ApiConstants.apiKey!.isNotEmpty) {
        request.headers['X-API-Key'] = ApiConstants.apiKey!;
      }
      if (ApiConstants.sessionToken != null && ApiConstants.sessionToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${ApiConstants.sessionToken}';
      }
      final ext = photoFile.path.split('.').last.toLowerCase();
      final mimeType = ext == 'png' ? MediaType('image', 'png') : MediaType('image', 'jpeg');
      request.files.add(await http.MultipartFile.fromPath('photo', photoFile.path, contentType: mimeType));

      final response = await request.send().timeout(ApiConstants.longTimeout);
      final body = await response.stream.bytesToString();
      final result = jsonDecode(body);

      if (response.statusCode == 200 && result['success'] == true) {
        final photos = result['photos'] as List?;
        return photos?.map((p) => p.toString()).toList();
      }
      return null;
    } catch (e) {
      Logger.error('Upload photo error', e);
      return null;
    }
  }

  static Future<List<String>?> deletePhoto({required String productId, required int index}) async {
    final result = await BaseHttpService.deleteRaw(
      endpoint: '/api/shop-catalog/products/$productId/photos/$index',
    );
    if (result == null || result['success'] != true) return null;
    final photos = result['photos'] as List?;
    return photos?.map((p) => p.toString()).toList();
  }

  // ==================== AUTHORIZED EMPLOYEES ====================

  static Future<List<Map<String, dynamic>>> getAuthorizedEmployees() async {
    final result = await BaseHttpService.getRaw(endpoint: '/api/shop-catalog/authorized-employees');
    if (result == null || result['success'] != true) return [];
    return List<Map<String, dynamic>>.from(result['employees'] ?? []);
  }

  static Future<bool> addAuthorizedEmployee({required String phone, String? name}) async {
    final result = await BaseHttpService.postRaw(
      endpoint: '/api/shop-catalog/authorized-employees',
      body: {'phone': phone, 'name': name ?? ''},
    );
    return result != null && result['success'] == true;
  }

  static Future<bool> removeAuthorizedEmployee(String phone) async {
    final result = await BaseHttpService.deleteRaw(
      endpoint: '/api/shop-catalog/authorized-employees/$phone',
    );
    return result != null && result['success'] == true;
  }
}
