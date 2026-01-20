import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/training_model.dart';
import '../models/content_block.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class TrainingArticleService {
  static const String baseEndpoint = ApiConstants.trainingArticlesEndpoint;

  /// Получить все статьи
  static Future<List<TrainingArticle>> getArticles() async {
    Logger.debug('📥 Загрузка статей обучения с сервера...');

    return await BaseHttpService.getList<TrainingArticle>(
      endpoint: baseEndpoint,
      fromJson: (json) => TrainingArticle.fromJson(json),
      listKey: 'articles',
    );
  }

  /// Создать новую статью
  static Future<TrainingArticle?> createArticle({
    required String group,
    required String title,
    required String content,
    String? url,
    List<ContentBlock>? contentBlocks,
  }) async {
    Logger.debug('📤 Создание статьи обучения: $title');

    final body = <String, dynamic>{
      'group': group,
      'title': title,
      'content': content,
    };
    if (url != null && url.isNotEmpty) {
      body['url'] = url;
    }
    if (contentBlocks != null && contentBlocks.isNotEmpty) {
      body['contentBlocks'] = contentBlocks.map((b) => b.toJson()).toList();
    }

    return await BaseHttpService.post<TrainingArticle>(
      endpoint: baseEndpoint,
      body: body,
      fromJson: (json) => TrainingArticle.fromJson(json),
      itemKey: 'article',
    );
  }

  /// Обновить статью
  static Future<TrainingArticle?> updateArticle({
    required String id,
    String? group,
    String? title,
    String? content,
    String? url,
    List<ContentBlock>? contentBlocks,
  }) async {
    Logger.debug('📤 Обновление статьи обучения: $id');

    final body = <String, dynamic>{};
    if (group != null) body['group'] = group;
    if (title != null) body['title'] = title;
    if (content != null) body['content'] = content;
    if (url != null) body['url'] = url;
    if (contentBlocks != null) {
      body['contentBlocks'] = contentBlocks.map((b) => b.toJson()).toList();
    }

    return await BaseHttpService.put<TrainingArticle>(
      endpoint: '$baseEndpoint/$id',
      body: body,
      fromJson: (json) => TrainingArticle.fromJson(json),
      itemKey: 'article',
    );
  }

  /// Удалить статью
  static Future<bool> deleteArticle(String id) async {
    Logger.debug('📤 Удаление статьи обучения: $id');

    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/$id',
    );
  }

  /// Загрузить изображение для статьи
  static Future<String?> uploadImage(File imageFile) async {
    Logger.debug('📤 Загрузка изображения для статьи обучения...');

    try {
      final uri = Uri.parse('${ApiConstants.serverBaseUrl}$baseEndpoint/upload-image');
      final request = http.MultipartRequest('POST', uri);

      request.files.add(await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['imageUrl'] != null) {
          Logger.debug('✅ Изображение загружено: ${data['imageUrl']}');
          return data['imageUrl'];
        }
      }

      Logger.error('Ошибка загрузки изображения: ${response.body}');
      return null;
    } catch (e) {
      Logger.error('Ошибка загрузки изображения', e);
      return null;
    }
  }

  /// Удалить изображение
  static Future<bool> deleteImage(String filename) async {
    Logger.debug('📤 Удаление изображения: $filename');

    return await BaseHttpService.delete(
      endpoint: '$baseEndpoint/delete-image/$filename',
    );
  }
}
