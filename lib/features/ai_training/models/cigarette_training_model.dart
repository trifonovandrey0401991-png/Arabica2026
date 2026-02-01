// Модели данных для обучения ИИ подсчёту сигарет

/// Статистика фото выкладки для конкретного магазина
class ShopDisplayStats {
  final String shopAddress;
  final String? shopName;
  final String? shopId;
  final int displayPhotosCount;
  final int requiredDisplayPhotos;
  final bool isDisplayComplete;

  ShopDisplayStats({
    required this.shopAddress,
    this.shopName,
    this.shopId,
    required this.displayPhotosCount,
    required this.requiredDisplayPhotos,
    required this.isDisplayComplete,
  });

  factory ShopDisplayStats.fromJson(Map<String, dynamic> json) {
    final count = json['displayPhotosCount'] ?? 0;
    final required = json['requiredDisplayPhotos'] ?? 3;
    return ShopDisplayStats(
      shopAddress: json['shopAddress'] ?? '',
      shopName: json['shopName'],
      shopId: json['shopId'],
      displayPhotosCount: count,
      requiredDisplayPhotos: required,
      isDisplayComplete: json['isDisplayComplete'] ?? (count >= required),
    );
  }

  Map<String, dynamic> toJson() => {
    'shopAddress': shopAddress,
    'shopName': shopName,
    'shopId': shopId,
    'displayPhotosCount': displayPhotosCount,
    'requiredDisplayPhotos': requiredDisplayPhotos,
    'isDisplayComplete': isDisplayComplete,
  };

  /// Процент прогресса (0-100)
  double get progress => requiredDisplayPhotos > 0
      ? (displayPhotosCount / requiredDisplayPhotos * 100).clamp(0, 100)
      : 0;
}

/// Товар для обучения (из вопросов пересчёта)
class CigaretteProduct {
  final String id;
  final String barcode;
  final String productGroup;
  final String productName;
  final int grade;

  // Статус ИИ проверки при пересчёте
  final bool isAiActive; // Если true - ИИ проверяет фото при пересчёте

  // Общая статистика
  final int trainingPhotosCount;
  final int requiredPhotosCount;
  final bool isTrainingComplete;

  // Раздельная статистика: крупный план (recount)
  final int recountPhotosCount;
  final int requiredRecountPhotos;
  final bool isRecountComplete;
  final List<int> completedTemplates; // Выполненные шаблоны (1-10)

  // Раздельная статистика: выкладка (display) - общая для обратной совместимости
  final int displayPhotosCount;
  final int requiredDisplayPhotos;
  final bool isDisplayComplete;

  // Раздельная статистика: пересчёт (counting) - фото с пересчёта
  final int countingPhotosCount;
  final int requiredCountingPhotos;
  final bool isCountingComplete;

  // НОВОЕ: Per-shop статистика выкладки
  final List<ShopDisplayStats> perShopDisplayStats;
  final int totalDisplayPhotos;
  final int requiredDisplayPhotosPerShop;
  final int shopsWithAiReady;
  final int totalShops;

  CigaretteProduct({
    required this.id,
    required this.barcode,
    required this.productGroup,
    required this.productName,
    required this.grade,
    this.isAiActive = false,
    this.trainingPhotosCount = 0,
    this.requiredPhotosCount = 20,
    this.isTrainingComplete = false,
    this.recountPhotosCount = 0,
    this.requiredRecountPhotos = 10,
    this.isRecountComplete = false,
    this.completedTemplates = const [],
    this.displayPhotosCount = 0,
    this.requiredDisplayPhotos = 10,
    this.isDisplayComplete = false,
    // Counting статистика
    this.countingPhotosCount = 0,
    this.requiredCountingPhotos = 10,
    this.isCountingComplete = false,
    // Per-shop статистика
    this.perShopDisplayStats = const [],
    this.totalDisplayPhotos = 0,
    this.requiredDisplayPhotosPerShop = 3,
    this.shopsWithAiReady = 0,
    this.totalShops = 0,
  });

  factory CigaretteProduct.fromJson(Map<String, dynamic> json) {
    final recountPhotos = json['recountPhotosCount'] ?? 0;
    final displayPhotos = json['displayPhotosCount'] ?? 0;
    final countingPhotos = json['countingPhotosCount'] ?? 0;
    final requiredRecount = json['requiredRecountPhotos'] ?? 10;
    final requiredDisplay = json['requiredDisplayPhotos'] ?? 3;  // Теперь per-shop
    final requiredCounting = json['requiredCountingPhotos'] ?? 10;
    final completedTemplatesList = (json['completedTemplates'] as List?)
        ?.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0)
        .toList() ?? [];

