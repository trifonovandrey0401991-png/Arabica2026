import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Сервис для работы с Google Drive через Google Apps Script
class GoogleDriveService {
  // URL вашего Google Apps Script (нужно будет обновить после создания скрипта)
  static const String scriptUrl = 'https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec';

  /// Загрузить фото в Google Drive
  static Future<String?> uploadPhoto(String photoPath, String fileName) async {
    try {
      final file = File(photoPath);
      if (!await file.exists()) {
        throw Exception('Файл не найден: $photoPath');
      }

      final bytes = await file.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'uploadPhoto',
          'fileName': fileName,
          'fileData': base64Image,
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return result['fileId'] as String?;
        } else {
          throw Exception(result['error'] ?? 'Ошибка загрузки фото');
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Ошибка загрузки фото: $e');
      rethrow;
    }
  }

  /// Получить URL фото по ID
  static String getPhotoUrl(String fileId) {
    return 'https://drive.google.com/uc?export=view&id=$fileId';
  }

  /// Удалить фото из Google Drive
  static Future<bool> deletePhoto(String fileId) async {
    try {
      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'deletePhoto',
          'fileId': fileId,
        }),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        return result['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Ошибка удаления фото: $e');
      return false;
    }
  }
}

