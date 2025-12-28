import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'utils/logger.dart';
import 'utils/cache_manager.dart';
import 'shop_service.dart';

/// Модель магазина
class Shop {
  final String id;
  final String name;
  final String address;
  final IconData icon;
  final double? latitude;  // Широта
  final double? longitude; // Долгота

  Shop({
    required this.id,
    required this.name,
    required this.address,
    required this.icon,
    this.latitude,
    this.longitude,
  });

  /// Создать Shop из JSON
  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      icon: _getIconForShop(json['name'] ?? ''),
      latitude: json['latitude'] != null ? (json['latitude'] is double ? json['latitude'] : double.tryParse(json['latitude'].toString())) : null,
      longitude: json['longitude'] != null ? (json['longitude'] is double ? json['longitude'] : double.tryParse(json['longitude'].toString())) : null,
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

  /// Получить иконку по названию магазина
  /// Используем outlined иконки для лучшей видимости на темном фоне
  static IconData _getIconForShop(String shopName) {
    final name = shopName.toLowerCase();
    if (name.contains('пятигорск')) return Icons.store_outlined;
    if (name.contains('ессентуки')) return Icons.store_mall_directory_outlined;
    if (name.contains('кисловодск')) return Icons.local_cafe_outlined;
    if (name.contains('железноводск')) return Icons.coffee_outlined;
    if (name.contains('минеральные')) return Icons.restaurant_outlined;
    if (name.contains('ставрополь')) return Icons.shopping_bag_outlined;
    return Icons.store_outlined; // По умолчанию
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

  /// Загрузить список магазинов из сервер (устаревший метод, оставлен для обратной совместимости)
  @Deprecated('Используйте loadShopsFromServer()')
  static Future<List<Shop>> loadShopsFromGoogleSheets() async {
    return loadShopsFromServer();
  }

  /// Парсинг CSV строки с учетом кавычек и запятых внутри кавычек
  static List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    StringBuffer current = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Двойная кавычка внутри кавычек - экранированная кавычка
          current.write('"');
          i++; // Пропускаем следующую кавычку
        } else {
          // Обычная кавычка - переключаем режим
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // Запятая вне кавычек - разделитель полей
        result.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    // Добавляем последнее поле
    result.add(current.toString());
    return result;
  }

  /// Извлечь название магазина из адреса
  static String _extractShopName(String address) {
    // Пытаемся извлечь название города или использовать первые слова адреса
    if (address.contains('г.')) {
      final parts = address.split(',');
      if (parts.isNotEmpty) {
        return 'Арабика ${parts[0].replaceAll('г.', '').trim()}';
      }
    }
    // Если не нашли город, используем первые слова адреса
    final words = address.split(' ').take(3).join(' ');
    return 'Арабика $words';
  }

  /// Получить координаты магазинов по адресу
  static Map<String, Map<String, double>> getShopCoordinates() {
    return {
      'с.Винсады,ул Подгорная 156д (На Выезде)': {
        'latitude': 44.091173,
        'longitude': 42.952451,
      },
      'Лермонтов,ул Пятигорская 19': {
        'latitude': 44.100923,
        'longitude': 42.967543,
      },
      'Лермонтов,Комсомольская 1 (На Площади)': {
        'latitude': 44.104619,
        'longitude': 42.970543,
      },
      'Лермонтов,пр-кт Лермонтова 1стр1 (На Остановке )': {
        'latitude': 44.105379,
        'longitude': 42.978421,
      },
      'Ессентуки , ул пятигорская 149/1 (Золотушка)': {
        'latitude': 44.055559,
        'longitude': 42.911012,
      },
      'Иноземцево , ул Гагарина 1': {
        'latitude': 44.080153,
        'longitude': 43.081593,
      },
      'Пятигорск, 295-стрелковой дивизии 2А стр1 (ромашка)': {
        'latitude': 44.061053,
        'longitude': 43.063672,
      },
      'Пятигорск,ул Коллективная 26а': {
        'latitude': 44.032997,
        'longitude': 43.042525,
      },
    };
  }

  /// Получить список магазинов по умолчанию (fallback)
  static List<Shop> _getDefaultShops() {
    return [
      Shop(
        id: 'shop_default_1',
        name: 'Арабика Пятигорск',
        address: 'г. Пятигорск, ул. Ленина, 10',
        icon: Icons.store,
      ),
      Shop(
        id: 'shop_default_2',
        name: 'Арабика Ессентуки',
        address: 'г. Ессентуки, ул. Мира, 5',
        icon: Icons.store_mall_directory,
      ),
    ];
  }
}

