import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Модель магазина
class Shop {
  final String name;
  final String address;
  final IconData icon;

  Shop({
    required this.name,
    required this.address,
    required this.icon,
  });

  /// Получить иконку по названию магазина
  static IconData _getIconForShop(String shopName) {
    final name = shopName.toLowerCase();
    if (name.contains('пятигорск')) return Icons.store;
    if (name.contains('ессентуки')) return Icons.store_mall_directory;
    if (name.contains('кисловодск')) return Icons.local_cafe;
    if (name.contains('железноводск')) return Icons.coffee;
    if (name.contains('минеральные')) return Icons.restaurant;
    if (name.contains('ставрополь')) return Icons.shopping_bag;
    return Icons.store; // По умолчанию
  }

  /// Загрузить список магазинов из Google Sheets (столбец D)
  static Future<List<Shop>> loadShopsFromGoogleSheets() async {
    try {
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Меню';
      
      final response = await http.get(Uri.parse(sheetUrl));
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки данных из Google Sheets: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      final Set<String> uniqueAddresses = {};
      
      // Парсим CSV, столбец D - это индекс 3
      for (var i = 1; i < lines.length; i++) {
        // Правильный парсинг CSV с учетом кавычек
        final row = _parseCsvLine(lines[i]);
        if (row.length > 3) {
          String address = row[3].trim().replaceAll('"', '').trim();
          if (address.isNotEmpty && address != 'Адрес') {
            uniqueAddresses.add(address);
          }
        }
      }

      // Создаем список магазинов из уникальных адресов
      final shops = <Shop>[];
      for (var address in uniqueAddresses) {
        // Извлекаем название магазина из адреса или используем адрес как название
        String shopName = _extractShopName(address);
        shops.add(Shop(
          name: shopName,
          address: address,
          icon: _getIconForShop(shopName),
        ));
      }

      // Сортируем по названию
      shops.sort((a, b) => a.name.compareTo(b.name));

      return shops;
    } catch (e) {
      print('⚠️ Ошибка загрузки магазинов из Google Sheets: $e');
      // Возвращаем список по умолчанию при ошибке
      return _getDefaultShops();
    }
  }

  /// Парсинг CSV строки с учетом кавычек
  static List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    String current = '';
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current);
        current = '';
      } else {
        current += char;
      }
    }
    result.add(current);
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

  /// Получить список магазинов по умолчанию (fallback)
  static List<Shop> _getDefaultShops() {
    return [
      Shop(
        name: 'Арабика Пятигорск',
        address: 'г. Пятигорск, ул. Ленина, 10',
        icon: Icons.store,
      ),
      Shop(
        name: 'Арабика Ессентуки',
        address: 'г. Ессентуки, ул. Мира, 5',
        icon: Icons.store_mall_directory,
      ),
    ];
  }
}

