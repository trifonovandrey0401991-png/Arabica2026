/// Модель сообщения руководству
class ManagementMessage {
  final String id;
  final String text;
  final String? imageUrl;
  final String timestamp;
  final String senderType; // "manager" | "client"
  final String senderName;
  final String? senderPhone;
  final bool isReadByClient;
  final bool isReadByManager;
  final bool isBroadcast;

  ManagementMessage({
    required this.id,
    required this.text,
    this.imageUrl,
    required this.timestamp,
    required this.senderType,
    required this.senderName,
    this.senderPhone,
    this.isReadByClient = false,
    this.isReadByManager = false,
    this.isBroadcast = false,
  });

  factory ManagementMessage.fromJson(Map<String, dynamic> json) => ManagementMessage(
    id: json['id'] ?? '',
    text: json['text'] ?? '',
    imageUrl: json['imageUrl'],
    timestamp: json['timestamp'] ?? '',
    senderType: json['senderType'] ?? 'manager',
    senderName: json['senderName'] ?? '',
    senderPhone: json['senderPhone'],
    isReadByClient: json['isReadByClient'] ?? false,
    isReadByManager: json['isReadByManager'] ?? false,
    isBroadcast: json['isBroadcast'] ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    if (imageUrl != null) 'imageUrl': imageUrl,
    'timestamp': timestamp,
    'senderType': senderType,
    'senderName': senderName,
    if (senderPhone != null) 'senderPhone': senderPhone,
    'isReadByClient': isReadByClient,
    'isReadByManager': isReadByManager,
    'isBroadcast': isBroadcast,
  };

  bool get isFromManager => senderType == 'manager';
  bool get isFromClient => senderType == 'client';
}

/// Модель данных диалога с руководством
class ManagementDialogData {
  final List<ManagementMessage> messages;
  final int unreadCount;

  ManagementDialogData({
    required this.messages,
    required this.unreadCount,
  });

  factory ManagementDialogData.fromJson(Map<String, dynamic> json) {
    final allMessages = (json['messages'] as List<dynamic>?)
        ?.map((m) => ManagementMessage.fromJson(m as Map<String, dynamic>))
        .toList() ?? [];
    final unread = json['unreadCount'] ?? 0;
    return ManagementDialogData(messages: allMessages, unreadCount: unread);
  }

  bool get hasUnread => unreadCount > 0;
  bool get hasMessages => messages.isNotEmpty;

  /// Только рассылки (broadcast)
  List<ManagementMessage> get broadcastMessages =>
      messages.where((m) => m.isBroadcast).toList();

  /// Только личные сообщения (не broadcast)
  List<ManagementMessage> get personalMessages =>
      messages.where((m) => !m.isBroadcast).toList();

  /// Непрочитанные рассылки
  int get broadcastUnreadCount =>
      broadcastMessages.where((m) => m.isFromManager && !m.isReadByClient).length;

  /// Непрочитанные личные
  int get personalUnreadCount =>
      personalMessages.where((m) => m.isFromManager && !m.isReadByClient).length;

  bool get hasBroadcastMessages => broadcastMessages.isNotEmpty;
  bool get hasPersonalMessages => personalMessages.isNotEmpty;
}
