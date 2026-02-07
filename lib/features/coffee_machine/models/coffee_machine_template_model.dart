import '../../ai_training/models/z_report_template_model.dart';

/// Шаблон кофемашины (тип машины с эталонным фото и областью счётчика)
class CoffeeMachineTemplate {
  final String id;
  final String name; // "WMF 1500S", "Termoplan BW4"
  final String machineType; // "wmf", "termoplan", etc.
  final String? referencePhotoUrl; // Эталонное фото для ориентира сотрудника
  final FieldRegion? counterRegion; // Область счётчика на фото (как в Z-отчётах)
  final DateTime createdAt;
  final DateTime? updatedAt;

  CoffeeMachineTemplate({
    required this.id,
    required this.name,
    required this.machineType,
    this.referencePhotoUrl,
    this.counterRegion,
    required this.createdAt,
    this.updatedAt,
  });

  factory CoffeeMachineTemplate.fromJson(Map<String, dynamic> json) {
    return CoffeeMachineTemplate(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      machineType: json['machineType'] ?? '',
      referencePhotoUrl: json['referencePhotoUrl'],
      counterRegion: json['counterRegion'] != null
          ? FieldRegion.fromJson(json['counterRegion'])
          : null,
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
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  CoffeeMachineTemplate copyWith({
    String? id,
    String? name,
    String? machineType,
    String? referencePhotoUrl,
    FieldRegion? counterRegion,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CoffeeMachineTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      machineType: machineType ?? this.machineType,
      referencePhotoUrl: referencePhotoUrl ?? this.referencePhotoUrl,
      counterRegion: counterRegion ?? this.counterRegion,
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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CoffeeMachineShopConfig({
    required this.shopAddress,
    required this.machineTemplateIds,
    this.hasComputerVerification = true,
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
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  CoffeeMachineShopConfig copyWith({
    String? shopAddress,
    List<String>? machineTemplateIds,
    bool? hasComputerVerification,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CoffeeMachineShopConfig(
      shopAddress: shopAddress ?? this.shopAddress,
      machineTemplateIds: machineTemplateIds ?? this.machineTemplateIds,
      hasComputerVerification: hasComputerVerification ?? this.hasComputerVerification,
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
