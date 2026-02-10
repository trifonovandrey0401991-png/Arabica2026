import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/envelope_question_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

// http и dart:convert оставлены для multipart загрузки эталонных фото

/// Сервис для работы с вопросами формирования конверта
class EnvelopeQuestionService {
  static const String _baseEndpoint = ApiConstants.envelopeQuestionsEndpoint;

  /// Получить все вопросы
  static Future<List<EnvelopeQuestion>> getQuestions() async {
    Logger.debug('📥 Загрузка вопросов конверта...');
    final questions = await BaseHttpService.getList<EnvelopeQuestion>(
      endpoint: _baseEndpoint,
      fromJson: (json) => EnvelopeQuestion.fromJson(json),
      listKey: 'questions',
    );
    questions.sort((a, b) => a.order.compareTo(b.order));
    return questions;
  }

  /// Создать вопрос
  static Future<EnvelopeQuestion?> createQuestion(EnvelopeQuestion question) async {
    Logger.debug('📤 Создание вопроса конверта: ${question.title}');
    return await BaseHttpService.post<EnvelopeQuestion>(
      endpoint: _baseEndpoint,
      body: question.toJson(),
      fromJson: (json) => EnvelopeQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Обновить вопрос
  static Future<EnvelopeQuestion?> updateQuestion(EnvelopeQuestion question) async {
    Logger.debug('📤 Обновление вопроса конверта: ${question.id}');
    return await BaseHttpService.put<EnvelopeQuestion>(
      endpoint: '$_baseEndpoint/${question.id}',
      body: question.toJson(),
      fromJson: (json) => EnvelopeQuestion.fromJson(json),
      itemKey: 'question',
    );
  }

  /// Удалить вопрос
  static Future<bool> deleteQuestion(String id) async {
    Logger.debug('🗑️ Удаление вопроса конверта: $id');
    return await BaseHttpService.delete(endpoint: '$_baseEndpoint/$id');
  }

  /// Инициализировать дефолтные вопросы (если их нет)
  static Future<void> initializeDefaultQuestions() async {
    try {
      final existing = await getQuestions();
      if (existing.isEmpty) {
        Logger.debug('📝 Инициализация дефолтных вопросов конверта...');
        for (final question in EnvelopeQuestion.defaultQuestions) {
          await createQuestion(question);
        }
        Logger.debug('✅ Дефолтные вопросы созданы');
      }
    } catch (e) {
      Logger.error('Ошибка инициализации вопросов', e);
    }
  }

  /// Загрузить эталонное фото для вопроса (multipart upload)
  static Future<String?> uploadReferencePhoto({
    required String questionId,
    required File photoFile,
  }) async {
    try {
      Logger.debug('📤 Загрузка эталонного фото для вопроса: $questionId');

      final uri = Uri.parse('${ApiConstants.serverUrl}/upload-media');
      final request = http.MultipartRequest('POST', uri);

      // Добавляем заголовки авторизации
      if (ApiConstants.apiKey != null && ApiConstants.apiKey!.isNotEmpty) {
        request.headers['X-API-Key'] = ApiConstants.apiKey!;
      }
      if (ApiConstants.sessionToken != null && ApiConstants.sessionToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${ApiConstants.sessionToken}';
      }

      final bytes = await photoFile.readAsBytes();
      final multipartFile = http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: 'envelope_reference_$questionId.jpg',
        contentType: MediaType('image', 'jpeg'),
      );

      request.files.add(multipartFile);

      final streamedResponse = await request.send().timeout(ApiConstants.uploadTimeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['url'] != null) {
          final photoUrl = data['url'] as String;
          Logger.debug('✅ Эталонное фото загружено: $photoUrl');
          return photoUrl;
        }
      }

      Logger.debug('⚠️ Ошибка загрузки фото: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Ошибка загрузки эталонного фото', e);
      return null;
    }
  }
}
