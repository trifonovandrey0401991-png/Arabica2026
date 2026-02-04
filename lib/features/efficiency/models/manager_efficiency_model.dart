/// Модель данных эффективности управляющего (admin)
///
/// Структура:
/// - Общий % = (Эффективность магазинов + Эффективность отчётов) / 2
/// - Эффективность магазинов (50%) - агрегация баллов сотрудников по managedShopIds
/// - Эффективность отчётов (50%) - баллы за проверку отчётов + задачи

class ManagerEfficiencyData {
  /// Общий процент эффективности (среднее от магазинов и отчётов)
  final double totalPercentage;

  /// Процент эффективности магазинов (агрегация сотрудников)
  final double shopEfficiencyPercentage;

  /// Процент эффективности отчётов (проверка + задачи)
  final double reviewEfficiencyPercentage;

  /// Разбивка по магазинам
  final List<ShopEfficiencyItem> shopBreakdown;

  /// Разбивка по категориям отчётов
  final CategoryBreakdown categoryBreakdown;

  /// Сравнение с прошлым месяцем
  final PreviousMonthComparison? comparison;

  ManagerEfficiencyData({
    required this.totalPercentage,
    required this.shopEfficiencyPercentage,
    required this.reviewEfficiencyPercentage,
    required this.shopBreakdown,
    required this.categoryBreakdown,
    this.comparison,
  });

  factory ManagerEfficiencyData.fromJson(Map<String, dynamic> json) {
    return ManagerEfficiencyData(
      totalPercentage: (json['totalPercentage'] ?? 0.0).toDouble(),
      shopEfficiencyPercentage: (json['shopEfficiencyPercentage'] ?? 0.0).toDouble(),
      reviewEfficiencyPercentage: (json['reviewEfficiencyPercentage'] ?? 0.0).toDouble(),
      shopBreakdown: (json['shopBreakdown'] as List<dynamic>?)
              ?.map((item) => ShopEfficiencyItem.fromJson(item))
              .toList() ??
          [],
      categoryBreakdown: json['categoryBreakdown'] != null
          ? CategoryBreakdown.fromJson(json['categoryBreakdown'])
          : CategoryBreakdown.empty(),
      comparison: json['comparison'] != null
          ? PreviousMonthComparison.fromJson(json['comparison'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'totalPercentage': totalPercentage,
        'shopEfficiencyPercentage': shopEfficiencyPercentage,
        'reviewEfficiencyPercentage': reviewEfficiencyPercentage,
        'shopBreakdown': shopBreakdown.map((s) => s.toJson()).toList(),
        'categoryBreakdown': categoryBreakdown.toJson(),
        if (comparison != null) 'comparison': comparison!.toJson(),
      };

  factory ManagerEfficiencyData.empty() {
    return ManagerEfficiencyData(
      totalPercentage: 0,
      shopEfficiencyPercentage: 0,
      reviewEfficiencyPercentage: 0,
      shopBreakdown: [],
      categoryBreakdown: CategoryBreakdown.empty(),
    );
  }
}

/// Эффективность одного магазина
class ShopEfficiencyItem {
  /// ID магазина
  final String shopId;

  /// Название магазина
  final String shopName;

  /// Общие баллы сотрудников магазина
  final double totalPoints;

  /// Процент от теоретического максимума
  final double percentage;

  /// Изменение по сравнению с прошлым месяцем
  final double? previousMonthChange;

  ShopEfficiencyItem({
    required this.shopId,
    required this.shopName,
    required this.totalPoints,
    required this.percentage,
    this.previousMonthChange,
  });

  factory ShopEfficiencyItem.fromJson(Map<String, dynamic> json) {
    return ShopEfficiencyItem(
      shopId: json['shopId'] ?? '',
      shopName: json['shopName'] ?? 'Магазин',
      totalPoints: (json['totalPoints'] ?? 0.0).toDouble(),
      percentage: (json['percentage'] ?? 0.0).toDouble(),
      previousMonthChange: json['previousMonthChange']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'shopId': shopId,
        'shopName': shopName,
        'totalPoints': totalPoints,
        'percentage': percentage,
        if (previousMonthChange != null) 'previousMonthChange': previousMonthChange,
      };
}

/// Разбивка баллов по категориям отчётов
class CategoryBreakdown {
  /// Баллы за пересменки
  final double shiftPoints;

  /// Баллы за пересчёты
  final double recountPoints;

  /// Баллы за сдачу смены
  final double shiftHandoverPoints;

  /// Баллы за задачи
  final double tasksPoints;

  /// Изменение по сравнению с прошлым месяцем для каждой категории
  final double? shiftChange;
  final double? recountChange;
  final double? shiftHandoverChange;
  final double? tasksChange;

  CategoryBreakdown({
    required this.shiftPoints,
    required this.recountPoints,
    required this.shiftHandoverPoints,
    required this.tasksPoints,
    this.shiftChange,
    this.recountChange,
    this.shiftHandoverChange,
    this.tasksChange,
  });

  factory CategoryBreakdown.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdown(
      shiftPoints: (json['shiftPoints'] ?? json['shift'] ?? 0.0).toDouble(),
      recountPoints: (json['recountPoints'] ?? json['recount'] ?? 0.0).toDouble(),
      shiftHandoverPoints: (json['shiftHandoverPoints'] ?? json['shiftHandover'] ?? 0.0).toDouble(),
      tasksPoints: (json['tasksPoints'] ?? json['tasks'] ?? 0.0).toDouble(),
      shiftChange: json['shiftChange']?.toDouble(),
      recountChange: json['recountChange']?.toDouble(),
      shiftHandoverChange: json['shiftHandoverChange']?.toDouble(),
      tasksChange: json['tasksChange']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'shiftPoints': shiftPoints,
        'recountPoints': recountPoints,
        'shiftHandoverPoints': shiftHandoverPoints,
        'tasksPoints': tasksPoints,
        if (shiftChange != null) 'shiftChange': shiftChange,
        if (recountChange != null) 'recountChange': recountChange,
        if (shiftHandoverChange != null) 'shiftHandoverChange': shiftHandoverChange,
        if (tasksChange != null) 'tasksChange': tasksChange,
      };

  factory CategoryBreakdown.empty() {
    return CategoryBreakdown(
      shiftPoints: 0,
      recountPoints: 0,
      shiftHandoverPoints: 0,
      tasksPoints: 0,
    );
  }

  /// Общее количество баллов
  double get totalPoints =>
      shiftPoints + recountPoints + shiftHandoverPoints + tasksPoints;
}

/// Сравнение с прошлым месяцем
class PreviousMonthComparison {
  /// Общее изменение %
  final double totalChange;

  /// Изменение эффективности магазинов
  final double shopEfficiencyChange;

  /// Изменение эффективности отчётов
  final double reviewEfficiencyChange;

  PreviousMonthComparison({
    required this.totalChange,
    required this.shopEfficiencyChange,
    required this.reviewEfficiencyChange,
  });

  factory PreviousMonthComparison.fromJson(Map<String, dynamic> json) {
    return PreviousMonthComparison(
      totalChange: (json['totalChange'] ?? 0.0).toDouble(),
      shopEfficiencyChange: (json['shopEfficiencyChange'] ?? 0.0).toDouble(),
      reviewEfficiencyChange: (json['reviewEfficiencyChange'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'totalChange': totalChange,
        'shopEfficiencyChange': shopEfficiencyChange,
        'reviewEfficiencyChange': reviewEfficiencyChange,
      };
}
