import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../models/shift_question_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class ShiftQuestionService {
  static const String baseEndpoint = '/api/shift-questions';

  /// Получить все вопросы
  static Future<List<ShiftQuestion>> getQuestions({String? shopAddress}) async {
    Logger.debug('📥 Загрузка вопросов пересменки с сервера...');
    if (shopAddress != null) {
      Logger.debug('   Фильтр по магазину: $shopAddress');
    }

    return await BaseHttpService.getList<ShiftQuestion>(
      endpoint: baseEndpoint,
      fromJson: (json) => ShiftQuestion.fromJson(json),
      listKey: 'questions',
      queryParams: shopAddress != null ? {'shopAddress': shopAddress} : null,
    );
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
  }) async {
    Logger.debug('📤 Создание вопроса пересменки: $question');

    final requestBody = <String, dynamic>{
      'question': question,
    };
    if (answerFormatB != null) requestBody['answerFormatB'] = answerFormatB;
    if (answerFormatC != null) requestBody['answerFormatC'] = answerFormatC;
    if (shops != null) requestBody['shops'] = shops;
    if (referencePhotos != null) requestBody['referencePhotos'] = referencePhotos;

    return await BaseHttpService.post<ShiftQuestion>(
      endpoint: baseEndpoint,
      body: requestBody,
      fromJson: (json) => ShiftQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Обновить вопрос
  static Future<ShiftQuestion?> updateQuestion({
    required String id,
    String? question,
    String? answerFormatB,
    String? answerFormatC,
    List<String>? shops,
    Map<String, String>? referencePhotos,
  }) async {
    Logger.debug('📤 Обновление вопроса пересменки: $id');

    final body = <String, dynamic>{};
    if (question != null) body['question'] = question;
    if (answerFormatB != null) body['answerFormatB'] = answerFormatB;
    if (answerFormatC != null) body['answerFormatC'] = answerFormatC;
    if (shops != null) body['shops'] = shops;
    if (referencePhotos != null) body['referencePhotos'] = referencePhotos;

    return await BaseHttpService.put<ShiftQuestion>(
      endpoint: '$baseEndpoint/$id',
      body: body,
      fromJson: (json) => ShiftQuestion.fromJson(json),
      itemKey: 'question',
    );
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

      // Добавляем файл
      request.files.add(
        await http.MultipartFile.fromPath('photo', photoFile.path),
      );

      // Добавляем адрес магазина
      request.fields['shopAddress'] = shopAddress;

      final streamedResponse = await request.send().timeout(ApiConstants.longTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final photoUrl = result['photoUrl'] as String;
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

  /// Удалить вопрос
  static Future<bool> deleteQuestion(String id) async {
    Logger.debug('📤 Удаление вопроса пересменки: $id');

    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/$id',
    );
  }
}


