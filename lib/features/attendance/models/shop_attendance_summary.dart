import 'attendance_model.dart';

/// Сводка по приходам для одного магазина
class ShopAttendanceSummary {
  final String shopAddress;
  final int todayAttendanceCount;
  final MonthAttendanceSummary currentMonth;
  final MonthAttendanceSummary previousMonth;
  final int totalRecords;   // Плановое количество (дни в месяце * 2)
  final int onTimeRecords;  // Фактическое количество приходов вовремя

  ShopAttendanceSummary({
    required this.shopAddress,
    required this.todayAttendanceCount,
    required this.currentMonth,
    required this.previousMonth,
    this.totalRecords = 0,
    this.onTimeRecords = 0,
  });

  /// День считается выполненным если есть минимум 2 отметки (утро + ночь)
  bool get isTodayComplete => todayAttendanceCount >= 2;

  /// Процент приходов вовремя (0-100)
  /// onTimeRecords / totalRecords * 100, где totalRecords = дни в месяце * 2
  double get onTimeRate => totalRecords > 0 ? (onTimeRecords / totalRecords) * 100 : 0;
}

/// Сводка по приходам за месяц
class MonthAttendanceSummary {
  final int year;
  final int month;
  final int actualCount;
  final int plannedCount;
  final List<DayAttendanceSummary> days;

  MonthAttendanceSummary({
    required this.year,
    required this.month,
    required this.actualCount,
    required this.plannedCount,
    required this.days,
  });

  String get displayName {
    const monthNames = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    return monthNames[month - 1];
  }

  /// Процент выполнения плана
  double get completionRate => plannedCount > 0 ? actualCount / plannedCount : 0;

  /// Статус: good (>90%), warning (70-90%), bad (<70%)
  String get status {
    if (completionRate >= 0.9) return 'good';
    if (completionRate >= 0.7) return 'warning';
    return 'bad';
  }
}

/// Сводка по приходам за один день
class DayAttendanceSummary {
  final DateTime date;
  final int attendanceCount;
  final bool hasMorning;
  final bool hasNight;
  final bool hasDay;
  final List<AttendanceRecord> records;

  DayAttendanceSummary({
    required this.date,
    required this.attendanceCount,
    required this.hasMorning,
    required this.hasNight,
    required this.hasDay,
    required this.records,
  });

  /// День считается выполненным если есть утро + ночь
  bool get isComplete => hasMorning && hasNight;

  /// Статус для отображения
  String get statusIcon {
    if (isComplete) return '✓';
    if (hasMorning || hasNight) return '⚠';
    return '✗';
  }
}
