import 'dart:convert';

/// Модель ответа на вопрос пересчета
class RecountAnswer {
  final String question;
  final int grade;
  final String answer; // "сходится" или "не сходится"
  final int? quantity; // Количество (если "сходится")
  final int? programBalance; // Остаток по программе (если "не сходится")
  final int? actualBalance; // Фактический остаток (если "не сходится")
  final int? difference; // Разница (programBalance - actualBalance)
  final String? photoPath; // Путь к локальному фото
  final String? photoUrl; // URL фото на сервере после загрузки
  final bool photoRequired; // Требовалось ли фото для этого вопроса

  RecountAnswer({
    required this.question,
    required this.grade,
    required this.answer,
    this.quantity,
    this.programBalance,
    this.actualBalance,
    this.difference,
    this.photoPath,
    this.photoUrl,
    this.photoRequired = false,
  });

  Map<String, dynamic> toJson() => {
    'question': question,
    'grade': grade,
    'answer': answer,
    'quantity': quantity,
    'programBalance': programBalance,
    'actualBalance': actualBalance,
    'difference': difference,
    'photoPath': photoPath,
    'photoUrl': photoUrl,
    'photoRequired': photoRequired,
  };

  factory RecountAnswer.fromJson(Map<String, dynamic> json) => RecountAnswer(
    question: json['question'] ?? '',
    grade: json['grade'] ?? 1,
    answer: json['answer'] ?? '',
    quantity: json['quantity'],
    programBalance: json['programBalance'],
    actualBalance: json['actualBalance'],
    difference: json['difference'],
    photoPath: json['photoPath'],
    photoUrl: json['photoUrl'],
    photoRequired: json['photoRequired'] ?? false,
  );
}












