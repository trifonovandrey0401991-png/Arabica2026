/// Категории эффективности
enum EfficiencyCategory {
  shift,          // Пересменка
  recount,        // Пересчет
  shiftHandover,  // Сдать смену
  attendance,     // Я на работе
  test,           // Тестирование
  reviews,        // Отзывы
  productSearch,  // Поиск товара
  rko,            // РКО
  orders,         // Заказы
  shiftPenalty,   // Штраф за пересменку
  tasks,          // Задачи
}

extension EfficiencyCategoryExtension on EfficiencyCategory {
  String get displayName {
    switch (this) {
      case EfficiencyCategory.shift:
        return 'Пересменка';
      case EfficiencyCategory.recount:
        return 'Пересчет';
      case EfficiencyCategory.shiftHandover:
        return 'Сдать смену';
      case EfficiencyCategory.attendance:
        return 'Я на работе';
      case EfficiencyCategory.test:
        return 'Тестирование';
      case EfficiencyCategory.reviews:
        return 'Отзывы';
      case EfficiencyCategory.productSearch:
        return 'Поиск товара';
      case EfficiencyCategory.rko:
        return 'РКО';
      case EfficiencyCategory.orders:
        return 'Заказы';
      case EfficiencyCategory.shiftPenalty:
        return 'Штраф за пересменку';
      case EfficiencyCategory.tasks:
        return 'Задачи';
    }
  }

  String get code {
    switch (this) {
      case EfficiencyCategory.shift:
        return 'shift';
      case EfficiencyCategory.recount:
        return 'recount';
      case EfficiencyCategory.shiftHandover:
        return 'shift_handover';
      case EfficiencyCategory.attendance:
        return 'attendance';
      case EfficiencyCategory.test:
        return 'test';
      case EfficiencyCategory.reviews:
        return 'reviews';
      case EfficiencyCategory.productSearch:
        return 'product_search';
      case EfficiencyCategory.rko:
        return 'rko';
      case EfficiencyCategory.orders:
        return 'orders';
      case EfficiencyCategory.shiftPenalty:
        return 'shift_penalty';
      case EfficiencyCategory.tasks:
        return 'tasks';
    }
  }

  static EfficiencyCategory fromCode(String code) {
    switch (code) {
      case 'shift':
        return EfficiencyCategory.shift;
      case 'recount':
        return EfficiencyCategory.recount;
      case 'shift_handover':
        return EfficiencyCategory.shiftHandover;
      case 'attendance':
        return EfficiencyCategory.attendance;
      case 'test':
        return EfficiencyCategory.test;
      case 'reviews':
        return EfficiencyCategory.reviews;
      case 'product_search':
        return EfficiencyCategory.productSearch;
      case 'rko':
        return EfficiencyCategory.rko;
      case 'orders':
        return EfficiencyCategory.orders;
      case 'shift_penalty':
        return EfficiencyCategory.shiftPenalty;
      case 'tasks':
        return EfficiencyCategory.tasks;
      default:
        return EfficiencyCategory.shift;
    }
  }
}

/// Запись об эффективности (один расчет баллов)
class EfficiencyRecord {
  final String id;
  final EfficiencyCategory category;
  final String shopAddress;
  final String employeeName;
  final DateTime date;
  final double points;
  final dynamic rawValue; // Исходное значение (rating, isOnTime, score, etc.)
  final String sourceId; // ID исходного отчета

  EfficiencyRecord({
    required this.id,
    required this.category,
    required this.shopAddress,
    required this.employeeName,
    required this.date,
    required this.points,
    required this.rawValue,
    required this.sourceId,
  });

  /// Название категории для отображения
  /// Для штрафов берём из rawValue (настоящее название с сервера)
  String get categoryName {
    if (category == EfficiencyCategory.shiftPenalty && rawValue is Map) {
      final customName = rawValue['categoryName'];
      if (customName != null && customName.toString().isNotEmpty) {
        return customName.toString();
      }
    }
    return category.displayName;
  }

