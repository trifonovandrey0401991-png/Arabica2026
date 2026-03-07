import 'package:intl/intl.dart';

enum MessageType { text, image, video, voice, emoji, call, videoNote, file, poll, sticker, gif, contact }

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
  final DateTime? editedAt;
  final List<String> deliveredTo;
  final String? fileName;
  final int? fileSize;
  final String? forwardedFromId;
  final String? forwardedFromName;
  final bool isPinned;
  final DateTime? pinnedAt;
  final String? pinnedBy;
  final String? mediaGroupId;

  // Client-only fields (not from server)
  final bool isPending;
  final bool isFailed;

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
    this.editedAt,
    this.deliveredTo = const [],
    this.fileName,
    this.fileSize,
    this.forwardedFromId,
    this.forwardedFromName,
    this.isPinned = false,
    this.pinnedAt,
    this.pinnedBy,
    this.mediaGroupId,
    this.isPending = false,
    this.isFailed = false,
  });

  bool get isEdited => editedAt != null;
  bool get isForwarded => forwardedFromId != null;

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
      id: (json['id'] as String?) ?? '',
      conversationId: (json['conversation_id'] as String?) ?? '',
      senderPhone: (json['sender_phone'] as String?) ?? '',
      senderName: json['sender_name'] as String?,
      type: _parseType(json['type'] as String?),
      content: json['content'] as String?,
      mediaUrl: json['media_url'] as String?,
      voiceDuration: (json['voice_duration'] as num?)?.toInt(),
      replyToId: json['reply_to_id'] as String?,
      reactions: reactions,
      isDeleted: json['is_deleted'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      editedAt: json['edited_at'] != null ? DateTime.tryParse(json['edited_at'].toString()) : null,
      deliveredTo: json['delivered_to'] is List
          ? (json['delivered_to'] as List).map((e) => e.toString()).toList()
          : const [],
      fileName: json['file_name'] as String?,
      fileSize: (json['file_size'] as num?)?.toInt(),
      forwardedFromId: json['forwarded_from_id'] as String?,
      forwardedFromName: json['forwarded_from_name'] as String?,
      isPinned: json['is_pinned'] == true,
      pinnedAt: json['pinned_at'] != null ? DateTime.tryParse(json['pinned_at'].toString()) : null,
      pinnedBy: json['pinned_by'] as String?,
      mediaGroupId: json['media_group_id'] as String?,
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
      case 'call':
        return MessageType.call;
      case 'video_note':
        return MessageType.videoNote;
      case 'file':
        return MessageType.file;
      case 'poll':
        return MessageType.poll;
      case 'sticker':
        return MessageType.sticker;
      case 'gif':
        return MessageType.gif;
      case 'contact':
        return MessageType.contact;
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
      case MessageType.call:
        return 'call';
      case MessageType.videoNote:
        return 'video_note';
      case MessageType.text:
        return 'text';
      case MessageType.file:
        return 'file';
      case MessageType.poll:
        return 'poll';
      case MessageType.sticker:
        return 'sticker';
      case MessageType.gif:
        return 'gif';
      case MessageType.contact:
        return 'contact';
    }
  }

  /// Превью сообщения для списка чатов
  String get preview {
    if (isDeleted) return 'Сообщение удалено';
    switch (type) {
      case MessageType.text:
        return content ?? '';
      case MessageType.image:
        return mediaGroupId != null ? '📷 Альбом' : '📷 Фото';
      case MessageType.video:
        return mediaGroupId != null ? '🎬 Альбом' : '🎬 Видео';
      case MessageType.voice:
        final dur = voiceDuration ?? 0;
        return '🎤 ${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}';
      case MessageType.emoji:
        return content ?? '😀';
      case MessageType.videoNote:
        return '📹 Видео-кружок';
      case MessageType.call:
        return content ?? '📞 Звонок';
      case MessageType.file:
        return '📎 ${fileName ?? 'Документ'}';
      case MessageType.poll:
        return '📊 Опрос';
      case MessageType.sticker:
        return '🎨 Стикер';
      case MessageType.gif:
        return 'GIF';
      case MessageType.contact:
        return '👤 Контакт';
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

  /// Create a copy with updated fields (used for edit, reactions, delete, etc.)
  MessengerMessage copyWith({
    String? content,
    DateTime? editedAt,
    Map<String, List<String>>? reactions,
    bool? isDeleted,
    List<String>? deliveredTo,
    bool? isPinned,
    bool? isPending,
    bool? isFailed,
  }) {
    return MessengerMessage(
      id: id,
      conversationId: conversationId,
      senderPhone: senderPhone,
      senderName: senderName,
      type: type,
      content: content ?? this.content,
      mediaUrl: mediaUrl,
      voiceDuration: voiceDuration,
      replyToId: replyToId,
      reactions: reactions ?? this.reactions,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      deliveredTo: deliveredTo ?? this.deliveredTo,
      fileName: fileName,
      fileSize: fileSize,
      forwardedFromId: forwardedFromId,
      forwardedFromName: forwardedFromName,
      isPinned: isPinned ?? this.isPinned,
      pinnedAt: pinnedAt,
      pinnedBy: pinnedBy,
      mediaGroupId: mediaGroupId,
      isPending: isPending ?? this.isPending,
      isFailed: isFailed ?? this.isFailed,
    );
  }
}
