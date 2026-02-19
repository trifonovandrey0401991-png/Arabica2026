import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../../../core/constants/api_constants.dart';
import '../models/z_report_sample_model.dart' show ZReportParseResult;

class ZReportService {
  /// Максимальный размер изображения для распознавания
  static const int _maxImageWidth = 1200;
  static const int _maxImageHeight = 1600;
  static const int _jpegQuality = 75;

  /// Сжать изображение для уменьшения размера
  /// Возвращает base64 сжатого JPEG
  static Future<String> compressImage(Uint8List imageBytes) async {
    return compute(_compressImageIsolate, imageBytes);
  }

  /// Функция сжатия в изоляте (отдельном потоке)
  static String _compressImageIsolate(Uint8List imageBytes) {
    // Декодируем изображение
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      // Если не удалось декодировать - возвращаем оригинал
      return base64Encode(imageBytes);
    }

    // Вычисляем новые размеры с сохранением пропорций
    int newWidth = image.width;
    int newHeight = image.height;

    if (image.width > _maxImageWidth || image.height > _maxImageHeight) {
      final widthRatio = _maxImageWidth / image.width;
      final heightRatio = _maxImageHeight / image.height;
      final ratio = widthRatio < heightRatio ? widthRatio : heightRatio;

      newWidth = (image.width * ratio).round();
      newHeight = (image.height * ratio).round();
    }

    // Масштабируем если нужно
    img.Image resized;
    if (newWidth != image.width || newHeight != image.height) {
      resized = img.copyResize(image, width: newWidth, height: newHeight);
    } else {
      resized = image;
    }

    // Кодируем в JPEG с заданным качеством
    final compressedBytes = img.encodeJpg(resized, quality: _jpegQuality);

    return base64Encode(compressedBytes);
  }

  /// Распознать Z-отчёт по фото (с автоматическим сжатием)
  static Future<ZReportParseResult> parseZReportFromBytes(Uint8List imageBytes, {String? shopAddress}) async {
    final compressedBase64 = await compressImage(imageBytes);
    return parseZReport(compressedBase64, shopAddress: shopAddress);
  }

  /// Распознать Z-отчёт по фото
  /// [shopAddress] — адрес магазина для подсказки ожидаемых диапазонов (intelligence)
  static Future<ZReportParseResult> parseZReport(String imageBase64, {String? shopAddress}) async {
    try {
      final body = <String, dynamic>{'imageBase64': imageBase64};
      if (shopAddress != null && shopAddress.isNotEmpty) {
        body['shopAddress'] = shopAddress;
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/parse'),
        headers: ApiConstants.headersWithApiKey,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ZReportParseResult.fromJson(data);
      } else {
        return ZReportParseResult(
          success: false,
          error: 'Ошибка сервера: ${response.statusCode}',
        );
      }
    } catch (e) {
      return ZReportParseResult(
        success: false,
        error: 'Ошибка подключения: $e',
      );
    }
  }

  /// Получить ожидаемые диапазоны (intelligence) для магазина
  static Future<Map<String, dynamic>?> getIntelligence(String shopAddress) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/intelligence?shopAddress=${Uri.encodeComponent(shopAddress)}'),
        headers: ApiConstants.headersWithApiKey,
      ).timeout(ApiConstants.shortTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['expectedRanges'] as Map<String, dynamic>?;
        }
      }
    } catch (_) {
      // Intelligence не критична — молча пропускаем ошибки
    }
    return null;
  }

  /// Сохранить образец для обучения
  static Future<bool> saveSample({
    required String imageBase64,
    required double totalSum,
    required double cashSum,
    required int ofdNotSent,
    int? resourceKeys,
    String? shopAddress,
    String? employeeName,
    Map<String, Map<String, double>>? fieldRegions,
  }) async {
    try {
      final body = <String, dynamic>{
        'imageBase64': imageBase64,
        'correctData': {
          'totalSum': totalSum,
          'cashSum': cashSum,
          'ofdNotSent': ofdNotSent,
          'resourceKeys': resourceKeys,
        },
        'shopAddress': shopAddress,
        'shopId': shopAddress,
        'employeeName': employeeName,
      };
      if (fieldRegions != null) {
        body['fieldRegions'] = fieldRegions;
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/training-samples'),
        headers: ApiConstants.headersWithApiKey,
        body: jsonEncode(body),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

}
