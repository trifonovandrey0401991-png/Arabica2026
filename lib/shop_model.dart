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

  /// Загрузить список магазинов из Google Sheets (столбец D) используя Google Sheets API
  static Future<List<Shop>> loadShopsFromGoogleSheets() async {
    try {
      const spreadsheetId = '1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU';
      const sheetName = 'Меню';
      const range = 'D1:D800'; // Столбец D, строки 1-800
      
      // Используем Google Sheets API v4 (публичный доступ)
      final apiUrl = Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$sheetName!$range'
      );
      
      print('📥 Загружаем данные из Google Sheets API (диапазон D1:D800)...');
      print('   URL: $apiUrl');
      
      final response = await http.get(apiUrl);
      if (response.statusCode != 200) {
        print('❌ Ошибка API: ${response.statusCode}');
        print('   Ответ: ${response.body}');
        throw Exception('Ошибка загрузки данных из Google Sheets API: ${response.statusCode}');
      }

      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final values = jsonData['values'] as List<dynamic>?;
      
      if (values == null || values.isEmpty) {
        throw Exception('Нет данных в ответе API');
      }

      print('📊 Всего строк получено из API: ${values.length}');
      
      final Map<String, String> uniqueAddresses = {}; // Используем Map для сохранения оригинального адреса
      
      int processedRows = 0;
      int emptyRows = 0;
      int headerRows = 0;
      int validAddresses = 0;
      final targetRows = 800;
      
      // Обрабатываем все строки до 800
      final rowsToProcess = values.length > targetRows ? targetRows : values.length;
      print('📊 Обрабатываем строки с 1 по $rowsToProcess (целевое: $targetRows)');
      
      for (var i = 0; i < rowsToProcess; i++) {
        try {
          final row = values[i] as List<dynamic>?;
          processedRows++;
          
          // Логируем первые несколько строк для отладки
          if (i < 10) {
            print('📝 Строка ${i + 1}: колонок = ${row?.length ?? 0}');
            if (row != null && row.isNotEmpty) {
              print('   [D] = "${row[0]}"');
            }
          }
          
          if (row != null && row.isNotEmpty) {
            String address = (row[0] ?? '').toString().trim();
            
            // Проверяем, является ли это заголовком
            if (address.toLowerCase() == 'адрес' || 
                address.toLowerCase() == 'address' ||
                address.toLowerCase() == 'd' ||
                address.toLowerCase().startsWith('столбец')) {
              headerRows++;
              if (i < 10) {
                print('⚠️ Строка ${i + 1}: заголовок - "$address"');
              }
              continue;
            }
            
            // Обрабатываем все адреса, включая пустые (для статистики)
            if (address.isEmpty) {
              emptyRows++;
              if (i < 10) {
                print('⚠️ Строка ${i + 1}: пустой адрес');
              }
            } else {
              validAddresses++;
              
              // Нормализуем адрес для сравнения (убираем лишние пробелы, но сохраняем регистр для отображения)
              String normalizedAddress = address.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
              
              // Сохраняем оригинальный адрес (первое вхождение)
              if (!uniqueAddresses.containsKey(normalizedAddress)) {
                uniqueAddresses[normalizedAddress] = address;
                print('✅ Строка ${i + 1}: добавлен адрес "$address"');
              } else {
                // Логируем дубликаты
                print('⚠️ Строка ${i + 1}: дубликат адреса "$address" (уже есть: "${uniqueAddresses[normalizedAddress]}")');
              }
            }
          } else {
            emptyRows++;
            if (i < 10) {
              print('⚠️ Строка ${i + 1}: пустая строка');
            }
          }
        } catch (e) {
          print('❌ Ошибка обработки строки ${i + 1}: $e');
        }
      }
      
      print('📊 Статистика обработки:');
      print('   Обработано строк: $processedRows из $rowsToProcess');
      print('   Пустых адресов: $emptyRows');
      print('   Заголовков: $headerRows');
      print('   Валидных адресов: $validAddresses');
      print('   Уникальных адресов: ${uniqueAddresses.length}');
      
      // Если получили меньше строк, чем ожидали, предупреждаем
      if (values.length < targetRows) {
        print('');
        print('⚠️ ВАЖНО: Получено меньше строк, чем запрошено!');
        print('   Запрошено: $targetRows строк');
        print('   Получено: ${values.length} строк');
        print('   Это может означать, что в таблице нет данных до строки $targetRows');
        print('   или таблица не публичная (нужен доступ "Все, у кого есть ссылка")');
        print('');
      }

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

