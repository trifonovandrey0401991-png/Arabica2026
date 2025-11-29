import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// Для веб-платформы используем dart:html
import 'dart:html' as html if (dart.library.io) 'dart:io';

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

      print('🔗 URL загрузки: $serverUrl/upload-photo');
      
      try {
        final uri = Uri.parse('$serverUrl/upload-photo');
        print('🌐 Отправляем POST запрос на: $uri');
        print('📋 Платформа: ${kIsWeb ? "Web" : "Mobile"}');
        
        final requestBody = jsonEncode({
          'fileName': fileName,
          'fileData': base64Image,
        });
        
        print('📦 Размер JSON тела: ${requestBody.length} символов');
        
        http.Response response;
        
        // Для веб-платформы используем XMLHttpRequest напрямую
        if (kIsWeb) {
          print('🌐 Используем XMLHttpRequest для веб-платформы');
          try {
            final xhr = html.HttpRequest();
            final completer = Completer<http.Response>();
            
            xhr.open('POST', uri.toString(), async: true);
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.setRequestHeader('Accept', 'application/json');
            
            xhr.onLoad.listen((e) {
              final status = xhr.status ?? 0;
              if (status >= 200 && status < 300) {
                final headers = <String, String>{};
                xhr.responseHeaders.forEach((key, value) {
                  headers[key] = value;
                });
                completer.complete(http.Response(
                  xhr.responseText ?? '',
                  status,
                  headers: headers,
                ));
              } else {
                completer.completeError(Exception('HTTP $status: ${xhr.statusText}'));
              }
            });
            
            xhr.onError.listen((e) {
              completer.completeError(Exception('Network error: ${xhr.statusText}'));
            });
            
            xhr.send(requestBody);
            
            response = await completer.future.timeout(
              const Duration(seconds: 120),
              onTimeout: () {
                xhr.abort();
                throw Exception('Таймаут при загрузке фото (120 секунд)');
              },
            );
            
            print('📥 Получен ответ через XMLHttpRequest: статус ${response.statusCode}');
          } catch (e) {
            print('⚠️ XMLHttpRequest не сработал, пробуем http.post: $e');
            // Fallback на обычный http.post
            response = await http.post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: requestBody,
            ).timeout(
              const Duration(seconds: 120),
              onTimeout: () {
                print('⏱️ Таймаут при загрузке фото (120 секунд)');
                throw Exception('Таймаут при загрузке фото (120 секунд)');
              },
            );
          }
        } else {
          // Для мобильных платформ используем обычный http.post
          response = await http.post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: requestBody,
          ).timeout(
            const Duration(seconds: 120),
            onTimeout: () {
              print('⏱️ Таймаут при загрузке фото (120 секунд)');
              throw Exception('Таймаут при загрузке фото (120 секунд)');
            },
          );
        }

        print('📥 Получен ответ: статус ${response.statusCode}');
        print('📥 Размер ответа: ${response.body.length} символов');

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
            print('⚠️ Тело ответа: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
            return null;
          }
        } else {
          print('⚠️ Ошибка HTTP: ${response.statusCode}');
          print('⚠️ Тело ответа: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
          return null;
        }
      } catch (e, stackTrace) {
        print('❌ Ошибка загрузки фото: $e');
        print('❌ Stack trace: $stackTrace');
        return null;
      }
    } catch (e) {
      print('❌ Критическая ошибка загрузки фото: $e');
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
