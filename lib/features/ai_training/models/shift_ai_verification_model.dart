import 'dart:typed_data';

/// Статус подтверждения товара
enum ConfirmationStatus {
  notConfirmed, // Ещё не подтверждён
  confirmedPresent, // Подтверждён как присутствующий (нарисован BBox)
  confirmedMissing, // Подтверждён как отсутствующий (недостача)
}

extension ConfirmationStatusExtension on ConfirmationStatus {
  String get name {
    switch (this) {
      case ConfirmationStatus.notConfirmed:
        return 'notConfirmed';
      case ConfirmationStatus.confirmedPresent:
        return 'confirmedPresent';
      case ConfirmationStatus.confirmedMissing:
        return 'confirmedMissing';
    }
  }

  String get label {
    switch (this) {
      case ConfirmationStatus.notConfirmed:
        return 'Не подтверждён';
      case ConfirmationStatus.confirmedPresent:
        return 'Присутствует';
      case ConfirmationStatus.confirmedMissing:
        return 'Отсутствует';
    }
  }

  static ConfirmationStatus fromString(String? value) {
    switch (value) {
      case 'confirmedPresent':
        return ConfirmationStatus.confirmedPresent;
      case 'confirmedMissing':
        return ConfirmationStatus.confirmedMissing;
      default:
        return ConfirmationStatus.notConfirmed;
    }
  }
}

/// Информация о товаре, который ИИ не смог найти на фото
class MissingProductInfo {
  final String productId;
  final String barcode;
  final String productName;
  final int? stockQuantity; // Количество на остатках (из DBF)
  ConfirmationStatus status;

  /// Счётчик попыток перепроверки ИИ через BBox
  int verificationAttempts;

  /// Пропущена ли проверка ИИ (после 3 неудачных попыток)
  bool aiVerificationSkipped;

  /// Максимальное количество попыток перепроверки
  static const int maxVerificationAttempts = 3;

  MissingProductInfo({
    required this.productId,
    required this.barcode,
    required this.productName,
    this.stockQuantity,
    this.status = ConfirmationStatus.notConfirmed,
    this.verificationAttempts = 0,
    this.aiVerificationSkipped = false,
  });

  factory MissingProductInfo.fromJson(Map<String, dynamic> json) {
    return MissingProductInfo(
      productId: json['productId'] ?? '',
      barcode: json['barcode'] ?? '',
      productName: json['productName'] ?? '',
      stockQuantity: json['stockQuantity'],
      status: ConfirmationStatusExtension.fromString(json['status']),
      verificationAttempts: json['verificationAttempts'] ?? 0,
      aiVerificationSkipped: json['aiVerificationSkipped'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'barcode': barcode,
      'productName': productName,
      'stockQuantity': stockQuantity,
      'status': status.name,
      'verificationAttempts': verificationAttempts,
      'aiVerificationSkipped': aiVerificationSkipped,
    };
  }

  /// Осталось попыток
  int get remainingAttempts => maxVerificationAttempts - verificationAttempts;

  /// Можно ли ещё пробовать
  bool get canRetry => verificationAttempts < maxVerificationAttempts;

  /// Можно показать кнопку "Пропустить"
  bool get canSkip =>
      verificationAttempts >= maxVerificationAttempts &&
      status == ConfirmationStatus.notConfirmed;
}

/// Информация о товаре, обнаруженном ИИ на фото
class DetectedProductInfo {
  final String productId;
  final String barcode;
  final String productName;
  final double confidence; // 0.0 - 1.0
  final Map<String, double>? boundingBox; // x, y, width, height (normalized 0-1)

  DetectedProductInfo({
    required this.productId,
    required this.barcode,
    required this.productName,
    required this.confidence,
    this.boundingBox,
  });

