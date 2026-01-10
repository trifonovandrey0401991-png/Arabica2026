import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../models/shift_handover_question_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

// http и dart:convert оставлены для multipart загрузки эталонных фото

class ShiftHandoverQuestionService {
  static const String baseEndpoint = ApiConstants.shiftHandoverQuestionsEndpoint;

  /// Получить все вопросы
  static Future<List<ShiftHandoverQuestion>> getQuestions({String? shopAddress}) async {
    Logger.debug('📥 Загрузка вопросов сдачи смены с сервера...');
    if (shopAddress != null) {
      Logger.debug('   Фильтр по магазину: $shopAddress');
    }

    return await BaseHttpService.getList<ShiftHandoverQuestion>(
      endpoint: baseEndpoint,
      fromJson: (json) => ShiftHandoverQuestion.fromJson(json),
      listKey: 'questions',
      queryParams: shopAddress != null ? {'shopAddress': shopAddress} : null,
    );
  }

  /// Получить один вопрос по ID
  static Future<ShiftHandoverQuestion?> getQuestion(String questionId) async {
    Logger.debug('📥 Загрузка вопроса сдачи смены: $questionId');

    return await BaseHttpService.get<ShiftHandoverQuestion>(
      endpoint: '$baseEndpoint/$questionId',
      fromJson: (json) => ShiftHandoverQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Создать новый вопрос
  static Future<ShiftHandoverQuestion?> createQuestion({
    required String question,
    String? answerFormatB,
    String? answerFormatC,
    List<String>? shops,
    Map<String, String>? referencePhotos,
    String? targetRole,
  }) async {
    Logger.debug('📤 Создание вопроса сдачи смены: $question');

    final requestBody = <String, dynamic>{
      'question': question,
    };
    if (answerFormatB != null) requestBody['answerFormatB'] = answerFormatB;
    if (answerFormatC != null) requestBody['answerFormatC'] = answerFormatC;
    if (shops != null) requestBody['shops'] = shops;
    if (referencePhotos != null) requestBody['referencePhotos'] = referencePhotos;
    if (targetRole != null) requestBody['targetRole'] = targetRole;

    return await BaseHttpService.post<ShiftHandoverQuestion>(
      endpoint: baseEndpoint,
      body: requestBody,
      fromJson: (json) => ShiftHandoverQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Обновить вопрос
  static Future<ShiftHandoverQuestion?> updateQuestion({
    required String id,
    String? question,
    String? answerFormatB,
    String? answerFormatC,
    List<String>? shops,
    Map<String, String>? referencePhotos,
    String? targetRole,
  }) async {
    Logger.debug('📤 Обновление вопроса сдачи смены: $id');

    final body = <String, dynamic>{};
    if (question != null) body['question'] = question;
    if (answerFormatB != null) body['answerFormatB'] = answerFormatB;
    if (answerFormatC != null) body['answerFormatC'] = answerFormatC;
    if (shops != null) body['shops'] = shops;
    if (referencePhotos != null) body['referencePhotos'] = referencePhotos;
    if (targetRole != null) body['targetRole'] = targetRole;

    return await BaseHttpService.put<ShiftHandoverQuestion>(
      endpoint: '$baseEndpoint/$id',
      body: body,
      fromJson: (json) => ShiftHandoverQuestion.fromJson(json),
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

      // Добавляем файл - поддержка веб и мобильных платформ
      final bytes = await photoFile.readAsBytes();

      // Генерируем безопасное имя файла
      final filename = 'ref_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';

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

  /// Удалить вопрос
  static Future<bool> deleteQuestion(String id) async {
    Logger.debug('📤 Удаление вопроса сдачи смены: $id');

    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/$id',
    );
  }
}
