/// Показание одного счётчика кофемашины
class CoffeeMachineReading {
  final String templateId;
  final String machineName; // "WMF 1500S"
  final String? photoUrl;
  final int? aiReadNumber; // Число, распознанное OCR
  final int confirmedNumber; // Подтверждённое число (ручное или AI)
  final bool wasManuallyEdited; // Редактировал ли сотрудник вручную
  final Map<String, double>? selectedRegion; // Область, выделенная сотрудником {x,y,width,height} 0.0-1.0

  CoffeeMachineReading({
    required this.templateId,
    required this.machineName,
    this.photoUrl,
    this.aiReadNumber,
    required this.confirmedNumber,
    this.wasManuallyEdited = false,
    this.selectedRegion,
  });

  factory CoffeeMachineReading.fromJson(Map<String, dynamic> json) {
    return CoffeeMachineReading(
      templateId: json['templateId'] ?? '',
      machineName: json['machineName'] ?? '',
      photoUrl: json['photoUrl'],
      aiReadNumber: json['aiReadNumber'],
      confirmedNumber: json['confirmedNumber'] ?? 0,
      wasManuallyEdited: json['wasManuallyEdited'] ?? false,
      selectedRegion: json['selectedRegion'] != null
          ? Map<String, double>.from((json['selectedRegion'] as Map).map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble())))
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'templateId': templateId,
    'machineName': machineName,
    'photoUrl': photoUrl,
    'aiReadNumber': aiReadNumber,
    'confirmedNumber': confirmedNumber,
    'wasManuallyEdited': wasManuallyEdited,
    if (selectedRegion != null) 'selectedRegion': selectedRegion,
  };

  CoffeeMachineReading copyWith({
    String? templateId,
    String? machineName,
    String? photoUrl,
    int? aiReadNumber,
    int? confirmedNumber,
    bool? wasManuallyEdited,
    Map<String, double>? selectedRegion,
  }) {
    return CoffeeMachineReading(
      templateId: templateId ?? this.templateId,
      machineName: machineName ?? this.machineName,
      photoUrl: photoUrl ?? this.photoUrl,
      aiReadNumber: aiReadNumber ?? this.aiReadNumber,
      confirmedNumber: confirmedNumber ?? this.confirmedNumber,
      wasManuallyEdited: wasManuallyEdited ?? this.wasManuallyEdited,
      selectedRegion: selectedRegion ?? this.selectedRegion,
    );
  }
}

/// Отчёт по счётчикам кофемашин за одну смену
class CoffeeMachineReport {
  final String id;
  final String employeeName;
  final String shopAddress;
  final String shiftType; // 'morning' | 'evening'
  final String date; // YYYY-MM-DD
  final List<CoffeeMachineReading> readings;

  // Показание компьютера (отрицательное число с копейками, напр. -138141.20)
  final double computerNumber;
  final String? computerPhotoUrl;

  // Сверка: computerNumber + sumOfMachines должно быть = 0
  final int sumOfMachines; // Сумма показаний всех машин (положительная)
  final bool hasDiscrepancy; // Есть расхождение
  final double discrepancyAmount; // Размер расхождения

  // Статус
  final String status; // 'pending' | 'confirmed' | 'failed' | 'expired'
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final String? confirmedByAdmin;
  final int? rating;

  CoffeeMachineReport({
    required this.id,
    required this.employeeName,
    required this.shopAddress,
    required this.shiftType,
    required this.date,
    this.readings = const [],
    this.computerNumber = 0.0,
    this.computerPhotoUrl,
    this.sumOfMachines = 0,
    this.hasDiscrepancy = false,
    this.discrepancyAmount = 0.0,
    this.status = 'pending',
    required this.createdAt,
    this.confirmedAt,
    this.confirmedByAdmin,
    this.rating,
  });

  /// Парсит дату из JSON, обрабатывая UTC и локальное время
  static DateTime _parseDateTime(String dateStr) {
    if (!dateStr.endsWith('Z') && !dateStr.contains('+')) {
      dateStr = '${dateStr}Z';
    }
    return DateTime.parse(dateStr).toLocal();
  }

  factory CoffeeMachineReport.fromJson(Map<String, dynamic> json) {
    List<CoffeeMachineReading> readings = [];
    if (json['readings'] != null && json['readings'] is List) {
      readings = (json['readings'] as List)
          .map((e) => CoffeeMachineReading.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return CoffeeMachineReport(
      id: json['id'] ?? '',
      employeeName: json['employeeName'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      shiftType: json['shiftType'] ?? 'morning',
      date: json['date'] ?? '',
      readings: readings,
      computerNumber: (json['computerNumber'] ?? 0).toDouble(),
      computerPhotoUrl: json['computerPhotoUrl'],
      sumOfMachines: json['sumOfMachines'] ?? 0,
      hasDiscrepancy: json['hasDiscrepancy'] ?? false,
      discrepancyAmount: (json['discrepancyAmount'] ?? 0).toDouble(),
      status: json['status'] ?? 'pending',
      createdAt: json['createdAt'] != null
          ? _parseDateTime(json['createdAt'])
          : DateTime.now(),
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
    'date': date,
    'readings': readings.map((e) => e.toJson()).toList(),
    'computerNumber': computerNumber,
    'computerPhotoUrl': computerPhotoUrl,
    'sumOfMachines': sumOfMachines,
    'hasDiscrepancy': hasDiscrepancy,
    'discrepancyAmount': discrepancyAmount,
    'status': status,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'confirmedAt': confirmedAt?.toUtc().toIso8601String(),
    'confirmedByAdmin': confirmedByAdmin,
    'rating': rating,
  };

  CoffeeMachineReport copyWith({
    String? id,
    String? employeeName,
    String? shopAddress,
    String? shiftType,
    String? date,
    List<CoffeeMachineReading>? readings,
    double? computerNumber,
    String? computerPhotoUrl,
    int? sumOfMachines,
    bool? hasDiscrepancy,
    double? discrepancyAmount,
    String? status,
    DateTime? createdAt,
    DateTime? confirmedAt,
    String? confirmedByAdmin,
    int? rating,
  }) {
    return CoffeeMachineReport(
      id: id ?? this.id,
      employeeName: employeeName ?? this.employeeName,
      shopAddress: shopAddress ?? this.shopAddress,
      shiftType: shiftType ?? this.shiftType,
      date: date ?? this.date,
      readings: readings ?? this.readings,
      computerNumber: computerNumber ?? this.computerNumber,
      computerPhotoUrl: computerPhotoUrl ?? this.computerPhotoUrl,
      sumOfMachines: sumOfMachines ?? this.sumOfMachines,
      hasDiscrepancy: hasDiscrepancy ?? this.hasDiscrepancy,
      discrepancyAmount: discrepancyAmount ?? this.discrepancyAmount,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      confirmedByAdmin: confirmedByAdmin ?? this.confirmedByAdmin,
      rating: rating ?? this.rating,
    );
  }

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
      case 'failed':
        return 'Не сдан';
      case 'expired':
        return 'Просрочен';
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
