import '../../ai_training/models/z_report_template_model.dart';

/// Шаблон кофемашины (тип машины с эталонным фото и областью счётчика)
class CoffeeMachineTemplate {
  final String id;
  final String name; // "WMF 1500S", "Termoplan BW4"
  final String machineType; // "wmf", "termoplan", etc.
  final String? referencePhotoUrl; // Эталонное фото для ориентира сотрудника
  final FieldRegion? counterRegion; // Область счётчика на фото (как в Z-отчётах)
  final String ocrPreset; // Пресет обработки: standard, invert_lcd, standard_resize
  final DateTime createdAt;
  final DateTime? updatedAt;

  CoffeeMachineTemplate({
    required this.id,
    required this.name,
    required this.machineType,
    this.referencePhotoUrl,
    this.counterRegion,
    this.ocrPreset = 'standard',
    required this.createdAt,
    this.updatedAt,
  });

  factory CoffeeMachineTemplate.fromJson(Map<String, dynamic> json) {
    // Поддержка старого формата: preprocessing → ocrPreset
    String preset = json['ocrPreset'] ?? 'standard';
    if (json['preprocessing'] != null) {
      if (json['preprocessing'] is Map) {
        // Новый формат: {"preset": "invert_lcd"}
        preset = json['preprocessing']['preset'] ?? preset;
      } else if (json['preprocessing'] is String) {
        // Старый формат: "invert_lcd" (строка напрямую)
        preset = json['preprocessing'];
      }
    }

    return CoffeeMachineTemplate(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      machineType: json['machineType'] ?? '',
      referencePhotoUrl: json['referencePhotoUrl'],
      counterRegion: json['counterRegion'] != null
          ? FieldRegion.fromJson(json['counterRegion'])
          : null,
      ocrPreset: preset,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'machineType': machineType,
    'referencePhotoUrl': referencePhotoUrl,
    'counterRegion': counterRegion?.toJson(),
    'ocrPreset': ocrPreset,
    // Также сохраняем в старом формате для совместимости с сервером
    'preprocessing': {'preset': ocrPreset},
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  CoffeeMachineTemplate copyWith({
    String? id,
    String? name,
    String? machineType,
    String? referencePhotoUrl,
    FieldRegion? counterRegion,
    String? ocrPreset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CoffeeMachineTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      machineType: machineType ?? this.machineType,
      referencePhotoUrl: referencePhotoUrl ?? this.referencePhotoUrl,
      counterRegion: counterRegion ?? this.counterRegion,
      ocrPreset: ocrPreset ?? this.ocrPreset,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Привязка шаблонов кофемашин к конкретному магазину
class CoffeeMachineShopConfig {
  final String shopAddress;
  final List<String> machineTemplateIds; // ID шаблонов машин в этом магазине
  final bool hasComputerVerification; // Есть ли компьютер для сверки
  final String? computerTemplateId; // ID шаблона компьютера (preset, region, фото)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CoffeeMachineShopConfig({
    required this.shopAddress,
    required this.machineTemplateIds,
    this.hasComputerVerification = true,
    this.computerTemplateId,
    this.createdAt,
    this.updatedAt,
  });

  factory CoffeeMachineShopConfig.fromJson(Map<String, dynamic> json) {
    return CoffeeMachineShopConfig(
      shopAddress: json['shopAddress'] ?? '',
      machineTemplateIds: (json['machineTemplateIds'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      hasComputerVerification: json['hasComputerVerification'] ?? true,
      computerTemplateId: json['computerTemplateId'],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'shopAddress': shopAddress,
    'machineTemplateIds': machineTemplateIds,
    'hasComputerVerification': hasComputerVerification,
    if (computerTemplateId != null) 'computerTemplateId': computerTemplateId,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  CoffeeMachineShopConfig copyWith({
    String? shopAddress,
    List<String>? machineTemplateIds,
    bool? hasComputerVerification,
    String? computerTemplateId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CoffeeMachineShopConfig(
      shopAddress: shopAddress ?? this.shopAddress,
      machineTemplateIds: machineTemplateIds ?? this.machineTemplateIds,
      hasComputerVerification: hasComputerVerification ?? this.hasComputerVerification,
      computerTemplateId: computerTemplateId ?? this.computerTemplateId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Типы кофемашин
class CoffeeMachineTypes {
  static const String wmf = 'wmf';
  static const String termoplan = 'termoplan';
  static const String other = 'other';

  static const Map<String, String> displayNames = {
    wmf: 'WMF',
    termoplan: 'Termoplan',
    other: 'Другая',
  };

  static String getDisplayName(String type) {
    return displayNames[type] ?? type;
  }

  static List<String> get all => [wmf, termoplan, other];
}

/// Пресеты обработки изображений для OCR
class OcrPresets {
  static const String standard = 'standard';
  static const String invertLcd = 'invert_lcd';
  static const String standardResize = 'standard_resize';
  static const String computer = 'computer';

  /// Понятные названия для UI
  static const Map<String, String> displayNames = {
    standard: 'Светлый экран',
    invertLcd: 'Тёмный экран (LCD)',
    standardResize: 'Тёмный сенсорный',
    computer: 'Экран компьютера',
  };

  /// Описания для подсказки
  static const Map<String, String> descriptions = {
    standard: 'Тёмный текст на светлом фоне (Thermoplan BW3)',
    invertLcd: 'Светлый текст на тёмном фоне (WMF)',
    standardResize: 'Сенсорный экран с увеличением (Thermoplan BW4)',
    computer: 'Экран Foxpro/1С (поиск поля "Остаток")',
  };

  static String getDisplayName(String preset) {
    return displayNames[preset] ?? preset;
  }

  static String getDescription(String preset) {
    return descriptions[preset] ?? '';
  }

  static List<String> get all => [standard, invertLcd, standardResize, computer];
}
