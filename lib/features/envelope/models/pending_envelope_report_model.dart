/// Модель pending отчета по конверту (ожидающего или не сданного)
class PendingEnvelopeReport {
  final String id;
  final String shopAddress;
  final String shiftType; // 'morning' | 'evening'
  final String status; // 'pending' | 'failed'
  final String date; // YYYY-MM-DD
  final String deadline; // HH:MM
  final DateTime createdAt;
  final DateTime? failedAt;

  PendingEnvelopeReport({
    required this.id,
    required this.shopAddress,
    required this.shiftType,
    required this.status,
    required this.date,
    required this.deadline,
    required this.createdAt,
    this.failedAt,
  });

  factory PendingEnvelopeReport.fromJson(Map<String, dynamic> json) {
    return PendingEnvelopeReport(
      id: json['id'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      shiftType: json['shiftType'] ?? 'morning',
      status: json['status'] ?? 'pending',
      date: json['date'] ?? '',
      deadline: json['deadline'] ?? '',
      createdAt: DateTime.parse(json['createdAt']),
      failedAt: json['failedAt'] != null ? DateTime.parse(json['failedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'shopAddress': shopAddress,
        'shiftType': shiftType,
        'status': status,
        'date': date,
        'deadline': deadline,
        'createdAt': createdAt.toIso8601String(),
        'failedAt': failedAt?.toIso8601String(),
      };

  /// Тип смены на русском
  String get shiftTypeText {
    switch (shiftType) {
      case 'morning':
        return 'Утренняя';
      case 'evening':
        return 'Вечерняя';
      default:
        return shiftType;
    }
  }

  /// Статус на русском
  String get statusText {
    switch (status) {
      case 'pending':
        return 'В очереди';
      case 'failed':
        return 'Не сдан';
      default:
        return status;
    }
  }
}
