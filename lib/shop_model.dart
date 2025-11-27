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

  /// Загрузить список магазинов из Google Sheets (столбец D) используя CSV экспорт
  static Future<List<Shop>> loadShopsFromGoogleSheets() async {
    try {
      // Используем CSV экспорт с явным указанием диапазона для получения всех строк
      // Пробуем несколько вариантов URL для надежности
      String sheetUrl = 'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Меню&range=D1:D800';
      
      print('📥 Загружаем данные из Google Sheets (CSV экспорт с диапазоном D1:D800)...');
      print('   URL: $sheetUrl');
      
      var response = await http.get(Uri.parse(sheetUrl));
      
      // Если не получилось с диапазоном, пробуем без него, но с запросом только столбца D
      if (response.statusCode != 200 || response.body.isEmpty) {
        print('⚠️ Первый вариант не сработал, пробуем альтернативный...');
        // Используем Google Visualization API Query Language для запроса только столбца D
        sheetUrl = 'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&tq=SELECT%20D&sheet=Меню';
        print('   Альтернативный URL: $sheetUrl');
        response = await http.get(Uri.parse(sheetUrl));
      }
      
      if (response.statusCode != 200) {
        print('❌ Ошибка загрузки: ${response.statusCode}');
        print('   Ответ: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
        throw Exception('Ошибка загрузки данных из Google Sheets: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      print('📊 Всего строк получено из CSV: ${lines.length}');
      
      // Если получили меньше строк, чем ожидалось, предупреждаем
      if (lines.length < 500) {
        print('⚠️ ВНИМАНИЕ: Получено только ${lines.length} строк, ожидалось больше!');
        print('   Это может означать, что CSV экспорт обрезает данные при пустых ячейках.');
        print('   Попробуем загрузить полный диапазон A1:D800...');
        
        // Пробуем загрузить полный диапазон A-D, чтобы получить все строки
        final fullRangeUrl = 'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Меню&range=A1:D800';
        final fullResponse = await http.get(Uri.parse(fullRangeUrl));
        if (fullResponse.statusCode == 200 && fullResponse.body.isNotEmpty) {
          final fullLines = const LineSplitter().convert(fullResponse.body);
          print('📊 При загрузке полного диапазона получено строк: ${fullLines.length}');
          if (fullLines.length > lines.length) {
            print('✅ Используем данные из полного диапазона');
            return _processCsvLines(fullLines);
          }
        }
      }
      
      return _processCsvLines(lines);
    } catch (e) {
      print('⚠️ Ошибка загрузки магазинов из Google Sheets: $e');
      print('Stack trace: ${StackTrace.current}');
      // Возвращаем список по умолчанию при ошибке
      return _getDefaultShops();
    }
  }

  /// Обработать CSV строки и извлечь уникальные адреса магазинов
  static Future<List<Shop>> _processCsvLines(List<String> lines) async {
    final Map<String, String> uniqueAddresses = {}; // Используем Map для сохранения оригинального адреса
    
    int processedRows = 0;
    int emptyRows = 0;
    int headerRows = 0;
    int validAddresses = 0;
    
    // Определяем, сколько столбцов в CSV
    // Если запрашивали только столбец D, то будет 1 столбец (индекс 0)
    // Если запрашивали A-D, то столбец D - это индекс 3
    bool isSingleColumn = false;
    if (lines.isNotEmpty) {
      final firstRow = parseCsvLine(lines[0]);
      isSingleColumn = firstRow.length == 1;
      print('📊 Определено столбцов в CSV: ${firstRow.length} (${isSingleColumn ? "только D" : "A-D"})');
    }
    
    // Парсим CSV
    // Если это один столбец (D), то индекс 0, иначе индекс 3
    final columnIndex = isSingleColumn ? 0 : 3;
    
    // Пропускаем заголовок (первая строка) и обрабатываем все остальные строки
    for (var i = 1; i < lines.length; i++) {
      try {
        final row = parseCsvLine(lines[i]);
        processedRows++;
        
        // Логируем первые несколько строк для отладки
        if (i <= 10) {
          print('📝 Строка $i: колонок = ${row.length}');
          if (row.length > columnIndex) {
            print('   [D] = "${row[columnIndex]}"');
          }
        }
        
        if (row.length > columnIndex) {
          String address = row[columnIndex].trim().replaceAll('"', '').trim();
          
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
              if (i <= 20 || uniqueAddresses.length <= 10) {
                print('✅ Строка $i: добавлен адрес "$address"');
              }
            } else {
              // Логируем дубликаты только для первых строк или первых 10 уникальных
              if (i <= 20 || uniqueAddresses.length <= 10) {
                print('⚠️ Строка $i: дубликат адреса "$address" (уже есть: "${uniqueAddresses[normalizedAddress]}")');
              }
            }
          }
        } else {
          if (i <= 10) {
            print('⚠️ Строка $i: недостаточно колонок (${row.length} <= $columnIndex)');
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

