/// Настройки баллов для управляющих
///
/// Управляющие оцениваются по:
/// 1. Эффективность магазинов (50%) — агрегация баллов сотрудников
/// 2. Эффективность отчётов (50%) — баллы за проверку отчётов + задачи

class ManagerPointsSettings {
  /// Настройки для оценки пересменок
  final ManagerCategorySettings shiftSettings;

  /// Настройки для оценки пересчётов
  final ManagerCategorySettings recountSettings;

  /// Настройки для оценки сдачи смены
  final ManagerCategorySettings shiftHandoverSettings;

  ManagerPointsSettings({
    required this.shiftSettings,
    required this.recountSettings,
    required this.shiftHandoverSettings,
  });

  factory ManagerPointsSettings.fromJson(Map<String, dynamic> json) {
    return ManagerPointsSettings(
      shiftSettings: json['shiftSettings'] != null
          ? ManagerCategorySettings.fromJson(json['shiftSettings'])
          : ManagerCategorySettings.defaults(),
      recountSettings: json['recountSettings'] != null
          ? ManagerCategorySettings.fromJson(json['recountSettings'])
          : ManagerCategorySettings.defaults(),
      shiftHandoverSettings: json['shiftHandoverSettings'] != null
          ? ManagerCategorySettings.fromJson(json['shiftHandoverSettings'])
          : ManagerCategorySettings.defaults(),
    );
  }

  Map<String, dynamic> toJson() => {
    'shiftSettings': shiftSettings.toJson(),
    'recountSettings': recountSettings.toJson(),
    'shiftHandoverSettings': shiftHandoverSettings.toJson(),
  };

  factory ManagerPointsSettings.defaults() {
    return ManagerPointsSettings(
      shiftSettings: ManagerCategorySettings.defaults(),
      recountSettings: ManagerCategorySettings.defaults(),
      shiftHandoverSettings: ManagerCategorySettings.defaults(),
    );
  }
}

/// Настройки баллов для одной категории управляющего
///
/// Упрощённая модель с 2 параметрами:
/// - confirmedPoints — баллы за проверенный отчёт (+)
/// - rejectedPenalty — штраф за непроверенный отчёт (-)
class ManagerCategorySettings {
  /// Баллы за проверенный отчёт (confirmed)
  final double confirmedPoints;

  /// Штраф за непроверенный отчёт (rejected/failed)
  final double rejectedPenalty;

  ManagerCategorySettings({
    required this.confirmedPoints,
    required this.rejectedPenalty,
  });

  factory ManagerCategorySettings.fromJson(Map<String, dynamic> json) {
    // Миграция со старой структуры
    if (json.containsKey('subordinateQualityMinPoints')) {
      // Старый формат — используем дефолты
      return ManagerCategorySettings.defaults();
    }

    return ManagerCategorySettings(
      confirmedPoints: (json['confirmedPoints'] ?? 1.0).toDouble(),
      rejectedPenalty: (json['rejectedPenalty'] ?? -2.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'confirmedPoints': confirmedPoints,
    'rejectedPenalty': rejectedPenalty,
  };

  factory ManagerCategorySettings.defaults() {
    return ManagerCategorySettings(
      confirmedPoints: 1.0,
      rejectedPenalty: -2.0,
    );
  }
}
