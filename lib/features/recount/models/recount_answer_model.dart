/// Модель ответа на вопрос пересчета
class RecountAnswer {
  final String question;
  final int grade;
  final String answer; // "сходится" или "не сходится"
  final int? quantity; // Количество (если "сходится" - берётся из DBF stock)
  final int? programBalance; // Остаток по программе (из DBF stock)
  final int? actualBalance; // Фактический остаток (рассчитывается)
  final int? difference; // Разница (programBalance - actualBalance)
  final int? moreBy; // "Больше на" - если товара больше чем в программе
  final int? lessBy; // "Меньше на" - если товара меньше чем в программе
  final String? photoPath; // Путь к локальному фото
  final String? photoUrl; // URL фото на сервере после загрузки
  final bool photoRequired; // Требовалось ли фото для этого вопроса

  // Поля для ИИ проверки
  final bool? aiVerified; // Проверено ли ИИ
  final int? aiQuantity; // Количество по ИИ
  final double? aiConfidence; // Уверенность ИИ (0-1)
  final bool? aiMismatch; // Есть расхождение между сотрудником и ИИ
  final String? aiAnnotatedImageUrl; // URL фото с разметкой ИИ

  RecountAnswer({
    required this.question,
    required this.grade,
    required this.answer,
    this.quantity,
    this.programBalance,
    this.actualBalance,
    this.difference,
    this.moreBy,
    this.lessBy,
    this.photoPath,
    this.photoUrl,
    this.photoRequired = false,
    this.aiVerified,
    this.aiQuantity,
    this.aiConfidence,
    this.aiMismatch,
    this.aiAnnotatedImageUrl,
  });

  /// Проверка: ответ "сходится"
  bool get isMatching => answer == 'сходится';

  /// Проверка: ответ "не сходится"
  bool get isNotMatching => answer == 'не сходится';

  /// Создать ответ "Сходится" с автоматическим количеством из DBF
  factory RecountAnswer.matching({
    required String question,
    required int grade,
    required int stockFromDbf,
    String? photoPath,
    String? photoUrl,
    bool photoRequired = false,
  }) {
    return RecountAnswer(
      question: question,
      grade: grade,
      answer: 'сходится',
      quantity: stockFromDbf,
      programBalance: stockFromDbf,
      actualBalance: stockFromDbf,
      difference: 0,
      moreBy: null,
      lessBy: null,
      photoPath: photoPath,
      photoUrl: photoUrl,
      photoRequired: photoRequired,
    );
  }

  /// Создать ответ "Не сходится" с указанием расхождения
  factory RecountAnswer.notMatching({
    required String question,
    required int grade,
    required int stockFromDbf,
    int? moreBy,
    int? lessBy,
    String? photoPath,
    String? photoUrl,
    bool photoRequired = false,
  }) {
    // Рассчитываем фактический остаток и разницу
    int actualBalance = stockFromDbf;
    int difference = 0;

    if (moreBy != null && moreBy > 0) {
      // Товара больше чем в программе
      actualBalance = stockFromDbf + moreBy;
      difference = -moreBy; // Отрицательная разница (излишек)
    } else if (lessBy != null && lessBy > 0) {
      // Товара меньше чем в программе
      actualBalance = stockFromDbf - lessBy;
      difference = lessBy; // Положительная разница (недостача)
    }

    return RecountAnswer(
      question: question,
      grade: grade,
      answer: 'не сходится',
      quantity: null,
      programBalance: stockFromDbf,
      actualBalance: actualBalance,
      difference: difference,
      moreBy: moreBy,
      lessBy: lessBy,
      photoPath: photoPath,
      photoUrl: photoUrl,
      photoRequired: photoRequired,
    );
  }

  Map<String, dynamic> toJson() => {
    'question': question,
    'grade': grade,
    'answer': answer,
    'quantity': quantity,
    'programBalance': programBalance,
    'actualBalance': actualBalance,
    'difference': difference,
    'moreBy': moreBy,
    'lessBy': lessBy,
    'photoPath': photoPath,
    'photoUrl': photoUrl,
    'photoRequired': photoRequired,
    'aiVerified': aiVerified,
    'aiQuantity': aiQuantity,
    'aiConfidence': aiConfidence,
    'aiMismatch': aiMismatch,
    'aiAnnotatedImageUrl': aiAnnotatedImageUrl,
  };

  factory RecountAnswer.fromJson(Map<String, dynamic> json) => RecountAnswer(
    question: json['question'] ?? '',
    grade: json['grade'] ?? 1,
    answer: json['answer'] ?? '',
    quantity: json['quantity'],
    programBalance: json['programBalance'],
    actualBalance: json['actualBalance'],
    difference: json['difference'],
    moreBy: json['moreBy'],
    lessBy: json['lessBy'],
    photoPath: json['photoPath'],
    photoUrl: json['photoUrl'],
    photoRequired: json['photoRequired'] ?? false,
    aiVerified: json['aiVerified'],
    aiQuantity: json['aiQuantity'],
    aiConfidence: json['aiConfidence'] != null
        ? (json['aiConfidence'] as num).toDouble()
        : null,
    aiMismatch: json['aiMismatch'],
    aiAnnotatedImageUrl: json['aiAnnotatedImageUrl'],
  );

  /// Копия с изменениями
  RecountAnswer copyWith({
    String? question,
    int? grade,
    String? answer,
    int? quantity,
    int? programBalance,
    int? actualBalance,
    int? difference,
    int? moreBy,
    int? lessBy,
    String? photoPath,
    String? photoUrl,
    bool? photoRequired,
    bool? aiVerified,
    int? aiQuantity,
    double? aiConfidence,
    bool? aiMismatch,
    String? aiAnnotatedImageUrl,
  }) {
    return RecountAnswer(
      question: question ?? this.question,
      grade: grade ?? this.grade,
      answer: answer ?? this.answer,
      quantity: quantity ?? this.quantity,
      programBalance: programBalance ?? this.programBalance,
      actualBalance: actualBalance ?? this.actualBalance,
      difference: difference ?? this.difference,
      moreBy: moreBy ?? this.moreBy,
      lessBy: lessBy ?? this.lessBy,
      photoPath: photoPath ?? this.photoPath,
      photoUrl: photoUrl ?? this.photoUrl,
      photoRequired: photoRequired ?? this.photoRequired,
      aiVerified: aiVerified ?? this.aiVerified,
      aiQuantity: aiQuantity ?? this.aiQuantity,
      aiConfidence: aiConfidence ?? this.aiConfidence,
      aiMismatch: aiMismatch ?? this.aiMismatch,
      aiAnnotatedImageUrl: aiAnnotatedImageUrl ?? this.aiAnnotatedImageUrl,
    );
  }
}












