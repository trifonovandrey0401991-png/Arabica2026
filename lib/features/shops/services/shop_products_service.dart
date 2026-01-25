import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Модель товара магазина (из DBF синхронизации)
class ShopProduct {
  final String kod;
  final String name;
  final String group;
  final int stock;
  final int sales;
  final DateTime? updatedAt;

  ShopProduct({
    required this.kod,
    required this.name,
    required this.group,
    required this.stock,
    this.sales = 0,
    this.updatedAt,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) {
    return ShopProduct(
      kod: json['kod']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      stock: json['stock'] is int ? json['stock'] : int.tryParse(json['stock']?.toString() ?? '0') ?? 0,
      sales: json['sales'] is int ? json['sales'] : int.tryParse(json['sales']?.toString() ?? '0') ?? 0,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt']) : null,
    );
  }

  /// Есть ли товар в наличии
  bool get hasStock => stock > 0;

  /// Рассчитать грейд на основе продаж и остатков
  /// Грейд 1 (очень важный): высокие продажи (>= 10) и есть остаток
  /// Грейд 2 (средний): средние продажи (3-9) или высокие без остатка
  /// Грейд 3 (менее важный): низкие продажи (< 3)
  int calculateGrade() {
    // Товары с высокими продажами и в наличии - самые важные
    if (sales >= 10 && stock > 0) {
      return 1;
    }
    // Товары со средними продажами или высокими но без остатка
    if (sales >= 3 || (sales >= 10 && stock == 0)) {
      return 2;
    }
    // Товары с низкими продажами
    return 3;
  }
}

/// Информация о синхронизации магазина
class ShopSyncInfo {
  final String shopId;
  final int productCount;
  final DateTime? lastSync;

  ShopSyncInfo({
    required this.shopId,
    required this.productCount,
    this.lastSync,
  });

  factory ShopSyncInfo.fromJson(Map<String, dynamic> json) {
    return ShopSyncInfo(
      shopId: json['shopId']?.toString() ?? '',
      productCount: json['productCount'] ?? 0,
      lastSync: json['lastSync'] != null ? DateTime.tryParse(json['lastSync']) : null,
    );
  }
}

/// Сервис для работы с товарами магазинов (синхронизированными из DBF)
class ShopProductsService {
  /// Получить список магазинов с синхронизированными товарами
  static Future<List<ShopSyncInfo>> getShopsWithProducts() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/shop-products/shops/list'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final shops = data['shops'] as List? ?? [];
        return shops.map((s) => ShopSyncInfo.fromJson(s)).toList();
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка получения списка магазинов с товарами', e);
      return [];
    }
  }

  /// Получить все товары магазина
  static Future<List<ShopProduct>> getShopProducts(String shopId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/shop-products/$shopId'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final products = data['products'] as List? ?? [];
        return products.map((p) => ShopProduct.fromJson(p)).toList();
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка получения товаров магазина $shopId', e);
      return [];
    }
  }

  /// Получить товары магазина с остатком > 0 (для пересчёта)
  static Future<List<ShopProduct>> getProductsForRecount(String shopId, {String? group}) async {
    try {
      var url = '${ApiConstants.serverUrl}/api/shop-products/$shopId/for-recount';
      if (group != null && group.isNotEmpty) {
        url += '?group=${Uri.encodeComponent(group)}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final products = data['products'] as List? ?? [];
        return products.map((p) => ShopProduct.fromJson(p)).toList();
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка получения товаров для пересчёта', e);
      return [];
    }
  }

  /// Получить группы товаров магазина
  static Future<List<String>> getProductGroups(String shopId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/shop-products/$shopId/groups'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<String>.from(data['groups'] ?? []);
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка получения групп товаров', e);
      return [];
    }
  }

  /// Поиск товара по всем магазинам
  static Future<List<ShopProduct>> searchProducts(String query, {String? shopId}) async {
    try {
      var url = '${ApiConstants.serverUrl}/api/shop-products/search?q=${Uri.encodeComponent(query)}';
      if (shopId != null) {
        url += '&shopId=$shopId';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List? ?? [];
        return results.map((p) => ShopProduct.fromJson(p)).toList();
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка поиска товаров', e);
      return [];
    }
  }

  /// Получить остаток товара по коду
  static Future<int?> getProductStock(String shopId, String kod) async {
    try {
      final products = await getShopProducts(shopId);
      final product = products.firstWhere(
        (p) => p.kod == kod,
        orElse: () => ShopProduct(kod: '', name: '', group: '', stock: 0),
      );
      return product.kod.isNotEmpty ? product.stock : null;
    } catch (e) {
      Logger.error('Ошибка получения остатка товара', e);
      return null;
    }
  }

  /// Создать Map остатков по коду товара для быстрого доступа
  static Future<Map<String, int>> getStockMap(String shopId) async {
    try {
      final products = await getShopProducts(shopId);
      final stockMap = <String, int>{};
      for (final product in products) {
        stockMap[product.kod] = product.stock;
      }
      return stockMap;
    } catch (e) {
      Logger.error('Ошибка создания карты остатков', e);
      return {};
    }
  }
}
