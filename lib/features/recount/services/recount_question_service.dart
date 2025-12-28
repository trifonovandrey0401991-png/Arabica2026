import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/recount_question_model.dart';
import 'core/utils/logger.dart';

class RecountQuestionService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/recount-questions';

  /// Получить все вопросы
  static Future<List<RecountQuestion>> getQuestions() async {
    try {
      Logger.debug('📥 Загрузка вопросов пересчета с сервера...');
      
      final response = await http.get(
        Uri.parse(baseUrl),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final questionsJson = result['questions'] as List<dynamic>;
          final questions = questionsJson
              .map((json) => RecountQuestion.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено вопросов пересчета: ${questions.length}');
          return questions;
        } else {
          Logger.error('❌ Ошибка загрузки вопросов: ${result['error']}');
          return [];
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки вопросов пересчета', e);
      return [];
    }
  }

  /// Создать новый вопрос
  static Future<RecountQuestion?> createQuestion({
    required String question,
    required int grade,
  }) async {
    try {
      Logger.debug('📤 Создание вопроса пересчета: $question');
      
      final requestBody = <String, dynamic>{
        'question': question,
        'grade': grade,
      };
      
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Вопрос создан: ${result['question']['id']}');
          return RecountQuestion.fromJson(result['question'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка создания вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания вопроса пересчета', e);
      return null;
    }
  }

  /// Обновить вопрос
  static Future<RecountQuestion?> updateQuestion({
    required String id,
    String? question,
    int? grade,
  }) async {
    try {
      Logger.debug('📤 Обновление вопроса пересчета: $id');
      
      final body = <String, dynamic>{};
      if (question != null) body['question'] = question;
      if (grade != null) body['grade'] = grade;
      
      final response = await http.put(
        Uri.parse('$baseUrl/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Вопрос обновлен: $id');
          return RecountQuestion.fromJson(result['question'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка обновления вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка обновления вопроса пересчета', e);
      return null;
    }
  }

  /// Удалить вопрос
  static Future<bool> deleteQuestion(String id) async {
    try {
      Logger.debug('📤 Удаление вопроса пересчета: $id');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/$id'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Вопрос удален: $id');
          return true;
        } else {
          Logger.error('❌ Ошибка удаления вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return false;
    } catch (e) {
      Logger.error('❌ Ошибка удаления вопроса пересчета', e);
      return false;
    }
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
        Uri.parse('$baseUrl/bulk-upload'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

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