    // Парсинг per-shop статистики
    final perShopStatsList = (json['perShopDisplayStats'] as List?)
        ?.map((s) => ShopDisplayStats.fromJson(s as Map<String, dynamic>))
        .toList() ?? [];

    return CigaretteProduct(
      id: json['id'] ?? '',
      barcode: json['barcode']?.toString() ?? '',
      // Поддержка обоих полей: productGroup (старое) и group (мастер-каталог)
      productGroup: json['productGroup']?.toString() ?? json['group']?.toString() ?? '',
      productName: json['productName']?.toString() ?? json['name']?.toString() ?? json['question']?.toString() ?? '',
      grade: json['grade'] is int ? json['grade'] : int.tryParse(json['grade'].toString()) ?? 1,
      isAiActive: json['isAiActive'] ?? false,
      trainingPhotosCount: json['trainingPhotosCount'] ?? (recountPhotos + displayPhotos),
      requiredPhotosCount: json['requiredPhotosCount'] ?? 20,
      isTrainingComplete: json['isTrainingComplete'] ?? false,
      recountPhotosCount: recountPhotos,
      requiredRecountPhotos: requiredRecount,
      isRecountComplete: json['isRecountComplete'] ?? (completedTemplatesList.length >= 10),
      completedTemplates: completedTemplatesList,
      displayPhotosCount: displayPhotos,
      requiredDisplayPhotos: requiredDisplay,
      isDisplayComplete: json['isDisplayComplete'] ?? (displayPhotos >= requiredDisplay),
      // Counting статистика
      countingPhotosCount: countingPhotos,
      requiredCountingPhotos: requiredCounting,
      isCountingComplete: json['isCountingComplete'] ?? (countingPhotos >= requiredCounting),
      // Per-shop статистика
      perShopDisplayStats: perShopStatsList,
      totalDisplayPhotos: json['totalDisplayPhotos'] ?? displayPhotos,
      requiredDisplayPhotosPerShop: json['requiredDisplayPhotosPerShop'] ?? 3,
      shopsWithAiReady: json['shopsWithAiReady'] ?? 0,
      totalShops: json['totalShops'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'barcode': barcode,
    'productGroup': productGroup,
    'productName': productName,
    'grade': grade,
    'isAiActive': isAiActive,
    'trainingPhotosCount': trainingPhotosCount,
    'requiredPhotosCount': requiredPhotosCount,
    'isTrainingComplete': isTrainingComplete,
    'recountPhotosCount': recountPhotosCount,
    'requiredRecountPhotos': requiredRecountPhotos,
    'isRecountComplete': isRecountComplete,
    'completedTemplates': completedTemplates,
    'displayPhotosCount': displayPhotosCount,
    'requiredDisplayPhotos': requiredDisplayPhotos,
    'isDisplayComplete': isDisplayComplete,
    // Counting статистика
    'countingPhotosCount': countingPhotosCount,
    'requiredCountingPhotos': requiredCountingPhotos,
    'isCountingComplete': isCountingComplete,
    // Per-shop статистика
    'perShopDisplayStats': perShopDisplayStats.map((s) => s.toJson()).toList(),
    'totalDisplayPhotos': totalDisplayPhotos,
    'requiredDisplayPhotosPerShop': requiredDisplayPhotosPerShop,
    'shopsWithAiReady': shopsWithAiReady,
    'totalShops': totalShops,
  };

  /// Получить статистику для конкретного магазина
  ShopDisplayStats? getShopStats(String shopAddress) {
    if (shopAddress.isEmpty) return null;

    // Нормализуем адрес для сравнения (trim и lowercase)
    final normalizedSearch = shopAddress.trim().toLowerCase();

    try {
      // Сначала пробуем точное совпадение
      return perShopDisplayStats.firstWhere(
        (s) => s.shopAddress == shopAddress,
      );
    } catch (e) {
      // Если точное не найдено - пробуем нормализованное сравнение
      try {
        return perShopDisplayStats.firstWhere(
          (s) => s.shopAddress.trim().toLowerCase() == normalizedSearch,
        );
      } catch (e2) {
        return null;
      }
    }
  }

  /// Может ли ИИ работать в этом магазине
  /// (крупный план завершён + выкладка для этого магазина завершена)
  bool isAiEnabledForShop(String shopAddress) {
    if (!isRecountComplete) return false;
    final stats = getShopStats(shopAddress);
    return stats?.isDisplayComplete ?? false;
  }

  /// Процент завершённости обучения (0-100)
  double get trainingProgress =>
    requiredPhotosCount > 0
      ? (trainingPhotosCount / requiredPhotosCount * 100).clamp(0, 100)
      : 0;

  /// Процент фото крупного плана
  double get recountProgress =>
    requiredRecountPhotos > 0
      ? (recountPhotosCount / requiredRecountPhotos * 100).clamp(0, 100)
      : 0;

  /// Процент фото выкладки
  double get displayProgress =>
    requiredDisplayPhotos > 0
      ? (displayPhotosCount / requiredDisplayPhotos * 100).clamp(0, 100)
      : 0;

  /// Процент фото пересчёта (counting)
  double get countingProgress =>
    requiredCountingPhotos > 0
      ? (countingPhotosCount / requiredCountingPhotos * 100).clamp(0, 100)
      : 0;
}

/// Аннотация bounding box для обучения YOLO (нормализованные координаты 0-1)
class AnnotationBox {
  final double xCenter;   // Центр X (0.0-1.0)
  final double yCenter;   // Центр Y (0.0-1.0)
  final double width;     // Ширина (0.0-1.0)
  final double height;    // Высота (0.0-1.0)

