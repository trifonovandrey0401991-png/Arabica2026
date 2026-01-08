/// Модель сетевого сообщения (broadcast)
class NetworkMessage {
  final String id;
  final String text;
  final String? imageUrl;
  final String timestamp;
  final String senderType; // "admin" | "client"
  final String senderName;
  final String? senderPhone;
  final bool isReadByClient;
  final bool isReadByAdmin;
  final bool isBroadcast;

  NetworkMessage({
    required this.id,
    required this.text,
    this.imageUrl,
    required this.timestamp,
    required this.senderType,
    required this.senderName,
    this.senderPhone,
    this.isReadByClient = false,
    this.isReadByAdmin = false,
    this.isBroadcast = false,
  });

  factory NetworkMessage.fromJson(Map<String, dynamic> json) => NetworkMessage(
    id: json['id'] ?? '',
    text: json['text'] ?? '',
    imageUrl: json['imageUrl'],
    timestamp: json['timestamp'] ?? '',
    senderType: json['senderType'] ?? 'admin',
    senderName: json['senderName'] ?? '',
    senderPhone: json['senderPhone'],
    isReadByClient: json['isReadByClient'] ?? false,
    isReadByAdmin: json['isReadByAdmin'] ?? false,
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
    'isReadByAdmin': isReadByAdmin,
    'isBroadcast': isBroadcast,
  };

  bool get isFromAdmin => senderType == 'admin';
  bool get isFromClient => senderType == 'client';
}

/// Модель данных сетевого диалога
class NetworkDialogData {
  final List<NetworkMessage> messages;
  final int unreadCount;

  NetworkDialogData({
    required this.messages,
    required this.unreadCount,
  });

  factory NetworkDialogData.fromJson(Map<String, dynamic> json) => NetworkDialogData(
    messages: (json['messages'] as List<dynamic>?)
        ?.map((m) => NetworkMessage.fromJson(m as Map<String, dynamic>))
        .toList() ?? [],
    unreadCount: json['unreadCount'] ?? 0,
  );

  bool get hasUnread => unreadCount > 0;
  bool get hasMessages => messages.isNotEmpty;
}
