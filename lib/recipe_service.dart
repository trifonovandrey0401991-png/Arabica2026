import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'recipe_model.dart';
import 'core/utils/logger.dart';

class RecipeService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/recipes';

  /// Получить все рецепты
  static Future<List<Recipe>> getRecipes() async {
    try {
      Logger.debug('📥 Загрузка рецептов с сервера...');
      Logger.debug('📥 URL: $baseUrl');
      
      final response = await http.get(
        Uri.parse(baseUrl),
      ).timeout(const Duration(seconds: 15));

      Logger.debug('📥 Ответ сервера: statusCode=${response.statusCode}');
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        Logger.debug('📥 Результат: success=${result['success']}, recipes count=${(result['recipes'] as List<dynamic>?)?.length ?? 0}');
        if (result['success'] == true) {
          final recipesJson = result['recipes'] as List<dynamic>;
          final recipes = recipesJson
              .map((json) => Recipe.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено рецептов: ${recipes.length}');
          return recipes;
        } else {
          Logger.error('❌ Ошибка загрузки рецептов: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}, body=${response.body.substring(0, 200)}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки рецептов', e);
      return [];
    }
  }

  /// Получить рецепт по ID
  static Future<Recipe?> getRecipe(String id) async {
    try {
      Logger.debug('📥 Загрузка рецепта: $id');
      
      final response = await http.get(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return Recipe.fromJson(result['recipe'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки рецепта', e);
      return null;
    }
  }

  /// Создать новый рецепт
  static Future<Recipe?> createRecipe({
    required String name,
    required String category,
    String? price,
    String? ingredients,
    String? steps,
  }) async {
    try {
      Logger.debug('📤 Создание рецепта: $name');
      Logger.debug('📤 URL: $baseUrl');
      
      final requestBody = <String, dynamic>{
        'name': name,
        'category': category,
        'ingredients': ingredients ?? '',
        'steps': steps ?? '',
      };
      if (price != null && price.isNotEmpty) {
        requestBody['price'] = price;
      }
      Logger.debug('📤 Request body: ${jsonEncode(requestBody)}');
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      Logger.debug('📤 Ответ сервера: statusCode=${response.statusCode}');
      Logger.debug('📤 Response body: ${response.body.substring(0, 200)}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Рецепт создан: ${result['recipe']['id']}');
          return Recipe.fromJson(result['recipe'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка создания рецепта: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}, body=${response.body.substring(0, 200)}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания рецепта', e);
      return null;
    }
  }

  /// Обновить рецепт
  static Future<Recipe?> updateRecipe({
    required String id,
    String? name,
    String? category,
    String? price,
    String? ingredients,
    String? steps,
    String? photoUrl,
  }) async {
    try {
      Logger.debug('📤 Обновление рецепта: $id');
      
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (category != null) body['category'] = category;
      if (price != null) body['price'] = price;
      if (ingredients != null) body['ingredients'] = ingredients;
      if (steps != null) body['steps'] = steps;
      if (photoUrl != null) body['photoUrl'] = photoUrl;
      
      final response = await http.put(
        Uri.parse('$baseUrl/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Рецепт обновлен: $id');
          return Recipe.fromJson(result['recipe'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка обновления рецепта: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка обновления рецепта', e);
      return null;
    }
  }

  /// Удалить рецепт
  static Future<bool> deleteRecipe(String id) async {
    try {
      Logger.debug('📤 Удаление рецепта: $id');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Рецепт удален: $id');
          return true;
        } else {
          Logger.error('❌ Ошибка удаления рецепта: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка удаления рецепта', e);
      return false;
    }
  }

  /// Загрузить фото рецепта
  static Future<String?> uploadPhoto({
    required String recipeId,
    required File photoFile,
  }) async {
    try {
      Logger.debug('📤 Загрузка фото для рецепта: $recipeId');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/upload-photo'),
      );
      
      request.fields['recipeId'] = recipeId;
      request.files.add(
        await http.MultipartFile.fromPath('photo', photoFile.path),
      );
      
      final response = await request.send().timeout(
        const Duration(seconds: 30),
      );
      
      final responseBody = await response.stream.bytesToString();
      final result = jsonDecode(responseBody);
      
      if (response.statusCode == 200 && result['success'] == true) {
        final photoUrl = '$serverUrl${result['photoUrl']}';
        Logger.debug('✅ Фото загружено: $photoUrl');
        return photoUrl;
      } else {
        Logger.error('❌ Ошибка загрузки фото: ${result['error']}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки фото', e);
      return null;
    }
  }

  /// Получить URL фото рецепта
  static String getPhotoUrl(String recipeId) {
    return '$serverUrl/api/recipes/photo/$recipeId';
  }
}

