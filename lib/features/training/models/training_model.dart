import '../../../core/utils/logger.dart';
import '../services/training_article_service.dart';

/// Модель статьи обучения
class TrainingArticle {
  final String id;
  final String group;
  final String title;
  final String url;

  TrainingArticle({
    required this.id,
    required this.group,
    required this.title,
    required this.url,
  });

  /// Создать TrainingArticle из JSON
  factory TrainingArticle.fromJson(Map<String, dynamic> json) {
    return TrainingArticle(
      id: json['id'] ?? '',
      group: json['group'] ?? '',
      title: json['title'] ?? '',
      url: json['url'] ?? '',
    );
  }

  /// Преобразовать TrainingArticle в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group': group,
      'title': title,
      'url': url,
    };
  }

  /// Загрузить статьи обучения с сервера
  static Future<List<TrainingArticle>> loadArticles() async {
    try {
      return await TrainingArticleService.getArticles();
    } catch (e) {
      Logger.error('Ошибка загрузки статей обучения', e);
      return [];
    }
  }
}
