/// Модель результата теста
class TestResult {
  final String id;
  final String employeeName;
  final String employeePhone;
  final int score;
  final int totalQuestions;
  final int timeSpent; // в секундах
  final DateTime completedAt;
  final DateTime? createdAt;
  final double? points; // Начисленные баллы (может быть null для старых результатов)
  final String? shopAddress; // Магазин сотрудника

  TestResult({
    required this.id,
    required this.employeeName,
    required this.employeePhone,
    required this.score,
    required this.totalQuestions,
    required this.timeSpent,
    required this.completedAt,
    this.createdAt,
    this.points,
    this.shopAddress,
  });

  /// Создать TestResult из JSON
  factory TestResult.fromJson(Map<String, dynamic> json) {
    return TestResult(
      id: json['id'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeePhone: json['employeePhone'] ?? '',
      score: json['score'] ?? 0,
      totalQuestions: json['totalQuestions'] ?? 20,
      timeSpent: json['timeSpent'] ?? 0,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : DateTime.now(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      points: json['points'] != null ? (json['points'] as num).toDouble() : null,
      shopAddress: json['shopAddress'] as String?,
    );
  }

  /// Преобразовать TestResult в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeName': employeeName,
      'employeePhone': employeePhone,
      'score': score,
      'totalQuestions': totalQuestions,
      'timeSpent': timeSpent,
      'completedAt': completedAt.toIso8601String(),
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (points != null) 'points': points,
      if (shopAddress != null) 'shopAddress': shopAddress,
    };
  }

  /// Процент правильных ответов
  double get percentage => totalQuestions > 0 ? (score / totalQuestions) * 100 : 0;

  /// Форматированное время прохождения
  String get formattedTime {
    final minutes = timeSpent ~/ 60;
    final seconds = timeSpent % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
