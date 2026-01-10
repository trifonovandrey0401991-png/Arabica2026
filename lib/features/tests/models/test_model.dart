import 'dart:math';
import '../../../core/utils/logger.dart';
import '../services/test_question_service.dart';

/// Модель вопроса теста
class TestQuestion {
  final String id;
  final String question;
  final List<String> options;
  final String correctAnswer;

  TestQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctAnswer,
  });

  /// Создать TestQuestion из JSON
  factory TestQuestion.fromJson(Map<String, dynamic> json) {
    return TestQuestion(
      id: json['id'] ?? '',
      question: json['question'] ?? '',
      options: json['options'] != null
          ? (json['options'] as List<dynamic>).map((e) => e.toString()).toList()
          : [],
      correctAnswer: json['correctAnswer'] ?? '',
    );
  }

  /// Преобразовать TestQuestion в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'options': options,
      'correctAnswer': correctAnswer,
    };
  }

  /// Загрузить вопросы с сервера
  static Future<List<TestQuestion>> loadQuestions() async {
    try {
      return await TestQuestionService.getQuestions();
    } catch (e) {
      Logger.error('Ошибка загрузки вопросов тестирования', e);
      return [];
    }
  }

  /// Получить случайные 20 вопросов
  static List<TestQuestion> getRandomQuestions(List<TestQuestion> allQuestions, int count) {
    if (allQuestions.length <= count) {
      final result = List<TestQuestion>.from(allQuestions);
      result.shuffle(Random());
      return result;
    }
    final shuffled = List<TestQuestion>.from(allQuestions);
    shuffled.shuffle(Random());
    return List<TestQuestion>.from(shuffled.take(count));
  }
}
