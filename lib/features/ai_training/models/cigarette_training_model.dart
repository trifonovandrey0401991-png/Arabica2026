// Модели данных для обучения ИИ подсчёту сигарет

/// Товар для обучения (из вопросов пересчёта)
class CigaretteProduct {
  final String id;
  final String barcode;
  final String productGroup;
  final String productName;
  final int grade;
  final int trainingPhotosCount; // Сколько фото для обучения загружено
  final int requiredPhotosCount; // Сколько нужно для обучения (минимум)
  final bool isTrainingComplete; // Достаточно ли фото

  CigaretteProduct({
    required this.id,
    required this.barcode,
    required this.productGroup,
    required this.productName,
    required this.grade,
    this.trainingPhotosCount = 0,
    this.requiredPhotosCount = 20, // Минимум 20 фото для начала обучения
    this.isTrainingComplete = false,
  });

  factory CigaretteProduct.fromJson(Map<String, dynamic> json) {
    final photosCount = json['trainingPhotosCount'] ?? 0;
    final required = json['requiredPhotosCount'] ?? 50;
    return CigaretteProduct(
      id: json['id'] ?? '',
      barcode: json['barcode']?.toString() ?? '',
      productGroup: json['productGroup']?.toString() ?? '',
      productName: json['productName']?.toString() ?? json['question']?.toString() ?? '',
      grade: json['grade'] is int ? json['grade'] : int.tryParse(json['grade'].toString()) ?? 1,
      trainingPhotosCount: photosCount,
      requiredPhotosCount: required,
      isTrainingComplete: photosCount >= required,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'barcode': barcode,
    'productGroup': productGroup,
    'productName': productName,
    'grade': grade,
    'trainingPhotosCount': trainingPhotosCount,
    'requiredPhotosCount': requiredPhotosCount,
    'isTrainingComplete': isTrainingComplete,
  };

  /// Процент завершённости обучения (0-100)
  double get trainingProgress =>
    requiredPhotosCount > 0
      ? (trainingPhotosCount / requiredPhotosCount * 100).clamp(0, 100)
      : 0;
}

/// Образец для обучения (фото + метаданные)
class TrainingSample {
  final String id;
  final String productId;
  final String barcode;
  final String productName;
  final String imageUrl;
  final String? shopAddress;
  final String? employeeName;
  final DateTime createdAt;
  final TrainingSampleType type; // Для пересчёта или для выкладки

  TrainingSample({
    required this.id,
    required this.productId,
    required this.barcode,
    required this.productName,
    required this.imageUrl,
    this.shopAddress,
    this.employeeName,
    required this.createdAt,
    required this.type,
  });

