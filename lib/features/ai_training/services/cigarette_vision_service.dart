import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/cigarette_training_model.dart';

/// Сервис для работы с ИИ распознавания сигарет
class CigaretteVisionService {
  /// Получить список товаров с информацией об обучении
  /// [shopAddress] - если передан, сервер вернёт perShopDisplayStats только для этого магазина
  /// Это критически важно для производительности при большом количестве магазинов
  static Future<List<CigaretteProduct>> getProducts({
    String? productGroup,
    String? shopAddress,
  }) async {
    try {
      var url = '${ApiConstants.serverUrl}${ApiConstants.cigaretteProductsEndpoint}';
      final queryParams = <String>[];

      if (productGroup != null && productGroup.isNotEmpty) {
        queryParams.add('productGroup=${Uri.encodeComponent(productGroup)}');
      }
      if (shopAddress != null && shopAddress.isNotEmpty) {
        queryParams.add('shopAddress=${Uri.encodeComponent(shopAddress)}');
      }

      if (queryParams.isNotEmpty) {
        url += '?${queryParams.join('&')}';
      }

      // Увеличиваем таймаут для больших данных
      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['products'] as List? ?? data as List;
        return list.map((json) => CigaretteProduct.fromJson(json)).toList();
      } else {
        Logger.error('Ошибка получения товаров: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка получения товаров', e);
      return [];
    }
  }

  /// Обновить статус ИИ проверки для товара
  static Future<bool> updateProductAiStatus({
    required String productId,
    required bool isAiActive,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConstants.serverUrl}/api/master-catalog/$productId/ai-status'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({'isAiActive': isAiActive}),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        Logger.info('AI статус для товара $productId: ${isAiActive ? 'активна' : 'неактивна'}');
        return true;
      } else {
        Logger.error('Ошибка изменения AI статуса: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      Logger.error('Ошибка изменения AI статуса', e);
      return false;
    }
  }

  /// Получить список групп товаров
  static Future<List<String>> getProductGroups() async {
    try {
      // Используем endpoint мастер-каталога для групп
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/master-catalog/groups/list'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<String>.from(data['groups'] ?? []);
      } else {
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка получения групп', e);
      return [];
    }
  }

