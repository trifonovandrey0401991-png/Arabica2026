/// Модель для месячной статистики магазина KPI
class KPIShopMonthStats {
  final String shopAddress;
  final int year;
  final int month;
  final int daysWorked;        // Дни с активностью (фактически)
  final int attendanceCount;   // Количество приходов
  final int shiftsCount;       // Количество пересменок
  final int recountsCount;     // Количество пересчётов
  final int rkosCount;         // Количество РКО
  final int envelopesCount;    // Количество конвертов
  final int shiftHandoversCount; // Количество сдач смены

  // Данные из графика работы
  final int scheduledDays; // Запланировано смен по графику (сумма по всем сотрудникам)
  final int missedDays; // Пропущенные смены (сотрудники не пришли)
  final int lateArrivals; // Количество опозданий
  final int totalEmployeesScheduled; // Уникальных сотрудников в графике

  const KPIShopMonthStats({
    required this.shopAddress,
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
    this.totalEmployeesScheduled = 0,
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

  // Дополнительные дроби
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

  /// Общий процент выполнения (среднее по всем показателям)
  double get overallPercentage {
    if (baseDays == 0) return 0;
    final total = attendancePercentage +
        shiftsPercentage +
        recountsPercentage +
        rkosPercentage +
        envelopesPercentage +
        shiftHandoversPercentage;
    return total / 6;
  }

  /// Есть ли данные из графика
  bool get hasScheduleData => scheduledDays > 0;
}
