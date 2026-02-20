import 'participant_model.dart';
import 'message_model.dart';

enum ConversationType { private_, group }

class Conversation {
  final String id;
  final ConversationType type;
  final String? name;
  final String? avatarUrl;
  final String? creatorPhone;
  final String? creatorName;
  final List<Participant> participants;
  final int unreadCount;
  final MessengerMessage? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastReadAt;

  Conversation({
    required this.id,
    required this.type,
    this.name,
    this.avatarUrl,
    this.creatorPhone,
    this.creatorName,
    this.participants = const [],
    this.unreadCount = 0,
    this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
    this.lastReadAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final participantsList = json['participants'];
    List<Participant> participants = [];
    if (participantsList is List) {
      participants = participantsList
          .where((p) => p != null)
          .map((p) => Participant.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    MessengerMessage? lastMessage;
    if (json['last_message'] != null) {
      lastMessage = MessengerMessage.fromJson(json['last_message'] as Map<String, dynamic>);
    }

    return Conversation(
      id: json['id'] as String,
      type: (json['type'] as String?) == 'group'
          ? ConversationType.group
          : ConversationType.private_,
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      creatorPhone: json['creator_phone'] as String?,
      creatorName: json['creator_name'] as String?,
      participants: participants,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      lastMessage: lastMessage,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
      lastReadAt: json['last_read_at'] != null
          ? DateTime.tryParse(json['last_read_at'].toString())
          : null,
    );
  }

  /// Отображаемое имя (для приватных чатов — имя собеседника)
  String displayName(String myPhone) {
    if (type == ConversationType.group) return name ?? 'Группа';

    final other = participants.where((p) => p.phone != myPhone).toList();
    if (other.isNotEmpty) return other.first.name ?? other.first.phone;
    if (participants.isNotEmpty) return participants.first.name ?? participants.first.phone;
    return 'Чат';
  }

  /// Телефон собеседника (для приватных чатов)
  String? otherPhone(String myPhone) {
    if (type != ConversationType.private_) return null;
    final other = participants.where((p) => p.phone != myPhone).toList();
    return other.isNotEmpty ? other.first.phone : null;
  }
}
