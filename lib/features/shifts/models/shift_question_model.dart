import '../services/shift_question_service.dart';
import '../../../core/utils/logger.dart';

/// Модель вопроса пересменки
class ShiftQuestion {
  final String id;
  final String question;
  final String? answerFormatB; // Столбец B
  final String? answerFormatC; // Столбец C
  final List<String>? shops; // Список адресов магазинов, для которых задан вопрос. null означает "для всех магазинов"
  final Map<String, String>? referencePhotos; // Объект с ключами-адресами магазинов и значениями-URL эталонных фото

  ShiftQuestion({
    required this.id,
    required this.question,
    this.answerFormatB,
    this.answerFormatC,
    this.shops,
    this.referencePhotos,
  });

  /// Создать ShiftQuestion из JSON
  factory ShiftQuestion.fromJson(Map<String, dynamic> json) {
    // Парсим shops (может быть null, массив или отсутствовать)
    List<String>? shops;
    if (json['shops'] != null) {
      if (json['shops'] is List) {
        shops = (json['shops'] as List<dynamic>).map((e) => e.toString()).toList();
      }
    }

    // Парсим referencePhotos (может быть null, объект или отсутствовать)
    Map<String, String>? referencePhotos;
    if (json['referencePhotos'] != null && json['referencePhotos'] is Map) {
      referencePhotos = Map<String, String>.from(
        (json['referencePhotos'] as Map).map((key, value) => MapEntry(key.toString(), value.toString()))
      );
    }

    return ShiftQuestion(
      id: json['id'] ?? '',
      question: json['question'] ?? '',
      answerFormatB: json['answerFormatB'],
      answerFormatC: json['answerFormatC'],
      shops: shops,
      referencePhotos: referencePhotos,
    );
  }

  /// Преобразовать ShiftQuestion в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'answerFormatB': answerFormatB,
      'answerFormatC': answerFormatC,
      if (shops != null) 'shops': shops,
      if (referencePhotos != null) 'referencePhotos': referencePhotos,
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
  static Future<List<ShiftQuestion>> loadQuestions({String? shopAddress}) async {
    try {
      return await ShiftQuestionService.getQuestions(shopAddress: shopAddress);
    } catch (e) {
      Logger.error('Ошибка загрузки вопросов пересменки', e);
      return [];
    }
  }
}
