import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../../../core/constants/api_constants.dart';
import '../models/z_report_sample_model.dart';

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
  static Future<ZReportParseResult> parseZReportFromBytes(Uint8List imageBytes) async {
    final compressedBase64 = await compressImage(imageBytes);
    return parseZReport(compressedBase64);
  }

  /// Распознать Z-отчёт по фото
  static Future<ZReportParseResult> parseZReport(String imageBase64) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/parse'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'imageBase64': imageBase64}),
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

  /// Валидация данных Z-отчёта
  static Future<ZReportValidationResult> validateZReport({
    required String imageBase64,
    required double totalSum,
    required double cashSum,
    required int ofdNotSent,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/validate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBase64': imageBase64,
          'userInput': {
            'totalSum': totalSum,
            'cashSum': cashSum,
            'ofdNotSent': ofdNotSent,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ZReportValidationResult.fromJson(data);
      } else {
        return ZReportValidationResult(
          success: false,
          error: 'Ошибка сервера: ${response.statusCode}',
        );
      }
    } catch (e) {
      return ZReportValidationResult(
        success: false,
        error: 'Ошибка подключения: $e',
      );
    }
  }

  /// Сохранить образец для обучения
  static Future<bool> saveSample({
    required String imageBase64,
    required double totalSum,
    required double cashSum,
    required int ofdNotSent,
    String? shopAddress,
    String? employeeName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/samples'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBase64': imageBase64,
          'correctData': {
            'totalSum': totalSum,
            'cashSum': cashSum,
            'ofdNotSent': ofdNotSent,
          },
          'shopAddress': shopAddress,
          'employeeName': employeeName,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Получить список образцов
  static Future<List<ZReportSample>> getSamples() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/samples'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final samples = (data['samples'] as List)
            .map((e) => ZReportSample.fromJson(e))
            .toList();
        return samples;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Удалить образец
  static Future<bool> deleteSample(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/samples/$id'),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
