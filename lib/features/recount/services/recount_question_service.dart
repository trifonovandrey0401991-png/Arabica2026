import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../models/recount_question_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class RecountQuestionService {
  static const String baseEndpoint = '/api/recount-questions';

  /// Получить все вопросы
  static Future<List<RecountQuestion>> getQuestions() async {
    Logger.debug('📥 Загрузка вопросов пересчета с сервера...');

    return await BaseHttpService.getList<RecountQuestion>(
      endpoint: baseEndpoint,
      fromJson: (json) => RecountQuestion.fromJson(json),
      listKey: 'questions',
    );
  }

  /// Создать новый вопрос
  static Future<RecountQuestion?> createQuestion({
    required String question,
    required int grade,
    Map<String, String>? referencePhotos,
  }) async {
    Logger.debug('📤 Создание вопроса пересчета: $question');

    final requestBody = <String, dynamic>{
      'question': question,
      'grade': grade,
    };
    if (referencePhotos != null) requestBody['referencePhotos'] = referencePhotos;

    return await BaseHttpService.post<RecountQuestion>(
      endpoint: baseEndpoint,
      body: requestBody,
      fromJson: (json) => RecountQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Обновить вопрос
  static Future<RecountQuestion?> updateQuestion({
    required String id,
    String? question,
    int? grade,
    Map<String, String>? referencePhotos,
  }) async {
    Logger.debug('📤 Обновление вопроса пересчета: $id');

    final body = <String, dynamic>{};
    if (question != null) body['question'] = question;
    if (grade != null) body['grade'] = grade;
    if (referencePhotos != null) body['referencePhotos'] = referencePhotos;

    return await BaseHttpService.put<RecountQuestion>(
      endpoint: '$baseEndpoint/$id',
      body: body,
      fromJson: (json) => RecountQuestion.fromJson(json),
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

      // Добавляем файл - читаем байты для поддержки веб и мобильных платформ
      final bytes = await photoFile.readAsBytes();

      // Генерируем безопасное имя файла с timestamp
      final filename = 'recount_ref_${questionId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

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
    Logger.debug('📤 Удаление вопроса пересчета: $id');

    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/$id',
    );
  }

  /// Массовая загрузка вопросов (заменяет все существующие)
  static Future<List<RecountQuestion>?> bulkUploadQuestions(
    List<Map<String, dynamic>> questions,
  ) async {
    try {
      Logger.debug('📤 Массовая загрузка вопросов пересчета: ${questions.length} вопросов');

      final requestBody = <String, dynamic>{
        'questions': questions,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}$baseEndpoint/bulk-upload'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(requestBody),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        // Проверяем, что ответ - JSON, а не HTML
        final contentType = response.headers['content-type'] ?? '';
        if (!contentType.contains('application/json')) {
          Logger.error('❌ Сервер вернул не JSON: ${response.body.substring(0, 200)}');
          return null;
        }

        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final questionsJson = result['questions'] as List<dynamic>;
          final createdQuestions = questionsJson
              .map((json) => RecountQuestion.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено вопросов: ${createdQuestions.length}');
          return createdQuestions;
        } else {
          Logger.error('❌ Ошибка массовой загрузки: ${result['error']}');
        }
      } else {
        // Пытаемся распарсить как JSON, если не получается - показываем текст
        try {
          final errorBody = jsonDecode(response.body);
          Logger.error('❌ Ошибка API: statusCode=${response.statusCode}, error=${errorBody['error']}');
        } catch (e) {
          Logger.error('❌ Ошибка API: statusCode=${response.statusCode}, body=${response.body.substring(0, 200)}');
        }
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка массовой загрузки вопросов пересчета', e);
      return null;
    }
  }
}

