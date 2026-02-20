import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';

/// Результат распознавания числа с фото счётчика
class OcrResult {
  final int? number;
  final double confidence;
  final String rawText;
  final bool success;
  final String? error;
  final Map<String, dynamic>? intelligence;

  OcrResult({
    this.number,
    this.confidence = 0.0,
    this.rawText = '',
    this.success = false,
    this.error,
    this.intelligence,
  });

  /// Ожидаемый диапазон из intelligence
  String? get expectedRangeText {
    if (intelligence == null) return null;
    final next = intelligence!['expectedNext'];
    if (next is Map && next['min'] != null && next['max'] != null) {
      return '${next['min']} — ${next['max']}';
    }
    return null;
  }

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    return OcrResult(
      number: json['number'],
      confidence: (json['confidence'] ?? 0).toDouble(),
      rawText: json['rawText'] ?? '',
      success: json['success'] ?? false,
      error: json['error'],
      intelligence: json['intelligence'] as Map<String, dynamic>?,
    );
  }
}

/// Сервис для распознавания чисел со счётчиков кофемашин (Tesseract OCR)
class CoffeeMachineOcrService {
  static const String _baseUrl = '${ApiConstants.serverUrl}/api/coffee-machine';

  /// Распознать число с фото счётчика
  ///
  /// [imageBase64] - фото в base64
  /// [region] - область обрезки (относительные координаты 0.0-1.0)
  /// [preset] - пресет предобработки: standard, invert_lcd, standard_resize
  /// [machineName] - название машины (для поиска обученного region)
  static Future<OcrResult> recognizeNumber({
    required String imageBase64,
    Map<String, double>? region,
    String? preset,
    String? machineName,
  }) async {
    try {
      final body = <String, dynamic>{
        'imageBase64': imageBase64,
      };
      if (region != null) {
        body['region'] = region;
      }
      if (preset != null) {
        body['preset'] = preset;
      }
      if (machineName != null) {
        body['machineName'] = machineName;
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/ocr'),
        headers: ApiConstants.headersWithApiKey,
        body: jsonEncode(body),
      ).timeout(ApiConstants.longTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return OcrResult.fromJson(data);
      } else {
        return OcrResult(
          success: false,
          error: 'Ошибка сервера: ${response.statusCode}',
        );
      }
    } catch (e) {
      return OcrResult(
        success: false,
        error: 'Ошибка подключения: $e',
      );
    }
  }
}