  /// Получить статистику обучения
  static Future<TrainingStats> getStats() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.cigaretteStatsEndpoint}'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        return TrainingStats.fromJson(jsonDecode(response.body));
      } else {
        return TrainingStats.empty();
      }
    } catch (e) {
      Logger.error('Ошибка получения статистики', e);
      return TrainingStats.empty();
    }
  }

  /// Загрузить образец для обучения (без аннотаций)
  static Future<bool> uploadTrainingSample({
    required Uint8List imageBytes,
    required String productId,
    required String barcode,
    required String productName,
    required TrainingSampleType type,
    String? shopAddress,
    String? employeeName,
  }) async {
    return uploadAnnotatedSample(
      imageBytes: imageBytes,
      productId: productId,
      barcode: barcode,
      productName: productName,
      type: type,
      boundingBoxes: [],
      shopAddress: shopAddress,
      employeeName: employeeName,
    );
  }

  /// Загрузить образец с аннотациями bounding boxes
  static Future<bool> uploadAnnotatedSample({
    required Uint8List imageBytes,
    required String productId,
    required String barcode,
    required String productName,
    required TrainingSampleType type,
    required List<AnnotationBox> boundingBoxes,
    int? templateId,
    String? shopAddress,
    String? employeeName,
  }) async {
    try {
      // Сжимаем изображение
      final compressedImage = await compressImage(imageBytes);
      final base64Image = base64Encode(compressedImage);

      final body = {
        'imageBase64': base64Image,
        'productId': productId,
        'barcode': barcode,
        'productName': productName,
        'type': type.value,
        'shopAddress': shopAddress,
        'employeeName': employeeName,
        'boundingBoxes': boundingBoxes.map((b) => b.toJson()).toList(),
      };

      // Добавляем templateId если указан
      if (templateId != null) {
        body['templateId'] = templateId;
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.cigaretteTrainingSamplesEndpoint}'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(body),
      ).timeout(ApiConstants.uploadTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        Logger.info('Образец с ${boundingBoxes.length} аннотациями загружен: $productName');
        return true;
      } else {
        Logger.error('Ошибка загрузки образца: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      Logger.error('Ошибка загрузки образца', e);
      return false;
    }
  }

  /// Получить образцы для конкретного товара
  static Future<List<TrainingSample>> getSamplesForProduct(String productId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.cigaretteTrainingSamplesEndpoint}?productId=$productId'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['samples'] as List? ?? [];
        return list.map((json) => TrainingSample.fromJson(json)).toList();
      } else {
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка получения образцов', e);
      return [];
    }
  }

  /// Удалить образец
  static Future<bool> deleteSample(String sampleId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.cigaretteTrainingSamplesEndpoint}/$sampleId'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      return response.statusCode == 200;
    } catch (e) {
      Logger.error('Ошибка удаления образца', e);
      return false;
    }
  }

  // ============ PENDING COUNTING SAMPLES (ожидающие подтверждения) ============

  /// Получить все pending фото пересчёта (для админа)
  static Future<List<TrainingSample>> getAllPendingCountingSamples() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/counting-pending'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['samples'] as List? ?? [];
        return list.map((json) => TrainingSample.fromJson(json)).toList();
      } else {
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка получения pending samples', e);
      return [];
    }
  }

  /// Получить pending фото пересчёта для товара
  static Future<List<TrainingSample>> getPendingCountingSamplesForProduct(String productId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/counting-pending/product/$productId'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['samples'] as List? ?? [];
        return list.map((json) => TrainingSample.fromJson(json)).toList();
      } else {
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка получения pending для товара', e);
      return [];
    }
  }

  /// Подтвердить pending фото (переместить в обучение)
  static Future<bool> approvePendingCountingSample(String sampleId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/counting-pending/$sampleId/approve'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка подтверждения pending sample', e);
      return false;
    }
  }

  /// Отклонить pending фото (удалить)
  static Future<bool> rejectPendingCountingSample(String sampleId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/counting-pending/$sampleId'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка отклонения pending sample', e);
      return false;
    }
  }

  /// Получить подтверждённые counting фото для товара
  static Future<List<TrainingSample>> getCountingSamplesForProduct(String productId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/counting-samples/$productId'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['samples'] as List? ?? [];
        return list.map((json) => TrainingSample.fromJson(json)).toList();
      } else {
        return [];
      }
    } catch (e) {
      Logger.error('Ошибка получения counting samples для товара', e);
      return [];
    }
  }

  /// Удалить counting фото
  static Future<bool> deleteCountingSample(String sampleId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/counting-samples/$sampleId'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка удаления counting sample', e);
      return false;
    }
  }

  /// Детекция и подсчёт пачек на фото (без сохранения для обучения)
  static Future<DetectionResult> detectAndCount({
    required Uint8List imageBytes,
    required String productId,
  }) async {
    try {
      // Сжимаем изображение
      final compressedImage = await compressImage(imageBytes);
      final base64Image = base64Encode(compressedImage);

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.cigaretteDetectEndpoint}'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'imageBase64': base64Image,
          'productId': productId,
        }),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        return DetectionResult.fromJson(jsonDecode(response.body));
      } else {
        final errorBody = jsonDecode(response.body);
        return DetectionResult.error(errorBody['error'] ?? 'Ошибка детекции');
      }
    } catch (e) {
      Logger.error('Ошибка детекции', e);
      return DetectionResult.error('Ошибка связи с сервером: $e');
    }
  }

  /// Детекция и подсчёт пачек с сохранением в COUNTING датасет
  /// Используется для пересчёта - успешные распознавания сохраняются для дообучения
  /// [isAiActive] - если true, фото будет сохранено для обучения независимо от результата детекции
  static Future<DetectionResult> detectAndCountWithTraining({
    required Uint8List imageBytes,
    required String productId,
    String? productName,
    String? shopAddress,
    bool isAiActive = false,
    int? employeeAnswer,
  }) async {
    try {
      // Сжимаем изображение
      final compressedImage = await compressImage(imageBytes);
      final base64Image = base64Encode(compressedImage);

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/count-with-training'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'imageBase64': base64Image,
          'productId': productId,
          'productName': productName,
          'shopAddress': shopAddress,
          'isAiActive': isAiActive,
          'employeeAnswer': employeeAnswer,
        }),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        return DetectionResult.fromJson(jsonDecode(response.body));
      } else {
        final errorBody = jsonDecode(response.body);
        return DetectionResult.error(errorBody['error'] ?? 'Ошибка детекции');
      }
    } catch (e) {
      Logger.error('Ошибка детекции с обучением', e);
      return DetectionResult.error('Ошибка связи с сервером: $e');
    }
  }

  /// Проверка выкладки - определить какие товары отсутствуют
  static Future<DisplayCheckResult> checkDisplay({
    required Uint8List imageBytes,
    String? shopAddress,
  }) async {
    try {
      // Сжимаем изображение
      final compressedImage = await compressImage(imageBytes);
      final base64Image = base64Encode(compressedImage);

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}${ApiConstants.cigaretteDisplayCheckEndpoint}'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'imageBase64': base64Image,
          'shopAddress': shopAddress,
        }),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        return DisplayCheckResult.fromJson(jsonDecode(response.body));
      } else {
        final errorBody = jsonDecode(response.body);
        return DisplayCheckResult.error(errorBody['error'] ?? 'Ошибка проверки выкладки');
      }
    } catch (e) {
      Logger.error('Ошибка проверки выкладки', e);
      return DisplayCheckResult.error('Ошибка связи с сервером: $e');
    }
  }

  /// Сжатие изображения для отправки на сервер
  static Future<Uint8List> compressImage(Uint8List imageBytes, {
    int maxWidth = 1200,
    int maxHeight = 1600,
    int quality = 75,
  }) async {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return imageBytes;

      // Изменяем размер если нужно
      img.Image resized = image;
      if (image.width > maxWidth || image.height > maxHeight) {
        final aspectRatio = image.width / image.height;
        int newWidth, newHeight;

        if (aspectRatio > maxWidth / maxHeight) {
          newWidth = maxWidth;
          newHeight = (maxWidth / aspectRatio).round();
        } else {
          newHeight = maxHeight;
          newWidth = (maxHeight * aspectRatio).round();
        }

        resized = img.copyResize(image, width: newWidth, height: newHeight);
      }

      // Кодируем в JPEG
      final compressed = img.encodeJpg(resized, quality: quality);
      return Uint8List.fromList(compressed);
    } catch (e) {
      Logger.error('Ошибка сжатия изображения', e);
      return imageBytes;
    }
  }

  // ============ НАСТРОЙКИ ============

  /// Получить настройки обучения
  static Future<TrainingSettings?> getSettings() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/settings'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return TrainingSettings.fromJson(data['settings']);
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка получения настроек', e);
      return null;
    }
  }

  /// Обновить настройки обучения
  static Future<TrainingSettings?> updateSettings({
    int? requiredRecountPhotos,
    int? requiredDisplayPhotosPerShop,
    String? catalogSource,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (requiredRecountPhotos != null) {
        body['requiredRecountPhotos'] = requiredRecountPhotos;
      }
      if (requiredDisplayPhotosPerShop != null) {
        body['requiredDisplayPhotosPerShop'] = requiredDisplayPhotosPerShop;
      }
      if (catalogSource != null) {
        body['catalogSource'] = catalogSource;
      }

      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/settings'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode(body),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return TrainingSettings.fromJson(data['settings']);
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка обновления настроек', e);
      return null;
    }
  }

  // ============ ВСЕ ОБРАЗЦЫ (для админки) ============

  /// Получить все образцы с фильтрацией
  static Future<SamplesResponse> getAllSamples({
    String? productId,
    String? type,
    int? limit,
    int? offset,
  }) async {
    try {
      var url = '${ApiConstants.serverUrl}/api/cigarette-vision/samples/all?';
      final params = <String>[];
      if (productId != null) params.add('productId=$productId');
      if (type != null) params.add('type=$type');
      if (limit != null) params.add('limit=$limit');
      if (offset != null) params.add('offset=$offset');
      url += params.join('&');

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        return SamplesResponse.fromJson(jsonDecode(response.body));
      }
      return SamplesResponse.empty();
    } catch (e) {
      Logger.error('Ошибка получения всех образцов', e);
      return SamplesResponse.empty();
    }
  }

  // ============ СИСТЕМА ОБРАТНОЙ СВЯЗИ И АВТООТКЛЮЧЕНИЯ ИИ ============

  /// Сообщить об ошибке ИИ (кнопка "ИИ ошибся")
  /// Сохраняет фото для анализа и увеличивает счётчик ошибок
  /// После 5 ошибок подряд ИИ автоматически отключается для товара
  static Future<AiErrorReport> reportAiError({
    required String productId,
    required String productName,
    required int expectedCount,
    required int aiCount,
    Uint8List? imageBytes,
    String? shopAddress,
    String? employeeName,
  }) async {
    try {
      String? base64Image;
      if (imageBytes != null) {
        final compressed = await compressImage(imageBytes);
        base64Image = base64Encode(compressed);
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/report-error'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'productId': productId,
          'productName': productName,
          'expectedCount': expectedCount,
          'aiCount': aiCount,
          'imageBase64': base64Image,
          'shopAddress': shopAddress,
          'employeeName': employeeName,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        return AiErrorReport.fromJson(jsonDecode(response.body));
      }
      return AiErrorReport.error('Ошибка отправки');
    } catch (e) {
      Logger.error('Ошибка отправки report-error', e);
      return AiErrorReport.error('Ошибка связи: $e');
    }
  }

  /// Проверить отключен ли ИИ для товара
  static Future<bool> isProductAiDisabled(String productId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/is-ai-disabled/$productId'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['isDisabled'] == true;
      }
      return false;
    } catch (e) {
      Logger.error('Ошибка проверки статуса ИИ', e);
      return false;
    }
  }

  /// Получить полный статус ИИ для товара
  static Future<ProductAiStatus?> getProductAiStatus(String productId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/product-ai-status/$productId'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        return ProductAiStatus.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка получения статуса ИИ', e);
      return null;
    }
  }

  /// Сбросить счётчик ошибок и включить ИИ (только админ)
  static Future<bool> resetProductAiErrors(String productId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/reset-product-ai/$productId'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      return response.statusCode == 200;
    } catch (e) {
      Logger.error('Ошибка сброса ошибок ИИ', e);
      return false;
    }
  }

  /// Получить список проблемных товаров (для админки)
  static Future<List<ProblematicProduct>> getProblematicProducts() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/problematic-products'),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final products = data['products'] as List? ?? [];
        return products.map((p) => ProblematicProduct.fromJson(p)).toList();
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка получения проблемных товаров', e);
      return [];
    }
  }

  /// Решение админа по ошибке ИИ
  /// decision: "approved_for_training" (ИИ ошибся) | "rejected_bad_photo" (плохое фото)
  static Future<AdminAiDecisionResult> reportAdminAiDecision({
    required String productId,
    required String decision,
    required String adminName,
    String? productName,
    Uint8List? imageBytes,
    int? expectedCount,
    int? aiCount,
    String? shopAddress,
  }) async {
    try {
      String? base64Image;
      if (imageBytes != null) {
        final compressed = await compressImage(imageBytes);
        base64Image = base64Encode(compressed);
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/cigarette-vision/admin-ai-decision'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'productId': productId,
          'productName': productName,
          'decision': decision,
          'adminName': adminName,
          'imageBase64': base64Image,
          'expectedCount': expectedCount,
          'aiCount': aiCount,
          'shopAddress': shopAddress,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        return AdminAiDecisionResult.fromJson(jsonDecode(response.body));
      }
      return AdminAiDecisionResult.error('Ошибка отправки решения');
    } catch (e) {
      Logger.error('Ошибка отправки решения админа', e);
      return AdminAiDecisionResult.error('Ошибка связи: $e');
    }
  }
}

