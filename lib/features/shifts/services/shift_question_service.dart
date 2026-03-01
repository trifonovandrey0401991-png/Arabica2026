import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../models/shift_question_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';

// http и dart:convert оставлены для multipart загрузки эталонных фото

class ShiftQuestionService {
  static const String baseEndpoint = ApiConstants.shiftQuestionsEndpoint;
  static const String _cachePrefix = 'shift_questions';

  /// Получить все вопросы (с кэшем)
  static Future<List<ShiftQuestion>> getQuestions({String? shopAddress}) async {
    final cacheKey = '${_cachePrefix}_${shopAddress ?? 'all'}';
    final cached = CacheManager.get<List<ShiftQuestion>>(cacheKey);
    if (cached != null) {
      Logger.debug('📦 Вопросы пересменки из кэша: ${cached.length}');
      return cached;
    }

    Logger.debug('📥 Загрузка вопросов пересменки с сервера...');
    if (shopAddress != null) {
      Logger.debug('   Фильтр по магазину: $shopAddress');
    }

    final questions = await BaseHttpService.getList<ShiftQuestion>(
      endpoint: baseEndpoint,
      fromJson: (json) => ShiftQuestion.fromJson(json),
      listKey: 'questions',
      queryParams: shopAddress != null ? {'shopAddress': shopAddress} : null,
    );
    CacheManager.set(cacheKey, questions);
    return questions;
  }

  /// Сбросить кэш вопросов
  static void invalidateCache() {
    CacheManager.clearByPattern(_cachePrefix);
  }
  
  /// Получить один вопрос по ID
  static Future<ShiftQuestion?> getQuestion(String questionId) async {
    Logger.debug('📥 Загрузка вопроса пересменки: $questionId');

    return await BaseHttpService.get<ShiftQuestion>(
      endpoint: '$baseEndpoint/$questionId',
      fromJson: (json) => ShiftQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Создать новый вопрос
  static Future<ShiftQuestion?> createQuestion({
    required String question,
    String? answerFormatB,
    String? answerFormatC,
    List<String>? shops,
    Map<String, String>? referencePhotos,
    bool? isAiCheck,
  }) async {
    Logger.debug('📤 Создание вопроса пересменки: $question');

    final requestBody = <String, dynamic>{
      'question': question,
    };
    if (answerFormatB != null) requestBody['answerFormatB'] = answerFormatB;
    if (answerFormatC != null) requestBody['answerFormatC'] = answerFormatC;
    if (shops != null) requestBody['shops'] = shops;
    if (referencePhotos != null) requestBody['referencePhotos'] = referencePhotos;
    if (isAiCheck != null) requestBody['isAiCheck'] = isAiCheck;

    final result = await BaseHttpService.post<ShiftQuestion>(
      endpoint: baseEndpoint,
      body: requestBody,
      fromJson: (json) => ShiftQuestion.fromJson(json),
      itemKey: 'question',
    );
    if (result != null) invalidateCache();
    return result;
  }

  /// Обновить вопрос
  static Future<ShiftQuestion?> updateQuestion({
    required String id,
    String? question,
    String? answerFormatB,
    String? answerFormatC,
    List<String>? shops,
    Map<String, String>? referencePhotos,
    bool? isAiCheck,
  }) async {
    Logger.debug('📤 Обновление вопроса пересменки: $id');

    final body = <String, dynamic>{};
    if (question != null) body['question'] = question;
    if (answerFormatB != null) body['answerFormatB'] = answerFormatB;
    if (answerFormatC != null) body['answerFormatC'] = answerFormatC;
    if (shops != null) body['shops'] = shops;
    if (referencePhotos != null) body['referencePhotos'] = referencePhotos;
    if (isAiCheck != null) body['isAiCheck'] = isAiCheck;

    final result = await BaseHttpService.put<ShiftQuestion>(
      endpoint: '$baseEndpoint/$id',
      body: body,
      fromJson: (json) => ShiftQuestion.fromJson(json),
      itemKey: 'question',
    );
    if (result != null) invalidateCache();
    return result;
  }

  /// Загрузить эталонное фото для вопроса
  static Future<String?> uploadReferencePhoto({
    required String questionId,
    required String shopAddress,
    required File photoFile,
  }) async {
    try {
      Logger.debug('📤 Загрузка эталонного фото для вопроса: $questionId, магазин: $shopAddress');

      final url = '${ApiConstants.serverUrl}$baseEndpoint/$questionId/reference-photo';
      final request = http.MultipartRequest('POST', Uri.parse(url));

      // Добавляем заголовки авторизации
      if (ApiConstants.apiKey != null && ApiConstants.apiKey!.isNotEmpty) {
        request.headers['X-API-Key'] = ApiConstants.apiKey!;
      }
      if (ApiConstants.sessionToken != null && ApiConstants.sessionToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${ApiConstants.sessionToken}';
      }

      // Добавляем файл - читаем байты для поддержки веб и мобильных платформ
      final bytes = await photoFile.readAsBytes();

      // Генерируем безопасное имя файла с timestamp
      final filename = 'shift_ref_${questionId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: filename,
        ),
      );

      // Добавляем адрес магазина
      request.fields['shopAddress'] = shopAddress;

      final streamedResponse = await request.send().timeout(ApiConstants.longTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          String photoUrl = result['photoUrl'] as String;

          // Если URL относительный, делаем его абсолютным
          if (!photoUrl.startsWith('http://') && !photoUrl.startsWith('https://')) {
            // Убираем начальный слеш если есть
            if (photoUrl.startsWith('/')) {
              photoUrl = '${ApiConstants.serverUrl}$photoUrl';
            } else {
              photoUrl = '${ApiConstants.serverUrl}/$photoUrl';
            }
            Logger.debug('📝 Преобразован относительный URL в абсолютный: $photoUrl');
          }

          Logger.debug('✅ Эталонное фото загружено: $photoUrl');
          return photoUrl;
        } else {
          Logger.error('❌ Ошибка загрузки эталонного фото: ${result['error']}');
        }
      } else {
        Logger.error('❌ HTTP ${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка загрузки эталонного фото', e);
      return null;
    }
  }

  /// Изменить порядок вопросов (массовое обновление order)
  static Future<bool> reorderQuestions(List<Map<String, dynamic>> orders) async {
    Logger.debug('📤 Обновление порядка вопросов: ${orders.length} шт.');

    final result = await BaseHttpService.simplePatch(
      endpoint: '$baseEndpoint/reorder',
      body: {'orders': orders},
    );
    if (result) invalidateCache();
    return result;
  }

  /// Удалить вопрос
  static Future<bool> deleteQuestion(String id) async {
    Logger.debug('📤 Удаление вопроса пересменки: $id');

    final result = await BaseHttpService.delete(
      endpoint: '$baseEndpoint/$id',
    );
    if (result) invalidateCache();
    return result;
  }
}

