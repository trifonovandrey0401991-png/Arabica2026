/// Модель KPI данных для одного дня работы сотрудника
class KPIDayData {
  final DateTime date;
  final String employeeName;
  final String shopAddress;
  final DateTime? attendanceTime; // Время прихода (самое раннее)
  final bool hasMorningAttendance; // Есть ли отметка до 15:00
  final bool hasEveningAttendance; // Есть ли отметка после 15:00
  final bool hasShift; // Есть ли отчёт о пересменке (НЕ запланированная смена!)
  final bool hasRecount; // Есть ли пересчет
  final bool hasRKO; // Есть ли РКО
  final bool hasEnvelope; // Есть ли конверт
  final bool hasShiftHandover; // Есть ли сдача смены

  // Данные из графика работы (WorkSchedule)
  final bool isScheduled; // Была ли запланирована смена на этот день
  final String? scheduledShiftType; // Тип смены: morning/day/evening
  final DateTime? scheduledStartTime; // Время начала смены по графику
  final bool isLate; // Опоздал ли сотрудник
  final int? lateMinutes; // На сколько минут опоздал

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
    // Поля графика
    this.isScheduled = false,
    this.scheduledShiftType,
    this.scheduledStartTime,
    this.isLate = false,
    this.lateMinutes,
  });

  /// Проверить, работал ли сотрудник в этот день
  bool get workedToday => attendanceTime != null || hasShift;

  /// Пропустил ли смену (была в графике, но не пришёл)
  bool get missedShift => isScheduled && !workedToday;

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
    // Поля графика
    'isScheduled': isScheduled,
    'scheduledShiftType': scheduledShiftType,
    'scheduledStartTime': scheduledStartTime?.toIso8601String(),
    'isLate': isLate,
    'lateMinutes': lateMinutes,
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
    // Поля графика
    isScheduled: json['isScheduled'] ?? false,
    scheduledShiftType: json['scheduledShiftType'],
    scheduledStartTime: json['scheduledStartTime'] != null
        ? DateTime.parse(json['scheduledStartTime'])
        : null,
    isLate: json['isLate'] ?? false,
    lateMinutes: json['lateMinutes'],
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

  // ====== МЕТОДЫ ДЛЯ УТРЕННЕЙ/ВЕЧЕРНЕЙ СМЕНЫ ======

  /// Сотрудники утренней смены:
  /// - С отметкой до 15:00 (hasMorningAttendance)
  /// - ИЛИ работали, но смена не определена (нет отметки прихода)
  List<KPIDayData> get morningEmployees {
    return employeesData.where((data) {
      // Явно утренняя смена
      if (data.hasMorningAttendance) return true;
      // Работал, но смена не определена - считаем утренней по умолчанию
      if (data.workedToday && !data.hasMorningAttendance && !data.hasEveningAttendance) return true;
      return false;
    }).toList();
  }

  /// Сотрудники вечерней смены (с отметкой после 15:00)
  List<KPIDayData> get eveningEmployees {
    return employeesData.where((data) => data.hasEveningAttendance).toList();
  }

  /// Есть ли хотя бы один сотрудник утренней смены
  bool get hasMorningEmployees => morningEmployees.isNotEmpty;

  /// Есть ли хотя бы один сотрудник вечерней смены
  bool get hasEveningEmployees => eveningEmployees.isNotEmpty;

  /// Статус утренней смены: 1 = всё выполнено, 0.5 = частично, 0 = ничего
  double get morningCompletionStatus {
    final employees = morningEmployees;
    if (employees.isEmpty) return -1; // Нет данных

    int fullyCompleted = 0;
    int partiallyCompleted = 0;

    for (final data in employees) {
      final hasAttendance = data.attendanceTime != null;
      final hasShift = data.hasShift;
      final hasRecount = data.hasRecount;
      final hasRKO = data.hasRKO;
      final hasEnvelope = data.hasEnvelope;
      final hasShiftHandover = data.hasShiftHandover;

      final completedCount = [hasAttendance, hasShift, hasRecount, hasRKO, hasEnvelope, hasShiftHandover]
          .where((v) => v).length;

      if (completedCount == 6) {
        fullyCompleted++;
      } else if (completedCount > 0) {
        partiallyCompleted++;
      }
    }

    if (fullyCompleted == employees.length) {
      return 1; // Все выполнено (зелёный)
    } else if (fullyCompleted > 0 || partiallyCompleted > 0) {
      return 0.5; // Частично выполнено (жёлтый)
    }
    return 0; // Ничего не выполнено (красный)
  }

  /// Статус вечерней смены: 1 = всё выполнено, 0.5 = частично, 0 = ничего
  double get eveningCompletionStatus {
    final employees = eveningEmployees;
    if (employees.isEmpty) return -1; // Нет данных

    int fullyCompleted = 0;
    int partiallyCompleted = 0;

    for (final data in employees) {
      final hasAttendance = data.attendanceTime != null;
      final hasShift = data.hasShift;
      final hasRecount = data.hasRecount;
      final hasRKO = data.hasRKO;
      final hasEnvelope = data.hasEnvelope;
      final hasShiftHandover = data.hasShiftHandover;

      final completedCount = [hasAttendance, hasShift, hasRecount, hasRKO, hasEnvelope, hasShiftHandover]
          .where((v) => v).length;

      if (completedCount == 6) {
        fullyCompleted++;
      } else if (completedCount > 0) {
        partiallyCompleted++;
      }
    }

    if (fullyCompleted == employees.length) {
      return 1; // Все выполнено (зелёный)
    } else if (fullyCompleted > 0 || partiallyCompleted > 0) {
      return 0.5; // Частично выполнено (жёлтый)
    }
    return 0; // Ничего не выполнено (красный)
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
  final bool hasShift; // Есть ли отчёт о пересменке (НЕ запланированная смена!)
  final bool hasRecount; // Есть ли пересчет
  final bool hasRKO; // Есть ли РКО
  final bool hasEnvelope; // Есть ли конверт
  final bool hasShiftHandover; // Есть ли сдача смены
  final String? rkoFileName; // Имя файла РКО (если есть)
  final String? recountReportId; // ID отчета пересчета (если есть)
  final String? shiftReportId; // ID отчета пересменки (если есть)
  final String? envelopeReportId; // ID отчета конверта (если есть)
  final String? shiftHandoverReportId; // ID отчета сдачи смены (если есть)

  // Данные из графика работы (WorkSchedule)
  final bool isScheduled; // Была ли запланирована смена на этот день
  final String? scheduledShiftType; // Тип смены: morning/day/evening
  final DateTime? scheduledStartTime; // Время начала смены по графику
  final bool isLate; // Опоздал ли сотрудник
  final int? lateMinutes; // На сколько минут опоздал

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
    // Поля графика
    this.isScheduled = false,
    this.scheduledShiftType,
    this.scheduledStartTime,
    this.isLate = false,
    this.lateMinutes,
  });

  /// Проверить, выполнены ли все условия
  bool get allConditionsMet => attendanceTime != null && hasShift && hasRecount && hasRKO && hasEnvelope && hasShiftHandover;

  /// Пропустил ли смену (была в графике, но не пришёл)
  bool get missedShift => isScheduled && attendanceTime == null && !hasShift;

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
    // Поля графика
    'isScheduled': isScheduled,
    'scheduledShiftType': scheduledShiftType,
    'scheduledStartTime': scheduledStartTime?.toIso8601String(),
    'isLate': isLate,
    'lateMinutes': lateMinutes,
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
    // Поля графика
    isScheduled: json['isScheduled'] ?? false,
    scheduledShiftType: json['scheduledShiftType'],
    scheduledStartTime: json['scheduledStartTime'] != null
        ? DateTime.parse(json['scheduledStartTime'])
        : null,
    isLate: json['isLate'] ?? false,
    lateMinutes: json['lateMinutes'],
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


