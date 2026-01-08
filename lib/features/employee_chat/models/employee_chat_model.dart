import 'employee_chat_message_model.dart';

/// Тип чата
enum EmployeeChatType {
  general,
  shop,
  private;

  static EmployeeChatType fromString(String? type) {
    switch (type) {
      case 'general':
        return EmployeeChatType.general;
      case 'shop':
        return EmployeeChatType.shop;
      case 'private':
        return EmployeeChatType.private;
      default:
        return EmployeeChatType.general;
    }
  }

  String get value {
    switch (this) {
      case EmployeeChatType.general:
        return 'general';
      case EmployeeChatType.shop:
        return 'shop';
      case EmployeeChatType.private:
        return 'private';
    }
  }
}

/// Модель чата сотрудников
class EmployeeChat {
  final String id;
  final EmployeeChatType type;
  final String name;
  final String? shopAddress;
  final List<String> participants;
  final int unreadCount;
  final EmployeeChatMessage? lastMessage;

  EmployeeChat({
    required this.id,
    required this.type,
    required this.name,
    this.shopAddress,
    this.participants = const [],
    this.unreadCount = 0,
    this.lastMessage,
  });

  factory EmployeeChat.fromJson(Map<String, dynamic> json) {
    return EmployeeChat(
      id: json['id'] ?? '',
      type: EmployeeChatType.fromString(json['type']),
      name: json['name'] ?? '',
      shopAddress: json['shopAddress'],
      participants: json['participants'] != null
          ? List<String>.from(json['participants'])
          : [],
      unreadCount: json['unreadCount'] ?? 0,
      lastMessage: json['lastMessage'] != null
          ? EmployeeChatMessage.fromJson(json['lastMessage'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.value,
    'name': name,
    'shopAddress': shopAddress,
    'participants': participants,
    'unreadCount': unreadCount,
    'lastMessage': lastMessage?.toJson(),
  };

  /// Иконка для типа чата
  String get typeIcon {
    switch (type) {
      case EmployeeChatType.general:
        return '🌐';
      case EmployeeChatType.shop:
        return '🏪';
      case EmployeeChatType.private:
        return '👤';
    }
  }

  /// Название для отображения
  String get displayName {
    switch (type) {
      case EmployeeChatType.general:
        return 'Общий чат';
      case EmployeeChatType.shop:
        return shopAddress ?? name;
      case EmployeeChatType.private:
        return name;
    }
  }

  /// Краткое описание последнего сообщения
  String get lastMessagePreview {
    if (lastMessage == null) return 'Нет сообщений';

    final sender = lastMessage!.senderName.split(' ').first;
    final text = lastMessage!.imageUrl != null && lastMessage!.text.isEmpty
        ? '[Фото]'
        : lastMessage!.text;

    final preview = text.length > 30 ? '${text.substring(0, 30)}...' : text;
    return '$sender: $preview';
  }

  /// Время последнего сообщения
  String get lastMessageTime {
    return lastMessage?.formattedTime ?? '';
  }
}
