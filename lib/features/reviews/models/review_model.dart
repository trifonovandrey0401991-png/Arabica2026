/// Модель сообщения в диалоге
class ReviewMessage {
  final String id;
  final String sender; // 'client' или 'admin'
  final String senderName;
  final String text;
  final DateTime createdAt;
  final bool isRead;

  ReviewMessage({
    required this.id,
    required this.sender,
    required this.senderName,
    required this.text,
    required this.createdAt,
    this.isRead = false,
  });

  factory ReviewMessage.fromJson(Map<String, dynamic> json) {
    return ReviewMessage(
      id: json['id'] ?? '',
      sender: json['sender'] ?? 'client',
      senderName: json['senderName'] ?? '',
      text: json['text'] ?? '',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      isRead: json['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender': sender,
      'senderName': senderName,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
    };
  }
}

/// Модель отзыва/диалога
class Review {
  final String id;
  final DateTime createdAt;
  final String clientPhone;
  final String clientName;
  final String shopAddress;
  final String reviewType; // 'positive' или 'negative'
  final String reviewText;
  final List<ReviewMessage> messages;

  Review({
    required this.id,
    required this.createdAt,
    required this.clientPhone,
    required this.clientName,
    required this.shopAddress,
    required this.reviewType,
    required this.reviewText,
    List<ReviewMessage>? messages,
  }) : messages = messages ?? [];

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] ?? '',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      clientPhone: json['clientPhone'] ?? '',
      clientName: json['clientName'] ?? '',
      shopAddress: json['shopAddress'] ?? '',
      reviewType: json['reviewType'] ?? 'positive',
      reviewText: json['reviewText'] ?? '',
      messages: (json['messages'] as List<dynamic>?)
          ?.map((m) => ReviewMessage.fromJson(m as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'clientPhone': clientPhone,
      'clientName': clientName,
      'shopAddress': shopAddress,
      'reviewType': reviewType,
      'reviewText': reviewText,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
  }

  /// Получить количество непрочитанных сообщений для клиента
  int getUnreadCountForClient() {
    return messages.where((m) => m.sender == 'admin' && !m.isRead).length;
  }

  /// Получить последнее сообщение
  ReviewMessage? getLastMessage() {
    if (messages.isEmpty) return null;
    return messages.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
  }

  /// Проверить, есть ли непрочитанные сообщения для клиента
  bool hasUnreadForClient() {
    return getUnreadCountForClient() > 0;
  }
}
















