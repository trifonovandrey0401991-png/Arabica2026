/// Model for a user-defined chat folder.
class ChatFolder {
  final String id;
  final String phone;
  final String name;
  final int sortOrder;
  final String filterType; // 'manual' | 'unread' | 'groups' | 'private' | 'channels'
  final List<String> conversationIds;
  final DateTime? createdAt;

  const ChatFolder({
    required this.id,
    required this.phone,
    required this.name,
    this.sortOrder = 0,
    this.filterType = 'manual',
    this.conversationIds = const [],
    this.createdAt,
  });

  factory ChatFolder.fromJson(Map<String, dynamic> json) {
    List<String> ids = [];
    if (json['conversation_ids'] is List) {
      ids = (json['conversation_ids'] as List).whereType<String>().toList();
    }
    return ChatFolder(
      id: json['id'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      name: json['name'] as String? ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      filterType: json['filter_type'] as String? ?? 'manual',
      conversationIds: ids,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'phone': phone,
    'name': name,
    'sort_order': sortOrder,
    'filter_type': filterType,
    'conversation_ids': conversationIds,
  };
}
