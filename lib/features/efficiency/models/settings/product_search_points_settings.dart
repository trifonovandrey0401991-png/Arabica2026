import 'points_settings_base.dart';

/// Настройки баллов за поиск товара (ответы на вопросы клиентов)
///
/// Использует бинарную логику (ответил вовремя / не ответил).
class ProductSearchPointsSettings extends PointsSettingsBase {
  @override
  final String id;

  @override
  final String category;

  /// Баллы за ответ вовремя
  final double answeredPoints;

  /// Баллы за отсутствие ответа (штраф)
  final double notAnsweredPoints;

  /// Таймаут на ответ в минутах
  final int answerTimeoutMinutes;

  @override
  final DateTime? createdAt;

  @override
  final DateTime? updatedAt;

  ProductSearchPointsSettings({
    this.id = 'product_search_points',
    this.category = 'product_search',
    required this.answeredPoints,
    required this.notAnsweredPoints,
    this.answerTimeoutMinutes = 30,
    this.createdAt,
    this.updatedAt,
  });

  factory ProductSearchPointsSettings.fromJson(Map<String, dynamic> json) {
    return ProductSearchPointsSettings(
      id: json['id'] ?? 'product_search_points',
      category: json['category'] ?? 'product_search',
      answeredPoints: (json['answeredPoints'] ?? 0.2).toDouble(),
      notAnsweredPoints: (json['notAnsweredPoints'] ?? -3).toDouble(),
      answerTimeoutMinutes: json['answerTimeoutMinutes'] ?? 30,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'answeredPoints': answeredPoints,
    'notAnsweredPoints': notAnsweredPoints,
    'answerTimeoutMinutes': answerTimeoutMinutes,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Настройки по умолчанию
  factory ProductSearchPointsSettings.defaults() {
    return ProductSearchPointsSettings(
      answeredPoints: 0.2,
      notAnsweredPoints: -3,
      answerTimeoutMinutes: 30,
    );
  }

  /// Расчёт баллов на основе статуса ответа
  double calculatePoints(bool answered) {
    return answered ? answeredPoints : notAnsweredPoints;
  }

  ProductSearchPointsSettings copyWith({
    double? answeredPoints,
    double? notAnsweredPoints,
    int? answerTimeoutMinutes,
  }) {
    return ProductSearchPointsSettings(
      id: id,
      category: category,
      answeredPoints: answeredPoints ?? this.answeredPoints,
      notAnsweredPoints: notAnsweredPoints ?? this.notAnsweredPoints,
      answerTimeoutMinutes: answerTimeoutMinutes ?? this.answerTimeoutMinutes,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
