/// Модель для месячной статистики сотрудника KPI
class KPIEmployeeMonthStats {
  final String employeeName;
  final int year;
  final int month;
  final int daysWorked; // Фактически отработанные дни
  final int attendanceCount;
  final int shiftsCount; // Отчёты пересменки
  final int recountsCount;
  final int rkosCount;
  final int envelopesCount;
  final int shiftHandoversCount;

  // Данные из графика работы
  final int scheduledDays; // Запланировано смен по графику
  final int missedDays; // Пропущенные смены (был в графике, не пришёл)
  final int lateArrivals; // Количество опозданий
  final int totalLateMinutes; // Общее время опозданий в минутах

  const KPIEmployeeMonthStats({
    required this.employeeName,
    required this.year,
    required this.month,
    required this.daysWorked,
    required this.attendanceCount,
    required this.shiftsCount,
    required this.recountsCount,
    required this.rkosCount,
    required this.envelopesCount,
    required this.shiftHandoversCount,
    // Новые поля с дефолтными значениями для обратной совместимости
    this.scheduledDays = 0,
    this.missedDays = 0,
    this.lateArrivals = 0,
    this.totalLateMinutes = 0,
  });

  /// Базовое значение для расчёта процентов
  /// Если есть график - используем scheduledDays, иначе daysWorked
  int get baseDays => scheduledDays > 0 ? scheduledDays : daysWorked;

  // Дроби в формате "выполнено/всего"
  String get attendanceFraction => '$attendanceCount/$baseDays';
  String get shiftsFraction => '$shiftsCount/$baseDays';
  String get recountsFraction => '$recountsCount/$baseDays';
  String get rkosFraction => '$rkosCount/$baseDays';
  String get envelopesFraction => '$envelopesCount/$baseDays';
  String get shiftHandoversFraction => '$shiftHandoversCount/$baseDays';

  // Дополнительные дроби для опозданий и пропусков
  String get lateArrivalsFraction => '$lateArrivals/$baseDays';
  String get missedDaysFraction => '$missedDays/$scheduledDays';

  // Процент выполнения для цветовой индикации
  double get attendancePercentage => baseDays > 0 ? attendanceCount / baseDays : 0;
  double get shiftsPercentage => baseDays > 0 ? shiftsCount / baseDays : 0;
  double get recountsPercentage => baseDays > 0 ? recountsCount / baseDays : 0;
  double get rkosPercentage => baseDays > 0 ? rkosCount / baseDays : 0;
  double get envelopesPercentage => baseDays > 0 ? envelopesCount / baseDays : 0;
  double get shiftHandoversPercentage => baseDays > 0 ? shiftHandoversCount / baseDays : 0;

  // Дополнительные проценты
  double get lateArrivalsPercentage => baseDays > 0 ? lateArrivals / baseDays : 0;
  double get missedDaysPercentage => scheduledDays > 0 ? missedDays / scheduledDays : 0;

  /// Средняя продолжительность опоздания в минутах
  double get averageLateMinutes => lateArrivals > 0 ? totalLateMinutes / lateArrivals : 0;

  /// Есть ли данные из графика
  bool get hasScheduleData => scheduledDays > 0;
}
