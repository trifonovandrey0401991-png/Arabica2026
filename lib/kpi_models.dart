import 'dart:convert';

/// Модель KPI данных для одного дня работы сотрудника
class KPIDayData {
  final DateTime date;
  final String employeeName;
  final String shopAddress;
  final DateTime? attendanceTime; // Время прихода
  final bool hasShift; // Есть ли пересменка
  final bool hasRecount; // Есть ли пересчет
  final bool hasRKO; // Есть ли РКО

  KPIDayData({
    required this.date,
    required this.employeeName,
    required this.shopAddress,
    this.attendanceTime,
    this.hasShift = false,
    this.hasRecount = false,
    this.hasRKO = false,
  });

  /// Проверить, работал ли сотрудник в этот день
  bool get workedToday => attendanceTime != null || hasShift;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'employeeName': employeeName,
    'shopAddress': shopAddress,
    'attendanceTime': attendanceTime?.toIso8601String(),
    'hasShift': hasShift,
    'hasRecount': hasRecount,
    'hasRKO': hasRKO,
  };

  factory KPIDayData.fromJson(Map<String, dynamic> json) => KPIDayData(
    date: DateTime.parse(json['date']),
    employeeName: json['employeeName'] ?? '',
    shopAddress: json['shopAddress'] ?? '',
    attendanceTime: json['attendanceTime'] != null 
        ? DateTime.parse(json['attendanceTime']) 
        : null,
    hasShift: json['hasShift'] ?? false,
    hasRecount: json['hasRecount'] ?? false,
    hasRKO: json['hasRKO'] ?? false,
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
}

/// Модель для отображения в таблице (для диалога дня)
class KPIDayTableRow {
  final String employeeName;
  final String? attendanceTime; // Форматированное время прихода
  final bool hasShift;
  final bool hasRecount;
  final bool hasRKO;

  KPIDayTableRow({
    required this.employeeName,
    this.attendanceTime,
    this.hasShift = false,
    this.hasRecount = false,
    this.hasRKO = false,
  });

  /// Создать из KPIDayData
  factory KPIDayTableRow.fromKPIDayData(KPIDayData data) {
    String? formattedTime;
    if (data.attendanceTime != null) {
      final time = data.attendanceTime!;
      formattedTime = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    
    return KPIDayTableRow(
      employeeName: data.employeeName,
      attendanceTime: formattedTime,
      hasShift: data.hasShift,
      hasRecount: data.hasRecount,
      hasRKO: data.hasRKO,
    );
  }
}




