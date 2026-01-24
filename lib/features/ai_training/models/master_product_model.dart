/// Продукт мастер-каталога
class MasterProduct {
  final String id;
  final String name;
  final String group;
  final String? barcode;
  final Map<String, String> shopCodes;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;

  // Для AI Training (опционально)
  final int recountPhotosCount;
  final int displayPhotosCount;
  final int trainingPhotosCount;
  final int requiredPhotos;
  final double completionPercentage;

  MasterProduct({
    required this.id,
    required this.name,
    this.group = '',
    this.barcode,
    this.shopCodes = const {},
    DateTime? createdAt,
    this.createdBy = 'admin',
    DateTime? updatedAt,
    this.recountPhotosCount = 0,
    this.displayPhotosCount = 0,
    this.trainingPhotosCount = 0,
    this.requiredPhotos = 10,
    this.completionPercentage = 0,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory MasterProduct.fromJson(Map<String, dynamic> json) {
    return MasterProduct(
      id: json['id'] ?? '',
      name: json['name'] ?? json['productName'] ?? '',
      group: json['group'] ?? '',
      barcode: json['barcode'],
      shopCodes: json['shopCodes'] != null
          ? Map<String, String>.from(json['shopCodes'])
          : {},
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      createdBy: json['createdBy'] ?? 'admin',
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
      // AI Training fields
      recountPhotosCount: json['recountPhotosCount'] ?? 0,
      displayPhotosCount: json['displayPhotosCount'] ?? 0,
      trainingPhotosCount: json['trainingPhotosCount'] ?? 0,
      requiredPhotos: json['requiredPhotos'] ?? 10,
      completionPercentage: (json['completionPercentage'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'group': group,
    'barcode': barcode,
    'shopCodes': shopCodes,
    'createdAt': createdAt.toIso8601String(),
    'createdBy': createdBy,
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// Количество привязанных магазинов
  int get linkedShopsCount => shopCodes.length;

  /// Есть ли привязки к магазинам
  bool get hasShopLinks => shopCodes.isNotEmpty;

  /// Общее количество фото для обучения
  int get totalPhotosCount =>
      recountPhotosCount + displayPhotosCount + trainingPhotosCount;

  /// Процент готовности для AI Training
  double get trainingProgress {
    if (requiredPhotos <= 0) return 0;
    return (totalPhotosCount / requiredPhotos * 100).clamp(0, 100);
  }

  /// Полностью ли обучен товар
  bool get isFullyTrained => totalPhotosCount >= requiredPhotos;

  /// Копия с изменениями
  MasterProduct copyWith({
    String? id,
    String? name,
    String? group,
    String? barcode,
    Map<String, String>? shopCodes,
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
  }) {
    return MasterProduct(
      id: id ?? this.id,
      name: name ?? this.name,
      group: group ?? this.group,
      barcode: barcode ?? this.barcode,
      shopCodes: shopCodes ?? this.shopCodes,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      updatedAt: updatedAt ?? this.updatedAt,
      recountPhotosCount: recountPhotosCount,
      displayPhotosCount: displayPhotosCount,
      trainingPhotosCount: trainingPhotosCount,
      requiredPhotos: requiredPhotos,
      completionPercentage: completionPercentage,
    );
  }
}
