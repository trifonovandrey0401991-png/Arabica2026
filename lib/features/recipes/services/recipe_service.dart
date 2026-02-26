import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'dart:io';
import '../models/recipe_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

// http и dart:convert оставлены для multipart загрузки фото

class RecipeService {
  // Кеш рецептов (5 минут TTL)
  static List<Recipe>? _cache;
  static DateTime? _cacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  /// Получить все рецепты (с кешированием)
  static Future<List<Recipe>> getRecipes({bool forceRefresh = false}) async {
    // Отдаём из кеша если свежий и непустой
    if (!forceRefresh && _cache != null && _cache!.isNotEmpty && _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl) {
      Logger.debug('📥 Рецепты из кеша (${_cache!.length} шт)');
      return _cache!;
    }

    Logger.debug('📥 Загрузка рецептов с сервера...');
    final recipes = await BaseHttpService.getList<Recipe>(
      endpoint: ApiConstants.recipesEndpoint,
      fromJson: (json) => Recipe.fromJson(json),
      listKey: 'recipes',
    );

    // Don't cache empty results — likely a network error, not real empty catalog
    if (recipes.isNotEmpty) {
      _cache = recipes;
      _cacheTime = DateTime.now();
    }
    return recipes;
  }

  /// Сбросить кеш (вызывать после создания/обновления/удаления)
  static void invalidateCache() {
    _cache = null;
    _cacheTime = null;
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
    int? pointsPrice,
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
    if (pointsPrice != null) {
      requestBody['pointsPrice'] = pointsPrice;
    }

    final result = await BaseHttpService.post<Recipe>(
      endpoint: ApiConstants.recipesEndpoint,
      body: requestBody,
      fromJson: (json) => Recipe.fromJson(json),
      itemKey: 'recipe',
    );
    if (result != null) invalidateCache();
    return result;
  }

  /// Обновить рецепт
  static Future<Recipe?> updateRecipe({
    required String id,
    String? name,
    String? category,
    String? price,
    int? pointsPrice,
    String? ingredients,
    String? steps,
    String? photoUrl,
  }) async {
    Logger.debug('📤 Обновление рецепта: $id');

    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (category != null) body['category'] = category;
    if (price != null) body['price'] = price;
    if (pointsPrice != null) body['pointsPrice'] = pointsPrice;
    if (ingredients != null) body['ingredients'] = ingredients;
    if (steps != null) body['steps'] = steps;
    if (photoUrl != null) body['photoUrl'] = photoUrl;

    final result = await BaseHttpService.put<Recipe>(
      endpoint: '${ApiConstants.recipesEndpoint}/$id',
      body: body,
      fromJson: (json) => Recipe.fromJson(json),
      itemKey: 'recipe',
    );
    if (result != null) invalidateCache();
    return result;
  }

  /// Удалить рецепт
  static Future<bool> deleteRecipe(String id) async {
    Logger.debug('📤 Удаление рецепта: $id');

    final result = await BaseHttpService.delete(
      endpoint: '${ApiConstants.recipesEndpoint}/$id',
    );
    if (result) invalidateCache();
    return result;
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

      // Добавляем заголовки авторизации
      if (ApiConstants.apiKey != null && ApiConstants.apiKey!.isNotEmpty) {
        request.headers['X-API-Key'] = ApiConstants.apiKey!;
      }
      if (ApiConstants.sessionToken != null && ApiConstants.sessionToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${ApiConstants.sessionToken}';
      }

      request.fields['recipeId'] = recipeId;

      // Определяем MIME-тип по расширению (fallback: image/jpeg)
      final ext = photoFile.path.split('.').last.toLowerCase();
      final mimeType = ext == 'png' ? MediaType('image', 'png')
          : ext == 'webp' ? MediaType('image', 'webp')
          : MediaType('image', 'jpeg');

      request.files.add(
        await http.MultipartFile.fromPath('photo', photoFile.path, contentType: mimeType),
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

