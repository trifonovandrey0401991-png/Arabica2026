/// Модель сообщения в диалоге вопроса о товаре
class ProductQuestionMessage {
  final String id;
  final String senderType; // "client" | "employee"
  final String? senderPhone; // телефон отправителя
  final String? senderName; // имя отправителя
  final String? shopAddress; // магазин, от имени которого отвечают (null для клиента)
  final String text;
  final String? imageUrl;
  final String timestamp;
  final String? questionId; // ID вопроса (для контекста)
  final String? originalShopAddress; // Изначальный магазин вопроса
  final bool? isNetworkWide; // Вопрос ко всей сети

  ProductQuestionMessage({
    required this.id,
    required this.senderType,
    this.senderPhone,
    this.senderName,
    this.shopAddress,
    required this.text,
    this.imageUrl,
    required this.timestamp,
    this.questionId,
    this.originalShopAddress,
    this.isNetworkWide,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderType': senderType,
    if (senderPhone != null) 'senderPhone': senderPhone,
    if (senderName != null) 'senderName': senderName,
    if (shopAddress != null) 'shopAddress': shopAddress,
    'text': text,
    if (imageUrl != null) 'imageUrl': imageUrl,
    'timestamp': timestamp,
    if (questionId != null) 'questionId': questionId,
    if (originalShopAddress != null) 'originalShopAddress': originalShopAddress,
    if (isNetworkWide != null) 'isNetworkWide': isNetworkWide,
  };

  factory ProductQuestionMessage.fromJson(Map<String, dynamic> json) => ProductQuestionMessage(
    id: json['id'] ?? '',
    senderType: json['senderType'] ?? 'client',
    senderPhone: json['senderPhone'] as String?,
    senderName: json['senderName'] as String?,
    shopAddress: json['shopAddress'] as String?,
    text: json['text'] ?? '',
    imageUrl: json['imageUrl'] as String?,
    timestamp: json['timestamp'] ?? '',
    questionId: json['questionId'] as String?,
    originalShopAddress: json['originalShopAddress'] as String?,
    isNetworkWide: json['isNetworkWide'] as bool?,
  );
}



