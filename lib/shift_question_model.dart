import 'package:http/http.dart' as http;
import 'dart:convert';
import 'shift_question_service.dart';

/// Модель вопроса пересменки
class ShiftQuestion {
  final String id;
  final String question;
  final String? answerFormatB; // Столбец B
  final String? answerFormatC; // Столбец C

  ShiftQuestion({
    required this.id,
    required this.question,
    this.answerFormatB,
    this.answerFormatC,
  });

  /// Создать ShiftQuestion из JSON
  factory ShiftQuestion.fromJson(Map<String, dynamic> json) {
    return ShiftQuestion(
      id: json['id'] ?? '',
      question: json['question'] ?? '',
      answerFormatB: json['answerFormatB'],
      answerFormatC: json['answerFormatC'],
    );
  }

  /// Преобразовать ShiftQuestion в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'answerFormatB': answerFormatB,
      'answerFormatC': answerFormatC,
    };
  }

  /// Определить тип ответа
  bool get isNumberOnly => 
      answerFormatC?.toLowerCase().trim() == 'число' ||
      answerFormatC?.toLowerCase().trim() == 'number';

  bool get isPhotoOnly => 
      answerFormatB?.toLowerCase().trim() == 'free' ||
      answerFormatB?.toLowerCase().trim() == 'photo';

  bool get isYesNo => 
      (answerFormatB == null || answerFormatB!.trim().isEmpty) &&
      (answerFormatC == null || answerFormatC!.trim().isEmpty);

  bool get isTextOnly => !isNumberOnly && !isPhotoOnly && !isYesNo;

  /// Загрузить вопросы с сервера
  static Future<List<ShiftQuestion>> loadQuestions() async {
    try {
      return await ShiftQuestionService.getQuestions();
    } catch (e) {
      print('❌ Ошибка загрузки вопросов пересменки: $e');
      return [];
    }
  }

  /// Загрузить вопросы из Google Sheets (устаревший метод)
  @Deprecated('Используйте loadQuestions()')
  static Future<List<ShiftQuestion>> loadQuestionsFromGoogleSheets() async {
    try {
      const sheetName = 'Пересменка';
      final encodedSheetName = Uri.encodeComponent(sheetName);
      final sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=$encodedSheetName';
      
      print('📥 Загружаем вопросы пересменки из Google Sheets...');
      print('   Лист: $sheetName');
      print('   URL: $sheetUrl');
      
      final response = await http.get(Uri.parse(sheetUrl));
      
      if (response.statusCode != 200) {
        print('❌ Ошибка загрузки: ${response.statusCode}');
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      print('📊 Получено строк из CSV: ${lines.length}');
      
      final List<ShiftQuestion> questions = [];

      // Нет заголовков, начинаем с первой строки
      for (var i = 0; i < lines.length; i++) {
        try {
          final line = lines[i];
          final row = _parseCsvLine(line);
          
          if (row.length > 0) {
            final question = row[0].trim().replaceAll('"', '');
            final formatB = row.length > 1 ? row[1].trim().replaceAll('"', '') : null;
            final formatC = row.length > 2 ? row[2].trim().replaceAll('"', '') : null;
            
            if (question.isNotEmpty) {
              questions.add(ShiftQuestion(
                question: question,
                answerFormatB: formatB?.isEmpty == true ? null : formatB,
                answerFormatC: formatC?.isEmpty == true ? null : formatC,
              ));
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
      print('❌ Ошибка загрузки вопросов: $e');
      throw Exception('Что-то пошло не так, попробуйте позже');
    }
  }

  static List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    String current = '';
    bool inQuotes = false;

    for (var i = 0; i < line.length; i++) {
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

