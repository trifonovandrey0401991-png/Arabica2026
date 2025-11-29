import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Сервис для работы с Google Drive через Google Apps Script
class GoogleDriveService {
  // URL вашего Google Apps Script (нужно будет обновить после создания скрипта)
  static const String scriptUrl = 'https://script.google.com/macros/s/AKfycbzOQoFZbPc_r2n4525e5_G6zL3q5R02mJvKHMY_xCILTH0uSYshSlyXiIRaROs3P03I/exec';

  /// Загрузить фото в Google Drive
  static Future<String?> uploadPhoto(String photoPath, String fileName) async {
    try {
      String base64Image;
      
      // Проверяем, является ли это base64 data URL (для веб)
      if (photoPath.startsWith('data:image/')) {
        // Извлекаем base64 часть из data URL
        final base64Index = photoPath.indexOf(',');
        if (base64Index != -1) {
          base64Image = photoPath.substring(base64Index + 1);
        } else {
          print('⚠️ Неверный формат data URL');
          return null;
        }
      } else {
        // Для мобильных платформ - читаем из файла
        try {
          final file = File(photoPath);
          if (!await file.exists()) {
            print('⚠️ Файл не найден: $photoPath');
            return null;
          }
          final bytes = await file.readAsBytes();
          base64Image = base64Encode(bytes);
        } catch (e) {
          print('⚠️ Ошибка чтения файла: $e');
          return null;
        }
      }

      // Добавляем таймаут для запроса (30 секунд)
      final response = await http.post(
        Uri.parse(scriptUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'uploadPhoto',
          'fileName': fileName,
          'fileData': base64Image,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Таймаут при загрузке фото (30 секунд)');
        },
      );

      if (response.statusCode == 200) {
        try {
          final result = jsonDecode(response.body);
          if (result['success'] == true) {
            return result['fileId'] as String?;
          } else {
            print('⚠️ Ошибка от сервера: ${result['error']}');
            return null;
          }
        } catch (e) {
          print('⚠️ Ошибка парсинга ответа: $e');
          return null;
        }
      } else {
        print('⚠️ Ошибка HTTP: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Ошибка загрузки фото: $e');
      // Возвращаем null вместо проброса ошибки, чтобы не блокировать сохранение отчета
      return null;
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

