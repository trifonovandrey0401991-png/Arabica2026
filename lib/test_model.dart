import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

/// Модель вопроса теста
class TestQuestion {
  final String question;
  final List<String> options;
  final String correctAnswer;

  TestQuestion({
    required this.question,
    required this.options,
    required this.correctAnswer,
  });

  /// Загрузить вопросы из Google Sheets
  static Future<List<TestQuestion>> loadQuestions() async {
    try {
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Вопросы_Тестирование';
      
      print('📥 Загружаем вопросы теста из Google Sheets...');
      final response = await http.get(Uri.parse(sheetUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      final List<TestQuestion> questions = [];

      // Пропускаем заголовок (первая строка)
      for (var i = 1; i < lines.length; i++) {
        try {
          final row = _parseCsvLine(lines[i]);
          
          if (row.length >= 3) {
            final question = row[0].trim().replaceAll('"', '');
            final optionsStr = row[1].trim().replaceAll('"', '');
            final correctAnswer = row[2].trim().replaceAll('"', '');
            
            if (question.isNotEmpty && optionsStr.isNotEmpty && correctAnswer.isNotEmpty) {
              // Парсим варианты ответов (разделены запятой)
              // Учитываем, что варианты могут быть в кавычках в CSV
              final options = optionsStr
                  .split(',')
                  .map((e) => e.trim().replaceAll('"', ''))
                  .where((e) => e.isNotEmpty)
                  .toList();
              
              if (options.isNotEmpty) {
                questions.add(TestQuestion(
                  question: question,
                  options: options,
                  correctAnswer: correctAnswer,
                ));
              }
            }
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
      return [];
    }
  }

  /// Получить случайные 20 вопросов
  static List<TestQuestion> getRandomQuestions(List<TestQuestion> allQuestions, int count) {
    if (allQuestions.length <= count) {
      return List.from(allQuestions)..shuffle(Random());
    }
    final shuffled = List.from(allQuestions)..shuffle(Random());
    return shuffled.take(count).toList();
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

