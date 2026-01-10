import '../../../core/utils/logger.dart';
import '../services/recount_question_service.dart';

/// Модель товара для пересчета
/// Поддерживает новый формат (barcode, productGroup, productName)
/// и старый формат (question) для обратной совместимости
class RecountQuestion {
  final String id;
  final String barcode;       // Баркод (уникальный идентификатор)
  final String productGroup;  // Группа товара
  final String productName;   // Наименование товара
  final int grade;            // 1 - очень важный, 2 - средней важности, 3 - не очень важный

  RecountQuestion({
    required this.id,
    required this.barcode,
    required this.productGroup,
    required this.productName,
    required this.grade,
  });

  /// Геттер для обратной совместимости с кодом, использующим question
  String get question => productName.isNotEmpty ? productName : barcode;

  /// Создать RecountQuestion из JSON
  /// Поддерживает новый формат (barcode, productGroup, productName) и старый (question)
  factory RecountQuestion.fromJson(Map<String, dynamic> json) {
    // Определяем формат данных
    final hasNewFormat = json['barcode'] != null;

    return RecountQuestion(
      id: json['id'] ?? '',
      barcode: json['barcode']?.toString() ?? json['id']?.toString() ?? '',
      productGroup: json['productGroup']?.toString() ?? '',
      productName: hasNewFormat
          ? (json['productName']?.toString() ?? '')
          : (json['question']?.toString() ?? ''),  // Для старого формата используем question как productName
      grade: json['grade'] is int ? json['grade'] : int.tryParse(json['grade'].toString()) ?? 1,
    );
  }

  /// Преобразовать RecountQuestion в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'barcode': barcode,
      'productGroup': productGroup,
      'productName': productName,
      'grade': grade,
    };
  }

  /// Загрузить вопросы с сервера
  static Future<List<RecountQuestion>> loadQuestions() async {
    try {
      return await RecountQuestionService.getQuestions();
    } catch (e) {
      Logger.error('Ошибка загрузки вопросов пересчета', e);
      return [];
    }
  }

  /// Выбрать вопросы по алгоритму: 50% грейд 1, 30% грейд 2, 20% грейд 3
  /// [totalCount] - общее количество вопросов для выбора (по умолчанию 30)
  static List<RecountQuestion> selectQuestions(List<RecountQuestion> allQuestions, {int totalCount = 30}) {
    // Разделяем по грейдам
    final grade1Questions = allQuestions.where((q) => q.grade == 1).toList();
    final grade2Questions = allQuestions.where((q) => q.grade == 2).toList();
    final grade3Questions = allQuestions.where((q) => q.grade == 3).toList();

    // Распределяем по пропорциям: 50% грейд 1, 30% грейд 2, 20% грейд 3
    final neededGrade1 = (totalCount * 0.5).round();
    final neededGrade2 = (totalCount * 0.3).round();
    final neededGrade3 = totalCount - neededGrade1 - neededGrade2; // остаток

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

    Logger.info('Выбрано вопросов (всего запрошено: $totalCount): Грейд 1: ${selectedGrade1.length}, Грейд 2: ${selectedGrade2.length}, Грейд 3: ${selectedGrade3.length}, Всего: ${selected.length}');

    return selected;
  }
}











