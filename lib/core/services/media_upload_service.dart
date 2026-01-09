import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../utils/logger.dart';

/// Тип медиа-контента
enum MediaType { image, video }

/// Сервис для загрузки медиа-файлов (фото и видео)
class MediaUploadService {
  /// Загрузить медиа-файл на сервер
  static Future<String?> uploadMedia(String filePath, {MediaType type = MediaType.image}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Logger.debug('Файл не найден: $filePath');
        return null;
      }

      final bytes = await file.readAsBytes();
      final fileName = _generateFileName(filePath, type);

      Logger.debug('📤 Загружаем ${type == MediaType.video ? "видео" : "фото"}: $fileName');
      Logger.debug('📦 Размер: ${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB');

      final uri = Uri.parse('${ApiConstants.serverUrl}/upload-media');

      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );
      request.fields['fileName'] = fileName;
      request.fields['mediaType'] = type == MediaType.video ? 'video' : 'image';

      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5), // Больше времени для видео
        onTimeout: () {
          throw Exception('Таймаут при загрузке медиа');
        },
      );

      final response = await http.Response.fromStream(streamedResponse);
      Logger.debug('📥 Ответ: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          // Сервер возвращает 'url', но может быть и 'filePath' для совместимости
          final mediaUrl = (result['url'] ?? result['filePath']) as String?;
          if (mediaUrl != null) {
            Logger.debug('✅ Медиа загружено: $mediaUrl');
            return mediaUrl;
          }
          Logger.debug('⚠️ URL не получен от сервера');
          return null;
        } else {
          Logger.debug('⚠️ Ошибка от сервера: ${result['error']}');
          return null;
        }
      } else {
        Logger.debug('⚠️ Ошибка HTTP: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      Logger.error('❌ Ошибка загрузки медиа', e);
      return null;
    }
  }

  /// Генерация имени файла
  static String _generateFileName(String filePath, MediaType type) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = filePath.split('.').last.toLowerCase();
    final prefix = type == MediaType.video ? 'video' : 'photo';
    return '${prefix}_$timestamp.$extension';
  }

  /// Получить полный URL медиа
  static String getMediaUrl(String filePath) {
    if (filePath.startsWith('http://') || filePath.startsWith('https://')) {
      return filePath;
    }
    return '${ApiConstants.serverUrl}/media/$filePath';
  }

  /// Проверить, является ли файл видео
  static bool isVideo(String? url) {
    if (url == null) return false;
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
           lower.endsWith('.mov') ||
           lower.endsWith('.avi') ||
           lower.endsWith('.webm') ||
           lower.contains('/videos/');
  }

  /// Загрузить фото для задачи
  static Future<String?> uploadTaskPhoto(File file) async {
    return uploadMedia(file.path, type: MediaType.image);
  }
}