  factory DetectedProductInfo.fromJson(Map<String, dynamic> json) {
    return DetectedProductInfo(
      productId: json['productId'] ?? '',
      barcode: json['barcode'] ?? '',
      productName: json['productName'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      boundingBox: json['boundingBox'] != null
          ? Map<String, double>.from(
              (json['boundingBox'] as Map).map(
                (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
              ),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'barcode': barcode,
      'productName': productName,
      'confidence': confidence,
      if (boundingBox != null) 'boundingBox': boundingBox,
    };
  }

  /// Процент уверенности
  int get confidencePercent => (confidence * 100).round();
}

/// Информация о товаре, пропущенном из-за неготовности ИИ
class SkippedProductInfo {
  final String productId;
  final String barcode;
  final String productName;
  final String reason;
  final bool recountComplete;
  final int recountCount;
  final int requiredRecount;
  final bool displayComplete;
  final int displayCountForShop;
  final int requiredDisplayPerShop;

  SkippedProductInfo({
    required this.productId,
    required this.barcode,
    required this.productName,
    required this.reason,
    this.recountComplete = false,
    this.recountCount = 0,
    this.requiredRecount = 10,
    this.displayComplete = false,
    this.displayCountForShop = 0,
    this.requiredDisplayPerShop = 3,
  });

  factory SkippedProductInfo.fromJson(Map<String, dynamic> json) {
    return SkippedProductInfo(
      productId: json['productId'] ?? '',
      barcode: json['barcode'] ?? '',
      productName: json['productName'] ?? '',
      reason: json['reason'] ?? '',
      recountComplete: json['recountComplete'] ?? false,
      recountCount: json['recountCount'] ?? 0,
      requiredRecount: json['requiredRecount'] ?? 10,
      displayComplete: json['displayComplete'] ?? false,
      displayCountForShop: json['displayCountForShop'] ?? 0,
      requiredDisplayPerShop: json['requiredDisplayPerShop'] ?? 3,
    );
  }
}

/// Результат ИИ проверки при пересменке
class ShiftAiVerificationResult {
  final bool success;
  final bool modelTrained; // Обучена ли модель YOLO
  final List<MissingProductInfo> missingProducts; // Не найденные товары
  final List<DetectedProductInfo> detectedProducts; // Найденные товары
  final List<SkippedProductInfo> skippedProducts; // Пропущенные товары (ИИ не готов)
  final String? message;
  final String? error;

  ShiftAiVerificationResult({
    required this.success,
    required this.modelTrained,
    required this.missingProducts,
    required this.detectedProducts,
    this.skippedProducts = const [],
    this.message,
    this.error,
  });

  factory ShiftAiVerificationResult.fromJson(Map<String, dynamic> json) {
    return ShiftAiVerificationResult(
      success: json['success'] ?? false,
      modelTrained: json['modelTrained'] ?? false,
      missingProducts: json['missingProducts'] != null
          ? (json['missingProducts'] as List<dynamic>)
              .map((m) => MissingProductInfo.fromJson(m))
              .toList()
          : [],
      detectedProducts: json['detectedProducts'] != null
          ? (json['detectedProducts'] as List<dynamic>)
              .map((d) => DetectedProductInfo.fromJson(d))
              .toList()
          : [],
      skippedProducts: json['skippedProducts'] != null
          ? (json['skippedProducts'] as List<dynamic>)
              .map((s) => SkippedProductInfo.fromJson(s))
              .toList()
          : [],
      message: json['message'],
      error: json['error'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'modelTrained': modelTrained,
      'missingProducts': missingProducts.map((m) => m.toJson()).toList(),
      'detectedProducts': detectedProducts.map((d) => d.toJson()).toList(),
      if (message != null) 'message': message,
      if (error != null) 'error': error,
    };
  }

  /// Все товары найдены (нет отсутствующих)
  /// ВАЖНО: true только если была реальная проверка (есть найденные товары)
  bool get allProductsFound =>
      detectedProducts.isNotEmpty && missingProducts.isEmpty;

  /// Есть ли пропущенные товары (ИИ не готов для магазина)
  bool get hasSkippedProducts => skippedProducts.isNotEmpty;

  /// Не было проверки вообще (все товары пропущены)
  bool get noVerificationPerformed =>
      detectedProducts.isEmpty && missingProducts.isEmpty && skippedProducts.isNotEmpty;

  /// Есть товары требующие подтверждения
  bool get hasUnconfirmedProducts =>
      missingProducts.any((p) => p.status == ConfirmationStatus.notConfirmed);

  /// Количество подтверждённых недостач
  int get confirmedShortagesCount =>
      missingProducts.where((p) => p.status == ConfirmationStatus.confirmedMissing).length;

  /// Создать пустой результат (модель не обучена)
  factory ShiftAiVerificationResult.notTrained() {
    return ShiftAiVerificationResult(
      success: false,
      modelTrained: false,
      missingProducts: [],
      detectedProducts: [],
      skippedProducts: [],
      error: 'Модель YOLO ещё не обучена',
    );
  }

  /// Создать результат с ошибкой (сеть, таймаут и т.д.)
  factory ShiftAiVerificationResult.error(String message) {
    return ShiftAiVerificationResult(
      success: false,
      modelTrained: false, // Неизвестно — ошибка связи, не факт что модель обучена
      missingProducts: [],
      detectedProducts: [],
      skippedProducts: [],
      error: message,
    );
  }
}

/// Результат перепроверки BBox через YOLO API
class BBoxVerificationResult {
  final bool success;
  final bool detected;
  final double? confidence;
  final String? productId;
  final String? annotationId; // ID аннотации для обучения (pending approval)
  final String? message;
  final String? error;

  BBoxVerificationResult({
    required this.success,
    required this.detected,
    this.confidence,
    this.productId,
    this.annotationId,
    this.message,
    this.error,
  });

  factory BBoxVerificationResult.fromJson(Map<String, dynamic> json) {
    return BBoxVerificationResult(
      success: json['success'] ?? false,
      detected: json['detected'] ?? false,
      confidence: json['confidence'] != null
          ? (json['confidence'] as num).toDouble()
          : null,
      productId: json['productId'],
      annotationId: json['annotationId'],
      message: json['message'],
      error: json['error'],
    );
  }

  /// Процент уверенности
  int get confidencePercent =>
      confidence != null ? (confidence! * 100).round() : 0;

  /// Ошибка или сообщение
  String? get displayMessage => error ?? message;
}

/// Результат диалога BBox (возвращается из _BoundingBoxDialog)
class BBoxDialogResult {
  final bool detected;
  final Uint8List imageData;
  final Map<String, double> boundingBox;
  final double? confidence;
  final String? annotationId; // ID аннотации для обучения (pending approval)

  BBoxDialogResult({
    required this.detected,
    required this.imageData,
    required this.boundingBox,
    this.confidence,
    this.annotationId,
  });

  /// Процент уверенности
  int get confidencePercent =>
      confidence != null ? (confidence! * 100).round() : 0;
}

/// Товар для обучения ИИ (из мастер-каталога)
class ShiftTrainingProduct {
  final String productId;
  final String barcode;
  final String productName;
  final String? productGroup;
  final bool isAiActive; // Включена ли ИИ проверка для этого товара
  final int trainingPhotosCount; // Количество фото для обучения

  ShiftTrainingProduct({
    required this.productId,
    required this.barcode,
    required this.productName,
    this.productGroup,
    this.isAiActive = false,
    this.trainingPhotosCount = 0,
  });

  factory ShiftTrainingProduct.fromJson(Map<String, dynamic> json) {
    return ShiftTrainingProduct(
      productId: json['productId'] ?? json['id'] ?? '',
      barcode: json['barcode'] ?? '',
      productName: json['productName'] ?? json['name'] ?? '',
      productGroup: json['productGroup'] ?? json['group'],
      isAiActive: json['isAiActive'] ?? false,
      trainingPhotosCount: json['trainingPhotosCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'barcode': barcode,
      'productName': productName,
      'productGroup': productGroup,
      'isAiActive': isAiActive,
      'trainingPhotosCount': trainingPhotosCount,
    };
  }

  /// Копия с изменённым флагом isAiActive
  ShiftTrainingProduct copyWith({bool? isAiActive, int? trainingPhotosCount}) {
    return ShiftTrainingProduct(
      productId: productId,
      barcode: barcode,
      productName: productName,
      productGroup: productGroup,
      isAiActive: isAiActive ?? this.isAiActive,
      trainingPhotosCount: trainingPhotosCount ?? this.trainingPhotosCount,
    );
  }
}
