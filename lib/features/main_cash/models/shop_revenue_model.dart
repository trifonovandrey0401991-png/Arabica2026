/// Направление тренда выручки
enum TrendDirection {
  up,     // Рост >10%
  stable, // Стабильно ±10%
  down,   // Падение >10%
}

/// Выручка за один день
class DailyRevenue {
  final DateTime date;
  final double oooRevenue;
  final double ipRevenue;

  double get totalRevenue => oooRevenue + ipRevenue;

  /// День месяца (1-31)
  int get day => date.day;

  DailyRevenue({
    required this.date,
    required this.oooRevenue,
    required this.ipRevenue,
  });

  /// Форматированная выручка
  String get formattedRevenue {
    if (totalRevenue >= 1000000) {
      return '${(totalRevenue / 1000000).toStringAsFixed(1)}M';
    } else if (totalRevenue >= 1000) {
      return '${(totalRevenue / 1000).toStringAsFixed(0)}k';
    } else {
      return totalRevenue.toStringAsFixed(0);
    }
  }
}

/// Данные выручки для одного магазина за период
class ShopRevenue {
  final String shopAddress;
  final DateTime startDate;
  final DateTime endDate;
  final double totalRevenue;     // Общая выручка (ООО + ИП)
  final double oooRevenue;       // Выручка ООО
  final double ipRevenue;        // Выручка ИП
  final int shiftsCount;         // Количество смен
  final double avgPerShift;      // Средняя выручка за смену

  // Сравнительные данные
  final double? prevPeriodRevenue;   // Выручка за предыдущий период
  final double? changeAmount;        // Абсолютное изменение в рублях
  final double? changePercent;       // Процент изменения
  final TrendDirection trend;        // Направление тренда

  ShopRevenue({
    required this.shopAddress,
    required this.startDate,
    required this.endDate,
    required this.totalRevenue,
    required this.oooRevenue,
    required this.ipRevenue,
    required this.shiftsCount,
    required this.avgPerShift,
    this.prevPeriodRevenue,
    this.changeAmount,
    this.changePercent,
    required this.trend,
  });

  /// Форматированная выручка (125,450 руб)
  String get formattedRevenue {
    return '${totalRevenue.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )} руб';
  }

  /// Форматированное изменение (+12.5% / -8.2%)
  String get formattedChange {
    if (changePercent == null) return 'Нет данных';

    final sign = changePercent! >= 0 ? '+' : '';
    return '$sign${changePercent!.toStringAsFixed(1)}%';
  }

  /// Форматированная сумма изменения (+12,300 руб / -5,400 руб)
  String get formattedChangeAmount {
    if (changeAmount == null) return '';

    final sign = changeAmount! >= 0 ? '+' : '';
    return '$sign${changeAmount!.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )} руб';
  }

  /// Иконка тренда (📈, 📊, 📉)
  String get trendIcon {
    switch (trend) {
      case TrendDirection.up:
        return '📈';
      case TrendDirection.stable:
        return '📊';
      case TrendDirection.down:
        return '📉';
    }
  }

  /// Цвет индикатора тренда
  String get trendColorHex {
    switch (trend) {
      case TrendDirection.up:
        return '#4CAF50'; // Зелёный
      case TrendDirection.stable:
        return '#FFA726'; // Оранжевый
      case TrendDirection.down:
        return '#EF5350'; // Красный
    }
  }

  /// Копирование с изменениями
  ShopRevenue copyWith({
    String? shopAddress,
    DateTime? startDate,
    DateTime? endDate,
    double? totalRevenue,
    double? oooRevenue,
    double? ipRevenue,
    int? shiftsCount,
    double? avgPerShift,
    double? prevPeriodRevenue,
    double? changeAmount,
    double? changePercent,
    TrendDirection? trend,
  }) {
    return ShopRevenue(
      shopAddress: shopAddress ?? this.shopAddress,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      totalRevenue: totalRevenue ?? this.totalRevenue,
      oooRevenue: oooRevenue ?? this.oooRevenue,
      ipRevenue: ipRevenue ?? this.ipRevenue,
      shiftsCount: shiftsCount ?? this.shiftsCount,
      avgPerShift: avgPerShift ?? this.avgPerShift,
      prevPeriodRevenue: prevPeriodRevenue ?? this.prevPeriodRevenue,
      changeAmount: changeAmount ?? this.changeAmount,
      changePercent: changePercent ?? this.changePercent,
      trend: trend ?? this.trend,
    );
  }
}

/// Расширение для расчёта тренда
extension TrendCalculator on double? {
  TrendDirection calculateTrend(double current) {
    if (this == null || this == 0) return TrendDirection.stable;

    final changePercent = ((current - this!) / this!) * 100;

    if (changePercent > 10) return TrendDirection.up;
    if (changePercent < -10) return TrendDirection.down;
    return TrendDirection.stable;
  }
}

/// Данные выручки за неделю
class WeeklyRevenue {
  final DateTime weekStart;  // Понедельник
  final List<double> dailyRevenues;  // 7 элементов (ПН-ВС)

  double get total => dailyRevenues.fold(0.0, (sum, v) => sum + v);

  /// Форматированная дата (dd.MM.yyyy)
  String get formattedDate {
    return '${weekStart.day.toString().padLeft(2, '0')}.${weekStart.month.toString().padLeft(2, '0')}.${weekStart.year}';
  }

  WeeklyRevenue({
    required this.weekStart,
    required this.dailyRevenues,
  });
}

/// Данные выручки за месяц (для таблицы)
class MonthlyRevenueTable {
  final int year;
  final int month;
  final List<WeeklyRevenue> weeks;
  final double totalRevenue;
  final double averageRevenue;
  final int daysWithRevenue;  // Количество дней с выручкой

  String get monthName => _getMonthName(month);

  /// Название месяца с годом
  String get monthNameWithYear => '$monthName $year';

  MonthlyRevenueTable({
    required this.year,
    required this.month,
    required this.weeks,
    required this.totalRevenue,
    required this.averageRevenue,
    required this.daysWithRevenue,
  });

  static String _getMonthName(int month) {
    const months = [
      '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    return months[month];
  }
}
