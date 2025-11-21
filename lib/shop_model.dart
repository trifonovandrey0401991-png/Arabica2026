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
      // Используем URL с указанием диапазона до 800 строки
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Меню&range=A1:D800';
      
      print('📥 Загружаем данные из Google Sheets (диапазон A1:D800)...');
      final response = await http.get(Uri.parse(sheetUrl));
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки данных из Google Sheets: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      final Map<String, String> uniqueAddresses = {}; // Используем Map для сохранения оригинального адреса
      
      print('📊 Всего строк получено из CSV: ${lines.length}');
      
      // Обрабатываем до 800 строки (индекс 0-799, но пропускаем заголовок, так что 1-800)
      // Если пришло меньше строк, обрабатываем все
      final maxRows = lines.length;
      final targetRows = 800;
      print('📊 Обрабатываем строки с 1 по ${maxRows > targetRows ? targetRows : maxRows} (целевое: $targetRows)');
      
      // Если пришло меньше 800 строк, это может означать, что Google Sheets не возвращает пустые строки
      if (maxRows < targetRows) {
        print('⚠️ Внимание: получено только $maxRows строк вместо $targetRows');
        print('   Google Sheets CSV может не возвращать пустые строки');
        print('   Попробуем альтернативный способ загрузки...');
      }
      
      int processedRows = 0;
      int emptyRows = 0;
      int headerRows = 0;
      int validAddresses = 0;
      
      // Парсим CSV, столбец D - это индекс 3 (A=0, B=1, C=2, D=3)
      // Обрабатываем все строки, которые пришли, но не более 800
      final rowsToProcess = maxRows > targetRows ? targetRows : maxRows;
      for (var i = 1; i < rowsToProcess; i++) {
        try {
          // Правильный парсинг CSV с учетом кавычек
          final row = parseCsvLine(lines[i]);
          processedRows++;
          
          // Логируем первые несколько строк для отладки
          if (i <= 10) {
            print('📝 Строка $i: колонок = ${row.length}');
            if (row.length > 3) {
              print('   [D] = "${row[3]}"');
            }
          }
          
          if (row.length > 3) {
            String address = row[3].trim().replaceAll('"', '').trim();
            
            // Проверяем, является ли это заголовком
            if (address.toLowerCase() == 'адрес' || 
                address.toLowerCase() == 'address' ||
                address.toLowerCase() == 'd' ||
                address.toLowerCase().startsWith('столбец')) {
              headerRows++;
              if (i <= 10) {
                print('⚠️ Строка $i: заголовок - "$address"');
              }
              continue;
            }
            
            // Обрабатываем все адреса, включая пустые (для статистики)
            if (address.isEmpty) {
              emptyRows++;
              if (i <= 10) {
                print('⚠️ Строка $i: пустой адрес');
              }
            } else {
              validAddresses++;
              
              // Нормализуем адрес для сравнения (убираем лишние пробелы, но сохраняем регистр для отображения)
              String normalizedAddress = address.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
              
              // Сохраняем оригинальный адрес (первое вхождение)
              if (!uniqueAddresses.containsKey(normalizedAddress)) {
                uniqueAddresses[normalizedAddress] = address;
                print('✅ Строка $i: добавлен адрес "$address"');
              } else {
                // Логируем дубликаты
                print('⚠️ Строка $i: дубликат адреса "$address" (уже есть: "${uniqueAddresses[normalizedAddress]}")');
              }
            }
          } else {
            if (i <= 10) {
              print('⚠️ Строка $i: недостаточно колонок (${row.length} < 4)');
            }
          }
        } catch (e) {
          print('❌ Ошибка парсинга строки $i: $e');
        }
      }
      
      print('📊 Статистика обработки:');
      print('   Обработано строк: $processedRows');
      print('   Пустых адресов: $emptyRows');
      print('   Заголовков: $headerRows');
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
  static List<String> parseCsvLine(String line) {
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

