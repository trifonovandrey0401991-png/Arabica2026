/// Модель рейтинга сотрудника
class EmployeeRating {
  final String employeeId;
  final String employeeName;
  final double totalPoints;
  final int shiftsCount;
  final double referralPoints;
  final double normalizedRating;
  final int position;
  final int totalEmployees;

  EmployeeRating({
    required this.employeeId,
    required this.employeeName,
    required this.totalPoints,
    required this.shiftsCount,
    required this.referralPoints,
    required this.normalizedRating,
    required this.position,
    required this.totalEmployees,
  });

  factory EmployeeRating.fromJson(Map<String, dynamic> json) {
    return EmployeeRating(
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      totalPoints: (json['totalPoints'] ?? 0).toDouble(),
      shiftsCount: json['shiftsCount'] ?? 0,
      referralPoints: (json['referralPoints'] ?? 0).toDouble(),
      normalizedRating: (json['normalizedRating'] ?? 0).toDouble(),
      position: json['position'] ?? 0,
      totalEmployees: json['totalEmployees'] ?? 0,
    );
  }

  /// Форматированная позиция (например: "3/27")
  String get positionString => '$position/$totalEmployees';

  /// Иконка для топ-3
  String get positionIcon {
    switch (position) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '📊';
    }
  }

  /// Является ли топ-3
  bool get isTop3 => position >= 1 && position <= 3;
}

/// Модель рейтинга за месяц (история)
class MonthlyRating {
  final String month;
  final String monthName;
  final String employeeId;
  final int position;
  final int totalEmployees;
  final double totalPoints;
  final int shiftsCount;
  final double referralPoints;
  final double normalizedRating;

  MonthlyRating({
    required this.month,
    required this.monthName,
    required this.employeeId,
    required this.position,
    required this.totalEmployees,
    required this.totalPoints,
    required this.shiftsCount,
    required this.referralPoints,
    required this.normalizedRating,
  });

  factory MonthlyRating.fromJson(Map<String, dynamic> json) {
    return MonthlyRating(
      month: json['month'] ?? '',
      monthName: json['monthName'] ?? '',
      employeeId: json['employeeId'] ?? '',
      position: json['position'] ?? 0,
      totalEmployees: json['totalEmployees'] ?? 0,
      totalPoints: (json['totalPoints'] ?? 0).toDouble(),
      shiftsCount: json['shiftsCount'] ?? 0,
      referralPoints: (json['referralPoints'] ?? 0).toDouble(),
      normalizedRating: (json['normalizedRating'] ?? 0).toDouble(),
    );
  }

  /// Форматированная позиция
  String get positionString => '$position/$totalEmployees';

  /// Иконка для топ-3
  String get positionIcon {
    switch (position) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '📊';
    }
  }

  /// Является ли топ-3
  bool get isTop3 => position >= 1 && position <= 3;

  /// Краткая статистика
  String get statsString =>
      'Баллы: ${totalPoints.toStringAsFixed(1)} | Смен: $shiftsCount | Рефы: ${referralPoints.toInt()}';
}
