import 'points_settings_base.dart';

/// Настройки баллов за отзывы клиентов
///
/// Использует бинарную логику (положительный / отрицательный отзыв).
class ReviewsPointsSettings extends PointsSettingsBase {
  @override
  final String id;

  @override
  final String category;

  /// Баллы за положительный отзыв
  final double positivePoints;

  /// Баллы за отрицательный отзыв (штраф)
  final double negativePoints;

  @override
  final DateTime? createdAt;

  @override
  final DateTime? updatedAt;

  ReviewsPointsSettings({
    this.id = 'reviews_points',
    this.category = 'reviews',
    required this.positivePoints,
    required this.negativePoints,
    this.createdAt,
    this.updatedAt,
  });

  factory ReviewsPointsSettings.fromJson(Map<String, dynamic> json) {
    return ReviewsPointsSettings(
      id: json['id'] ?? 'reviews_points',
      category: json['category'] ?? 'reviews',
      positivePoints: (json['positivePoints'] ?? 3).toDouble(),
      negativePoints: (json['negativePoints'] ?? -5).toDouble(),
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
    'positivePoints': positivePoints,
    'negativePoints': negativePoints,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Настройки по умолчанию
  factory ReviewsPointsSettings.defaults() {
    return ReviewsPointsSettings(
      positivePoints: 3,
      negativePoints: -5,
    );
  }

  /// Расчёт баллов на основе типа отзыва
  double calculatePoints(bool isPositive) {
    return isPositive ? positivePoints : negativePoints;
  }

  ReviewsPointsSettings copyWith({
    double? positivePoints,
    double? negativePoints,
  }) {
    return ReviewsPointsSettings(
      id: id,
      category: category,
      positivePoints: positivePoints ?? this.positivePoints,
      negativePoints: negativePoints ?? this.negativePoints,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
