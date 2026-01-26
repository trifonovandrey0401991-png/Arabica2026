import 'points_settings_base.dart';

/// Настройки баллов за тестирование
///
/// Использует линейную интерполяцию по количеству правильных ответов (0-20).
/// Имеет порог нулевых баллов (zeroThreshold).
class TestPointsSettings extends PointsSettingsBase {
  @override
  final String id;

  @override
  final String category;

  /// Баллы за минимальный результат (штраф)
  final double minPoints;

  /// Порог нулевых баллов (количество правильных ответов для 0 баллов)
  final int zeroThreshold;

  /// Баллы за максимальный результат (бонус)
  final double maxPoints;

  /// Общее количество вопросов (фиксировано: 20)
  final int totalQuestions;

  /// Проходной балл (фиксировано: 16)
  final int passingScore;

  @override
  final DateTime? createdAt;

  @override
  final DateTime? updatedAt;

  TestPointsSettings({
    this.id = 'test_points',
    this.category = 'testing',
    required this.minPoints,
    required this.zeroThreshold,
    required this.maxPoints,
    this.totalQuestions = 20,
    this.passingScore = 16,
    this.createdAt,
    this.updatedAt,
  });

  factory TestPointsSettings.fromJson(Map<String, dynamic> json) {
    return TestPointsSettings(
      id: json['id'] ?? 'test_points',
      category: json['category'] ?? 'testing',
      minPoints: (json['minPoints'] ?? -2).toDouble(),
      zeroThreshold: json['zeroThreshold'] ?? 15,
      maxPoints: (json['maxPoints'] ?? 1).toDouble(),
      totalQuestions: json['totalQuestions'] ?? 20,
      passingScore: json['passingScore'] ?? 16,
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
    'minPoints': minPoints,
    'zeroThreshold': zeroThreshold,
    'maxPoints': maxPoints,
    'totalQuestions': totalQuestions,
    'passingScore': passingScore,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Настройки по умолчанию
  factory TestPointsSettings.defaults() {
    return TestPointsSettings(
      minPoints: -2,
      zeroThreshold: 15,
      maxPoints: 1,
    );
  }

  /// Расчёт баллов эффективности по количеству правильных ответов
  ///
  /// Логика интерполяции:
  /// - score <= 0 → minPoints
  /// - score >= totalQuestions → maxPoints
  /// - score <= zeroThreshold → интерполяция от minPoints до 0
  /// - score > zeroThreshold → интерполяция от 0 до maxPoints
  double calculatePoints(int score) {
    if (score <= 0) return minPoints;
    if (score >= totalQuestions) return maxPoints;

    if (score <= zeroThreshold) {
      // Интерполяция от minPoints до 0 (score: 0 -> zeroThreshold)
      return minPoints + (0 - minPoints) * (score / zeroThreshold);
    } else {
      // Интерполяция от 0 до maxPoints (score: zeroThreshold -> totalQuestions)
      final range = totalQuestions - zeroThreshold;
      return 0 + (maxPoints - 0) * ((score - zeroThreshold) / range);
    }
  }

  TestPointsSettings copyWith({
    double? minPoints,
    int? zeroThreshold,
    double? maxPoints,
  }) {
    return TestPointsSettings(
      id: id,
      category: category,
      minPoints: minPoints ?? this.minPoints,
      zeroThreshold: zeroThreshold ?? this.zeroThreshold,
      maxPoints: maxPoints ?? this.maxPoints,
      totalQuestions: totalQuestions,
      passingScore: passingScore,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
