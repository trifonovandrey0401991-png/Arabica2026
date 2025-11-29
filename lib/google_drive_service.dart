import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Сервис для работы с фото пересменки (сохранение на сервере)
class GoogleDriveService {
  // URL сервера для загрузки фото
  static const String serverUrl = 'https://arabica26.ru';

  /// Загрузить фото на сервер
  static Future<String?> uploadPhoto(String photoPath, String fileName) async {
    try {
      String base64Image;
      
      // Проверяем, является ли это base64 data URL (для веб)
      if (photoPath.startsWith('data:image/')) {
        final base64Index = photoPath.indexOf(',');
        if (base64Index != -1) {
          base64Image = photoPath.substring(base64Index + 1);
        } else {
          print('⚠️ Неверный формат data URL');
          return null;
        }
      } else {
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

      print('📤 Начинаем загрузку фото на сервер: $fileName');
      print('📏 Размер base64 данных: ${base64Image.length} символов');
      if (base64Image.length > 1000000) {
        final sizeMB = (base64Image.length / 1024 / 1024).toStringAsFixed(2);
        print('⚠️ Внимание: Размер данных очень большой ($sizeMB MB)');
      }

      final response = await http.post(
        Uri.parse('$serverUrl/upload-photo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
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
            final photoUrl = result['filePath'] as String;
            print('✅ Фото успешно загружено на сервер: $photoUrl');
            return photoUrl; // Возвращаем URL фото
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
        print('⚠️ Тело ответа: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
        return null;
      }
    } catch (e) {
      print('❌ Ошибка загрузки фото: $e');
      return null;
    }
  }

  /// Получить URL фото (теперь это просто URL с сервера)
  static String getPhotoUrl(String filePath) {
    // Если это уже полный URL, возвращаем как есть
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      return filePath;
    }
    // Иначе добавляем базовый URL сервера
    return '$serverUrl/photos/$filePath';
  }

  /// Удалить фото с сервера
  static Future<bool> deletePhoto(String fileName) async {
    try {
      // Извлекаем имя файла из URL, если это URL
      String actualFileName = fileName;
      if (fileName.contains('/')) {
        final parts = fileName.split('/');
        actualFileName = parts.isNotEmpty ? parts.last : fileName;
      }

      final response = await http.post(
        Uri.parse('$serverUrl/delete-photo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fileName': actualFileName,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Таймаут при удалении фото');
        },
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
