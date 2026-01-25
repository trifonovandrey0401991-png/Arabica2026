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
  static Future<List<CigaretteProduct>> getProducts({String? productGroup}) async {
    try {
      var url = '${ApiConstants.serverUrl}${ApiConstants.cigaretteProductsEndpoint}';
      if (productGroup != null && productGroup.isNotEmpty) {
        url += '?productGroup=${Uri.encodeComponent(productGroup)}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.jsonHeaders,
      ).timeout(ApiConstants.defaultTimeout);

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

  /// Детекция и подсчёт пачек на фото
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
    int? requiredDisplayPhotos,
    String? catalogSource,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (requiredRecountPhotos != null) {
        body['requiredRecountPhotos'] = requiredRecountPhotos;
      }
      if (requiredDisplayPhotos != null) {
        body['requiredDisplayPhotos'] = requiredDisplayPhotos;
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
}

/// Настройки обучения
class TrainingSettings {
  final int requiredRecountPhotos;
  final int requiredDisplayPhotos;
  /// Источник каталога товаров:
  /// - "recount-questions" - текущий каталог (вопросы пересчёта)
  /// - "master-catalog" - единый мастер-каталог (новый)
  final String catalogSource;

  TrainingSettings({
    required this.requiredRecountPhotos,
    required this.requiredDisplayPhotos,
    this.catalogSource = 'recount-questions',
  });

  factory TrainingSettings.fromJson(Map<String, dynamic> json) {
    return TrainingSettings(
      requiredRecountPhotos: json['requiredRecountPhotos'] ?? 10,
      requiredDisplayPhotos: json['requiredDisplayPhotos'] ?? 10,
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
