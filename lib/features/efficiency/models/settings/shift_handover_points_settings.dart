import 'points_settings_base.dart';

/// Настройки баллов за сдачу смены (Shift Handover)
///
/// Использует рейтинг 1-10 с линейной интерполяцией.
/// Включает временные окна для утренней и вечерней смены.
class ShiftHandoverPointsSettings extends PointsSettingsBase
    with TimeWindowSettings, RatingBasedSettings {
  @override
  final String id;

  @override
  final String category;

  @override
  final double minPoints;

  @override
  final int zeroThreshold;

  @override
  final double maxPoints;

  @override
  final int minRating;

  @override
  final int maxRating;

  @override
  final String morningStartTime;

  @override
  final String morningEndTime;

  @override
  final String eveningStartTime;

  @override
  final String eveningEndTime;

  @override
  final double missedPenalty;

  @override
  final int adminReviewTimeout;

  @override
  final DateTime? createdAt;

  @override
  final DateTime? updatedAt;

  ShiftHandoverPointsSettings({
    this.id = 'shift_handover_points',
    this.category = 'shift_handover',
    required this.minPoints,
    required this.zeroThreshold,
    required this.maxPoints,
    this.minRating = 1,
    this.maxRating = 10,
    this.morningStartTime = '07:00',
    this.morningEndTime = '14:00',
    this.eveningStartTime = '14:00',
    this.eveningEndTime = '23:00',
    this.missedPenalty = -3.0,
    this.adminReviewTimeout = 4,
    this.createdAt,
    this.updatedAt,
  });

  factory ShiftHandoverPointsSettings.fromJson(Map<String, dynamic> json) {
    return ShiftHandoverPointsSettings(
      id: json['id'] ?? 'shift_handover_points',
      category: json['category'] ?? 'shift_handover',
      minPoints: (json['minPoints'] ?? -3).toDouble(),
      zeroThreshold: json['zeroThreshold'] ?? 7,
      maxPoints: (json['maxPoints'] ?? 1).toDouble(),
      minRating: json['minRating'] ?? 1,
      maxRating: json['maxRating'] ?? 10,
      morningStartTime: json['morningStartTime'] ?? '07:00',
      morningEndTime: json['morningEndTime'] ?? '14:00',
      eveningStartTime: json['eveningStartTime'] ?? '14:00',
      eveningEndTime: json['eveningEndTime'] ?? '23:00',
      missedPenalty: (json['missedPenalty'] ?? -3.0).toDouble(),
      adminReviewTimeout: json['adminReviewTimeout'] ?? 4,
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
    'minRating': minRating,
    'maxRating': maxRating,
    'morningStartTime': morningStartTime,
    'morningEndTime': morningEndTime,
    'eveningStartTime': eveningStartTime,
    'eveningEndTime': eveningEndTime,
    'missedPenalty': missedPenalty,
    'adminReviewTimeout': adminReviewTimeout,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Настройки по умолчанию
  factory ShiftHandoverPointsSettings.defaults() {
    return ShiftHandoverPointsSettings(
      minPoints: -3,
      zeroThreshold: 7,
      maxPoints: 1,
      morningStartTime: '07:00',
      morningEndTime: '14:00',
      eveningStartTime: '14:00',
      eveningEndTime: '23:00',
      missedPenalty: -3.0,
      adminReviewTimeout: 4,
    );
  }

  /// Расчёт баллов эффективности по рейтингу
  double calculatePoints(int rating) => calculatePointsFromRating(rating);

  ShiftHandoverPointsSettings copyWith({
    double? minPoints,
    int? zeroThreshold,
    double? maxPoints,
    String? morningStartTime,
    String? morningEndTime,
    String? eveningStartTime,
    String? eveningEndTime,
    double? missedPenalty,
    int? adminReviewTimeout,
  }) {
    return ShiftHandoverPointsSettings(
      id: id,
      category: category,
      minPoints: minPoints ?? this.minPoints,
      zeroThreshold: zeroThreshold ?? this.zeroThreshold,
      maxPoints: maxPoints ?? this.maxPoints,
      minRating: minRating,
      maxRating: maxRating,
      morningStartTime: morningStartTime ?? this.morningStartTime,
      morningEndTime: morningEndTime ?? this.morningEndTime,
      eveningStartTime: eveningStartTime ?? this.eveningStartTime,
      eveningEndTime: eveningEndTime ?? this.eveningEndTime,
      missedPenalty: missedPenalty ?? this.missedPenalty,
      adminReviewTimeout: adminReviewTimeout ?? this.adminReviewTimeout,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
