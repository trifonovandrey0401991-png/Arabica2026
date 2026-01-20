/// Модель клиента
class Client {
  final String phone;
  final String name;
  final String? fcmToken;
  final bool hasUnreadFromClient;
  final bool hasUnreadManagement;
  final String? lastClientMessageTime;
  final String? lastManagementMessageTime;
  final int freeDrinksGiven;  // Количество выданных бесплатных напитков

  Client({
    required this.phone,
    required this.name,
    this.fcmToken,
    this.hasUnreadFromClient = false,
    this.hasUnreadManagement = false,
    this.lastClientMessageTime,
    this.lastManagementMessageTime,
    this.freeDrinksGiven = 0,
  });

  /// Создать Client из JSON
  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      phone: json['phone'] ?? '',
      name: json['name'] ?? '',
      fcmToken: json['fcmToken'],
      hasUnreadFromClient: json['hasUnreadFromClient'] ?? false,
      hasUnreadManagement: json['hasUnreadManagement'] ?? false,
      lastClientMessageTime: json['lastClientMessageTime'],
      lastManagementMessageTime: json['lastManagementMessageTime'],
      freeDrinksGiven: json['freeDrinksGiven'] ?? 0,
    );
  }

  /// Преобразовать Client в JSON
  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'name': name,
      if (fcmToken != null) 'fcmToken': fcmToken,
      'hasUnreadFromClient': hasUnreadFromClient,
      'hasUnreadManagement': hasUnreadManagement,
      if (lastClientMessageTime != null) 'lastClientMessageTime': lastClientMessageTime,
      if (lastManagementMessageTime != null) 'lastManagementMessageTime': lastManagementMessageTime,
      'freeDrinksGiven': freeDrinksGiven,
    };
  }
}


