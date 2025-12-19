import 'dart:convert';

/// Унифицированная модель сообщения в диалоге
class UnifiedDialogMessage {
  final String id;
  final String type; // "review" | "product_question" | "order" | "employee_response"
  final String timestamp;
  final String senderType; // "client" | "employee"
  final String senderName;
  final String shopAddress;
  final Map<String, dynamic> data;
  final bool? isRead;

  UnifiedDialogMessage({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.senderType,
    required this.senderName,
    required this.shopAddress,
    required this.data,
    this.isRead,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'timestamp': timestamp,
    'senderType': senderType,
    'senderName': senderName,
    'shopAddress': shopAddress,
    'data': data,
    if (isRead != null) 'isRead': isRead,
  };

  factory UnifiedDialogMessage.fromJson(Map<String, dynamic> json) => UnifiedDialogMessage(
    id: json['id'] ?? '',
    type: json['type'] ?? 'review',
    timestamp: json['timestamp'] ?? '',
    senderType: json['senderType'] ?? 'client',
    senderName: json['senderName'] ?? '',
    shopAddress: json['shopAddress'] ?? '',
    data: json['data'] != null ? Map<String, dynamic>.from(json['data']) : {},
    isRead: json['isRead'] as bool?,
  );

  /// Проверить, является ли сообщение непрочитанным
  bool isUnread() {
    return senderType == 'employee' && (isRead == false || isRead == null);
  }

  /// Получить текст сообщения в зависимости от типа
  String getDisplayText() {
    switch (type) {
      case 'review':
        return data['reviewText'] ?? '';
      case 'product_question':
        return data['questionText'] ?? '';
      case 'order':
        return 'Заказ #${data['orderId'] ?? ''}';
      case 'employee_response':
        return data['text'] ?? '';
      default:
        return '';
    }
  }

  /// Получить URL изображения, если есть
  String? getImageUrl() {
    if (type == 'product_question') {
      return data['questionImageUrl'] as String?;
    } else if (type == 'employee_response') {
      return data['imageUrl'] as String?;
    }
    return null;
  }
}

