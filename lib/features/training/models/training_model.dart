import '../../../core/utils/logger.dart';
import '../services/training_article_service.dart';
import 'content_block.dart';

/// Модель статьи обучения
class TrainingArticle {
  final String id;
  final String group;
  final String title;
  final String content;  // Контент статьи (для обратной совместимости - простой текст)
  final String? url;     // Опциональная внешняя ссылка (для обратной совместимости)
  final List<ContentBlock> contentBlocks;  // Блоки контента (текст + изображения)
  final String visibility;  // Видимость статьи: 'all' (все) или 'managers' (только заведующие)

  TrainingArticle({
    required this.id,
    required this.group,
    required this.title,
    this.content = '',
    this.url,
    this.contentBlocks = const [],
    this.visibility = 'all',  // По умолчанию видно всем
  });

  /// Проверить, есть ли контент у статьи (простой текст или блоки)
  bool get hasContent => content.isNotEmpty || contentBlocks.isNotEmpty;

  /// Проверить, есть ли блоки контента
  bool get hasBlocks => contentBlocks.isNotEmpty;

  /// Проверить, есть ли внешняя ссылка
  bool get hasUrl => url != null && url!.isNotEmpty;

  /// Создать TrainingArticle из JSON
  factory TrainingArticle.fromJson(Map<String, dynamic> json) {
    // Парсим блоки контента если есть
    List<ContentBlock> blocks = [];
    if (json['contentBlocks'] != null && json['contentBlocks'] is List) {
      Logger.debug('📦 Парсинг contentBlocks для статьи ${json['id']}: ${(json['contentBlocks'] as List).length} блоков');
      blocks = (json['contentBlocks'] as List)
          .map((b) => ContentBlock.fromJson(b as Map<String, dynamic>))
          .toList();
    } else {
      Logger.debug('📦 Нет contentBlocks для статьи ${json['id']}');
    }

    return TrainingArticle(
      id: json['id'] ?? '',
      group: json['group'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      url: json['url'] as String?,
      contentBlocks: blocks,
      visibility: json['visibility'] as String? ?? 'all',
    );
  }

  /// Преобразовать TrainingArticle в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group': group,
      'title': title,
      'content': content,
      if (url != null && url!.isNotEmpty) 'url': url,
      if (contentBlocks.isNotEmpty)
        'contentBlocks': contentBlocks.map((b) => b.toJson()).toList(),
      'visibility': visibility,
    };
  }

  /// Копировать с изменениями
  TrainingArticle copyWith({
    String? id,
    String? group,
    String? title,
    String? content,
    String? url,
    List<ContentBlock>? contentBlocks,
    String? visibility,
  }) {
    return TrainingArticle(
      id: id ?? this.id,
      group: group ?? this.group,
      title: title ?? this.title,
      content: content ?? this.content,
      url: url ?? this.url,
      contentBlocks: contentBlocks ?? this.contentBlocks,
      visibility: visibility ?? this.visibility,
    );
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