/// Результат решения админа по ошибке ИИ
class AdminAiDecisionResult {
  final bool success;
  final String? error;
  final String? productId;
  final String? decision;
  final String? adminName;
  final int consecutiveErrors;
  final int totalErrors;
  final bool isDisabled;
  final int threshold;

  AdminAiDecisionResult({
    required this.success,
    this.error,
    this.productId,
    this.decision,
    this.adminName,
    this.consecutiveErrors = 0,
    this.totalErrors = 0,
    this.isDisabled = false,
    this.threshold = 5,
  });

  factory AdminAiDecisionResult.fromJson(Map<String, dynamic> json) {
    return AdminAiDecisionResult(
      success: json['success'] == true,
      error: json['error'],
      productId: json['productId'],
      decision: json['decision'],
      adminName: json['adminName'],
      consecutiveErrors: json['consecutiveErrors'] ?? 0,
      totalErrors: json['totalErrors'] ?? 0,
      isDisabled: json['isDisabled'] == true,
      threshold: json['threshold'] ?? 5,
    );
  }

  factory AdminAiDecisionResult.error(String message) => AdminAiDecisionResult(
    success: false,
    error: message,
  );
}

/// Результат отправки ошибки ИИ
class AiErrorReport {
  final bool success;
  final String? error;
  final String? productId;
  final int consecutiveErrors;
  final int totalErrors;
  final bool isDisabled;
  final int threshold;

