/// Модель расхода в конверте
class ExpenseItem {
  final String supplierId;
  final String supplierName;
  final double amount;
  final String? comment;

  ExpenseItem({
    required this.supplierId,
    required this.supplierName,
    required this.amount,
    this.comment,
  });

  factory ExpenseItem.fromJson(Map<String, dynamic> json) {
    return ExpenseItem(
      supplierId: json['supplierId'] ?? '',
      supplierName: json['supplierName'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      comment: json['comment'],
    );
  }

  Map<String, dynamic> toJson() => {
    'supplierId': supplierId,
    'supplierName': supplierName,
    'amount': amount,
    'comment': comment,
  };

  ExpenseItem copyWith({
    String? supplierId,
    String? supplierName,
    double? amount,
    String? comment,
  }) {
    return ExpenseItem(
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      amount: amount ?? this.amount,
      comment: comment ?? this.comment,
    );
  }
}

/// Модель отчета конверта
class EnvelopeReport {
  final String id;
  final String employeeName;
  final String shopAddress;
  final String shiftType; // 'morning' | 'evening'
  final DateTime createdAt;

  // ООО данные
  final String? oooZReportPhotoUrl;
  final double oooRevenue;
  final double oooCash;
  final String? oooEnvelopePhotoUrl;

  // ИП данные
  final String? ipZReportPhotoUrl;
  final double ipRevenue;
  final double ipCash;
  final List<ExpenseItem> expenses;
  final String? ipEnvelopePhotoUrl;

  // Статус
  final String status; // 'pending' | 'confirmed'
  final DateTime? confirmedAt;
  final String? confirmedByAdmin;
  final int? rating;

  EnvelopeReport({
    required this.id,
    required this.employeeName,
    required this.shopAddress,
    required this.shiftType,
    required this.createdAt,
    this.oooZReportPhotoUrl,
    this.oooRevenue = 0,
    this.oooCash = 0,
    this.oooEnvelopePhotoUrl,
    this.ipZReportPhotoUrl,
    this.ipRevenue = 0,
    this.ipCash = 0,
    this.expenses = const [],
    this.ipEnvelopePhotoUrl,
    this.status = 'pending',
    this.confirmedAt,
    this.confirmedByAdmin,
    this.rating,
  });

  /// Парсит дату из JSON, обрабатывая UTC и локальное время
  static DateTime _parseDateTime(String dateStr) {
    // Если строка не заканчивается на Z, добавляем Z чтобы считать её UTC
    if (!dateStr.endsWith('Z') && !dateStr.contains('+')) {
      dateStr = '${dateStr}Z';
    }
    return DateTime.parse(dateStr).toLocal();
  }

  factory EnvelopeReport.fromJson(Map<String, dynamic> json) {
    List<ExpenseItem> expenses = [];
    if (json['expenses'] != null && json['expenses'] is List) {
      expenses = (json['expenses'] as List)
          .map((e) => ExpenseItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return EnvelopeReport(
      id: json['id'] ?? '',
      employeeName: json['employeeName'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      shiftType: json['shiftType'] ?? 'morning',
      createdAt: json['createdAt'] != null
          ? _parseDateTime(json['createdAt'])
          : DateTime.now(),
      oooZReportPhotoUrl: json['oooZReportPhotoUrl'],
      oooRevenue: (json['oooRevenue'] ?? 0).toDouble(),
      oooCash: (json['oooCash'] ?? 0).toDouble(),
      oooEnvelopePhotoUrl: json['oooEnvelopePhotoUrl'],
      ipZReportPhotoUrl: json['ipZReportPhotoUrl'],
      ipRevenue: (json['ipRevenue'] ?? 0).toDouble(),
      ipCash: (json['ipCash'] ?? 0).toDouble(),
      expenses: expenses,
      ipEnvelopePhotoUrl: json['ipEnvelopePhotoUrl'],
      status: json['status'] ?? 'pending',
      confirmedAt: json['confirmedAt'] != null
          ? _parseDateTime(json['confirmedAt'])
          : null,
      confirmedByAdmin: json['confirmedByAdmin'],
      rating: json['rating'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeName': employeeName,
    'shopAddress': shopAddress,
    'shiftType': shiftType,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'oooZReportPhotoUrl': oooZReportPhotoUrl,
    'oooRevenue': oooRevenue,
    'oooCash': oooCash,
    'oooEnvelopePhotoUrl': oooEnvelopePhotoUrl,
    'ipZReportPhotoUrl': ipZReportPhotoUrl,
    'ipRevenue': ipRevenue,
    'ipCash': ipCash,
    'expenses': expenses.map((e) => e.toJson()).toList(),
    'ipEnvelopePhotoUrl': ipEnvelopePhotoUrl,
    'status': status,
    'confirmedAt': confirmedAt?.toUtc().toIso8601String(),
    'confirmedByAdmin': confirmedByAdmin,
    'rating': rating,
  };

  EnvelopeReport copyWith({
    String? id,
    String? employeeName,
    String? shopAddress,
    String? shiftType,
    DateTime? createdAt,
    String? oooZReportPhotoUrl,
    double? oooRevenue,
    double? oooCash,
    String? oooEnvelopePhotoUrl,
    String? ipZReportPhotoUrl,
    double? ipRevenue,
    double? ipCash,
    List<ExpenseItem>? expenses,
    String? ipEnvelopePhotoUrl,
    String? status,
    DateTime? confirmedAt,
    String? confirmedByAdmin,
    int? rating,
  }) {
    return EnvelopeReport(
      id: id ?? this.id,
      employeeName: employeeName ?? this.employeeName,
      shopAddress: shopAddress ?? this.shopAddress,
      shiftType: shiftType ?? this.shiftType,
      createdAt: createdAt ?? this.createdAt,
      oooZReportPhotoUrl: oooZReportPhotoUrl ?? this.oooZReportPhotoUrl,
      oooRevenue: oooRevenue ?? this.oooRevenue,
      oooCash: oooCash ?? this.oooCash,
      oooEnvelopePhotoUrl: oooEnvelopePhotoUrl ?? this.oooEnvelopePhotoUrl,
      ipZReportPhotoUrl: ipZReportPhotoUrl ?? this.ipZReportPhotoUrl,
      ipRevenue: ipRevenue ?? this.ipRevenue,
      ipCash: ipCash ?? this.ipCash,
      expenses: expenses ?? this.expenses,
      ipEnvelopePhotoUrl: ipEnvelopePhotoUrl ?? this.ipEnvelopePhotoUrl,
      status: status ?? this.status,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      confirmedByAdmin: confirmedByAdmin ?? this.confirmedByAdmin,
      rating: rating ?? this.rating,
    );
  }

  /// Общая сумма расходов ИП
  double get totalExpenses {
    return expenses.fold(0.0, (sum, e) => sum + e.amount);
  }

  /// Сумма в конверте ООО (наличные)
  double get oooEnvelopeAmount => oooCash;

  /// Сумма в конверте ИП (наличные минус расходы)
  double get ipEnvelopeAmount => ipCash - totalExpenses;

  /// Общая сумма в конвертах
  double get totalEnvelopeAmount => oooEnvelopeAmount + ipEnvelopeAmount;

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
        return 'Ожидает проверки';
      case 'confirmed':
        return 'Подтверждён';
      default:
        return status;
    }
  }

  /// Просрочен ли отчет (более 24 часов без подтверждения)
  bool get isExpired {
    if (status == 'confirmed') return false;
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    return diff.inHours >= 24;
  }
}
