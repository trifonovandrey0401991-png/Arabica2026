import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../models/recipe_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class RecipeService {
  /// Получить все рецепты
  static Future<List<Recipe>> getRecipes() async {
    Logger.debug('📥 Загрузка рецептов с сервера...');

    return await BaseHttpService.getList<Recipe>(
      endpoint: ApiConstants.recipesEndpoint,
      fromJson: (json) => Recipe.fromJson(json),
      listKey: 'recipes',
    );
  }

  /// Получить рецепт по ID
  static Future<Recipe?> getRecipe(String id) async {
    Logger.debug('📥 Загрузка рецепта: $id');

    return await BaseHttpService.get<Recipe>(
      endpoint: '${ApiConstants.recipesEndpoint}/$id',
      fromJson: (json) => Recipe.fromJson(json),
      itemKey: 'recipe',
    );
  }

  /// Создать новый рецепт
  static Future<Recipe?> createRecipe({
    required String name,
    required String category,
    String? price,
    String? ingredients,
    String? steps,
  }) async {
    Logger.debug('📤 Создание рецепта: $name');

    final requestBody = <String, dynamic>{
      'name': name,
      'category': category,
      'ingredients': ingredients ?? '',
      'steps': steps ?? '',
    };
    if (price != null && price.isNotEmpty) {
      requestBody['price'] = price;
    }

    return await BaseHttpService.post<Recipe>(
      endpoint: ApiConstants.recipesEndpoint,
      body: requestBody,
      fromJson: (json) => Recipe.fromJson(json),
      itemKey: 'recipe',
    );
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
    Logger.debug('📤 Обновление рецепта: $id');

    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (category != null) body['category'] = category;
    if (price != null) body['price'] = price;
    if (ingredients != null) body['ingredients'] = ingredients;
    if (steps != null) body['steps'] = steps;
    if (photoUrl != null) body['photoUrl'] = photoUrl;

    return await BaseHttpService.put<Recipe>(
      endpoint: '${ApiConstants.recipesEndpoint}/$id',
      body: body,
      fromJson: (json) => Recipe.fromJson(json),
      itemKey: 'recipe',
    );
  }

  /// Удалить рецепт
  static Future<bool> deleteRecipe(String id) async {
    Logger.debug('📤 Удаление рецепта: $id');

    return await BaseHttpService.delete(
      endpoint: '${ApiConstants.recipesEndpoint}/$id',
    );
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
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.recipesEndpoint}/upload-photo'),
      );

      request.fields['recipeId'] = recipeId;
      request.files.add(
        await http.MultipartFile.fromPath('photo', photoFile.path),
      );

      final response = await request.send().timeout(ApiConstants.longTimeout);

      final responseBody = await response.stream.bytesToString();
      final result = jsonDecode(responseBody);

      if (response.statusCode == 200 && result['success'] == true) {
        final photoUrl = '${ApiConstants.serverUrl}${result['photoUrl']}';
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
    return '${ApiConstants.serverUrl}${ApiConstants.recipesEndpoint}/photo/$recipeId';
  }
}