  AiErrorReport({
    required this.success,
    this.error,
    this.productId,
    this.consecutiveErrors = 0,
    this.totalErrors = 0,
    this.isDisabled = false,
    this.threshold = 5,
  });

  factory AiErrorReport.fromJson(Map<String, dynamic> json) {
    return AiErrorReport(
      success: json['success'] == true,
      error: json['error'],
      productId: json['productId'],
      consecutiveErrors: json['consecutiveErrors'] ?? 0,
      totalErrors: json['totalErrors'] ?? 0,
      isDisabled: json['isDisabled'] == true,
      threshold: json['threshold'] ?? 5,
    );
  }

  factory AiErrorReport.error(String message) => AiErrorReport(
    success: false,
    error: message,
  );
}

/// Статус ИИ для товара
class ProductAiStatus {
  final String productId;
  final String? productName;
  final bool exists;
  final bool isDisabled;
  final int consecutiveErrors;
  final int totalErrors;
  final DateTime? lastErrorAt;
  final DateTime? disabledAt;
  final int threshold;
  final int resetDays;

  ProductAiStatus({
    required this.productId,
    this.productName,
    this.exists = false,
    this.isDisabled = false,
    this.consecutiveErrors = 0,
    this.totalErrors = 0,
    this.lastErrorAt,
    this.disabledAt,
    this.threshold = 5,
    this.resetDays = 7,
  });

