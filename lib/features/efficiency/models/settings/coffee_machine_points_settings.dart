import 'points_settings_base.dart';

/// Настройки баллов за счётчик кофемашин
///
/// Использует бинарную логику (сдан / не сдан).
class CoffeeMachinePointsSettings extends PointsSettingsBase {
  @override
  final String id;

  @override
  final String category;

  /// Баллы за сданный счётчик
  final double submittedPoints;

  /// Баллы за несданный счётчик (штраф)
  final double notSubmittedPoints;

  /// Начало временного окна для сдачи после утренней смены
  final String morningStartTime;

  /// Конец временного окна для сдачи после утренней смены
  final String morningEndTime;

  /// Начало временного окна для сдачи после вечерней смены
  final String eveningStartTime;

  /// Конец временного окна для сдачи после вечерней смены
  final String eveningEndTime;

  /// Таймаут проверки админом (часы)
  final int adminReviewTimeoutHours;

  @override
  final DateTime? createdAt;

  @override
  final DateTime? updatedAt;

  CoffeeMachinePointsSettings({
    this.id = 'coffee_machine_points',
    this.category = 'coffee_machine',
    required this.submittedPoints,
    required this.notSubmittedPoints,
    this.morningStartTime = '07:00',
    this.morningEndTime = '12:00',
    this.eveningStartTime = '14:00',
    this.eveningEndTime = '22:00',
    this.adminReviewTimeoutHours = 4,
    this.createdAt,
    this.updatedAt,
  });

  factory CoffeeMachinePointsSettings.fromJson(Map<String, dynamic> json) {
    return CoffeeMachinePointsSettings(
      id: json['id'] ?? 'coffee_machine_points',
      category: json['category'] ?? 'coffee_machine',
      submittedPoints: (json['submittedPoints'] ?? 1.0).toDouble(),
      notSubmittedPoints: (json['notSubmittedPoints'] ?? -3.0).toDouble(),
      morningStartTime: json['morningStartTime'] ?? '07:00',
      morningEndTime: json['morningEndTime'] ?? '12:00',
      eveningStartTime: json['eveningStartTime'] ?? '14:00',
      eveningEndTime: json['eveningEndTime'] ?? '22:00',
      adminReviewTimeoutHours: json['adminReviewTimeoutHours'] ?? 4,
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
    'adminReviewTimeoutHours': adminReviewTimeoutHours,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Настройки по умолчанию
  factory CoffeeMachinePointsSettings.defaults() {
    return CoffeeMachinePointsSettings(
      submittedPoints: 1.0,
      notSubmittedPoints: -3.0,
    );
  }

  /// Расчёт баллов на основе статуса сдачи счётчика
  double calculatePoints(bool submitted) {
    return submitted ? submittedPoints : notSubmittedPoints;
  }

  CoffeeMachinePointsSettings copyWith({
    double? submittedPoints,
    double? notSubmittedPoints,
    String? morningStartTime,
    String? morningEndTime,
    String? eveningStartTime,
    String? eveningEndTime,
    int? adminReviewTimeoutHours,
  }) {
    return CoffeeMachinePointsSettings(
      id: id,
      category: category,
      submittedPoints: submittedPoints ?? this.submittedPoints,
      notSubmittedPoints: notSubmittedPoints ?? this.notSubmittedPoints,
      morningStartTime: morningStartTime ?? this.morningStartTime,
      morningEndTime: morningEndTime ?? this.morningEndTime,
      eveningStartTime: eveningStartTime ?? this.eveningStartTime,
      eveningEndTime: eveningEndTime ?? this.eveningEndTime,
      adminReviewTimeoutHours: adminReviewTimeoutHours ?? this.adminReviewTimeoutHours,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
