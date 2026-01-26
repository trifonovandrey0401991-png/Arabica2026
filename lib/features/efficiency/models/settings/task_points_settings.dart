import 'points_settings_base.dart';

/// Настройки баллов за обычные задачи
///
/// Использует бинарную логику (выполнено / не выполнено).
class RegularTaskPointsSettings extends PointsSettingsBase {
  @override
  String get id => 'regular_task_points';

  @override
  String get category => 'regular_task';

  @override
  DateTime? get createdAt => null;

  @override
  DateTime? get updatedAt => null;

  /// Баллы за выполненную задачу
  final double completionPoints;

  /// Баллы за невыполненную задачу (штраф)
  final double penaltyPoints;

  RegularTaskPointsSettings({
    required this.completionPoints,
    required this.penaltyPoints,
  });

  factory RegularTaskPointsSettings.defaults() {
    return RegularTaskPointsSettings(
      completionPoints: 1.0,
      penaltyPoints: -3.0,
    );
  }

  factory RegularTaskPointsSettings.fromJson(Map<String, dynamic> json) {
    return RegularTaskPointsSettings(
      completionPoints: (json['completionPoints'] as num?)?.toDouble() ?? 1.0,
      penaltyPoints: (json['penaltyPoints'] as num?)?.toDouble() ?? -3.0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'completionPoints': completionPoints,
      'penaltyPoints': penaltyPoints,
    };
  }

  /// Расчёт баллов на основе статуса задачи
  double calculatePoints(bool completed) {
    return completed ? completionPoints : penaltyPoints;
  }

  RegularTaskPointsSettings copyWith({
    double? completionPoints,
    double? penaltyPoints,
  }) {
    return RegularTaskPointsSettings(
      completionPoints: completionPoints ?? this.completionPoints,
      penaltyPoints: penaltyPoints ?? this.penaltyPoints,
    );
  }
}

/// Настройки баллов за циклические задачи
///
/// Использует бинарную логику (выполнено / не выполнено).
class RecurringTaskPointsSettings extends PointsSettingsBase {
  @override
  String get id => 'recurring_task_points';

  @override
  String get category => 'recurring_task';

  @override
  DateTime? get createdAt => null;

  @override
  DateTime? get updatedAt => null;

  /// Баллы за выполненную задачу
  final double completionPoints;

  /// Баллы за невыполненную задачу (штраф)
  final double penaltyPoints;

  RecurringTaskPointsSettings({
    required this.completionPoints,
    required this.penaltyPoints,
  });

  factory RecurringTaskPointsSettings.defaults() {
    return RecurringTaskPointsSettings(
      completionPoints: 2.0,
      penaltyPoints: -3.0,
    );
  }

  factory RecurringTaskPointsSettings.fromJson(Map<String, dynamic> json) {
    return RecurringTaskPointsSettings(
      completionPoints: (json['completionPoints'] as num?)?.toDouble() ?? 2.0,
      penaltyPoints: (json['penaltyPoints'] as num?)?.toDouble() ?? -3.0,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'completionPoints': completionPoints,
      'penaltyPoints': penaltyPoints,
    };
  }

  /// Расчёт баллов на основе статуса задачи
  double calculatePoints(bool completed) {
    return completed ? completionPoints : penaltyPoints;
  }

  RecurringTaskPointsSettings copyWith({
    double? completionPoints,
    double? penaltyPoints,
  }) {
    return RecurringTaskPointsSettings(
      completionPoints: completionPoints ?? this.completionPoints,
      penaltyPoints: penaltyPoints ?? this.penaltyPoints,
    );
  }
}
