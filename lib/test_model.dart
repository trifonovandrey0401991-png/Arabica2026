import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'test_question_service.dart';

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
      print('❌ Ошибка загрузки вопросов тестирования: $e');
      return [];
    }
  }

  /// Загрузить вопросы из сервер (устаревший метод)
  @Deprecated('Используйте loadQuestions()')
  static Future<List<TestQuestion>> loadQuestionsFromGoogleSheets() async {
    try {
      // Правильно кодируем название листа с кириллицей
      // Используем точное название листа: "Вопросы Тестирования" (с пробелом, БЕЗ подчеркивания)
      const sheetName = 'Вопросы Тестирования';
      final encodedSheetName = Uri.encodeComponent(sheetName);
      final sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=$encodedSheetName';
      
      print('📥 Загружаем вопросы теста из сервер...');
      print('   Лист: $sheetName');
      print('   Закодированное название: $encodedSheetName');
      print('   URL: $sheetUrl');
      
      final response = await http.get(Uri.parse(sheetUrl));
      
      if (response.statusCode != 200) {
        print('❌ Ошибка загрузки: ${response.statusCode}');
        print('   Тело ответа: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      print('📊 Получено строк из CSV: ${lines.length}');
      
      // Логируем первые несколько строк для отладки
      if (lines.isNotEmpty && lines.length > 1) {
        print('📝 Первая строка (заголовок): ${lines[0]}');
        if (lines.length > 1) {
          print('📝 Вторая строка (данные): ${lines[1]}');
        }
      }

      final List<TestQuestion> questions = [];

      // Пропускаем заголовок (первая строка)
      for (var i = 1; i < lines.length; i++) {
        try {
          final row = _parseCsvLine(lines[i]);
          
          // Столбец A (индекс 0) - вопрос
          // Столбец B (индекс 1) - варианты ответов через запятую
          // Столбец C (индекс 2) - правильный ответ
          if (row.length >= 3) {
            final question = row[0].trim().replaceAll('"', '');
            final optionsStr = row[1].trim().replaceAll('"', '');
            final correctAnswer = row[2].trim().replaceAll('"', '');
            
            if (question.isNotEmpty && optionsStr.isNotEmpty && correctAnswer.isNotEmpty) {
              // Парсим варианты ответов (разделены запятой)
              final options = optionsStr
                  .split(',')
                  .map((e) => e.trim().replaceAll('"', ''))
                  .where((e) => e.isNotEmpty)
                  .toList();
              
              if (options.isNotEmpty) {
                questions.add(TestQuestion(
                  id: 'test_question_${i}_${question.hashCode}',
                  question: question,
                  options: options,
                  correctAnswer: correctAnswer,
                ));
                
                // Логируем первые несколько вопросов для отладки
                if (questions.length <= 3) {
                  print('✅ Вопрос ${questions.length}: "$question"');
                  print('   Варианты: $options');
                  print('   Правильный ответ: "$correctAnswer"');
                }
              }
            }
          } else {
            print('⚠️ Строка $i: недостаточно столбцов (${row.length} < 3)');
          }
        } catch (e) {
          print('⚠️ Ошибка парсинга строки $i: $e');
          continue;
        }
      }

      print('✅ Загружено вопросов: ${questions.length}');
      return questions;
    } catch (e) {
      print('⚠️ Ошибка загрузки вопросов: $e');
      print('   Stack trace: ${StackTrace.current}');
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

  static List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    String current = '';
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current);
        current = '';
      } else {
        current += char;
      }
    }
    result.add(current);
    return result;
  }
}

