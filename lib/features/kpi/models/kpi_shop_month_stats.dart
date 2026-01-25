/// Модель для месячной статистики магазина KPI
class KPIShopMonthStats {
  final String shopAddress;
  final int year;
  final int month;
  final int daysWorked;        // Дни с активностью
  final int attendanceCount;   // Количество приходов
  final int shiftsCount;       // Количество пересменок
  final int recountsCount;     // Количество пересчётов
  final int rkosCount;         // Количество РКО
  final int envelopesCount;    // Количество конвертов
  final int shiftHandoversCount; // Количество сдач смены

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
  });

  // Дроби в формате "выполнено/всего"
  String get attendanceFraction => '$attendanceCount/$daysWorked';
  String get shiftsFraction => '$shiftsCount/$daysWorked';
  String get recountsFraction => '$recountsCount/$daysWorked';
  String get rkosFraction => '$rkosCount/$daysWorked';
  String get envelopesFraction => '$envelopesCount/$daysWorked';
  String get shiftHandoversFraction => '$shiftHandoversCount/$daysWorked';

  // Процент выполнения для цветовой индикации
  double get attendancePercentage => daysWorked > 0 ? attendanceCount / daysWorked : 0;
  double get shiftsPercentage => daysWorked > 0 ? shiftsCount / daysWorked : 0;
  double get recountsPercentage => daysWorked > 0 ? recountsCount / daysWorked : 0;
  double get rkosPercentage => daysWorked > 0 ? rkosCount / daysWorked : 0;
  double get envelopesPercentage => daysWorked > 0 ? envelopesCount / daysWorked : 0;
  double get shiftHandoversPercentage => daysWorked > 0 ? shiftHandoversCount / daysWorked : 0;

  /// Общий процент выполнения (среднее по всем показателям)
  double get overallPercentage {
    if (daysWorked == 0) return 0;
    final total = attendancePercentage +
        shiftsPercentage +
        recountsPercentage +
        rkosPercentage +
        envelopesPercentage +
        shiftHandoversPercentage;
    return total / 6;
  }
}
