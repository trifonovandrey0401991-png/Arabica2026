import '../services/recipe_service.dart';

class Recipe {
  final String id;
  final String name;        // Название напитка
  final String category;    // Категория напитка
  final String? photoUrl;   // URL фото (вместо photoId)
  final String? photoId;    // Старое поле для обратной совместимости
  final String ingredients; // Ингредиенты
  final String steps;       // Последовательность приготовления
  final String? recipe;     // Старое поле (рецепт) для обратной совместимости
  final String? price;      // Цена напитка
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
    this.price,
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
      price: json['price'],
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
      'price': price,
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
