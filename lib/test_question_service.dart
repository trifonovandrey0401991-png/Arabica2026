import 'package:http/http.dart' as http;
import 'dart:convert';
import 'test_model.dart';
import 'utils/logger.dart';

class TestQuestionService {
  static const String serverUrl = 'https://arabica26.ru';
  static const String baseUrl = '$serverUrl/api/test-questions';

  /// Получить все вопросы
  static Future<List<TestQuestion>> getQuestions() async {
    try {
      Logger.debug('📥 Загрузка вопросов тестирования с сервера...');
      
      final response = await http.get(
        Uri.parse(baseUrl),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final questionsJson = result['questions'] as List<dynamic>;
          final questions = questionsJson
              .map((json) => TestQuestion.fromJson(json as Map<String, dynamic>))
              .toList();
          Logger.debug('✅ Загружено вопросов тестирования: ${questions.length}');
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
      Logger.error('❌ Ошибка загрузки вопросов тестирования', e);
      return [];
    }
  }

  /// Создать новый вопрос
  static Future<TestQuestion?> createQuestion({
    required String question,
    required List<String> options,
    required String correctAnswer,
  }) async {
    try {
      Logger.debug('📤 Создание вопроса тестирования: $question');
      
      final requestBody = <String, dynamic>{
        'question': question,
        'options': options,
        'correctAnswer': correctAnswer,
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
          return TestQuestion.fromJson(result['question'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка создания вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка создания вопроса тестирования', e);
      return null;
    }
  }

  /// Обновить вопрос
  static Future<TestQuestion?> updateQuestion({
    required String id,
    String? question,
    List<String>? options,
    String? correctAnswer,
  }) async {
    try {
      Logger.debug('📤 Обновление вопроса тестирования: $id');
      
      final body = <String, dynamic>{};
      if (question != null) body['question'] = question;
      if (options != null) body['options'] = options;
      if (correctAnswer != null) body['correctAnswer'] = correctAnswer;
      
      final response = await http.put(
        Uri.parse('$baseUrl/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          Logger.debug('✅ Вопрос обновлен: $id');
          return TestQuestion.fromJson(result['question'] as Map<String, dynamic>);
        } else {
          Logger.error('❌ Ошибка обновления вопроса: ${result['error']}');
        }
      } else {
        Logger.error('❌ Ошибка API: statusCode=${response.statusCode}');
      }
      return null;
    } catch (e) {
      Logger.error('❌ Ошибка обновления вопроса тестирования', e);
      return null;
    }
  }

  /// Удалить вопрос
  static Future<bool> deleteQuestion(String id) async {
    try {
      Logger.debug('📤 Удаление вопроса тестирования: $id');
      
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
      Logger.error('❌ Ошибка удаления вопроса тестирования', e);
      return false;
    }
  }
}


