/// Модель сообщения в чате сотрудников
class EmployeeChatMessage {
  final String id;
  final String chatId;
  final String senderPhone;
  final String senderName;
  final String text;
  final String? imageUrl;
  final DateTime timestamp;
  final List<String> readBy;

  EmployeeChatMessage({
    required this.id,
    required this.chatId,
    required this.senderPhone,
    required this.senderName,
    required this.text,
    this.imageUrl,
    required this.timestamp,
    required this.readBy,
  });

  factory EmployeeChatMessage.fromJson(Map<String, dynamic> json) {
    return EmployeeChatMessage(
      id: json['id'] ?? '',
      chatId: json['chatId'] ?? '',
      senderPhone: json['senderPhone'] ?? '',
      senderName: json['senderName'] ?? '',
      text: json['text'] ?? '',
      imageUrl: json['imageUrl'],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      readBy: json['readBy'] != null
          ? List<String>.from(json['readBy'])
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'chatId': chatId,
    'senderPhone': senderPhone,
    'senderName': senderName,
    'text': text,
    'imageUrl': imageUrl,
    'timestamp': timestamp.toIso8601String(),
    'readBy': readBy,
  };

  /// Проверка, прочитано ли сообщение пользователем
  bool isReadBy(String phone) => readBy.contains(phone);

  /// Форматирование времени для отображения
  String get formattedTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'вчера';
    } else {
      return '${timestamp.day}.${timestamp.month.toString().padLeft(2, '0')}';
    }
  }
}
