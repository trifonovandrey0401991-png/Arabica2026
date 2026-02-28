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

  /// Сумма заработанных баллов
  final double totalEarned;

  /// Сумма потерянных баллов (штрафы)
  final double totalLost;

  /// Итого баллов (earned - lost)
  final double totalPoints;

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
    required this.totalEarned,
    required this.totalLost,
    required this.totalPoints,
    required this.shopBreakdown,
    required this.categoryBreakdown,
    this.comparison,
  });

  factory ManagerEfficiencyData.fromJson(Map<String, dynamic> json) {
    return ManagerEfficiencyData(
      totalPercentage: (json['totalPercentage'] ?? 0.0).toDouble(),
      shopEfficiencyPercentage: (json['shopEfficiencyPercentage'] ?? 0.0).toDouble(),
      reviewEfficiencyPercentage: (json['reviewEfficiencyPercentage'] ?? 0.0).toDouble(),
      totalEarned: (json['totalEarned'] ?? 0.0).toDouble(),
      totalLost: (json['totalLost'] ?? 0.0).toDouble(),
      totalPoints: (json['totalPoints'] ?? 0.0).toDouble(),
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
        'totalEarned': totalEarned,
        'totalLost': totalLost,
        'totalPoints': totalPoints,
        'shopBreakdown': shopBreakdown.map((s) => s.toJson()).toList(),
        'categoryBreakdown': categoryBreakdown.toJson(),
        if (comparison != null) 'comparison': comparison!.toJson(),
      };

  factory ManagerEfficiencyData.empty() {
    return ManagerEfficiencyData(
      totalPercentage: 0,
      shopEfficiencyPercentage: 0,
      reviewEfficiencyPercentage: 0,
      totalEarned: 0,
      totalLost: 0,
      totalPoints: 0,
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

  /// Адрес магазина (совпадает с entityId в EfficiencySummary)
  final String shopAddress;

  /// Общие баллы сотрудников магазина
  final double totalPoints;

  /// Заработанные баллы
  final double earnedPoints;

  /// Потерянные баллы (штрафы)
  final double lostPoints;

  /// Количество записей
  final int recordsCount;

  /// Процент от теоретического максимума
  final double percentage;

  /// Изменение по сравнению с прошлым месяцем
  final double? previousMonthChange;

  ShopEfficiencyItem({
    required this.shopId,
    required this.shopName,
    this.shopAddress = '',
    required this.totalPoints,
    this.earnedPoints = 0,
    this.lostPoints = 0,
    this.recordsCount = 0,
    required this.percentage,
    this.previousMonthChange,
  });

  factory ShopEfficiencyItem.fromJson(Map<String, dynamic> json) {
    return ShopEfficiencyItem(
      shopId: json['shopId'] ?? '',
      shopName: json['shopName'] ?? 'Магазин',
      shopAddress: json['shopAddress'] ?? '',
      totalPoints: (json['totalPoints'] ?? 0.0).toDouble(),
      earnedPoints: (json['earnedPoints'] ?? 0.0).toDouble(),
      lostPoints: (json['lostPoints'] ?? 0.0).toDouble(),
      recordsCount: (json['recordsCount'] ?? 0) as int,
      percentage: (json['percentage'] ?? 0.0).toDouble(),
      previousMonthChange: json['previousMonthChange']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'shopId': shopId,
        'shopName': shopName,
        'shopAddress': shopAddress,
        'totalPoints': totalPoints,
        'earnedPoints': earnedPoints,
        'lostPoints': lostPoints,
        'recordsCount': recordsCount,
        'percentage': percentage,
        if (previousMonthChange != null) 'previousMonthChange': previousMonthChange,
      };
}

/// Разбивка баллов по категориям (суммарно по всем сотрудникам магазинов управляющей)
class CategoryBreakdown {
  final double shiftPoints;
  final double recountPoints;
  final double shiftHandoverPoints;
  final double tasksPoints;
  final double attendancePoints;
  final double reviewsPoints;
  final double rkoPoints;
  final double coffeeMachinePoints;
  final double envelopePoints;
  final double productSearchPoints;
  final double orderPoints;
  final double referralPoints;

  CategoryBreakdown({
    required this.shiftPoints,
    required this.recountPoints,
    required this.shiftHandoverPoints,
    required this.tasksPoints,
    this.attendancePoints = 0,
    this.reviewsPoints = 0,
    this.rkoPoints = 0,
    this.coffeeMachinePoints = 0,
    this.envelopePoints = 0,
    this.productSearchPoints = 0,
    this.orderPoints = 0,
    this.referralPoints = 0,
  });

  factory CategoryBreakdown.fromJson(Map<String, dynamic> json) {
    return CategoryBreakdown(
      shiftPoints:          (json['shiftPoints'] ?? 0.0).toDouble(),
      recountPoints:        (json['recountPoints'] ?? 0.0).toDouble(),
      shiftHandoverPoints:  (json['shiftHandoverPoints'] ?? 0.0).toDouble(),
      tasksPoints:          (json['tasksPoints'] ?? 0.0).toDouble(),
      attendancePoints:     (json['attendancePoints'] ?? 0.0).toDouble(),
      reviewsPoints:        (json['reviewsPoints'] ?? 0.0).toDouble(),
      rkoPoints:            (json['rkoPoints'] ?? 0.0).toDouble(),
      coffeeMachinePoints:  (json['coffeeMachinePoints'] ?? 0.0).toDouble(),
      envelopePoints:       (json['envelopePoints'] ?? 0.0).toDouble(),
      productSearchPoints:  (json['productSearchPoints'] ?? 0.0).toDouble(),
      orderPoints:          (json['orderPoints'] ?? 0.0).toDouble(),
      referralPoints:       (json['referralPoints'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'shiftPoints':         shiftPoints,
        'recountPoints':       recountPoints,
        'shiftHandoverPoints': shiftHandoverPoints,
        'tasksPoints':         tasksPoints,
        'attendancePoints':    attendancePoints,
        'reviewsPoints':       reviewsPoints,
        'rkoPoints':           rkoPoints,
        'coffeeMachinePoints': coffeeMachinePoints,
        'envelopePoints':      envelopePoints,
        'productSearchPoints': productSearchPoints,
        'orderPoints':         orderPoints,
        'referralPoints':      referralPoints,
      };

  factory CategoryBreakdown.empty() {
    return CategoryBreakdown(
      shiftPoints: 0,
      recountPoints: 0,
      shiftHandoverPoints: 0,
      tasksPoints: 0,
    );
  }

  double get totalPoints =>
      shiftPoints + recountPoints + shiftHandoverPoints + tasksPoints +
      attendancePoints + reviewsPoints + rkoPoints + coffeeMachinePoints +
      envelopePoints + productSearchPoints + orderPoints + referralPoints;
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
