/// Модель непройденного пересчёта
class PendingRecountReport {
  final String id;
  final String shopAddress;
  final String date;
  final String status; // "pending" | "completed"
  final String? completedBy;
  final DateTime createdAt;
  final DateTime? completedAt;

  PendingRecountReport({
    required this.id,
    required this.shopAddress,
    required this.date,
    required this.status,
    this.completedBy,
    required this.createdAt,
    this.completedAt,
  });

  factory PendingRecountReport.fromJson(Map<String, dynamic> json) {
    return PendingRecountReport(
      id: json['id'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      date: json['date'] ?? '',
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
    'date': date,
    'status': status,
    'completedBy': completedBy,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };
}
