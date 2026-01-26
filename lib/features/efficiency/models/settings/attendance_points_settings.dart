import 'points_settings_base.dart';

/// Настройки баллов за посещаемость (Attendance / "Я на работе")
///
/// Использует бинарную логику (вовремя / опоздание).
/// Включает временные окна для утренней и вечерней смены.
class AttendancePointsSettings extends PointsSettingsBase with TimeWindowSettings {
  @override
  final String id;

  @override
  final String category;

  /// Баллы за отметку вовремя
  final double onTimePoints;

  /// Баллы за опоздание (отрицательные)
  final double latePoints;

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
  final DateTime? createdAt;

  @override
  final DateTime? updatedAt;

  AttendancePointsSettings({
    this.id = 'attendance_points',
    this.category = 'attendance',
    required this.onTimePoints,
    required this.latePoints,
    this.morningStartTime = '07:00',
    this.morningEndTime = '09:00',
    this.eveningStartTime = '19:00',
    this.eveningEndTime = '21:00',
    this.missedPenalty = -2.0,
    this.createdAt,
    this.updatedAt,
  });

  factory AttendancePointsSettings.fromJson(Map<String, dynamic> json) {
    return AttendancePointsSettings(
      id: json['id'] ?? 'attendance_points',
      category: json['category'] ?? 'attendance',
      onTimePoints: (json['onTimePoints'] ?? 0.5).toDouble(),
      latePoints: (json['latePoints'] ?? -1).toDouble(),
      morningStartTime: json['morningStartTime'] ?? '07:00',
      morningEndTime: json['morningEndTime'] ?? '09:00',
      eveningStartTime: json['eveningStartTime'] ?? '19:00',
      eveningEndTime: json['eveningEndTime'] ?? '21:00',
      missedPenalty: (json['missedPenalty'] ?? -2.0).toDouble(),
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
    'onTimePoints': onTimePoints,
    'latePoints': latePoints,
    'morningStartTime': morningStartTime,
    'morningEndTime': morningEndTime,
    'eveningStartTime': eveningStartTime,
    'eveningEndTime': eveningEndTime,
    'missedPenalty': missedPenalty,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Настройки по умолчанию
  factory AttendancePointsSettings.defaults() {
    return AttendancePointsSettings(
      onTimePoints: 0.5,
      latePoints: -1,
      morningStartTime: '07:00',
      morningEndTime: '09:00',
      eveningStartTime: '19:00',
      eveningEndTime: '21:00',
      missedPenalty: -2.0,
    );
  }

  /// Расчёт баллов на основе статуса посещаемости
  double calculatePoints(bool isOnTime) {
    return isOnTime ? onTimePoints : latePoints;
  }

  AttendancePointsSettings copyWith({
    double? onTimePoints,
    double? latePoints,
    String? morningStartTime,
    String? morningEndTime,
    String? eveningStartTime,
    String? eveningEndTime,
    double? missedPenalty,
  }) {
    return AttendancePointsSettings(
      id: id,
      category: category,
      onTimePoints: onTimePoints ?? this.onTimePoints,
      latePoints: latePoints ?? this.latePoints,
      morningStartTime: morningStartTime ?? this.morningStartTime,
      morningEndTime: morningEndTime ?? this.morningEndTime,
      eveningStartTime: eveningStartTime ?? this.eveningStartTime,
      eveningEndTime: eveningEndTime ?? this.eveningEndTime,
      missedPenalty: missedPenalty ?? this.missedPenalty,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
