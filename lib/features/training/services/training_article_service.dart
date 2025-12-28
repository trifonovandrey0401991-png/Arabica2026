import '../models/training_model.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';

class TrainingArticleService {
  static const String baseEndpoint = '/api/training-articles';

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
    required String url,
  }) async {
    Logger.debug('📤 Создание статьи обучения: $title');

    return await BaseHttpService.post<TrainingArticle>(
      endpoint: baseEndpoint,
      body: {
        'group': group,
        'title': title,
        'url': url,
      },
      fromJson: (json) => TrainingArticle.fromJson(json),
      itemKey: 'article',
    );
  }

  /// Обновить статью
  static Future<TrainingArticle?> updateArticle({
    required String id,
    String? group,
    String? title,
    String? url,
  }) async {
    Logger.debug('📤 Обновление статьи обучения: $id');

    final body = <String, dynamic>{};
    if (group != null) body['group'] = group;
    if (title != null) body['title'] = title;
    if (url != null) body['url'] = url;

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
}
