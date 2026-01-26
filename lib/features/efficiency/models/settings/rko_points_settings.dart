import 'points_settings_base.dart';

/// Настройки баллов за РКО (расходные кассовые ордера)
///
/// Использует бинарную логику (есть РКО / нет РКО).
/// Включает временные окна для утренней и вечерней смены.
class RkoPointsSettings extends PointsSettingsBase with TimeWindowSettings {
  @override
  final String id;

  @override
  final String category;

  /// Баллы когда РКО есть
  final double hasRkoPoints;

  /// Баллы когда РКО нет (отрицательные)
  final double noRkoPoints;

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

  RkoPointsSettings({
    this.id = 'rko_points',
    this.category = 'rko',
    required this.hasRkoPoints,
    required this.noRkoPoints,
    this.morningStartTime = '07:00',
    this.morningEndTime = '14:00',
    this.eveningStartTime = '14:00',
    this.eveningEndTime = '23:00',
    this.missedPenalty = -3.0,
    this.createdAt,
    this.updatedAt,
  });

  factory RkoPointsSettings.fromJson(Map<String, dynamic> json) {
    return RkoPointsSettings(
      id: json['id'] ?? 'rko_points',
      category: json['category'] ?? 'rko',
      hasRkoPoints: (json['hasRkoPoints'] ?? 1).toDouble(),
      noRkoPoints: (json['noRkoPoints'] ?? -3).toDouble(),
      morningStartTime: json['morningStartTime'] ?? '07:00',
      morningEndTime: json['morningEndTime'] ?? '14:00',
      eveningStartTime: json['eveningStartTime'] ?? '14:00',
      eveningEndTime: json['eveningEndTime'] ?? '23:00',
      missedPenalty: (json['missedPenalty'] ?? -3.0).toDouble(),
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
    'hasRkoPoints': hasRkoPoints,
    'noRkoPoints': noRkoPoints,
    'morningStartTime': morningStartTime,
    'morningEndTime': morningEndTime,
    'eveningStartTime': eveningStartTime,
    'eveningEndTime': eveningEndTime,
    'missedPenalty': missedPenalty,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Настройки по умолчанию
  factory RkoPointsSettings.defaults() {
    return RkoPointsSettings(
      hasRkoPoints: 1,
      noRkoPoints: -3,
      morningStartTime: '07:00',
      morningEndTime: '14:00',
      eveningStartTime: '14:00',
      eveningEndTime: '23:00',
      missedPenalty: -3.0,
    );
  }

  /// Расчёт баллов на основе статуса РКО
  double calculatePoints(bool hasRko) {
    return hasRko ? hasRkoPoints : noRkoPoints;
  }

  RkoPointsSettings copyWith({
    double? hasRkoPoints,
    double? noRkoPoints,
    String? morningStartTime,
    String? morningEndTime,
    String? eveningStartTime,
    String? eveningEndTime,
    double? missedPenalty,
  }) {
    return RkoPointsSettings(
      id: id,
      category: category,
      hasRkoPoints: hasRkoPoints ?? this.hasRkoPoints,
      noRkoPoints: noRkoPoints ?? this.noRkoPoints,
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