  AnnotationBox({
    required this.xCenter,
    required this.yCenter,
    required this.width,
    required this.height,
  });

  /// Создать из координат левого верхнего угла и размеров (пиксели → нормализованные)
  factory AnnotationBox.fromRect({
    required double left,
    required double top,
    required double rectWidth,
    required double rectHeight,
    required double imageWidth,
    required double imageHeight,
  }) {
    return AnnotationBox(
      xCenter: (left + rectWidth / 2) / imageWidth,
      yCenter: (top + rectHeight / 2) / imageHeight,
      width: rectWidth / imageWidth,
      height: rectHeight / imageHeight,
    );
  }

  factory AnnotationBox.fromJson(Map<String, dynamic> json) {
    return AnnotationBox(
      xCenter: (json['xCenter'] ?? json['x_center'] ?? 0).toDouble(),
      yCenter: (json['yCenter'] ?? json['y_center'] ?? 0).toDouble(),
      width: (json['width'] ?? 0).toDouble(),
      height: (json['height'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'xCenter': xCenter,
    'yCenter': yCenter,
    'width': width,
    'height': height,
  };

  /// Конвертировать в строку YOLO формата: "class_id x_center y_center width height"
  String toYoloFormat(int classId) {
    return '$classId ${xCenter.toStringAsFixed(6)} ${yCenter.toStringAsFixed(6)} ${width.toStringAsFixed(6)} ${height.toStringAsFixed(6)}';
  }
}

/// Образец для обучения (фото + метаданные + аннотации)
class TrainingSample {
  final String id;
  final String productId;
  final String barcode;
  final String productName;
  final String imageUrl;
  final String? shopAddress;
  final String? employeeName;
  final DateTime createdAt;
  final TrainingSampleType type;
  final int? templateId; // ID шаблона (1-10) для крупного плана
  final List<AnnotationBox> boundingBoxes; // Аннотации для обучения

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
    this.templateId,
    this.boundingBoxes = const [],
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
      templateId: json['templateId'] is int ? json['templateId'] : null,
      boundingBoxes: (json['boundingBoxes'] as List?)
          ?.map((b) => AnnotationBox.fromJson(b))
          .toList() ?? [],
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
    'templateId': templateId,
    'boundingBoxes': boundingBoxes.map((b) => b.toJson()).toList(),
  };

  /// Количество аннотаций
  int get annotationCount => boundingBoxes.length;

  /// Есть ли аннотации
  bool get hasAnnotations => boundingBoxes.isNotEmpty;
}

/// Тип образца для обучения
enum TrainingSampleType {
  recount('recount'),    // Фото крупного плана (шаблоны)
  display('display'),    // Фото выкладки витрины
  counting('counting');  // Фото с пересчёта товаров

  final String value;
  const TrainingSampleType(this.value);

  static TrainingSampleType fromString(String? value) {
    switch (value) {
      case 'display':
        return TrainingSampleType.display;
      case 'counting':
        return TrainingSampleType.counting;
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
