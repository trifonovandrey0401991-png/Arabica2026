/// Тип блока контента
enum ContentBlockType {
  text,
  image,
}

/// Блок контента статьи (текст или изображение)
class ContentBlock {
  final String id;
  final ContentBlockType type;
  final String content; // Для text - текст, для image - URL изображения
  final String? caption; // Подпись к изображению (опционально)

  ContentBlock({
    required this.id,
    required this.type,
    required this.content,
    this.caption,
  });

  /// Создать текстовый блок
  factory ContentBlock.text(String content) {
    return ContentBlock(
      id: 'block_${DateTime.now().millisecondsSinceEpoch}',
      type: ContentBlockType.text,
      content: content,
    );
  }

  /// Создать блок изображения
  factory ContentBlock.image(String imageUrl, {String? caption}) {
    return ContentBlock(
      id: 'block_${DateTime.now().millisecondsSinceEpoch}',
      type: ContentBlockType.image,
      content: imageUrl,
      caption: caption,
    );
  }

  /// Создать из JSON
  factory ContentBlock.fromJson(Map<String, dynamic> json) {
    return ContentBlock(
      id: json['id'] ?? 'block_${DateTime.now().millisecondsSinceEpoch}',
      type: json['type'] == 'image' ? ContentBlockType.image : ContentBlockType.text,
      content: json['content'] ?? '',
      caption: json['caption'] as String?,
    );
  }

  /// Преобразовать в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type == ContentBlockType.image ? 'image' : 'text',
      'content': content,
      if (caption != null && caption!.isNotEmpty) 'caption': caption,
    };
  }

  /// Копировать с изменениями
  ContentBlock copyWith({
    String? id,
    ContentBlockType? type,
    String? content,
    String? caption,
  }) {
    return ContentBlock(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      caption: caption ?? this.caption,
    );
  }
}
