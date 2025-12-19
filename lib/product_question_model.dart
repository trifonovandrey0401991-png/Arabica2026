import 'dart:convert';
import 'product_question_message_model.dart';

/// Модель вопроса о товаре
class ProductQuestion {
  final String id;
  final String clientPhone;
  final String clientName;
  final String shopAddress;
  final String questionText;
  final String? questionImageUrl;
  final String timestamp;
  final bool isAnswered;
  final String? lastAnswerTime;
  final List<ProductQuestionMessage> messages;

  ProductQuestion({
    required this.id,
    required this.clientPhone,
    required this.clientName,
    required this.shopAddress,
    required this.questionText,
    this.questionImageUrl,
    required this.timestamp,
    required this.isAnswered,
    this.lastAnswerTime,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientPhone': clientPhone,
    'clientName': clientName,
    'shopAddress': shopAddress,
    'questionText': questionText,
    if (questionImageUrl != null) 'questionImageUrl': questionImageUrl,
    'timestamp': timestamp,
    'isAnswered': isAnswered,
    if (lastAnswerTime != null) 'lastAnswerTime': lastAnswerTime,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ProductQuestion.fromJson(Map<String, dynamic> json) => ProductQuestion(
    id: json['id'] ?? '',
    clientPhone: json['clientPhone'] ?? '',
    clientName: json['clientName'] ?? '',
    shopAddress: json['shopAddress'] ?? '',
    questionText: json['questionText'] ?? '',
    questionImageUrl: json['questionImageUrl'] as String?,
    timestamp: json['timestamp'] ?? '',
    isAnswered: json['isAnswered'] ?? false,
    lastAnswerTime: json['lastAnswerTime'] as String?,
    messages: (json['messages'] as List<dynamic>?)
        ?.map((m) => ProductQuestionMessage.fromJson(m as Map<String, dynamic>))
        .toList() ?? [],
  );

  /// Получить последнее сообщение
  ProductQuestionMessage? getLastMessage() {
    if (messages.isEmpty) return null;
    return messages[messages.length - 1];
  }

  /// Проверить, есть ли непрочитанные сообщения для клиента
  bool hasUnreadForClient() {
    if (messages.isEmpty) return false;
    // Если есть ответы от сотрудников, считаем прочитанным
    // (можно добавить поле isRead в будущем)
    return !isAnswered;
  }
}

/// Модель диалога клиента (группировка по магазину)
class ProductQuestionDialog {
  final String shopAddress;
  final String questionId;
  final ProductQuestionMessage? lastMessage;
  final bool isAnswered;
  final String timestamp;
  final String? lastAnswerTime;

  ProductQuestionDialog({
    required this.shopAddress,
    required this.questionId,
    this.lastMessage,
    required this.isAnswered,
    required this.timestamp,
    this.lastAnswerTime,
  });

  factory ProductQuestionDialog.fromJson(Map<String, dynamic> json) => ProductQuestionDialog(
    shopAddress: json['shopAddress'] ?? '',
    questionId: json['questionId'] ?? '',
    lastMessage: json['lastMessage'] != null
        ? ProductQuestionMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
        : null,
    isAnswered: json['isAnswered'] ?? false,
    timestamp: json['timestamp'] ?? '',
    lastAnswerTime: json['lastAnswerTime'] as String?,
  );
}

