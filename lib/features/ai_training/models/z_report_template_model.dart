import 'dart:ui';

/// Область на изображении для распознавания поля
class FieldRegion {
  final String fieldName; // totalSum, cashSum, ofdNotSent
  final double x; // относительная координата X (0.0 - 1.0)
  final double y; // относительная координата Y (0.0 - 1.0)
  final double width; // относительная ширина (0.0 - 1.0)
  final double height; // относительная высота (0.0 - 1.0)

  FieldRegion({
    required this.fieldName,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Преобразовать в абсолютные координаты для изображения
  Rect toAbsoluteRect(double imageWidth, double imageHeight) {
    return Rect.fromLTWH(
      x * imageWidth,
      y * imageHeight,
      width * imageWidth,
      height * imageHeight,
    );
  }

  /// Создать из абсолютных координат
  factory FieldRegion.fromAbsolute({
    required String fieldName,
    required Rect rect,
    required double imageWidth,
    required double imageHeight,
  }) {
    return FieldRegion(
      fieldName: fieldName,
      x: rect.left / imageWidth,
      y: rect.top / imageHeight,
      width: rect.width / imageWidth,
      height: rect.height / imageHeight,
    );
  }

  factory FieldRegion.fromJson(Map<String, dynamic> json) {
    return FieldRegion(
      fieldName: json['fieldName'] ?? '',
      x: (json['x'] ?? 0).toDouble(),
      y: (json['y'] ?? 0).toDouble(),
      width: (json['width'] ?? 0).toDouble(),
      height: (json['height'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fieldName': fieldName,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
  }

  FieldRegion copyWith({
    String? fieldName,
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return FieldRegion(
      fieldName: fieldName ?? this.fieldName,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

/// Набор областей для одного формата чека
class RegionSet {
  final String id;
  final String name; // "Формат 1", "Касса АТОЛ старая"
  final List<FieldRegion> regions;

  RegionSet({
    required this.id,
    required this.name,
    this.regions = const [],
  });

  factory RegionSet.fromJson(Map<String, dynamic> json) {
    return RegionSet(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Формат 1',
      regions: (json['regions'] as List?)
              ?.map((e) => FieldRegion.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'regions': regions.map((e) => e.toJson()).toList(),
    };
  }

  RegionSet copyWith({
    String? id,
    String? name,
    List<FieldRegion>? regions,
  }) {
    return RegionSet(
      id: id ?? this.id,
      name: name ?? this.name,
      regions: regions ?? this.regions,
    );
  }

  /// Проверить есть ли область для поля
  bool hasRegion(String fieldName) {
    return regions.any((r) => r.fieldName == fieldName);
  }

  /// Получить область для поля
  FieldRegion? getRegion(String fieldName) {
    try {
      return regions.firstWhere((r) => r.fieldName == fieldName);
    } catch (_) {
      return null;
    }
  }
}

/// Шаблон распознавания для конкретного магазина/кассы
class ZReportTemplate {
  final String id;
  final String name; // Название шаблона (напр. "АТОЛ Белопольского 2")
  final String? shopId; // ID магазина (если привязан к магазину)
  final String? shopAddress; // Адрес магазина
  final String? cashRegisterType; // Тип кассы (АТОЛ, Штрих-М, Эвотор)
  final List<RegionSet> regionSets; // Наборы областей для разных форматов
  final List<String> customPatterns; // Дополнительные regex паттерны
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int usageCount; // Сколько раз использовался
  final double successRate; // Процент успешных распознаваний

  ZReportTemplate({
    required this.id,
    required this.name,
    this.shopId,
    this.shopAddress,
    this.cashRegisterType,
    this.regionSets = const [],
    this.customPatterns = const [],
    required this.createdAt,
    this.updatedAt,
    this.usageCount = 0,
    this.successRate = 0.0,
  });

  /// Для обратной совместимости — возвращает области первого набора
  List<FieldRegion> get regions =>
      regionSets.isNotEmpty ? regionSets.first.regions : [];

  factory ZReportTemplate.fromJson(Map<String, dynamic> json) {
    // Поддержка старого формата (regions) и нового (regionSets)
    List<RegionSet> sets = [];

    if (json['regionSets'] != null) {
      // Новый формат
      sets = (json['regionSets'] as List)
          .map((e) => RegionSet.fromJson(e))
          .toList();
    } else if (json['regions'] != null && (json['regions'] as List).isNotEmpty) {
      // Старый формат — конвертируем в regionSets
      final oldRegions = (json['regions'] as List)
          .map((e) => FieldRegion.fromJson(e))
          .toList();
      sets = [
        RegionSet(
          id: 'default',
          name: 'Формат 1',
          regions: oldRegions,
        ),
      ];
    }

    return ZReportTemplate(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      shopId: json['shopId'],
      shopAddress: json['shopAddress'],
      cashRegisterType: json['cashRegisterType'],
      regionSets: sets,
      customPatterns: List<String>.from(json['customPatterns'] ?? []),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      usageCount: json['usageCount'] ?? 0,
      successRate: (json['successRate'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'shopId': shopId,
      'shopAddress': shopAddress,
      'cashRegisterType': cashRegisterType,
      'regionSets': regionSets.map((e) => e.toJson()).toList(),
      'customPatterns': customPatterns,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'usageCount': usageCount,
      'successRate': successRate,
    };
  }

  ZReportTemplate copyWith({
    String? id,
    String? name,
    String? shopId,
    String? shopAddress,
    String? cashRegisterType,
    List<RegionSet>? regionSets,
    List<String>? customPatterns,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? usageCount,
    double? successRate,
  }) {
    return ZReportTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      shopId: shopId ?? this.shopId,
      shopAddress: shopAddress ?? this.shopAddress,
      cashRegisterType: cashRegisterType ?? this.cashRegisterType,
      regionSets: regionSets ?? this.regionSets,
      customPatterns: customPatterns ?? this.customPatterns,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      usageCount: usageCount ?? this.usageCount,
      successRate: successRate ?? this.successRate,
    );
  }

  /// Проверить есть ли область для поля (в любом наборе)
  bool hasRegion(String fieldName) {
    return regionSets.any((set) => set.hasRegion(fieldName));
  }

  /// Получить область для поля (из первого набора)
  FieldRegion? getRegion(String fieldName) {
    for (final set in regionSets) {
      final region = set.getRegion(fieldName);
      if (region != null) return region;
    }
    return null;
  }
}

/// Типы кассовых аппаратов
class CashRegisterTypes {
  static const String atol = 'АТОЛ';
  static const String shtrihM = 'Штрих-М';
  static const String evotor = 'Эвотор';
  static const String mercury = 'Меркурий';
  static const String other = 'Другой';

  static List<String> get all => [atol, shtrihM, evotor, mercury, other];
}

/// Названия полей для отображения
class FieldNames {
  static const Map<String, String> displayNames = {
    'totalSum': 'Общая сумма',
    'cashSum': 'Наличные',
    'ofdNotSent': 'Не передано в ОФД',
    'resourceKeys': 'Ресурс ключей',
  };

  static String getDisplayName(String fieldName) {
    return displayNames[fieldName] ?? fieldName;
  }

  static List<String> get all => ['totalSum', 'cashSum', 'ofdNotSent', 'resourceKeys'];
}
