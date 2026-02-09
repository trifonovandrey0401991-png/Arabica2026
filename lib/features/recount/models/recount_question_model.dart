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
  final int stock;            // Остаток товара из DBF (0 = нет в наличии)
  final bool isAiActive;      // Активна ли ИИ проверка для этого товара
  final String? productPhotoUrl; // Фото товара из обучения ИИ (крупный план)

  RecountQuestion({
    required this.id,
    required this.barcode,
    required this.productGroup,
    required this.productName,
    required this.grade,
    this.stock = 0,
    this.isAiActive = false,
    this.productPhotoUrl,
  });

  /// Есть ли товар в наличии
  bool get hasStock => stock > 0;

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
      stock: json['stock'] is int ? json['stock'] : int.tryParse(json['stock']?.toString() ?? '0') ?? 0,
      isAiActive: json['isAiActive'] ?? false,
      productPhotoUrl: json['productPhotoUrl'] as String?,
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
      'stock': stock,
      'isAiActive': isAiActive,
      'productPhotoUrl': productPhotoUrl,
    };
  }

  /// Создать копию с новым остатком
  RecountQuestion copyWithStock(int newStock) {
    return RecountQuestion(
      id: id,
      barcode: barcode,
      productGroup: productGroup,
      productName: productName,
      grade: grade,
      stock: newStock,
      isAiActive: isAiActive,
      productPhotoUrl: productPhotoUrl,
    );
  }

  /// Создать копию с указанным isAiActive
  RecountQuestion copyWith({
    String? id,
    String? barcode,
    String? productGroup,
    String? productName,
    int? grade,
    int? stock,
    bool? isAiActive,
    String? productPhotoUrl,
  }) {
    return RecountQuestion(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      productGroup: productGroup ?? this.productGroup,
      productName: productName ?? this.productName,
      grade: grade ?? this.grade,
      stock: stock ?? this.stock,
      isAiActive: isAiActive ?? this.isAiActive,
      productPhotoUrl: productPhotoUrl ?? this.productPhotoUrl,
    );
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
  /// Если в какой-то категории не хватает товаров, добираем из других категорий
  static List<RecountQuestion> selectQuestions(List<RecountQuestion> allQuestions, {int totalCount = 30}) {
    // Разделяем по грейдам
    final grade1Questions = allQuestions.where((q) => q.grade == 1).toList()..shuffle();
    final grade2Questions = allQuestions.where((q) => q.grade == 2).toList()..shuffle();
    final grade3Questions = allQuestions.where((q) => q.grade == 3).toList()..shuffle();

    Logger.debug('📊 Распределение по грейдам: G1=${grade1Questions.length}, G2=${grade2Questions.length}, G3=${grade3Questions.length}');

    // Распределяем по пропорциям: 50% грейд 1, 30% грейд 2, 20% грейд 3
    int neededGrade1 = (totalCount * 0.5).round();
    int neededGrade2 = (totalCount * 0.3).round();
    int neededGrade3 = totalCount - neededGrade1 - neededGrade2;

    // Выбираем вопросы с учётом доступных
    final selectedGrade1 = grade1Questions.take(neededGrade1).toList();
    final selectedGrade2 = grade2Questions.take(neededGrade2).toList();
    final selectedGrade3 = grade3Questions.take(neededGrade3).toList();

    // Подсчитываем сколько не хватает
    int missing = totalCount - selectedGrade1.length - selectedGrade2.length - selectedGrade3.length;

    // Если не хватает, добираем из оставшихся товаров в порядке приоритета
    if (missing > 0) {
      Logger.debug('📊 Не хватает $missing вопросов, добираем из других грейдов...');

      // Создаём пул оставшихся товаров (которые ещё не выбраны)
      final usedIds = <String>{
        ...selectedGrade1.map((q) => q.id),
        ...selectedGrade2.map((q) => q.id),
        ...selectedGrade3.map((q) => q.id),
      };

      // Приоритет добора: грейд 1 > грейд 2 > грейд 3
      final remainingPool = [
        ...grade1Questions.where((q) => !usedIds.contains(q.id)),
        ...grade2Questions.where((q) => !usedIds.contains(q.id)),
        ...grade3Questions.where((q) => !usedIds.contains(q.id)),
      ];

      final additional = remainingPool.take(missing).toList();
      Logger.debug('📊 Добрано ${additional.length} вопросов из других грейдов');

      // Объединяем и перемешиваем
      final selected = [
        ...selectedGrade1,
        ...selectedGrade2,
        ...selectedGrade3,
        ...additional,
      ]..shuffle();

      Logger.info('Выбрано вопросов (всего запрошено: $totalCount): Грейд 1: ${selectedGrade1.length}, Грейд 2: ${selectedGrade2.length}, Грейд 3: ${selectedGrade3.length}, Добор: ${additional.length}, Всего: ${selected.length}');

      return selected;
    }

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