  /// Форматированное значение для отображения
  String get formattedRawValue {
    if (rawValue == null) return '-';

    switch (category) {
      case EfficiencyCategory.shift:
      case EfficiencyCategory.recount:
      case EfficiencyCategory.shiftHandover:
        return '$rawValue/10';
      case EfficiencyCategory.attendance:
        return rawValue == true ? 'Вовремя' : 'Опоздание';
      case EfficiencyCategory.test:
        return '$rawValue%';
      case EfficiencyCategory.reviews:
        return rawValue == true ? 'Положительный' : 'Отрицательный';
      case EfficiencyCategory.productSearch:
        return rawValue == true ? 'Отвечено' : 'Не отвечено';
      case EfficiencyCategory.rko:
        return rawValue == true ? 'Есть' : 'Нет';
      case EfficiencyCategory.orders:
        return rawValue == true ? 'Принят' : 'Отклонен';
      case EfficiencyCategory.shiftPenalty:
        if (rawValue is Map) {
          // Показываем причину штрафа если есть
          final reason = rawValue['reason'];
          if (reason != null && reason.toString().isNotEmpty) {
            return reason.toString();
          }
          // Иначе показываем смену
          final shift = rawValue['shiftType'] == 'morning' ? 'Утро' : 'Вечер';
          return 'Штраф ($shift)';
        }
        return 'Штраф';
      case EfficiencyCategory.tasks:
        if (rawValue is Map) {
          final status = rawValue['status'];
          switch (status) {
            case 'approved':
              return 'Выполнено';
            case 'rejected':
              return 'Отклонено';
            case 'expired':
              return 'Просрочено';
            case 'declined':
              return 'Отказ';
            default:
              return rawValue.toString();
          }
        }
        return rawValue?.toString() ?? '-';
    }
  }

  /// Форматированные баллы с знаком
  String get formattedPoints {
    if (points >= 0) {
      return '+${points.toStringAsFixed(2)}';
    }
    return points.toStringAsFixed(2);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category.code,
    'shopAddress': shopAddress,
    'employeeName': employeeName,
    'date': date.toIso8601String(),
    'points': points,
    'rawValue': rawValue,
    'sourceId': sourceId,
  };

  factory EfficiencyRecord.fromJson(Map<String, dynamic> json) {
    return EfficiencyRecord(
      id: json['id'] ?? '',
      category: EfficiencyCategoryExtension.fromCode(json['category'] ?? 'shift'),
      shopAddress: json['shopAddress'] ?? '',
      employeeName: json['employeeName'] ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      points: (json['points'] ?? 0).toDouble(),
      rawValue: json['rawValue'],
      sourceId: json['sourceId'] ?? '',
    );
  }
}

/// Агрегированные данные по сущности (магазин или сотрудник)
class EfficiencySummary {
  final String entityId; // shopAddress или employeeName
  final String entityName; // Название для отображения
  final double earnedPoints; // Сумма положительных баллов
  final double lostPoints; // Сумма отрицательных баллов (абсолютное значение)
  final double totalPoints; // earnedPoints - lostPoints
  final int recordsCount;
  final List<EfficiencyRecord> records;
  final List<CategoryData> categorySummaries; // Группировка по categoryName

  EfficiencySummary({
    required this.entityId,
    required this.entityName,
    required this.earnedPoints,
    required this.lostPoints,
    required this.totalPoints,
    required this.recordsCount,
    required this.records,
    required this.categorySummaries,
  });

  /// Создать сводку из списка записей
  factory EfficiencySummary.fromRecords({
    required String entityId,
    required String entityName,
    required List<EfficiencyRecord> records,
  }) {
    double earned = 0;
    double lost = 0;
    // Группируем по categoryName (для штрафов разные имена)
    final Map<String, double> pointsByCategoryName = {};
    final Map<String, EfficiencyCategory> categoryByName = {};

    for (final record in records) {
      if (record.points >= 0) {
        earned += record.points;
      } else {
        lost += record.points.abs();
      }

      // Используем categoryName вместо enum для группировки
      final categoryName = record.categoryName;
      pointsByCategoryName[categoryName] = (pointsByCategoryName[categoryName] ?? 0) + record.points;
      categoryByName[categoryName] = record.category;
    }

    // Преобразуем в List<CategoryData> и сортируем по абсолютному значению
    final summaries = pointsByCategoryName.entries.map((entry) {
      return CategoryData(
        name: entry.key,
        baseCategory: categoryByName[entry.key]!,
        points: entry.value,
      );
    }).toList()
      ..sort((a, b) => b.points.abs().compareTo(a.points.abs()));

    return EfficiencySummary(
      entityId: entityId,
      entityName: entityName,
      earnedPoints: earned,
      lostPoints: lost,
      totalPoints: earned - lost,
      recordsCount: records.length,
      records: records,
      categorySummaries: summaries,
    );
  }

  /// Форматированные баллы для отображения
  String get formattedSummary {
    final earnedStr = '+${earnedPoints.toStringAsFixed(1)}';
    final lostStr = '-${lostPoints.toStringAsFixed(1)}';
    final totalStr = totalPoints >= 0
        ? '+${totalPoints.toStringAsFixed(1)}'
        : totalPoints.toStringAsFixed(1);
    return '$earnedStr / $lostStr = $totalStr';
  }

