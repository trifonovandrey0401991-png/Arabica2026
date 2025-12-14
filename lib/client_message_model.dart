/// Модель сообщения клиенту
class ClientMessage {
  final String id;
  final String clientPhone;
  final String senderPhone;
  final String text;
  final String? imageUrl;
  final String timestamp;
  final bool isRead;

  ClientMessage({
    required this.id,
    required this.clientPhone,
    required this.senderPhone,
    required this.text,
    this.imageUrl,
    required this.timestamp,
    required this.isRead,
  });

  /// Создать ClientMessage из JSON
  factory ClientMessage.fromJson(Map<String, dynamic> json) {
    return ClientMessage(
      id: json['id'] ?? '',
      clientPhone: json['clientPhone'] ?? '',
      senderPhone: json['senderPhone'] ?? '',
      text: json['text'] ?? '',
      imageUrl: json['imageUrl'],
      timestamp: json['timestamp'] ?? '',
      isRead: json['isRead'] ?? false,
    );
  }

  /// Преобразовать ClientMessage в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientPhone': clientPhone,
      'senderPhone': senderPhone,
      'text': text,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'timestamp': timestamp,
      'isRead': isRead,
    };
  }
}

