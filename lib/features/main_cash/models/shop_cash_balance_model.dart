/// Модель баланса кассы магазина
class ShopCashBalance {
  final String shopAddress;
  final double oooBalance;
  final double ipBalance;
  final double oooTotalIncome; // Всего поступило ООО
  final double ipTotalIncome; // Всего поступило ИП
  final double oooTotalWithdrawals; // Всего выемок ООО
  final double ipTotalWithdrawals; // Всего выемок ИП

  ShopCashBalance({
    required this.shopAddress,
    required this.oooBalance,
    required this.ipBalance,
    this.oooTotalIncome = 0,
    this.ipTotalIncome = 0,
    this.oooTotalWithdrawals = 0,
    this.ipTotalWithdrawals = 0,
  });

  double get totalBalance => oooBalance + ipBalance;

  factory ShopCashBalance.fromJson(Map<String, dynamic> json) {
    return ShopCashBalance(
      shopAddress: json['shopAddress'] as String,
      oooBalance: (json['oooBalance'] as num).toDouble(),
      ipBalance: (json['ipBalance'] as num).toDouble(),
      oooTotalIncome: (json['oooTotalIncome'] as num?)?.toDouble() ?? 0,
      ipTotalIncome: (json['ipTotalIncome'] as num?)?.toDouble() ?? 0,
      oooTotalWithdrawals: (json['oooTotalWithdrawals'] as num?)?.toDouble() ?? 0,
      ipTotalWithdrawals: (json['ipTotalWithdrawals'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shopAddress': shopAddress,
      'oooBalance': oooBalance,
      'ipBalance': ipBalance,
      'oooTotalIncome': oooTotalIncome,
      'ipTotalIncome': ipTotalIncome,
      'oooTotalWithdrawals': oooTotalWithdrawals,
      'ipTotalWithdrawals': ipTotalWithdrawals,
    };
  }

  /// Форматирование суммы для отображения
  static String formatAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}k';
    }
    return amount.toStringAsFixed(0);
  }

  String get formattedOooBalance => formatAmount(oooBalance);
  String get formattedIpBalance => formatAmount(ipBalance);
  String get formattedTotalBalance => formatAmount(totalBalance);
}

/// Модель данных оборота за день
class DayTurnover {
  final DateTime date;
  final double oooRevenue;
  final double ipRevenue;

  DayTurnover({
    required this.date,
    required this.oooRevenue,
    required this.ipRevenue,
  });

  double get totalRevenue => oooRevenue + ipRevenue;

  factory DayTurnover.fromJson(Map<String, dynamic> json) {
    return DayTurnover(
      date: DateTime.parse(json['date'] as String),
      oooRevenue: (json['oooRevenue'] as num).toDouble(),
      ipRevenue: (json['ipRevenue'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'oooRevenue': oooRevenue,
      'ipRevenue': ipRevenue,
    };
  }

  String get formattedDate {
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }
}

/// Модель для сравнения оборота
class TurnoverComparison {
  final DayTurnover current;
  final DayTurnover? weekAgo;
  final DayTurnover? monthAgo;

  TurnoverComparison({
    required this.current,
    this.weekAgo,
    this.monthAgo,
  });

  /// Процент изменения по сравнению с неделей назад
  double? get weekAgoChangePercent {
    if (weekAgo == null || weekAgo!.totalRevenue == 0) return null;
    return ((current.totalRevenue - weekAgo!.totalRevenue) / weekAgo!.totalRevenue) * 100;
  }

  /// Процент изменения по сравнению с месяцем назад
  double? get monthAgoChangePercent {
    if (monthAgo == null || monthAgo!.totalRevenue == 0) return null;
    return ((current.totalRevenue - monthAgo!.totalRevenue) / monthAgo!.totalRevenue) * 100;
  }
}
