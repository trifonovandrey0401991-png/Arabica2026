import 'points_settings_base.dart';

/// Настройки баллов за конверт (сдача наличных)
///
/// Использует бинарную логику (сдан / не сдан).
class EnvelopePointsSettings extends PointsSettingsBase {
  @override
  final String id;

  @override
  final String category;

  /// Баллы за сданный конверт
  final double submittedPoints;

  /// Баллы за несданный конверт (штраф)
  final double notSubmittedPoints;

  @override
  final DateTime? createdAt;

  @override
  final DateTime? updatedAt;

  EnvelopePointsSettings({
    this.id = 'envelope_points',
    this.category = 'envelope',
    required this.submittedPoints,
    required this.notSubmittedPoints,
    this.createdAt,
    this.updatedAt,
  });

  factory EnvelopePointsSettings.fromJson(Map<String, dynamic> json) {
    return EnvelopePointsSettings(
      id: json['id'] ?? 'envelope_points',
      category: json['category'] ?? 'envelope',
      submittedPoints: (json['submittedPoints'] ?? 1.0).toDouble(),
      notSubmittedPoints: (json['notSubmittedPoints'] ?? -3.0).toDouble(),
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
    'submittedPoints': submittedPoints,
    'notSubmittedPoints': notSubmittedPoints,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Настройки по умолчанию
  factory EnvelopePointsSettings.defaults() {
    return EnvelopePointsSettings(
      submittedPoints: 1.0,
      notSubmittedPoints: -3.0,
    );
  }

  /// Расчёт баллов на основе статуса сдачи конверта
  double calculatePoints(bool submitted) {
    return submitted ? submittedPoints : notSubmittedPoints;
  }

  EnvelopePointsSettings copyWith({
    double? submittedPoints,
    double? notSubmittedPoints,
  }) {
    return EnvelopePointsSettings(
      id: id,
      category: category,
      submittedPoints: submittedPoints ?? this.submittedPoints,
      notSubmittedPoints: notSubmittedPoints ?? this.notSubmittedPoints,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
