import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_services.dart';

/// P3 Тесты рецептов для роли СОТРУДНИК
/// Покрывает: Просмотр рецептов, категории, поиск
void main() {
  group('Recipes Tests (P3)', () {
    late MockRecipesService mockRecipesService;

    setUp(() async {
      mockRecipesService = MockRecipesService();
    });

    tearDown(() async {
      mockRecipesService.clear();
    });

    // ==================== СПИСОК РЕЦЕПТОВ ====================

    group('Recipe List Tests', () {
      test('ET-RCP-001: Получение списка рецептов', () async {
        // Act
        final recipes = await mockRecipesService.getRecipes();

        // Assert
        expect(recipes, isA<List>());
      });

      test('ET-RCP-002: Рецепт содержит название и ингредиенты', () async {
        // Arrange
        await mockRecipesService.addRecipe({
          'name': 'Капучино',
          'ingredients': ['Эспрессо', 'Молоко'],
          'steps': ['Налить эспрессо', 'Добавить молоко'],
        });

        // Act
        final recipes = await mockRecipesService.getRecipes();

        // Assert
        expect(recipes.first['name'], 'Капучино');
        expect(recipes.first['ingredients'], isA<List>());
      });

      test('ET-RCP-003: Рецепт содержит пошаговую инструкцию', () async {
        // Arrange
        await mockRecipesService.addRecipe({
          'name': 'Латте',
          'ingredients': ['Эспрессо', 'Молоко'],
          'steps': ['Шаг 1', 'Шаг 2', 'Шаг 3'],
        });

        // Act
        final recipes = await mockRecipesService.getRecipes();

        // Assert
        expect(recipes.first['steps'], isA<List>());
        expect(recipes.first['steps'].length, 3);
      });

      test('ET-RCP-004: Рецепт может содержать фото', () async {
        // Arrange
        await mockRecipesService.addRecipe({
          'name': 'Латте',
          'imageUrl': '/images/latte.jpg',
          'ingredients': [],
          'steps': [],
        });

        // Act
        final recipes = await mockRecipesService.getRecipes();

        // Assert
        expect(recipes.first['imageUrl'], isNotNull);
      });
    });

    // ==================== КАТЕГОРИИ ====================

    group('Categories Tests', () {
      test('ET-RCP-005: Фильтрация по категории "Кофе"', () async {
        // Arrange
        await mockRecipesService.addRecipe({
          'name': 'Эспрессо',
          'category': 'coffee',
          'ingredients': [],
          'steps': [],
        });
        await mockRecipesService.addRecipe({
          'name': 'Чай',
          'category': 'tea',
          'ingredients': [],
          'steps': [],
        });

        // Act
        final coffeeRecipes = await mockRecipesService.getRecipesByCategory('coffee');

        // Assert
        expect(coffeeRecipes.every((r) => r['category'] == 'coffee'), true);
      });

      test('ET-RCP-006: Получение списка категорий', () async {
        // Act
        final categories = await mockRecipesService.getCategories();

        // Assert
        expect(categories, isA<List>());
        expect(categories.contains('coffee'), true);
      });
    });

    // ==================== ПОИСК ====================

    group('Search Tests', () {
      test('ET-RCP-007: Поиск рецепта по названию', () async {
        // Arrange
        await mockRecipesService.addRecipe({
          'name': 'Капучино классический',
          'ingredients': [],
          'steps': [],
        });

        // Act
        final results = await mockRecipesService.searchRecipes('капучино');

        // Assert
        expect(results.isNotEmpty, true);
      });

      test('ET-RCP-008: Поиск по ингредиенту', () async {
        // Arrange
        await mockRecipesService.addRecipe({
          'name': 'Латте',
          'ingredients': ['Эспрессо', 'Овсяное молоко'],
          'steps': [],
        });

        // Act
        final results = await mockRecipesService.searchRecipes('овсяное');

        // Assert
        expect(results.isNotEmpty, true);
      });
    });

    // ==================== ИЗБРАННОЕ ====================

    group('Favorites Tests', () {
      test('ET-RCP-009: Добавление рецепта в избранное', () async {
        // Arrange
        await mockRecipesService.addRecipe({
          'id': 'recipe_001',
          'name': 'Латте',
          'ingredients': [],
          'steps': [],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];

        // Act
        final result = await mockRecipesService.addToFavorites(
          employeeId,
          'recipe_001',
        );

        // Assert
        expect(result['success'], true);
      });

      test('ET-RCP-010: Получение избранных рецептов', () async {
        // Arrange
        await mockRecipesService.addRecipe({
          'id': 'recipe_001',
          'name': 'Латте',
          'ingredients': [],
          'steps': [],
        });
        final employeeId = MockEmployeeData.validEmployee['id'];
        await mockRecipesService.addToFavorites(employeeId, 'recipe_001');

        // Act
        final favorites = await mockRecipesService.getFavorites(employeeId);

        // Assert
        expect(favorites.length, 1);
      });
    });
  });
}

// ==================== MOCK SERVICE ====================

class MockRecipesService {
  final List<Map<String, dynamic>> _recipes = [];
  final Map<String, List<String>> _favorites = {};

  Future<List<Map<String, dynamic>>> getRecipes() async {
    return _recipes;
  }

  Future<void> addRecipe(Map<String, dynamic> recipe) async {
    recipe['id'] ??= 'recipe_${DateTime.now().millisecondsSinceEpoch}';
    _recipes.add(recipe);
  }

  Future<List<Map<String, dynamic>>> getRecipesByCategory(String category) async {
    return _recipes.where((r) => r['category'] == category).toList();
  }

  Future<List<String>> getCategories() async {
    return ['coffee', 'tea', 'dessert', 'smoothie'];
  }

  Future<List<Map<String, dynamic>>> searchRecipes(String query) async {
    final lowerQuery = query.toLowerCase();
    return _recipes.where((r) {
      final name = (r['name'] ?? '').toString().toLowerCase();
      final ingredients = (r['ingredients'] as List?)?.join(' ').toLowerCase() ?? '';
      return name.contains(lowerQuery) || ingredients.contains(lowerQuery);
    }).toList();
  }

  Future<Map<String, dynamic>> addToFavorites(String employeeId, String recipeId) async {
    _favorites.putIfAbsent(employeeId, () => []);
    if (!_favorites[employeeId]!.contains(recipeId)) {
      _favorites[employeeId]!.add(recipeId);
    }
    return {'success': true};
  }

  Future<List<Map<String, dynamic>>> getFavorites(String employeeId) async {
    final favoriteIds = _favorites[employeeId] ?? [];
    return _recipes.where((r) => favoriteIds.contains(r['id'])).toList();
  }

  void clear() {
    _recipes.clear();
    _favorites.clear();
  }
}
