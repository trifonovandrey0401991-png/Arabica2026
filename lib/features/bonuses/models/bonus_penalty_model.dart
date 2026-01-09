/// Модель для премий и штрафов
class BonusPenalty {
  final String id;
  final String employeeId;
  final String employeeName;
  final String type; // 'bonus' или 'penalty'
  final double amount;
  final String comment;
  final String adminName;
  final DateTime createdAt;
  final String month;

  BonusPenalty({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.type,
    required this.amount,
    required this.comment,
    required this.adminName,
    required this.createdAt,
    required this.month,
  });

  bool get isBonus => type == 'bonus';
  bool get isPenalty => type == 'penalty';

  /// Сумма со знаком (+ для бонуса, - для штрафа)
  double get signedAmount => isBonus ? amount : -amount;

  factory BonusPenalty.fromJson(Map<String, dynamic> json) {
    return BonusPenalty(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      type: json['type'] ?? 'bonus',
      amount: (json['amount'] ?? 0).toDouble(),
      comment: json['comment'] ?? '',
      adminName: json['adminName'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      month: json['month'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'type': type,
      'amount': amount,
      'comment': comment,
      'adminName': adminName,
      'createdAt': createdAt.toIso8601String(),
      'month': month,
    };
  }
}

/// Сводка по премиям/штрафам для сотрудника
class BonusPenaltySummary {
  final double currentMonthTotal;
  final List<BonusPenalty> currentMonthRecords;
  final double previousMonthTotal;
  final List<BonusPenalty> previousMonthRecords;

  BonusPenaltySummary({
    required this.currentMonthTotal,
    required this.currentMonthRecords,
    required this.previousMonthTotal,
    required this.previousMonthRecords,
  });

  factory BonusPenaltySummary.fromJson(Map<String, dynamic> json) {
    final currentMonth = json['currentMonth'] ?? {};
    final previousMonth = json['previousMonth'] ?? {};

    return BonusPenaltySummary(
      currentMonthTotal: (currentMonth['total'] ?? 0).toDouble(),
      currentMonthRecords: (currentMonth['records'] as List<dynamic>? ?? [])
          .map((r) => BonusPenalty.fromJson(r))
          .toList(),
      previousMonthTotal: (previousMonth['total'] ?? 0).toDouble(),
      previousMonthRecords: (previousMonth['records'] as List<dynamic>? ?? [])
          .map((r) => BonusPenalty.fromJson(r))
          .toList(),
    );
  }

  factory BonusPenaltySummary.empty() {
    return BonusPenaltySummary(
      currentMonthTotal: 0,
      currentMonthRecords: [],
      previousMonthTotal: 0,
      previousMonthRecords: [],
    );
  }
}
