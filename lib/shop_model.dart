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

  /// Загрузить список магазинов из Google Sheets (столбец D)
  static Future<List<Shop>> loadShopsFromGoogleSheets() async {
    try {
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Меню';
      
      print('📥 Загружаем адреса магазинов из Google Sheets...');
      print('   URL: $sheetUrl');
      
      final response = await http.get(Uri.parse(sheetUrl));
      if (response.statusCode != 200) {
        print('❌ Ошибка загрузки: ${response.statusCode}');
        throw Exception('Ошибка загрузки данных из Google Sheets: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      print('📊 Всего строк получено из CSV: ${lines.length}');
      
      final Map<String, String> uniqueAddresses = {}; // Используем Map для сохранения оригинального адреса
      int processedRows = 0;
      int emptyRows = 0;
      int validAddresses = 0;
      
      // Парсим CSV, столбец D - это индекс 3 (A=0, B=1, C=2, D=3)
      for (var i = 1; i < lines.length; i++) {
        try {
          // Правильный парсинг CSV с учетом кавычек
          final row = _parseCsvLine(lines[i]);
          processedRows++;
          
          if (row.length > 3) {
            String address = row[3].trim().replaceAll('"', '').trim();
            
            // Пропускаем пустые адреса и заголовки
            if (address.isEmpty) {
              emptyRows++;
            } else if (address.toLowerCase() != 'адрес' && 
                       address.toLowerCase() != 'address' &&
                       !address.toLowerCase().startsWith('столбец')) {
              validAddresses++;
              
              // Нормализуем адрес для сравнения (убираем лишние пробелы)
              String normalizedAddress = address.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
              
              // Сохраняем оригинальный адрес (первое вхождение)
              if (!uniqueAddresses.containsKey(normalizedAddress)) {
                uniqueAddresses[normalizedAddress] = address;
                print('✅ Строка $i: добавлен новый адрес "$address"');
              }
            }
          } else if (i <= 10) {
            print('⚠️ Строка $i: недостаточно колонок (${row.length} < 4)');
          }
        } catch (e) {
          print('❌ Ошибка парсинга строки $i: $e');
        }
      }

      print('📊 Статистика обработки:');
      print('   Обработано строк: $processedRows');
      print('   Пустых адресов: $emptyRows');
      print('   Валидных адресов: $validAddresses');
      print('   Уникальных адресов: ${uniqueAddresses.length}');
      
      print('📋 Найдено уникальных адресов: ${uniqueAddresses.length}');
      for (var addr in uniqueAddresses.values) {
        print('  - $addr');
      }

      // Создаем список магазинов из уникальных адресов
      final shops = <Shop>[];
      int shopIndex = 0;
      final icons = [
        Icons.store,
        Icons.store_mall_directory,
        Icons.local_cafe,
        Icons.coffee,
        Icons.restaurant,
        Icons.shopping_bag,
        Icons.bakery_dining,
        Icons.local_dining,
      ];

      for (var address in uniqueAddresses.values) {
        // Извлекаем название магазина из адреса
        String shopName = _extractShopName(address);
        shops.add(Shop(
          name: shopName,
          address: address, // Используем оригинальный адрес
          icon: shopIndex < icons.length ? icons[shopIndex] : Icons.store,
        ));
        shopIndex++;
      }

      // Сортируем по адресу
      shops.sort((a, b) => a.address.compareTo(b.address));

      print('✅ Загружено магазинов: ${shops.length}');
      return shops;
    } catch (e) {
      print('⚠️ Ошибка загрузки магазинов из Google Sheets: $e');
      print('Stack trace: ${StackTrace.current}');
      // Возвращаем список по умолчанию при ошибке
      return _getDefaultShops();
    }
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

