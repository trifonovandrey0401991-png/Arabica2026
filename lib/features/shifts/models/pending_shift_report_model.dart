/// Модель непройденной пересменки
class PendingShiftReport {
  final String id;
  final String shopAddress;
  final String shiftType; // "morning" | "evening"
  final String shiftLabel; // "Утро" | "Вечер"
  final String date;
  final String deadline;
  final String status; // "pending" | "completed"
  final String? completedBy;
  final DateTime createdAt;
  final DateTime? completedAt;

  PendingShiftReport({
    required this.id,
    required this.shopAddress,
    required this.shiftType,
    required this.shiftLabel,
    required this.date,
    required this.deadline,
    required this.status,
    this.completedBy,
    required this.createdAt,
    this.completedAt,
  });

  /// Проверка, является ли пересменка просроченной
  bool get isOverdue {
    if (status == 'completed') return false;

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Только для сегодняшних пересменок проверяем дедлайн
    if (date != todayStr) return false;

    final deadlineParts = deadline.split(':');
    final deadlineHour = int.parse(deadlineParts[0]);
    final deadlineMinute = int.parse(deadlineParts[1]);

    final deadlineTime = DateTime(now.year, now.month, now.day, deadlineHour, deadlineMinute);
    return now.isAfter(deadlineTime);
  }

  factory PendingShiftReport.fromJson(Map<String, dynamic> json) {
    return PendingShiftReport(
      id: json['id'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      shiftType: json['shiftType'] ?? 'morning',
      shiftLabel: json['shiftLabel'] ?? (json['shiftType'] == 'morning' ? 'Утро' : 'Вечер'),
      date: json['date'] ?? '',
      deadline: json['deadline'] ?? '',
      status: json['status'] ?? 'pending',
      completedBy: json['completedBy'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'shopAddress': shopAddress,
    'shiftType': shiftType,
    'shiftLabel': shiftLabel,
    'date': date,
    'deadline': deadline,
    'status': status,
    'completedBy': completedBy,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };
}
