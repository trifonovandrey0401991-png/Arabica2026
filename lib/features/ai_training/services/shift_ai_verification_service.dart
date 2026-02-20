import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../models/shift_ai_verification_model.dart';

/// Сервис для ИИ проверки товаров при пересменке
class ShiftAiVerificationService {
  /// Проверить фото с помощью YOLO
  static Future<ShiftAiVerificationResult> verifyShiftPhotos({
    required List<Uint8List> photos,
    required String shopAddress,
  }) async {
    try {
      // Конвертируем фото в base64
      final imagesBase64 = photos.map((photo) => base64Encode(photo)).toList();

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/verify'),
        headers: ApiConstants.headersWithApiKey,
        body: jsonEncode({
          'imagesBase64': imagesBase64,
          'shopAddress': shopAddress,
        }),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ShiftAiVerificationResult.fromJson(data);
      } else {
        Logger.error('Ошибка проверки ИИ: ${response.statusCode}');
        return ShiftAiVerificationResult.error('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      Logger.error('Ошибка проверки ИИ', e);
      return ShiftAiVerificationResult.error('Ошибка: $e');
    }
  }

  /// Получить активные товары для магазина
  static Future<List<ShiftTrainingProduct>> getActiveAiProducts(String shopId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/active-products/${Uri.encodeComponent(shopId)}'),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['products'] != null) {
          return (data['products'] as List<dynamic>)
              .map((p) => ShiftTrainingProduct.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка загрузки активных товаров', e);
      return [];
    }
  }

  /// Получить все товары с настройками ИИ
  static Future<List<ShiftTrainingProduct>> getAllProducts({String? group}) async {
    try {
      String url = '${ApiConstants.serverUrl}/api/shift-ai/products';
      if (group != null) {
        url += '?group=${Uri.encodeComponent(group)}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['products'] != null) {
          return (data['products'] as List<dynamic>)
              .map((p) => ShiftTrainingProduct.fromJson(p as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка загрузки товаров', e);
      return [];
    }
  }

  /// Получить группы товаров
  static Future<List<String>> getProductGroups() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/product-groups'),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['groups'] != null) {
          return (data['groups'] as List<dynamic>).map((g) => g.toString()).toList();
        }
      }
      return [];
    } catch (e) {
      Logger.error('Ошибка загрузки групп товаров', e);
      return [];
    }
  }

  /// Обновить настройки ИИ для товара
  static Future<bool> updateProductAiSettings({
    required String barcode,
    required bool isAiActive,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/products/${Uri.encodeComponent(barcode)}'),
        headers: ApiConstants.headersWithApiKey,
        body: jsonEncode({
          'isAiActive': isAiActive,
        }),
      ).timeout(ApiConstants.defaultTimeout);

      return response.statusCode == 200;
    } catch (e) {
      Logger.error('Ошибка обновления настроек ИИ', e);
      return false;
    }
  }

  /// Проверить обучена ли модель
  static Future<bool> isModelTrained() async {
    try {
      final status = await getModelStatus();
      return status['isTrained'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Получить статус модели YOLO
  static Future<Map<String, dynamic>> getModelStatus() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/model-status'),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'isTrained': false, 'samplesCount': 0};
    } catch (e) {
      Logger.error('Ошибка получения статуса модели', e);
      return {'isTrained': false, 'samplesCount': 0};
    }
  }

  /// Сохранить аннотацию (BBox) от сотрудника
  static Future<bool> saveEmployeeAnnotation({
    required Uint8List imageData,
    required String productId,
    required String barcode,
    required String productName,
    required Map<String, double> boundingBox, // x, y, width, height normalized 0-1
    required String shopAddress,
    required String employeeName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/annotations'),
        headers: ApiConstants.headersWithApiKey,
        body: jsonEncode({
          'imageBase64': base64Encode(imageData),
          'productId': productId,
          'barcode': barcode,
          'productName': productName,
          'boundingBox': boundingBox,
          'shopAddress': shopAddress,
          'employeeName': employeeName,
        }),
      ).timeout(ApiConstants.longTimeout);

      return response.statusCode == 200;
    } catch (e) {
      Logger.error('Ошибка сохранения аннотации', e);
      return false;
    }
  }

  /// Перепроверить товар в выделенной области BBox с помощью YOLO
  ///
  /// Возвращает результат детекции и сохраняет успешные распознавания для обучения
  static Future<BBoxVerificationResult> verifyBoundingBox({
    required Uint8List imageData,
    required Map<String, double> boundingBox, // x, y, width, height normalized 0-1
    required String productId,
    required String barcode,
    required String productName,
    required String shopAddress,
    required String employeeName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/verify-bbox'),
        headers: ApiConstants.headersWithApiKey,
        body: jsonEncode({
          'imageBase64': base64Encode(imageData),
          'boundingBox': boundingBox,
          'productId': productId,
          'barcode': barcode,
          'productName': productName,
          'shopAddress': shopAddress,
          'employeeName': employeeName,
        }),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return BBoxVerificationResult.fromJson(data);
      } else {
        Logger.error('Ошибка перепроверки BBox: ${response.statusCode}');
        return BBoxVerificationResult(
          success: false,
          detected: false,
          error: 'Ошибка сервера: ${response.statusCode}',
        );
      }
    } catch (e) {
      Logger.error('Ошибка перепроверки BBox', e);
      return BBoxVerificationResult(
        success: false,
        detected: false,
        error: 'Ошибка: $e',
      );
    }
  }

  /// Получить остатки товара
  static Future<int?> getProductStock(String shopAddress, String barcode) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/stock/${Uri.encodeComponent(shopAddress)}/${Uri.encodeComponent(barcode)}'),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['quantity'] as int?;
        }
      }
      return null;
    } catch (e) {
      Logger.error('Ошибка получения остатков', e);
      return null;
    }
  }

  /// Одобрить аннотацию — загрузить фото для обучения YOLO
  static Future<bool> approveAnnotation(String annotationId) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/annotations/${Uri.encodeComponent(annotationId)}/approve'),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(ApiConstants.defaultTimeout);

      return response.statusCode == 200;
    } catch (e) {
      Logger.error('Ошибка одобрения аннотации', e);
      return false;
    }
  }

  /// Отклонить аннотацию — НЕ использовать для обучения
  static Future<bool> rejectAnnotation(String annotationId) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/annotations/${Uri.encodeComponent(annotationId)}/reject'),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(ApiConstants.defaultTimeout);

      return response.statusCode == 200;
    } catch (e) {
      Logger.error('Ошибка отклонения аннотации', e);
      return false;
    }
  }

  /// Получить статистику обучения
  static Future<Map<String, dynamic>> getTrainingStats() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/shift-ai/stats'),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['stats'] != null) {
          return data['stats'] as Map<String, dynamic>;
        }
      }
      return {};
    } catch (e) {
      Logger.error('Ошибка получения статистики', e);
      return {};
    }
  }
}
