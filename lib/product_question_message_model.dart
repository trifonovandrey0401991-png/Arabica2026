import 'dart:convert';

/// Модель сообщения в диалоге вопроса о товаре
class ProductQuestionMessage {
  final String id;
  final String senderType; // "client" | "employee"
  final String? senderPhone; // телефон отправителя (для сотрудника)
  final String shopAddress; // магазин, от имени которого отвечают
  final String text;
  final String? imageUrl;
  final String timestamp;

  ProductQuestionMessage({
    required this.id,
    required this.senderType,
    this.senderPhone,
    required this.shopAddress,
    required this.text,
    this.imageUrl,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderType': senderType,
    if (senderPhone != null) 'senderPhone': senderPhone,
    'shopAddress': shopAddress,
    'text': text,
    if (imageUrl != null) 'imageUrl': imageUrl,
    'timestamp': timestamp,
  };

  factory ProductQuestionMessage.fromJson(Map<String, dynamic> json) => ProductQuestionMessage(
    id: json['id'] ?? '',
    senderType: json['senderType'] ?? 'client',
    senderPhone: json['senderPhone'] as String?,
    shopAddress: json['shopAddress'] ?? '',
    text: json['text'] ?? '',
    imageUrl: json['imageUrl'] as String?,
    timestamp: json['timestamp'] ?? '',
  );
}

