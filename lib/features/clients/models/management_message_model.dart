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

  factory ManagementDialogData.fromJson(Map<String, dynamic> json) => ManagementDialogData(
    messages: (json['messages'] as List<dynamic>?)
        ?.map((m) => ManagementMessage.fromJson(m as Map<String, dynamic>))
        .toList() ?? [],
    unreadCount: json['unreadCount'] ?? 0,
  );

  bool get hasUnread => unreadCount > 0;
  bool get hasMessages => messages.isNotEmpty;
}
