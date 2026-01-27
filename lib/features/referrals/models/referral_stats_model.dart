/// Модель статистики приглашений сотрудника
class EmployeeReferralStats {
  final String employeeId;
  final String employeeName;
  final int referralCode;
  final int today;
  final int currentMonth;
  final int previousMonth;
  final int total;

  EmployeeReferralStats({
    required this.employeeId,
    required this.employeeName,
    required this.referralCode,
    required this.today,
    required this.currentMonth,
    required this.previousMonth,
    required this.total,
  });

  factory EmployeeReferralStats.fromJson(Map<String, dynamic> json) {
    return EmployeeReferralStats(
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      referralCode: json['referralCode'] ?? 0,
      today: json['today'] ?? 0,
      currentMonth: json['currentMonth'] ?? 0,
      previousMonth: json['previousMonth'] ?? 0,
      total: json['total'] ?? 0,
    );
  }

  /// Строка статистики в формате: сегодня/месяц/прошлый/всего
  String get statsString => '$today/$currentMonth/$previousMonth/$total';
}

/// Модель приглашённого клиента
class ReferredClient {
  final String phone;
  final String name;
  final DateTime referredAt;

  ReferredClient({
    required this.phone,
    required this.name,
    required this.referredAt,
  });

  factory ReferredClient.fromJson(Map<String, dynamic> json) {
    return ReferredClient(
      phone: json['phone'] ?? '',
      name: json['name'] ?? '',
      referredAt: json['referredAt'] != null
          ? DateTime.parse(json['referredAt'])
          : DateTime.now(),
    );
  }

  /// Маскированный номер телефона
  String get maskedPhone {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 4)}...${phone.substring(phone.length - 2)}';
  }
}

/// Модель настроек баллов за приглашения
class ReferralSettings {
  final int pointsPerReferral;

  ReferralSettings({
    required this.pointsPerReferral,
  });

  factory ReferralSettings.fromJson(Map<String, dynamic> json) {
    return ReferralSettings(
      pointsPerReferral: json['pointsPerReferral'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pointsPerReferral': pointsPerReferral,
    };
  }
}

/// Модель баллов сотрудника за приглашения
class EmployeeReferralPoints {
  final int currentMonthPoints;
  final int previousMonthPoints;
  final int currentMonthReferrals;
  final int previousMonthReferrals;
  final int pointsPerReferral;

  EmployeeReferralPoints({
    required this.currentMonthPoints,
    required this.previousMonthPoints,
    required this.currentMonthReferrals,
    required this.previousMonthReferrals,
    required this.pointsPerReferral,
  });

  factory EmployeeReferralPoints.fromJson(Map<String, dynamic> json) {
    return EmployeeReferralPoints(
      currentMonthPoints: json['currentMonthPoints'] ?? 0,
      previousMonthPoints: json['previousMonthPoints'] ?? 0,
      currentMonthReferrals: json['currentMonthReferrals'] ?? 0,
      previousMonthReferrals: json['previousMonthReferrals'] ?? 0,
      pointsPerReferral: json['pointsPerReferral'] ?? 1,
    );
  }
}

/// Модель настроек баллов за приглашения с милестоунами
class ReferralsPointsSettings {
  final int basePoints;
  final int milestoneThreshold;
  final int milestonePoints;

  ReferralsPointsSettings({
    required this.basePoints,
    required this.milestoneThreshold,
    required this.milestonePoints,
  });

  factory ReferralsPointsSettings.fromJson(Map<String, dynamic> json) {
    return ReferralsPointsSettings(
      basePoints: json['basePoints'] ?? 1,
      milestoneThreshold: json['milestoneThreshold'] ?? 0,
      milestonePoints: json['milestonePoints'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'basePoints': basePoints,
      'milestoneThreshold': milestoneThreshold,
      'milestonePoints': milestonePoints,
    };
  }

  /// Рассчитать баллы с учетом милестоунов
  ///
  /// Примеры:
  /// - 10 клиентов, base=1, threshold=5, milestone=3:
  ///   клиенты 1,2,3,4 = 4*1 = 4
  ///   клиент 5 = 1*3 = 3
  ///   клиенты 6,7,8,9 = 4*1 = 4
  ///   клиент 10 = 1*3 = 3
  ///   ИТОГО: 14 баллов
  int calculatePoints(int referralsCount) {
    // Если threshold = 0, милестоуны отключены
    if (milestoneThreshold == 0) {
      return referralsCount * basePoints;
    }

    int totalPoints = 0;

    for (int i = 1; i <= referralsCount; i++) {
      // Каждый N-й клиент получает milestone вместо base
      if (i % milestoneThreshold == 0) {
        totalPoints += milestonePoints;
      } else {
        totalPoints += basePoints;
      }
    }

    return totalPoints;
  }
}
