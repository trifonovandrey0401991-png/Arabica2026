import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../models/z_report_template_model.dart';

/// Сервис для работы с шаблонами распознавания Z-отчётов
class ZReportTemplateService {
  /// Получить все шаблоны
  static Future<List<ZReportTemplate>> getTemplates({String? shopId}) async {
    try {
      var url = '${ApiConstants.serverUrl}/api/z-report/templates';
      if (shopId != null) {
        url += '?shopId=$shopId';
      }

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['templates'] as List?)
                ?.map((e) => ZReportTemplate.fromJson(e))
                .toList() ??
            [];
      }
      return [];
    } catch (e) {
      print('Ошибка получения шаблонов: $e');
      return [];
    }
  }

  /// Получить шаблон по ID
  static Future<ZReportTemplate?> getTemplate(String id) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/templates/$id'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ZReportTemplate.fromJson(data['template']);
      }
      return null;
    } catch (e) {
      print('Ошибка получения шаблона: $e');
      return null;
    }
  }

  /// Получить изображение шаблона
  static Future<Uint8List?> getTemplateImage(String templateId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/templates/$templateId/image'),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      print('Ошибка получения изображения шаблона: $e');
      return null;
    }
  }

  /// Получить изображение формата (region set)
  static Future<Uint8List?> getRegionSetImage(String templateId, String setId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/templates/$templateId/region-sets/$setId/image'),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      print('Ошибка получения изображения формата: $e');
      return null;
    }
  }

  /// Сохранить шаблон (создать или обновить)
  /// [regionSetImages] - карта setId -> imageBytes для изображений форматов
  static Future<bool> saveTemplate({
    required ZReportTemplate template,
    Uint8List? sampleImageBase64,
    Map<String, Uint8List>? regionSetImages,
  }) async {
    try {
      // Преобразуем изображения форматов в base64
      Map<String, String>? regionSetImagesBase64;
      if (regionSetImages != null && regionSetImages.isNotEmpty) {
        regionSetImagesBase64 = {};
        for (final entry in regionSetImages.entries) {
          regionSetImagesBase64[entry.key] = base64Encode(entry.value);
        }
      }

      final body = {
        'template': template.toJson(),
        if (sampleImageBase64 != null)
          'sampleImage': base64Encode(sampleImageBase64),
        if (regionSetImagesBase64 != null)
          'regionSetImages': regionSetImagesBase64,
      };

      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/templates'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка сохранения шаблона: $e');
      return false;
    }
  }

  /// Удалить шаблон
  static Future<bool> deleteTemplate(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/templates/$id'),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Ошибка удаления шаблона: $e');
      return false;
    }
  }

  /// Найти подходящий шаблон для магазина
  static Future<ZReportTemplate?> findTemplateForShop(String shopId) async {
    try {
      final response = await http.get(
        Uri.parse(
            '${ApiConstants.serverUrl}/api/z-report/templates/find?shopId=$shopId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['template'] != null) {
          return ZReportTemplate.fromJson(data['template']);
        }
      }
      return null;
    } catch (e) {
      print('Ошибка поиска шаблона: $e');
      return null;
    }
  }

  /// Распознать с использованием шаблона (области на изображении)
  static Future<Map<String, dynamic>> parseWithTemplate({
    required String imageBase64,
    required String templateId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/parse-with-template'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBase64': imageBase64,
          'templateId': templateId,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'success': false, 'error': 'Ошибка сервера'};
    } catch (e) {
      return {'success': false, 'error': 'Ошибка подключения: $e'};
    }
  }

  /// Обновить статистику использования шаблона
  static Future<void> updateTemplateStats({
    required String templateId,
    required bool wasSuccessful,
  }) async {
    try {
      await http.post(
        Uri.parse(
            '${ApiConstants.serverUrl}/api/z-report/templates/$templateId/stats'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'wasSuccessful': wasSuccessful}),
      );
    } catch (e) {
      print('Ошибка обновления статистики: $e');
    }
  }

  /// Результат сохранения образца для обучения
  /// Содержит информацию о выученных паттернах
  static Map<String, dynamic>? lastLearningResult;

  /// Сохранить образец для машинного обучения
  /// Возвращает true при успехе и сохраняет результат обучения в lastLearningResult
  static Future<bool> saveTrainingSample({
    required String imageBase64,
    required String rawText,
    required Map<String, dynamic> correctData,
    required Map<String, dynamic> recognizedData,
    String? shopId,
    String? templateId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/training-samples'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'imageBase64': imageBase64,
          'rawText': rawText,
          'correctData': correctData,
          'recognizedData': recognizedData,
          'shopId': shopId,
          'templateId': templateId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Сохраняем результат обучения
        lastLearningResult = data['learningResult'];
        return true;
      }
      return false;
    } catch (e) {
      print('Ошибка сохранения образца: $e');
      return false;
    }
  }

  /// Получить статистику обучения
  static Future<Map<String, dynamic>> getTrainingStats() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/z-report/training-stats'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {};
    } catch (e) {
      print('Ошибка получения статистики: $e');
      return {};
    }
  }
}
