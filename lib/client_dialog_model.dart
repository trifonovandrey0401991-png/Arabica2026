import 'dart:convert';
import 'unified_dialog_message_model.dart';

/// Модель диалога клиента с магазином
class ClientDialog {
  final String shopAddress;
  final List<UnifiedDialogMessage> messages;
  final String? lastMessageTime;
  final int unreadCount;

  ClientDialog({
    required this.shopAddress,
    required this.messages,
    this.lastMessageTime,
    required this.unreadCount,
  });

  Map<String, dynamic> toJson() => {
    'shopAddress': shopAddress,
    'messages': messages.map((m) => m.toJson()).toList(),
    if (lastMessageTime != null) 'lastMessageTime': lastMessageTime,
    'unreadCount': unreadCount,
  };

  factory ClientDialog.fromJson(Map<String, dynamic> json) => ClientDialog(
    shopAddress: json['shopAddress'] ?? '',
    messages: (json['messages'] as List<dynamic>?)
        ?.map((m) => UnifiedDialogMessage.fromJson(m as Map<String, dynamic>))
        .toList() ?? [],
    lastMessageTime: json['lastMessageTime'] as String?,
    unreadCount: json['unreadCount'] ?? 0,
  );

  /// Получить последнее сообщение
  UnifiedDialogMessage? getLastMessage() {
    if (messages.isEmpty) return null;
    return messages[messages.length - 1];
  }

  /// Проверить, есть ли непрочитанные сообщения
  bool hasUnread() {
    return unreadCount > 0;
  }
}


