import 'package:http/http.dart' as http;
import 'dart:convert';

class Recipe {
  final String name;        // Столбец A
  final String category;    // Столбец C
  final String? photoId;    // Столбец F (ID фото, как в меню)
  final String recipe;      // Столбец G

  Recipe({
    required this.name,
    required this.category,
    this.photoId,
    required this.recipe,
  });

  factory Recipe.fromCsvRow(List<String> row) {
    return Recipe(
      name: row.length > 0 ? row[0].trim() : '',
      category: row.length > 2 ? row[2].trim() : '',
      photoId: row.length > 5 && row[5].trim().isNotEmpty 
          ? row[5].trim() 
          : null,
      recipe: row.length > 6 ? row[6].trim() : '',
    );
  }

  /// Загрузить рецепты из Google Sheets
  static Future<List<Recipe>> loadRecipesFromGoogleSheets() async {
    try {
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Меню';
      
      print('📥 Загружаем рецепты из Google Sheets...');
      
      final response = await http.get(Uri.parse(sheetUrl));
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки данных: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      print('📊 Получено строк из CSV: ${lines.length}');
      
      final Map<String, Recipe> uniqueRecipes = {}; // Для удаления дубликатов по названию
      
      // Парсим CSV, пропускаем заголовок (строка 0)
      for (var i = 1; i < lines.length; i++) {
        try {
          final row = _parseCsvLine(lines[i]);
          
          // Проверяем, что есть рецепт (столбец G не пустой)
          if (row.length > 6 && row[6].trim().isNotEmpty) {
            final recipe = Recipe.fromCsvRow(row);
            
            // Пропускаем, если название пустое
            if (recipe.name.isEmpty) continue;
            
            // Удаляем дубликаты по названию (столбец A)
            final normalizedName = recipe.name.toLowerCase().trim();
            if (!uniqueRecipes.containsKey(normalizedName)) {
              uniqueRecipes[normalizedName] = recipe;
            }
          }
        } catch (e) {
          print('⚠️ Ошибка парсинга строки $i: $e');
        }
      }
      
      final recipes = uniqueRecipes.values.toList();
      print('✅ Загружено рецептов: ${recipes.length}');
      
      return recipes;
    } catch (e) {
      print('❌ Ошибка загрузки рецептов: $e');
      return [];
    }
  }

  /// Парсинг CSV строки с учетом кавычек
  static List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    bool inQuotes = false;
    String currentField = '';

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(currentField);
        currentField = '';
      } else {
        currentField += char;
      }
    }
    result.add(currentField);
    
    return result;
  }

  /// Получить уникальные категории
  static Future<List<String>> getUniqueCategories() async {
    final recipes = await loadRecipesFromGoogleSheets();
    final categories = recipes.map((r) => r.category).where((c) => c.isNotEmpty).toSet().toList();
    categories.sort();
    return categories;
  }
}










