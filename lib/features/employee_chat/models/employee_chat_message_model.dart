import 'package:arabica_app/core/utils/date_formatter.dart';

/// Модель пересланного сообщения
class ForwardedFrom {
  final String chatId;
  final String messageId;
  final String originalSenderName;
  final DateTime originalTimestamp;

  ForwardedFrom({
    required this.chatId,
    required this.messageId,
    required this.originalSenderName,
    required this.originalTimestamp,
  });

  factory ForwardedFrom.fromJson(Map<String, dynamic> json) {
    return ForwardedFrom(
      chatId: json['chatId'] ?? '',
      messageId: json['messageId'] ?? '',
      originalSenderName: json['originalSenderName'] ?? '',
      originalTimestamp: parseServerDateOrNow(json['originalTimestamp']),
    );
  }

  Map<String, dynamic> toJson() => {
    'chatId': chatId,
    'messageId': messageId,
    'originalSenderName': originalSenderName,
    'originalTimestamp': originalTimestamp.toIso8601String(),
  };
}

/// Модель сообщения в чате сотрудников
class EmployeeChatMessage {
  final String id;
  final String chatId;
  final String senderPhone;
  final String senderName;
  final String text;
  final String? imageUrl;
  final DateTime timestamp;
  final List<String> readBy;
  final Map<String, List<String>> reactions; // {"👍": ["phone1", "phone2"]}
  final ForwardedFrom? forwardedFrom;

  EmployeeChatMessage({
    required this.id,
    required this.chatId,
    required this.senderPhone,
    required this.senderName,
    required this.text,
    this.imageUrl,
    required this.timestamp,
    required this.readBy,
    this.reactions = const {},
    this.forwardedFrom,
  });

  factory EmployeeChatMessage.fromJson(Map<String, dynamic> json) {
    // Парсим reactions
    Map<String, List<String>> reactionsMap = {};
    if (json['reactions'] != null && json['reactions'] is Map) {
      final rawReactions = json['reactions'] as Map<String, dynamic>;
      for (final entry in rawReactions.entries) {
        if (entry.value is List) {
          reactionsMap[entry.key] = List<String>.from(entry.value);
        }
      }
    }

    return EmployeeChatMessage(
      id: json['id'] ?? '',
      chatId: json['chatId'] ?? '',
      senderPhone: json['senderPhone'] ?? '',
      senderName: json['senderName'] ?? '',
      text: json['text'] ?? '',
      imageUrl: json['imageUrl'],
      timestamp: parseServerDateOrNow(json['timestamp']),
      readBy: json['readBy'] != null
          ? List<String>.from(json['readBy'])
          : [],
      reactions: reactionsMap,
      forwardedFrom: json['forwardedFrom'] != null
          ? ForwardedFrom.fromJson(json['forwardedFrom'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'chatId': chatId,
    'senderPhone': senderPhone,
    'senderName': senderName,
    'text': text,
    'imageUrl': imageUrl,
    'timestamp': timestamp.toIso8601String(),
    'readBy': readBy,
    'reactions': reactions,
    if (forwardedFrom != null) 'forwardedFrom': forwardedFrom!.toJson(),
  };

  /// Копирование с изменениями (для обновления реакций)
  EmployeeChatMessage copyWith({
    String? id,
    String? chatId,
    String? senderPhone,
    String? senderName,
    String? text,
    String? imageUrl,
    DateTime? timestamp,
    List<String>? readBy,
    Map<String, List<String>>? reactions,
    ForwardedFrom? forwardedFrom,
  }) {
    return EmployeeChatMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderPhone: senderPhone ?? this.senderPhone,
      senderName: senderName ?? this.senderName,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      timestamp: timestamp ?? this.timestamp,
      readBy: readBy ?? this.readBy,
      reactions: reactions ?? this.reactions,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
    );
  }

  /// Общее количество реакций
  int get totalReactions {
    int count = 0;
    for (final phones in reactions.values) {
      count += phones.length;
    }
    return count;
  }

  /// Проверка, ставил ли пользователь реакцию
  bool hasReactionFrom(String phone, String reaction) {
    return reactions[reaction]?.contains(phone) ?? false;
  }

  /// Проверка, есть ли у сообщения какие-либо реакции
  bool get hasReactions => reactions.isNotEmpty;

  /// Проверка, прочитано ли сообщение пользователем
  bool isReadBy(String phone) => readBy.contains(phone);

  /// Форматирование времени для отображения
  String get formattedTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'вчера';
    } else {
      return '${timestamp.day}.${timestamp.month.toString().padLeft(2, '0')}';
    }
  }
}
