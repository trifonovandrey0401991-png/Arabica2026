import 'package:http/http.dart' as http;
import 'dart:convert';
import 'recipe_service.dart';
import 'utils/logger.dart';

class Recipe {
  final String id;
  final String name;        // Название напитка
  final String category;    // Категория напитка
  final String? photoUrl;   // URL фото (вместо photoId)
  final String? photoId;    // Старое поле для обратной совместимости
  final String ingredients; // Ингредиенты
  final String steps;       // Последовательность приготовления
  final String? recipe;     // Старое поле (рецепт) для обратной совместимости
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Recipe({
    required this.id,
    required this.name,
    required this.category,
    this.photoUrl,
    this.photoId,
    required this.ingredients,
    required this.steps,
    this.recipe,
    this.createdAt,
    this.updatedAt,
  });

  /// Создать из JSON (с сервера)
  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      photoUrl: json['photoUrl'],
      photoId: json['photoId'], // Для обратной совместимости
      ingredients: json['ingredients'] ?? '',
      steps: json['steps'] ?? '',
      recipe: json['recipe'], // Для обратной совместимости
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : null,
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt']) 
          : null,
    );
  }

  /// Преобразовать в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'photoUrl': photoUrl,
      'ingredients': ingredients,
      'steps': steps,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  /// Получить URL фото (приоритет: photoUrl, затем photoId из assets)
  String? get photoUrlOrId {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      // Если это полный URL, возвращаем как есть
      if (photoUrl!.startsWith('http')) {
        return photoUrl;
      }
      // Если это относительный путь, добавляем базовый URL
      return 'https://arabica26.ru$photoUrl';
    }
    // Для обратной совместимости с photoId
    return photoId;
  }

  /// Получить текст рецепта (для обратной совместимости)
  String get recipeText {
    if (steps.isNotEmpty) {
      return steps;
    }
    // Для обратной совместимости
    return recipe ?? '';
  }

  /// Загрузить рецепты с сервера
  static Future<List<Recipe>> loadRecipesFromServer() async {
    return await RecipeService.getRecipes();
  }

  /// Загрузить рецепты из Google Sheets (старый метод, для обратной совместимости)
  static Future<List<Recipe>> loadRecipesFromGoogleSheets() async {
    try {
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Меню';
      
      Logger.debug('📥 Загружаем рецепты из Google Sheets...');
      
      final response = await http.get(Uri.parse(sheetUrl));
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки данных: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      Logger.debug('📊 Получено строк из CSV: ${lines.length}');
      
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
          Logger.debug('⚠️ Ошибка парсинга строки $i: $e');
        }
      }
      
      final recipes = uniqueRecipes.values.toList();
      Logger.debug('✅ Загружено рецептов: ${recipes.length}');
      
      return recipes;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки рецептов', e);
      return [];
    }
  }

  /// Создать из CSV строки (для обратной совместимости)
  factory Recipe.fromCsvRow(List<String> row) {
    return Recipe(
      id: 'csv_${row.length > 0 ? row[0].trim().hashCode : DateTime.now().millisecondsSinceEpoch}',
      name: row.length > 0 ? row[0].trim() : '',
      category: row.length > 2 ? row[2].trim() : '',
      photoId: row.length > 5 && row[5].trim().isNotEmpty 
          ? row[5].trim() 
          : null,
      ingredients: '', // В CSV нет отдельного поля для ингредиентов
      steps: row.length > 6 ? row[6].trim() : '',
      recipe: row.length > 6 ? row[6].trim() : '', // Для обратной совместимости
    );
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
    final recipes = await loadRecipesFromServer();
    final categories = recipes
        .map((r) => r.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }
}