  factory TrainingSample.fromJson(Map<String, dynamic> json) {
    return TrainingSample(
      id: json['id'] ?? '',
      productId: json['productId'] ?? '',
      barcode: json['barcode'] ?? '',
      productName: json['productName'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      shopAddress: json['shopAddress'],
      employeeName: json['employeeName'],
      createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'])
        : DateTime.now(),
      type: TrainingSampleType.fromString(json['type']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'barcode': barcode,
    'productName': productName,
    'imageUrl': imageUrl,
    'shopAddress': shopAddress,
    'employeeName': employeeName,
    'createdAt': createdAt.toIso8601String(),
    'type': type.value,
  };
}

/// Тип образца для обучения
enum TrainingSampleType {
  recount('recount'),    // Фото для подсчёта количества
  display('display');    // Фото выкладки витрины

  final String value;
  const TrainingSampleType(this.value);

  static TrainingSampleType fromString(String? value) {
    switch (value) {
      case 'display':
        return TrainingSampleType.display;
      case 'recount':
      default:
        return TrainingSampleType.recount;
    }
  }
}

/// Статистика обучения ИИ
class TrainingStats {
  final int totalProducts;           // Всего товаров
  final int productsWithPhotos;      // Товаров с фото
  final int productsFullyTrained;    // Товаров с достаточным кол-вом фото
  final int totalRecountPhotos;      // Всего фото для пересчёта
  final int totalDisplayPhotos;      // Всего фото выкладки
  final double overallProgress;      // Общий прогресс (0-100)

  TrainingStats({
    required this.totalProducts,
    required this.productsWithPhotos,
    required this.productsFullyTrained,
    required this.totalRecountPhotos,
    required this.totalDisplayPhotos,
    required this.overallProgress,
  });

  factory TrainingStats.fromJson(Map<String, dynamic> json) {
    return TrainingStats(
      totalProducts: json['totalProducts'] ?? 0,
      productsWithPhotos: json['productsWithPhotos'] ?? 0,
      productsFullyTrained: json['productsFullyTrained'] ?? 0,
      totalRecountPhotos: json['totalRecountPhotos'] ?? 0,
      totalDisplayPhotos: json['totalDisplayPhotos'] ?? 0,
      overallProgress: (json['overallProgress'] ?? 0).toDouble(),
    );
  }

  factory TrainingStats.empty() => TrainingStats(
    totalProducts: 0,
    productsWithPhotos: 0,
    productsFullyTrained: 0,
    totalRecountPhotos: 0,
    totalDisplayPhotos: 0,
    overallProgress: 0,
  );
}

/// Результат детекции (подсчёта) сигарет
class DetectionResult {
  final bool success;
  final String? error;
  final String? productId;
  final String? productName;
  final int count;                  // Количество найденных пачек
  final double confidence;          // Уверенность модели (0-1)
  final String? annotatedImageUrl;  // Фото с выделенными объектами
  final List<BoundingBox> boxes;    // Координаты найденных пачек

  DetectionResult({
    required this.success,
    this.error,
    this.productId,
    this.productName,
    this.count = 0,
    this.confidence = 0,
    this.annotatedImageUrl,
    this.boxes = const [],
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      success: json['success'] ?? false,
      error: json['error'],
      productId: json['productId'],
      productName: json['productName'],
      count: json['count'] ?? 0,
      confidence: (json['confidence'] ?? 0).toDouble(),
      annotatedImageUrl: json['annotatedImageUrl'],
      boxes: (json['boxes'] as List?)
          ?.map((b) => BoundingBox.fromJson(b))
          .toList() ?? [],
    );
  }

  factory DetectionResult.error(String message) => DetectionResult(
    success: false,
    error: message,
  );
}

/// Bounding box для отображения найденных объектов
class BoundingBox {
  final double x;      // Относительная координата (0-1)
  final double y;
  final double width;
  final double height;
  final double confidence;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x: (json['x'] ?? 0).toDouble(),
      y: (json['y'] ?? 0).toDouble(),
      width: (json['width'] ?? 0).toDouble(),
      height: (json['height'] ?? 0).toDouble(),
      confidence: (json['confidence'] ?? 0).toDouble(),
    );
  }
}

/// Результат проверки выкладки
class DisplayCheckResult {
  final bool success;
  final String? error;
  final List<MissingProduct> missingProducts;  // Отсутствующие товары
  final List<DetectedProduct> detectedProducts; // Обнаруженные товары
  final String? annotatedImageUrl;

  DisplayCheckResult({
    required this.success,
    this.error,
    this.missingProducts = const [],
    this.detectedProducts = const [],
    this.annotatedImageUrl,
  });

  factory DisplayCheckResult.fromJson(Map<String, dynamic> json) {
    return DisplayCheckResult(
      success: json['success'] ?? false,
      error: json['error'],
      missingProducts: (json['missingProducts'] as List?)
          ?.map((m) => MissingProduct.fromJson(m))
          .toList() ?? [],
      detectedProducts: (json['detectedProducts'] as List?)
          ?.map((d) => DetectedProduct.fromJson(d))
          .toList() ?? [],
      annotatedImageUrl: json['annotatedImageUrl'],
    );
  }

  factory DisplayCheckResult.error(String message) => DisplayCheckResult(
    success: false,
    error: message,
  );
}

/// Отсутствующий товар на выкладке
class MissingProduct {
  final String productId;
  final String barcode;
  final String productName;
  final String productGroup;

  MissingProduct({
    required this.productId,
    required this.barcode,
    required this.productName,
    required this.productGroup,
  });

  factory MissingProduct.fromJson(Map<String, dynamic> json) {
    return MissingProduct(
      productId: json['productId'] ?? '',
      barcode: json['barcode'] ?? '',
      productName: json['productName'] ?? '',
      productGroup: json['productGroup'] ?? '',
    );
  }
}

/// Обнаруженный товар на выкладке
class DetectedProduct {
  final String productId;
  final String barcode;
  final String productName;
  final int count;
  final double confidence;

  DetectedProduct({
    required this.productId,
    required this.barcode,
    required this.productName,
    required this.count,
    required this.confidence,
  });

  factory DetectedProduct.fromJson(Map<String, dynamic> json) {
    return DetectedProduct(
      productId: json['productId'] ?? '',
      barcode: json['barcode'] ?? '',
      productName: json['productName'] ?? '',
      count: json['count'] ?? 0,
      confidence: (json['confidence'] ?? 0).toDouble(),
    );
  }
}
