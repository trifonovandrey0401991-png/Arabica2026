import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../constants/api_constants.dart';
import '../utils/logger.dart';

// Условный импорт: по умолчанию stub, на веб - dart:html
import 'html_stub.dart' as html if (dart.library.html) 'dart:html';

// http и dart:convert оставлены для multipart загрузки фото и веб-специфичных XMLHttpRequest

/// Сжатие изображения в isolate (top-level для compute)
List<int> _compressImageIsolate(List<int> bytes) {
  try {
    final image = img.decodeImage(Uint8List.fromList(bytes));
    if (image == null) return bytes;

    const maxDimension = 1280;
    img.Image result;

    if (image.width > maxDimension || image.height > maxDimension) {
      if (image.width > image.height) {
        result = img.copyResize(image, width: maxDimension);
      } else {
        result = img.copyResize(image, height: maxDimension);
      }
    } else {
      result = image;
    }

    return img.encodeJpg(result, quality: 75);
  } catch (e) {
    return bytes;
  }
}

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

      final originalSize = bytes.length;
      Logger.debug('📤 Начинаем загрузку фото на сервер: $fileName');
      Logger.debug('📦 Размер оригинала: ${originalSize} байт (${(originalSize / 1024).toStringAsFixed(2)} KB)');

      // Сжатие фото если больше 500 KB (resize 1280px + JPEG quality 75%)
      if (originalSize > 512 * 1024) {
        try {
          if (kIsWeb) {
            // На web isolate недоступен — сжимаем в основном потоке
            bytes = _compressImageIsolate(bytes);
          } else {
            bytes = await compute(_compressImageIsolate, bytes);
          }
          final saved = originalSize - bytes.length;
          Logger.debug('📦 После сжатия: ${bytes.length} байт (сэкономлено ${(saved / 1024).toStringAsFixed(0)} KB)');
        } catch (e) {
          Logger.debug('⚠️ Сжатие не удалось, загружаем оригинал: $e');
        }
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

      // Добавляем заголовки авторизации
      if (ApiConstants.apiKey != null && ApiConstants.apiKey!.isNotEmpty) {
        request.headers['X-API-Key'] = ApiConstants.apiKey!;
      }
      if (ApiConstants.sessionToken != null && ApiConstants.sessionToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${ApiConstants.sessionToken}';
      }

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

  /// Загрузить несколько фото пакетами (по [batchSize] одновременно).
  /// Не перегружает сеть — хоть 100 фото загрузятся надёжно.
  /// [photoTasks] — карта {индекс: [photoPath, fileName]}
  static Future<Map<int, String?>> uploadInBatches(
    Map<int, List<String>> photoTasks, {
    int batchSize = 3,
  }) async {
    final results = <int, String?>{};
    if (photoTasks.isEmpty) return results;

    final entries = photoTasks.entries.toList();
    final totalBatches = (entries.length + batchSize - 1) ~/ batchSize;

    Logger.debug('📤 Загрузка ${entries.length} фото пакетами по $batchSize (всего $totalBatches пакетов)');

    for (var batchNum = 0; batchNum < totalBatches; batchNum++) {
      final start = batchNum * batchSize;
      final end = start + batchSize > entries.length ? entries.length : start + batchSize;
      final batch = entries.sublist(start, end);

      Logger.debug('📦 Пакет ${batchNum + 1}/$totalBatches: загрузка ${batch.length} фото...');

      final batchResults = await Future.wait(
        batch.map((e) => uploadPhoto(e.value[0], e.value[1])
            .catchError((error) { Logger.error('Ошибка загрузки фото ${e.key}', error); return null; })),
      );

      for (var j = 0; j < batch.length; j++) {
        results[batch[j].key] = batchResults[j];
      }

      final uploaded = results.values.where((v) => v != null).length;
      final failed = results.values.where((v) => v == null).length;
      Logger.debug('📊 Прогресс: $uploaded загружено, $failed ошибок из ${results.length}/${entries.length}');
    }

    Logger.debug('✅ Все пакеты обработаны: ${results.values.where((v) => v != null).length}/${entries.length} успешно');
    return results;
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
