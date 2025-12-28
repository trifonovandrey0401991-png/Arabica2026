import 'package:http/http.dart' as http;
import 'dart:convert';
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
  }) async {
    Logger.debug('📤 Создание вопроса пересчета: $question');

    return await BaseHttpService.post<RecountQuestion>(
      endpoint: baseEndpoint,
      body: {
        'question': question,
        'grade': grade,
      },
      fromJson: (json) => RecountQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Обновить вопрос
  static Future<RecountQuestion?> updateQuestion({
    required String id,
    String? question,
    int? grade,
  }) async {
    Logger.debug('📤 Обновление вопроса пересчета: $id');

    final body = <String, dynamic>{};
    if (question != null) body['question'] = question;
    if (grade != null) body['grade'] = grade;

    return await BaseHttpService.put<RecountQuestion>(
      endpoint: '$baseEndpoint/$id',
      body: body,
      fromJson: (json) => RecountQuestion.fromJson(json),
      itemKey: 'question',
    );
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

