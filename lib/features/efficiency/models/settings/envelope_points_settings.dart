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

  /// Начало временного окна для сдачи конверта после утренней смены
  final String morningStartTime;

  /// Конец временного окна для сдачи конверта после утренней смены
  final String morningEndTime;

  /// Начало временного окна для сдачи конверта после вечерней смены
  final String eveningStartTime;

  /// Конец временного окна для сдачи конверта после вечерней смены
  final String eveningEndTime;

  @override
  final DateTime? createdAt;

  @override
  final DateTime? updatedAt;

  EnvelopePointsSettings({
    this.id = 'envelope_points',
    this.category = 'envelope',
    required this.submittedPoints,
    required this.notSubmittedPoints,
    this.morningStartTime = '08:00',
    this.morningEndTime = '12:00',
    this.eveningStartTime = '08:00',
    this.eveningEndTime = '12:00',
    this.createdAt,
    this.updatedAt,
  });

  factory EnvelopePointsSettings.fromJson(Map<String, dynamic> json) {
    return EnvelopePointsSettings(
      id: json['id'] ?? 'envelope_points',
      category: json['category'] ?? 'envelope',
      submittedPoints: (json['submittedPoints'] ?? 1.0).toDouble(),
      notSubmittedPoints: (json['notSubmittedPoints'] ?? -3.0).toDouble(),
      morningStartTime: json['morningStartTime'] ?? '08:00',
      morningEndTime: json['morningEndTime'] ?? '12:00',
      eveningStartTime: json['eveningStartTime'] ?? '08:00',
      eveningEndTime: json['eveningEndTime'] ?? '12:00',
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
    'morningStartTime': morningStartTime,
    'morningEndTime': morningEndTime,
    'eveningStartTime': eveningStartTime,
    'eveningEndTime': eveningEndTime,
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
    String? morningStartTime,
    String? morningEndTime,
    String? eveningStartTime,
    String? eveningEndTime,
  }) {
    return EnvelopePointsSettings(
      id: id,
      category: category,
      submittedPoints: submittedPoints ?? this.submittedPoints,
      notSubmittedPoints: notSubmittedPoints ?? this.notSubmittedPoints,
      morningStartTime: morningStartTime ?? this.morningStartTime,
      morningEndTime: morningEndTime ?? this.morningEndTime,
      eveningStartTime: eveningStartTime ?? this.eveningStartTime,
      eveningEndTime: eveningEndTime ?? this.eveningEndTime,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
