/// Модель клиента
class Client {
  final String phone;
  final String name;
  final String? fcmToken;

  Client({
    required this.phone,
    required this.name,
    this.fcmToken,
  });

  /// Создать Client из JSON
  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      phone: json['phone'] ?? '',
      name: json['name'] ?? '',
      fcmToken: json['fcmToken'],
    );
  }

  /// Преобразовать Client в JSON
  Map<String, dynamic> toJson() {
    return {
      'phone': phone,
      'name': name,
      if (fcmToken != null) 'fcmToken': fcmToken,
    };
  }
}


