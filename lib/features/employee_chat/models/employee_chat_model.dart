import 'employee_chat_message_model.dart';

/// Тип чата
enum EmployeeChatType {
  general,
  shop,
  private,
  group; // НОВЫЙ - пользовательские группы

  static EmployeeChatType fromString(String? type) {
    switch (type) {
      case 'general':
        return EmployeeChatType.general;
      case 'shop':
        return EmployeeChatType.shop;
      case 'private':
        return EmployeeChatType.private;
      case 'group':
        return EmployeeChatType.group;
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
      case EmployeeChatType.group:
        return 'group';
    }
  }
}

/// Модель чата сотрудников
class EmployeeChat {
  final String id;
  final EmployeeChatType type;
  final String name;
  final String? shopAddress;
  final String? imageUrl; // Картинка группы
  final String? creatorPhone; // Создатель группы
  final String? creatorName; // Имя создателя
  final List<String> participants;
  final Map<String, String>? participantNames; // {phone: name}
  final int unreadCount;
  final EmployeeChatMessage? lastMessage;

  EmployeeChat({
    required this.id,
    required this.type,
    required this.name,
    this.shopAddress,
    this.imageUrl,
    this.creatorPhone,
    this.creatorName,
    this.participants = const [],
    this.participantNames,
    this.unreadCount = 0,
    this.lastMessage,
  });

  factory EmployeeChat.fromJson(Map<String, dynamic> json) {
    // Парсим participantNames
    Map<String, String>? participantNamesMap;
    if (json['participantNames'] != null && json['participantNames'] is Map) {
      participantNamesMap = Map<String, String>.from(
        (json['participantNames'] as Map).map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        ),
      );
    }

    return EmployeeChat(
      id: json['id'] ?? '',
      type: EmployeeChatType.fromString(json['type']),
      name: json['name'] ?? '',
      shopAddress: json['shopAddress'],
      imageUrl: json['imageUrl'],
      creatorPhone: json['creatorPhone'],
      creatorName: json['creatorName'],
      participants: json['participants'] != null
          ? List<String>.from(json['participants'])
          : [],
      participantNames: participantNamesMap,
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
    'imageUrl': imageUrl,
    'creatorPhone': creatorPhone,
    'creatorName': creatorName,
    'participants': participants,
    'participantNames': participantNames,
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
      case EmployeeChatType.group:
        return '👥';
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
      case EmployeeChatType.group:
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

  /// Проверка что пользователь - создатель группы
  bool isCreator(String phone) {
    if (type != EmployeeChatType.group || creatorPhone == null) {
      return false;
    }
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
    final normalizedCreator = creatorPhone!.replaceAll(RegExp(r'[\s+]'), '');
    return normalizedPhone == normalizedCreator;
  }

  /// Количество участников (для групп)
  int get participantsCount => participants.length;

  /// Получить имя участника по телефону
  String getParticipantName(String phone) {
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s+]'), '');
    return participantNames?[normalizedPhone] ?? phone;
  }
}
