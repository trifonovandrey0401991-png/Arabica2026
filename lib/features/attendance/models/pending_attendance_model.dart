/// Model for pending attendance report
class PendingAttendanceReport {
  final String id;
  final String shopAddress;
  final String shopName;
  final String shiftType;
  final String status; // 'pending' | 'failed'
  final DateTime createdAt;
  final DateTime deadline;
  final String? employeeName;
  final String? employeePhone;
  final DateTime? markedAt;
  final DateTime? failedAt;
  final bool? isOnTime;
  final int? lateMinutes;

  PendingAttendanceReport({
    required this.id,
    required this.shopAddress,
    required this.shopName,
    required this.shiftType,
    required this.status,
    required this.createdAt,
    required this.deadline,
    this.employeeName,
    this.employeePhone,
    this.markedAt,
    this.failedAt,
    this.isOnTime,
    this.lateMinutes,
  });

  factory PendingAttendanceReport.fromJson(Map<String, dynamic> json) {
    return PendingAttendanceReport(
      id: json['id'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      shopName: json['shopName'] ?? '',
      shiftType: json['shiftType'] ?? 'morning',
      status: json['status'] ?? 'pending',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      deadline: json['deadline'] != null
          ? DateTime.parse(json['deadline'])
          : DateTime.now(),
      employeeName: json['employeeName'],
      employeePhone: json['employeePhone'],
      markedAt: json['markedAt'] != null
          ? DateTime.parse(json['markedAt'])
          : null,
      failedAt: json['failedAt'] != null
          ? DateTime.parse(json['failedAt'])
          : null,
      isOnTime: json['isOnTime'],
      lateMinutes: json['lateMinutes'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'shopAddress': shopAddress,
    'shopName': shopName,
    'shiftType': shiftType,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'deadline': deadline.toIso8601String(),
    'employeeName': employeeName,
    'employeePhone': employeePhone,
    'markedAt': markedAt?.toIso8601String(),
    'failedAt': failedAt?.toIso8601String(),
    'isOnTime': isOnTime,
    'lateMinutes': lateMinutes,
  };

  /// Check if deadline has passed
  bool get isOverdue => DateTime.now().isAfter(deadline);

  /// Get remaining time until deadline
  Duration get timeUntilDeadline => deadline.difference(DateTime.now());

  /// Get shift type display name
  String get shiftTypeDisplay => shiftType == 'morning' ? 'Утро' : 'Вечер';
}
