import 'package:intl/intl.dart';

enum MessageType { text, image, video, voice, emoji }

class MessengerMessage {
  final String id;
  final String conversationId;
  final String senderPhone;
  final String? senderName;
  final MessageType type;
  final String? content;
  final String? mediaUrl;
  final int? voiceDuration;
  final String? replyToId;
  final Map<String, List<String>> reactions;
  final bool isDeleted;
  final DateTime createdAt;

  MessengerMessage({
    required this.id,
    required this.conversationId,
    required this.senderPhone,
    this.senderName,
    this.type = MessageType.text,
    this.content,
    this.mediaUrl,
    this.voiceDuration,
    this.replyToId,
    this.reactions = const {},
    this.isDeleted = false,
    required this.createdAt,
  });

  factory MessengerMessage.fromJson(Map<String, dynamic> json) {
    // Парсим reactions из JSONB
    Map<String, List<String>> reactions = {};
    if (json['reactions'] != null && json['reactions'] is Map) {
      final raw = json['reactions'] as Map<String, dynamic>;
      for (final entry in raw.entries) {
        if (entry.value is List) {
          reactions[entry.key] = (entry.value as List).map((e) => e.toString()).toList();
        }
      }
    }

    return MessengerMessage(
      id: json['id'] as String,
      conversationId: (json['conversation_id'] as String?) ?? '',
      senderPhone: json['sender_phone'] as String,
      senderName: json['sender_name'] as String?,
      type: _parseType(json['type'] as String?),
      content: json['content'] as String?,
      mediaUrl: json['media_url'] as String?,
      voiceDuration: (json['voice_duration'] as num?)?.toInt(),
      replyToId: json['reply_to_id'] as String?,
      reactions: reactions,
      isDeleted: json['is_deleted'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  static MessageType _parseType(String? type) {
    switch (type) {
      case 'image':
        return MessageType.image;
      case 'video':
        return MessageType.video;
      case 'voice':
        return MessageType.voice;
      case 'emoji':
        return MessageType.emoji;
      default:
        return MessageType.text;
    }
  }

  String get typeString {
    switch (type) {
      case MessageType.image:
        return 'image';
      case MessageType.video:
        return 'video';
      case MessageType.voice:
        return 'voice';
      case MessageType.emoji:
        return 'emoji';
      case MessageType.text:
        return 'text';
    }
  }

  /// Превью сообщения для списка чатов
  String get preview {
    if (isDeleted) return 'Сообщение удалено';
    switch (type) {
      case MessageType.text:
        return content ?? '';
      case MessageType.image:
        return '📷 Фото';
      case MessageType.video:
        return '🎬 Видео';
      case MessageType.voice:
        final dur = voiceDuration ?? 0;
        return '🎤 ${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}';
      case MessageType.emoji:
        return content ?? '😀';
    }
  }

  /// Форматированное время
  String get formattedTime {
    return DateFormat('HH:mm').format(createdAt.toLocal());
  }

  /// Форматированная дата
  String get formattedDate {
    final now = DateTime.now();
    final local = createdAt.toLocal();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return 'Сегодня';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (local.year == yesterday.year && local.month == yesterday.month && local.day == yesterday.day) {
      return 'Вчера';
    }
    return DateFormat('dd.MM.yyyy').format(local);
  }

  bool get isMine => false; // будет вычисляться при отображении
}
