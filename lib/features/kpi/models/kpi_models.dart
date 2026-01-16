/// Модель KPI данных для одного дня работы сотрудника
class KPIDayData {
  final DateTime date;
  final String employeeName;
  final String shopAddress;
  final DateTime? attendanceTime; // Время прихода (самое раннее)
  final bool hasMorningAttendance; // Есть ли отметка до 15:00
  final bool hasEveningAttendance; // Есть ли отметка после 15:00
  final bool hasShift; // Есть ли пересменка
  final bool hasRecount; // Есть ли пересчет
  final bool hasRKO; // Есть ли РКО
  final bool hasEnvelope; // Есть ли конверт
  final bool hasShiftHandover; // Есть ли сдача смены

  KPIDayData({
    required this.date,
    required this.employeeName,
    required this.shopAddress,
    this.attendanceTime,
    this.hasMorningAttendance = false,
    this.hasEveningAttendance = false,
    this.hasShift = false,
    this.hasRecount = false,
    this.hasRKO = false,
    this.hasEnvelope = false,
    this.hasShiftHandover = false,
  });

  /// Проверить, работал ли сотрудник в этот день
  bool get workedToday => attendanceTime != null || hasShift;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'employeeName': employeeName,
    'shopAddress': shopAddress,
    'attendanceTime': attendanceTime?.toIso8601String(),
    'hasMorningAttendance': hasMorningAttendance,
    'hasEveningAttendance': hasEveningAttendance,
    'hasShift': hasShift,
    'hasRecount': hasRecount,
    'hasRKO': hasRKO,
    'hasEnvelope': hasEnvelope,
    'hasShiftHandover': hasShiftHandover,
  };

  factory KPIDayData.fromJson(Map<String, dynamic> json) => KPIDayData(
    date: DateTime.parse(json['date']),
    employeeName: json['employeeName'] ?? '',
    shopAddress: json['shopAddress'] ?? '',
    attendanceTime: json['attendanceTime'] != null
        ? DateTime.parse(json['attendanceTime'])
        : null,
    hasMorningAttendance: json['hasMorningAttendance'] ?? false,
    hasEveningAttendance: json['hasEveningAttendance'] ?? false,
    hasShift: json['hasShift'] ?? false,
    hasRecount: json['hasRecount'] ?? false,
    hasRKO: json['hasRKO'] ?? false,
    hasEnvelope: json['hasEnvelope'] ?? false,
    hasShiftHandover: json['hasShiftHandover'] ?? false,
  );

  /// Создать ключ для группировки по дате (без времени)
  String get dateKey {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Модель KPI данных сотрудника за период
class KPIEmployeeData {
  final String employeeName;
  final Map<String, KPIDayData> daysData; // Данные по дням (ключ - dateKey)
  final int totalDaysWorked;
  final int totalShifts;
  final int totalRecounts;
  final int totalRKOs;

  KPIEmployeeData({
    required this.employeeName,
    required this.daysData,
    required this.totalDaysWorked,
    required this.totalShifts,
    required this.totalRecounts,
    required this.totalRKOs,
  });

  /// Получить данные за конкретный день
  KPIDayData? getDayData(DateTime date) {
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return daysData[key];
  }

  /// Получить все даты, когда сотрудник работал
  List<DateTime> get workedDates {
    return daysData.values
        .where((day) => day.workedToday)
        .map((day) => day.date)
        .toList()
      ..sort((a, b) => b.compareTo(a)); // Новые первыми
  }

  /// Получить данные за месяц
  List<KPIDayData> getMonthData(int year, int month) {
    return daysData.values
        .where((day) => day.date.year == year && day.date.month == month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date)); // Новые первыми
  }
}

/// Модель KPI данных магазина за день
class KPIShopDayData {
  final DateTime date;
  final String shopAddress;
  final List<KPIDayData> employeesData; // Данные всех сотрудников за день

  KPIShopDayData({
    required this.date,
    required this.shopAddress,
    required this.employeesData,
  });

  /// Получить количество сотрудников, которые работали в этот день
  int get employeesWorkedCount {
    return employeesData.where((data) => data.workedToday).length;
  }

  /// Проверить, есть ли утренние отметки в этот день
  bool get hasMorningAttendance {
    return employeesData.any((data) => data.hasMorningAttendance);
  }

  /// Проверить, есть ли вечерние отметки в этот день
  bool get hasEveningAttendance {
    return employeesData.any((data) => data.hasEveningAttendance);
  }

  /// Проверить, выполнены ли все действия для всех сотрудников
  /// Возвращает true, если для всех сотрудников выполнены: приход, пересменка, пересчет, РКО
  bool get allActionsCompleted {
    if (employeesData.isEmpty) return false;
    
    // Проверяем, что для всех сотрудников, которые работали, выполнены все действия
    final workingEmployees = employeesData.where((data) => data.workedToday).toList();
    if (workingEmployees.isEmpty) return false;
    
    // Для каждого сотрудника проверяем наличие всех действий
    return workingEmployees.every((data) =>
      data.attendanceTime != null && // Приход
      data.hasShift && // Пересменка
      data.hasRecount && // Пересчет
      data.hasRKO && // РКО
      data.hasEnvelope && // Конверт
      data.hasShiftHandover // Сдача смены
    );
  }

  /// Проверить, есть ли хотя бы один сотрудник, который работал
  bool get hasWorkingEmployees {
    return employeesData.any((data) => data.workedToday);
  }
}

