import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';
import '../../../core/widgets/shop_icon.dart';
import '../services/shop_service.dart';

/// Модель магазина
class Shop {
  final String id;
  final String name;
  final String address;
  final IconData icon; // Оставлено для обратной совместимости
  final double? latitude;  // Широта
  final double? longitude; // Долгота

  Shop({
    required this.id,
    required this.name,
    required this.address,
    this.icon = Icons.store, // Fallback иконка
    this.latitude,
    this.longitude,
  });

  /// Виджет иконки магазина (используйте вместо Icon(shop.icon))
  Widget get iconWidget => const ShopIcon(size: 72);

  /// Виджет иконки для leading в ListTile
  Widget get leadingIcon => const ShopIcon(size: 72);

  /// Создать Shop из JSON
  factory Shop.fromJson(Map<String, dynamic> json) {
    // Парсинг и валидация координат
    double? parsedLat;
    double? parsedLon;

    if (json['latitude'] != null) {
      final lat = json['latitude'] is double
          ? json['latitude']
          : double.tryParse(json['latitude'].toString());
      // Валидация: широта от -90 до 90
      if (lat != null && lat >= -90 && lat <= 90) {
        parsedLat = lat;
      }
    }

    if (json['longitude'] != null) {
      final lon = json['longitude'] is double
          ? json['longitude']
          : double.tryParse(json['longitude'].toString());
      // Валидация: долгота от -180 до 180
      if (lon != null && lon >= -180 && lon <= 180) {
        parsedLon = lon;
      }
    }

    return Shop(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      icon: Icons.store, // Fallback, используйте iconWidget вместо Icon(shop.icon)
      latitude: parsedLat,
      longitude: parsedLon,
    );
  }

  /// Преобразовать Shop в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  /// Загрузить список магазинов с сервера
  /// Использует кэширование на 10 минут для уменьшения запросов
  static Future<List<Shop>> loadShopsFromServer() async {
    // Проверяем кэш
    const cacheKey = 'shops_list';
    final cached = CacheManager.get<List<Shop>>(cacheKey);
    if (cached != null) {
      Logger.debug('📥 Магазины загружены из кэша');
      return cached;
    }
    
    try {
      Logger.debug('📥 Загружаем магазины с сервера...');
      
      // Загружаем магазины через сервис
      final shops = await ShopService.getShops();
      
      // Сохраняем в кэш на 10 минут
      CacheManager.set(cacheKey, shops, duration: const Duration(minutes: 10));
      
      Logger.success('Загружено магазинов: ${shops.length}');
      return shops;
    } catch (e) {
      Logger.warning('Ошибка загрузки магазинов с сервера: $e');
      // Возвращаем список по умолчанию при ошибке
      return _getDefaultShops();
    }
  }

  /// Получить пустой список магазинов (fallback при ошибке сервера)
  static List<Shop> _getDefaultShops() {
    return [];
  }
}

