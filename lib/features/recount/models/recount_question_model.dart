import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/recount_question_service.dart';

/// Модель вопроса пересчета
class RecountQuestion {
  final String id;
  final String question;
  final int grade; // 1 - очень важный, 2 - средней важности, 3 - не очень важный

  RecountQuestion({
    required this.id,
    required this.question,
    required this.grade,
  });

  /// Создать RecountQuestion из JSON
  factory RecountQuestion.fromJson(Map<String, dynamic> json) {
    return RecountQuestion(
      id: json['id'] ?? '',
      question: json['question'] ?? '',
      grade: json['grade'] is int ? json['grade'] : int.tryParse(json['grade'].toString()) ?? 1,
    );
  }

  /// Преобразовать RecountQuestion в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'grade': grade,
    };
  }

  /// Загрузить вопросы с сервера
  static Future<List<RecountQuestion>> loadQuestions() async {
    try {
      return await RecountQuestionService.getQuestions();
    } catch (e) {
      print('❌ Ошибка загрузки вопросов пересчета: $e');
      return [];
    }
  }

  /// Загрузить вопросы из сервер (устаревший метод)
  @Deprecated('Используйте loadQuestions()')
  static Future<List<RecountQuestion>> loadQuestionsFromGoogleSheets() async {
    try {
      const sheetName = 'ПЕРЕСЧЕТ';
      final encodedSheetName = Uri.encodeComponent(sheetName);
      final sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=$encodedSheetName';
      
      print('📥 Загружаем вопросы пересчета из сервер...');
      print('   Лист: $sheetName');
      print('   URL: $sheetUrl');
      
      final response = await http.get(Uri.parse(sheetUrl));
      
      if (response.statusCode != 200) {
        print('❌ Ошибка загрузки: ${response.statusCode}');
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      print('📊 Получено строк из CSV: ${lines.length}');
      
      final List<RecountQuestion> questions = [];

      // Парсим строки (столбец A = вопрос, столбец B = грейд)
      for (var i = 0; i < lines.length; i++) {
        try {
          final line = lines[i];
          final row = _parseCsvLine(line);
          
          if (row.length >= 2) {
            final question = row[0].trim().replaceAll('"', '');
            final gradeStr = row[1].trim().replaceAll('"', '');
            
            if (question.isNotEmpty && gradeStr.isNotEmpty) {
              final grade = int.tryParse(gradeStr);
              if (grade != null && grade >= 1 && grade <= 3) {
                questions.add(RecountQuestion(
                  id: 'recount_question_${i}_${question.hashCode}',
                  question: question,
                  grade: grade,
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
      print('❌ Ошибка загрузки вопросов: $e');
      throw Exception('Что-то пошло не так, попробуйте позже');
    }
  }

  /// Выбрать 30 вопросов по алгоритму: 50% грейд 1, 30% грейд 2, 20% грейд 3
  static List<RecountQuestion> selectQuestions(List<RecountQuestion> allQuestions) {
    // Разделяем по грейдам
    final grade1Questions = allQuestions.where((q) => q.grade == 1).toList();
    final grade2Questions = allQuestions.where((q) => q.grade == 2).toList();
    final grade3Questions = allQuestions.where((q) => q.grade == 3).toList();

    // Нужно: 15 вопросов грейда 1, 9 грейда 2, 6 грейда 3
    final neededGrade1 = 15;
    final neededGrade2 = 9;
    final neededGrade3 = 6;

    // Выбираем вопросы (если недостаточно, берем все доступные)
    final selectedGrade1 = grade1Questions.length >= neededGrade1
        ? (grade1Questions..shuffle()).take(neededGrade1).toList()
        : grade1Questions;
    
    final selectedGrade2 = grade2Questions.length >= neededGrade2
        ? (grade2Questions..shuffle()).take(neededGrade2).toList()
        : grade2Questions;
    
    final selectedGrade3 = grade3Questions.length >= neededGrade3
        ? (grade3Questions..shuffle()).take(neededGrade3).toList()
        : grade3Questions;

    // Объединяем и перемешиваем
    final selected = [
      ...selectedGrade1,
      ...selectedGrade2,
      ...selectedGrade3,
    ]..shuffle();

    print('📋 Выбрано вопросов:');
    print('   Грейд 1: ${selectedGrade1.length}');
    print('   Грейд 2: ${selectedGrade2.length}');
    print('   Грейд 3: ${selectedGrade3.length}');
    print('   Всего: ${selected.length}');

    return selected;
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











