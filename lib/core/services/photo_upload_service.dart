import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../utils/logger.dart';

// Условный импорт: по умолчанию stub, на веб - dart:html
import 'html_stub.dart' as html if (dart.library.html) 'dart:html';

// http и dart:convert оставлены для multipart загрузки фото и веб-специфичных XMLHttpRequest

/// Сервис для работы с фото пересменки (сохранение на сервере)
class PhotoUploadService {

  /// Загрузить фото на сервер
  static Future<String?> uploadPhoto(String photoPath, String fileName) async {
    try {
      List<int> bytes;
      
      // Проверяем, является ли это base64 data URL (для веб)
      if (photoPath.startsWith('data:image/')) {
        final base64Index = photoPath.indexOf(',');
        if (base64Index != -1) {
          final base64Image = photoPath.substring(base64Index + 1);
          bytes = base64Decode(base64Image);
        } else {
          Logger.debug('⚠️ Неверный формат data URL');
          return null;
        }
      } else {
        try {
          final file = File(photoPath);
          if (!await file.exists()) {
            Logger.debug('⚠️ Файл не найден: $photoPath');
            return null;
          }
          bytes = await file.readAsBytes();
        } catch (e) {
          Logger.error('⚠️ Ошибка чтения файла', e);
          return null;
        }
      }

      Logger.debug('📤 Начинаем загрузку фото на сервер: $fileName');
      Logger.debug('📦 Размер файла: ${bytes.length} байт (${(bytes.length / 1024).toStringAsFixed(2)} KB)');
      if (bytes.length > 1000000) {
        final sizeMB = (bytes.length / 1024 / 1024).toStringAsFixed(2);
        Logger.debug('⚠️ Внимание: Размер файла очень большой ($sizeMB MB)');
      }

      Logger.debug('🔗 URL загрузки: ${ApiConstants.serverUrl}/upload-photo');
      Logger.debug('📋 Платформа: ${kIsWeb ? "Web" : "Mobile"}');

      // Для веб используем нативный fetch API, для мобильных - MultipartRequest
      if (kIsWeb) {
        return await _uploadPhotoWeb(bytes, fileName);
      } else {
        return await _uploadPhotoMobile(bytes, fileName);
      }
    } catch (e) {
      Logger.error('❌ Критическая ошибка загрузки фото', e);
      return null;
    }
  }

  /// Загрузка фото на веб-платформе через XMLHttpRequest
  static Future<String?> _uploadPhotoWeb(List<int> bytes, String fileName) async {
    try {
      // Используем XMLHttpRequest для веб (более надежно, чем fetch)
      final formData = html.FormData();

      // Создаем Blob из bytes
      final blob = html.Blob(bytes, 'image/jpeg');
      formData.appendBlob('file', blob, fileName);
      formData.append('fileName', fileName);

      Logger.debug('📤 Отправляем запрос через XMLHttpRequest...');

      final completer = Completer<String?>();
      final xhr = html.HttpRequest();

      xhr.open('POST', '${ApiConstants.serverUrl}/upload-photo', true);
      
      xhr.onLoad.listen((e) {
        final status = xhr.status ?? 0;
        Logger.debug('📥 Получен ответ: статус $status');

        if (status >= 200 && status < 300) {
          try {
            final result = jsonDecode(xhr.responseText ?? '') as Map<String, dynamic>;
            if (result['success'] == true) {
              final photoUrl = result['filePath'] as String;
              Logger.debug('✅ Фото успешно загружено на сервер: $photoUrl');
              completer.complete(photoUrl);
            } else {
              Logger.debug('⚠️ Ошибка от сервера: ${result['error']}');
              completer.complete(null);
            }
          } catch (e) {
            Logger.error('⚠️ Ошибка парсинга ответа', e);
            completer.complete(null);
          }
        } else {
          final responseText = xhr.responseText ?? '';
          Logger.debug('⚠️ Ошибка HTTP: $status');
          Logger.debug('⚠️ Тело ответа: ${responseText.length > 500 ? responseText.substring(0, 500) : responseText}');
          completer.complete(null);
        }
      });

      xhr.onError.listen((e) {
        Logger.debug('❌ Ошибка XMLHttpRequest: ${xhr.statusText ?? "Unknown error"}');
        completer.complete(null);
      });
      
      // Отправляем запрос
      xhr.send(formData);
      
      // Таймаут
      return completer.future.timeout(
        ApiConstants.uploadTimeout,
        onTimeout: () {
          Logger.debug('⏱️ Таймаут при загрузке фото (120 секунд)');
          xhr.abort();
          return null;
        },
      );
    } catch (e, stackTrace) {
      Logger.error('❌ Ошибка загрузки фото (веб)', e);
      Logger.debug('❌ Stack trace: $stackTrace');
      return null;
    }
  }

  /// Загрузка фото на мобильных платформах через MultipartRequest
  static Future<String?> _uploadPhotoMobile(List<int> bytes, String fileName) async {
    try {
      final uri = Uri.parse('${ApiConstants.serverUrl}/upload-photo');
      
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );
      request.fields['fileName'] = fileName;

      Logger.debug('📤 Отправляем multipart/form-data запрос...');

      final streamedResponse = await request.send().timeout(
        ApiConstants.uploadTimeout,
        onTimeout: () {
          Logger.debug('⏱️ Таймаут при загрузке фото (120 секунд)');
          throw Exception('Таймаут при загрузке фото');
        },
      );

      final response = await http.Response.fromStream(streamedResponse);
      Logger.debug('📥 Получен ответ: статус ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final photoUrl = result['filePath'] as String;
          Logger.debug('✅ Фото успешно загружено на сервер: $photoUrl');
          return photoUrl;
        } else {
          Logger.debug('⚠️ Ошибка от сервера: ${result['error']}');
          return null;
        }
      } else {
        Logger.debug('⚠️ Ошибка HTTP: ${response.statusCode}');
        Logger.debug('⚠️ Тело ответа: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
        return null;
      }
    } catch (e, stackTrace) {
      Logger.error('❌ Ошибка загрузки фото (мобильный)', e);
      Logger.debug('❌ Stack trace: $stackTrace');
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
    return '${ApiConstants.serverUrl}/photos/$filePath';
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
        Uri.parse('${ApiConstants.serverUrl}/delete-photo'),
        headers: ApiConstants.jsonHeaders,
        body: jsonEncode({
          'fileName': actualFileName,
        }),
      ).timeout(
        ApiConstants.shortTimeout,
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
      Logger.error('❌ Ошибка удаления фото', e);
      return false;
    }
  }
}
