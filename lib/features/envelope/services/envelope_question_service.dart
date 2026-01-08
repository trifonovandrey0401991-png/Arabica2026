import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/envelope_question_model.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

/// Сервис для работы с вопросами формирования конверта
class EnvelopeQuestionService {
  static const String _baseUrl = '${ApiConstants.serverUrl}/api/envelope-questions';

  /// Получить все вопросы
  static Future<List<EnvelopeQuestion>> getQuestions() async {
    try {
      Logger.debug('📥 Загрузка вопросов конверта...');

      final response = await http.get(
        Uri.parse(_baseUrl),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['questions'] != null) {
          final questions = (data['questions'] as List)
              .map((q) => EnvelopeQuestion.fromJson(q))
              .toList();
          questions.sort((a, b) => a.order.compareTo(b.order));
          Logger.debug('✅ Загружено вопросов конверта: ${questions.length}');
          return questions;
        }
      }

      Logger.debug('⚠️ Ошибка загрузки вопросов: ${response.statusCode}');
      return [];
    } catch (e) {
      Logger.error('Ошибка загрузки вопросов конверта', e);
      return [];
    }
  }

  /// Создать вопрос
  static Future<EnvelopeQuestion?> createQuestion(EnvelopeQuestion question) async {
    try {
      Logger.debug('📤 Создание вопроса конверта: ${question.title}');

      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(question.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['question'] != null) {
          Logger.debug('✅ Вопрос создан');
          return EnvelopeQuestion.fromJson(data['question']);
        }
      }

      Logger.debug('⚠️ Ошибка создания вопроса: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Ошибка создания вопроса конверта', e);
      return null;
    }
  }

  /// Обновить вопрос
  static Future<EnvelopeQuestion?> updateQuestion(EnvelopeQuestion question) async {
    try {
      Logger.debug('📤 Обновление вопроса конверта: ${question.id}');

      final response = await http.put(
        Uri.parse('$_baseUrl/${question.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(question.toJson()),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['question'] != null) {
          Logger.debug('✅ Вопрос обновлен');
          return EnvelopeQuestion.fromJson(data['question']);
        }
      }

      Logger.debug('⚠️ Ошибка обновления вопроса: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Ошибка обновления вопроса конверта', e);
      return null;
    }
  }

  /// Удалить вопрос
  static Future<bool> deleteQuestion(String id) async {
    try {
      Logger.debug('🗑️ Удаление вопроса конверта: $id');

      final response = await http.delete(
        Uri.parse('$_baseUrl/$id'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          Logger.debug('✅ Вопрос удален');
          return true;
        }
      }

      Logger.debug('⚠️ Ошибка удаления вопроса: ${response.statusCode}');
      return false;
    } catch (e) {
      Logger.error('Ошибка удаления вопроса конверта', e);
      return false;
    }
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

  /// Загрузить эталонное фото для вопроса
  static Future<String?> uploadReferencePhoto({
    required String questionId,
    required File photoFile,
  }) async {
    try {
      Logger.debug('📤 Загрузка эталонного фото для вопроса: $questionId');

      final uri = Uri.parse('${ApiConstants.serverUrl}/upload-media');
      final request = http.MultipartRequest('POST', uri);

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