  String get formattedTotal {
    if (totalPoints >= 0) {
      return '+${totalPoints.toStringAsFixed(1)}';
    }
    return totalPoints.toStringAsFixed(1);
  }
}

/// Штраф эффективности (с сервера)
class EfficiencyPenalty {
  final String id;
  final String type;            // 'shop' | 'employee'
  final String entityId;
  final String entityName;
  final String shopAddress;
  final String? employeeName;
  final String category;
  final String categoryName;
  final String date;
  final String? shiftType;
  final String? shiftLabel;
  final double points;
  final String? reason;
  final String? createdAt;

  EfficiencyPenalty({
    required this.id,
    required this.type,
    required this.entityId,
    required this.entityName,
    required this.shopAddress,
    this.employeeName,
    required this.category,
    required this.categoryName,
    required this.date,
    this.shiftType,
    this.shiftLabel,
    required this.points,
    this.reason,
    this.createdAt,
  });

  factory EfficiencyPenalty.fromJson(Map<String, dynamic> json) {
    return EfficiencyPenalty(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      entityId: json['entityId'] ?? '',
      entityName: json['entityName'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      employeeName: json['employeeName'],
      category: json['category'] ?? '',
      categoryName: json['categoryName'] ?? '',
      date: json['date'] ?? '',
      shiftType: json['shiftType'],
      shiftLabel: json['shiftLabel'],
      points: (json['points'] ?? 0).toDouble(),
      reason: json['reason'],
      createdAt: json['createdAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'entityId': entityId,
      'entityName': entityName,
      'shopAddress': shopAddress,
      if (employeeName != null) 'employeeName': employeeName,
      'category': category,
      'categoryName': categoryName,
      'date': date,
      if (shiftType != null) 'shiftType': shiftType,
      if (shiftLabel != null) 'shiftLabel': shiftLabel,
      'points': points,
      if (reason != null) 'reason': reason,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  /// Преобразовать штраф в EfficiencyRecord
  /// Для штрафов типа 'shop': заполняется только shopAddress
  /// Для штрафов типа 'employee': заполняются и employeeName, и shopAddress
  ///   - employeeName для группировки по сотрудникам
  ///   - shopAddress для агрегации в статистику магазина
  EfficiencyRecord toRecord() {
    return EfficiencyRecord(
      id: id,
      category: EfficiencyCategory.shiftPenalty,
      // Для employee-штрафов также заполняем shopAddress для агрегации в магазин
      shopAddress: shopAddress,
      employeeName: type == 'employee' ? (employeeName ?? entityName) : '',
      date: DateTime.tryParse(date) ?? DateTime.now(),
      points: points,
      rawValue: {
        'shiftType': shiftType,
        'reason': reason,
        'shopAddress': shopAddress,
        'employeeName': employeeName ?? entityName,
        'categoryName': categoryName,
      },
      sourceId: id,
    );
  }

  /// Локализованное название смены
  String get localizedShiftLabel {
    switch (shiftType) {
      case 'morning':
        return 'Утро';
      case 'evening':
        return 'Вечер';
      default:
        return shiftLabel ?? '';
    }
  }
}

/// Данные категории для отображения (группировка по categoryName)
class CategoryData {
  final String name;           // Название категории для отображения
  final EfficiencyCategory baseCategory;  // Базовая категория (enum) для иконки/цвета
  final double points;

  CategoryData({
    required this.name,
    required this.baseCategory,
    required this.points,
  });
}

/// Данные эффективности за период
class EfficiencyData {
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<EfficiencySummary> byShop;
  final List<EfficiencySummary> byEmployee;
  final List<EfficiencyRecord> allRecords;
  final List<EfficiencyPenalty> penalties;

  EfficiencyData({
    required this.periodStart,
    required this.periodEnd,
    required this.byShop,
    required this.byEmployee,
    required this.allRecords,
    this.penalties = const [],
  });

  /// Название периода для отображения
  String get periodName {
    const months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    return '${months[periodStart.month - 1]} ${periodStart.year}';
  }

  /// Общая сумма баллов
  double get totalEarned => byShop.fold(0, (sum, s) => sum + s.earnedPoints);
  double get totalLost => byShop.fold(0, (sum, s) => sum + s.lostPoints);
  double get totalPoints => totalEarned - totalLost;

  /// Пустые данные
  factory EfficiencyData.empty({DateTime? start, DateTime? end}) {
    final now = DateTime.now();
    return EfficiencyData(
      periodStart: start ?? DateTime(now.year, now.month, 1),
      periodEnd: end ?? DateTime(now.year, now.month + 1, 0),
      byShop: [],
      byEmployee: [],
      allRecords: [],
    );
  }
}