/// Модель для отображения в таблице (для диалога дня)
class KPIDayTableRow {
  final String employeeName;
  final String? attendanceTime; // Форматированное время прихода
  final bool hasShift;
  final bool hasRecount;
  final bool hasRKO;
  final bool hasEnvelope;
  final bool hasShiftHandover;

  KPIDayTableRow({
    required this.employeeName,
    this.attendanceTime,
    this.hasShift = false,
    this.hasRecount = false,
    this.hasRKO = false,
    this.hasEnvelope = false,
    this.hasShiftHandover = false,
  });

  /// Создать из KPIDayData
  factory KPIDayTableRow.fromKPIDayData(KPIDayData data) {
    String? formattedTime;
    if (data.attendanceTime != null) {
      final time = data.attendanceTime!;
      // Используем локальное время для отображения
      final localTime = time.isUtc ? time.toLocal() : time;
      formattedTime = '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    }
    
    return KPIDayTableRow(
      employeeName: data.employeeName,
      attendanceTime: formattedTime,
      hasShift: data.hasShift,
      hasRecount: data.hasRecount,
      hasRKO: data.hasRKO,
      hasEnvelope: data.hasEnvelope,
      hasShiftHandover: data.hasShiftHandover,
    );
  }
}

/// Модель данных одного дня работы сотрудника в магазине
class KPIEmployeeShopDayData {
  final DateTime date;
  final String shopAddress;
  final String employeeName;
  final DateTime? attendanceTime; // Время прихода
  final bool hasShift; // Есть ли пересменка
  final bool hasRecount; // Есть ли пересчет
  final bool hasRKO; // Есть ли РКО
  final bool hasEnvelope; // Есть ли конверт
  final bool hasShiftHandover; // Есть ли сдача смены
  final String? rkoFileName; // Имя файла РКО (если есть)
  final String? recountReportId; // ID отчета пересчета (если есть)
  final String? shiftReportId; // ID отчета пересменки (если есть)
  final String? envelopeReportId; // ID отчета конверта (если есть)
  final String? shiftHandoverReportId; // ID отчета сдачи смены (если есть)

  KPIEmployeeShopDayData({
    required this.date,
    required this.shopAddress,
    required this.employeeName,
    this.attendanceTime,
    this.hasShift = false,
    this.hasRecount = false,
    this.hasRKO = false,
    this.hasEnvelope = false,
    this.hasShiftHandover = false,
    this.rkoFileName,
    this.recountReportId,
    this.shiftReportId,
    this.envelopeReportId,
    this.shiftHandoverReportId,
  });

  /// Проверить, выполнены ли все условия
  bool get allConditionsMet => attendanceTime != null && hasShift && hasRecount && hasRKO && hasEnvelope && hasShiftHandover;

  /// Получить форматированное время прихода
  String? get formattedAttendanceTime {
    if (attendanceTime == null) return null;
    final time = attendanceTime!.isUtc ? attendanceTime!.toLocal() : attendanceTime!;
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Получить форматированную дату
  String get formattedDate {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  /// Получить строку для отображения (Магазин - ДД.ММ.ГГГГ)
  String get displayTitle {
    return '$shopAddress - $formattedDate';
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'shopAddress': shopAddress,
    'employeeName': employeeName,
    'attendanceTime': attendanceTime?.toIso8601String(),
    'hasShift': hasShift,
    'hasRecount': hasRecount,
    'hasRKO': hasRKO,
    'hasEnvelope': hasEnvelope,
    'hasShiftHandover': hasShiftHandover,
    'rkoFileName': rkoFileName,
    'recountReportId': recountReportId,
    'shiftReportId': shiftReportId,
    'envelopeReportId': envelopeReportId,
    'shiftHandoverReportId': shiftHandoverReportId,
  };

  factory KPIEmployeeShopDayData.fromJson(Map<String, dynamic> json) => KPIEmployeeShopDayData(
    date: DateTime.parse(json['date']),
    shopAddress: json['shopAddress'] ?? '',
    employeeName: json['employeeName'] ?? '',
    attendanceTime: json['attendanceTime'] != null ? DateTime.parse(json['attendanceTime']) : null,
    hasShift: json['hasShift'] ?? false,
    hasRecount: json['hasRecount'] ?? false,
    hasRKO: json['hasRKO'] ?? false,
    hasEnvelope: json['hasEnvelope'] ?? false,
    hasShiftHandover: json['hasShiftHandover'] ?? false,
    rkoFileName: json['rkoFileName'],
    recountReportId: json['recountReportId'],
    shiftReportId: json['shiftReportId'],
    envelopeReportId: json['envelopeReportId'],
    shiftHandoverReportId: json['shiftHandoverReportId'],
  );
}

/// Модель данных сотрудника по магазинам и датам
class KPIEmployeeShopDaysData {
  final String employeeName;
  final List<KPIEmployeeShopDayData> shopDays; // Данные по всем магазинам и датам

  KPIEmployeeShopDaysData({
    required this.employeeName,
    required this.shopDays,
  });

  /// Получить данные за конкретный магазин и дату
  KPIEmployeeShopDayData? getShopDayData(String shopAddress, DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    try {
      return shopDays.firstWhere(
        (data) =>
          data.shopAddress == shopAddress &&
          data.date.year == normalizedDate.year &&
          data.date.month == normalizedDate.month &&
          data.date.day == normalizedDate.day,
      );
    } catch (e) {
      return null;
    }
  }

  /// Получить все даты работы
  List<DateTime> get allDates {
    return shopDays.map((d) => d.date).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
  }

  /// Получить все магазины
  List<String> get allShops {
    return shopDays.map((d) => d.shopAddress).toSet().toList()..sort();
  }
}