  factory ProductAiStatus.fromJson(Map<String, dynamic> json) {
    return ProductAiStatus(
      productId: json['productId'] ?? '',
      productName: json['productName'],
      exists: json['exists'] == true,
      isDisabled: json['isDisabled'] == true,
      consecutiveErrors: json['consecutiveErrors'] ?? 0,
      totalErrors: json['totalErrors'] ?? 0,
      lastErrorAt: json['lastErrorAt'] != null ? DateTime.tryParse(json['lastErrorAt']) : null,
      disabledAt: json['disabledAt'] != null ? DateTime.tryParse(json['disabledAt']) : null,
      threshold: json['threshold'] ?? 5,
      resetDays: json['resetDays'] ?? 7,
    );
  }
}

/// Проблемный товар (для админки)
class ProblematicProduct {
  final String productId;
  final String? productName;
  final bool isDisabled;
  final int consecutiveErrors;
  final int totalErrors;
  final DateTime? lastErrorAt;

  ProblematicProduct({
    required this.productId,
    this.productName,
    this.isDisabled = false,
    this.consecutiveErrors = 0,
    this.totalErrors = 0,
    this.lastErrorAt,
  });

  factory ProblematicProduct.fromJson(Map<String, dynamic> json) {
    return ProblematicProduct(
      productId: json['productId'] ?? '',
      productName: json['productName'],
      isDisabled: json['isDisabled'] == true,
      consecutiveErrors: json['consecutiveErrors'] ?? 0,
      totalErrors: json['totalErrors'] ?? 0,
      lastErrorAt: json['lastErrorAt'] != null ? DateTime.tryParse(json['lastErrorAt']) : null,
    );
  }
}

/// Настройки обучения
class TrainingSettings {
  final int requiredRecountPhotos;
  /// Количество фото выкладки НА МАГАЗИН (каждый магазин должен добавить свои фото)
  final int requiredDisplayPhotosPerShop;
  /// Количество фото пересчёта (общее для всех магазинов)
  final int requiredCountingPhotos;
  /// Источник каталога товаров:
  /// - "recount-questions" - текущий каталог (вопросы пересчёта)
  /// - "master-catalog" - единый мастер-каталог (новый)
  final String catalogSource;

  TrainingSettings({
    required this.requiredRecountPhotos,
    required this.requiredDisplayPhotosPerShop,
    this.requiredCountingPhotos = 10,
    this.catalogSource = 'recount-questions',
  });

  factory TrainingSettings.fromJson(Map<String, dynamic> json) {
    return TrainingSettings(
      requiredRecountPhotos: json['requiredRecountPhotos'] ?? 10,
      requiredDisplayPhotosPerShop: json['requiredDisplayPhotosPerShop'] ?? json['requiredDisplayPhotos'] ?? 3,
      requiredCountingPhotos: json['requiredCountingPhotos'] ?? 10,
      catalogSource: json['catalogSource'] ?? 'recount-questions',
    );
  }

  /// Проверка: используется ли текущий каталог (вопросы пересчёта)
  bool get useRecountQuestions => catalogSource == 'recount-questions';

  /// Проверка: используется ли мастер-каталог
  bool get useMasterCatalog => catalogSource == 'master-catalog';
}

/// Ответ с образцами
class SamplesResponse {
  final List<TrainingSample> samples;
  final int total;
  final int offset;
  final int limit;

  SamplesResponse({
    required this.samples,
    required this.total,
    required this.offset,
    required this.limit,
  });

  factory SamplesResponse.fromJson(Map<String, dynamic> json) {
    return SamplesResponse(
      samples: (json['samples'] as List?)
          ?.map((s) => TrainingSample.fromJson(s))
          .toList() ?? [],
      total: json['total'] ?? 0,
      offset: json['offset'] ?? 0,
      limit: json['limit'] ?? 50,
    );
  }

  factory SamplesResponse.empty() => SamplesResponse(
    samples: [],
    total: 0,
    offset: 0,
    limit: 50,
  );
}
