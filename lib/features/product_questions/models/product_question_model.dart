import 'product_question_message_model.dart';

/// Модель вопроса о товаре
class ProductQuestion {
  final String id;
  final String clientPhone;
  final String clientName;
  final String shopAddress;
  final String? shopName;
  final String questionText;
  final String? questionImageUrl;
  final String timestamp;
  final bool isAnswered;
  final String? answeredBy;
  final String? answeredByName;
  final String? lastAnswerTime;
  final bool isNetworkWide;
  final List<ProductQuestionMessage> messages;

  ProductQuestion({
    required this.id,
    required this.clientPhone,
    required this.clientName,
    required this.shopAddress,
    this.shopName,
    required this.questionText,
    this.questionImageUrl,
    required this.timestamp,
    required this.isAnswered,
    this.answeredBy,
    this.answeredByName,
    this.lastAnswerTime,
    this.isNetworkWide = false,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientPhone': clientPhone,
    'clientName': clientName,
    'shopAddress': shopAddress,
    if (shopName != null) 'shopName': shopName,
    'questionText': questionText,
    if (questionImageUrl != null) 'questionImageUrl': questionImageUrl,
    'timestamp': timestamp,
    'isAnswered': isAnswered,
    if (answeredBy != null) 'answeredBy': answeredBy,
    if (answeredByName != null) 'answeredByName': answeredByName,
    if (lastAnswerTime != null) 'lastAnswerTime': lastAnswerTime,
    'isNetworkWide': isNetworkWide,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ProductQuestion.fromJson(Map<String, dynamic> json) {
    // Поддержка новой структуры с shops[] и старой структуры
    String shopAddress = '';
    bool isAnswered = false;
    String? answeredBy;
    String? answeredByName;
    String? lastAnswerTime;

    // Новая структура - shops[] массив
    if (json['shops'] != null && json['shops'] is List && (json['shops'] as List).isNotEmpty) {
      final shops = json['shops'] as List;
      final firstShop = shops[0] as Map<String, dynamic>;
      shopAddress = firstShop['shopAddress'] ?? json['originalShopAddress'] ?? '';
      isAnswered = firstShop['isAnswered'] ?? false;
      answeredBy = firstShop['answeredBy'] as String?;
      answeredByName = firstShop['answeredByName'] as String?;
      lastAnswerTime = firstShop['lastAnswerTime'] as String?;
    }
    // Старая структура - прямые поля
    else {
      shopAddress = json['shopAddress'] ?? '';
      isAnswered = json['isAnswered'] ?? false;
      answeredBy = json['answeredBy'] as String?;
      answeredByName = json['answeredByName'] as String?;
      lastAnswerTime = json['lastAnswerTime'] as String?;
    }

    return ProductQuestion(
      id: json['id'] ?? '',
      clientPhone: json['clientPhone'] ?? '',
      clientName: json['clientName'] ?? '',
      shopAddress: shopAddress,
      shopName: json['shopName'] as String?,
      questionText: json['questionText'] ?? '',
      questionImageUrl: json['questionImageUrl'] as String?,
      timestamp: json['timestamp'] ?? json['createdAt'] ?? '',
      isAnswered: isAnswered,
      answeredBy: answeredBy,
      answeredByName: answeredByName,
      lastAnswerTime: lastAnswerTime,
      isNetworkWide: json['isNetworkWide'] ?? false,
      messages: (json['messages'] as List<dynamic>?)
          ?.map((m) => ProductQuestionMessage.fromJson(m as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  /// Получить последнее сообщение
  ProductQuestionMessage? getLastMessage() {
    if (messages.isEmpty) return null;
    return messages[messages.length - 1];
  }

  /// Проверить, есть ли непрочитанные сообщения для клиента
  bool hasUnreadForClient() {
    if (messages.isEmpty) return false;
    // Если есть ответы от сотрудников, считаем прочитанным
    // (можно добавить поле isRead в будущем)
    return !isAnswered;
  }
}

/// Модель диалога клиента (группировка по магазину)
class ProductQuestionDialog {
  final String shopAddress;
  final String questionId;
  final ProductQuestionMessage? lastMessage;
  final bool isAnswered;
  final String timestamp;
  final String? lastAnswerTime;

  ProductQuestionDialog({
    required this.shopAddress,
    required this.questionId,
    this.lastMessage,
    required this.isAnswered,
    required this.timestamp,
    this.lastAnswerTime,
  });

  factory ProductQuestionDialog.fromJson(Map<String, dynamic> json) => ProductQuestionDialog(
    shopAddress: json['shopAddress'] ?? '',
    questionId: json['questionId'] ?? '',
    lastMessage: json['lastMessage'] != null
        ? ProductQuestionMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
        : null,
    isAnswered: json['isAnswered'] ?? false,
    timestamp: json['timestamp'] ?? '',
    lastAnswerTime: json['lastAnswerTime'] as String?,
  );
}

/// Данные диалога клиента по поиску товара
class ProductQuestionClientDialogData {
  final bool hasQuestions;
  final List<ProductQuestionMessage> messages;
  final int unreadCount;
  final ProductQuestionLastMessage? lastMessage;

  ProductQuestionClientDialogData({
    required this.hasQuestions,
    required this.messages,
    required this.unreadCount,
    this.lastMessage,
  });

  factory ProductQuestionClientDialogData.fromJson(Map<String, dynamic> json) {
    return ProductQuestionClientDialogData(
      hasQuestions: json['hasQuestions'] ?? false,
      messages: (json['messages'] as List<dynamic>?)
          ?.map((m) => ProductQuestionMessage.fromJson(m as Map<String, dynamic>))
          .toList() ?? [],
      unreadCount: json['unreadCount'] ?? 0,
      lastMessage: json['lastMessage'] != null
          ? ProductQuestionLastMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Краткая информация о последнем сообщении
class ProductQuestionLastMessage {
  final String text;
  final String timestamp;
  final String? shopAddress;
  final String? senderName;
  final String senderType;

  ProductQuestionLastMessage({
    required this.text,
    required this.timestamp,
    this.shopAddress,
    this.senderName,
    required this.senderType,
  });

  factory ProductQuestionLastMessage.fromJson(Map<String, dynamic> json) {
    return ProductQuestionLastMessage(
      text: json['text'] ?? '',
      timestamp: json['timestamp'] ?? '',
      shopAddress: json['shopAddress'] as String?,
      senderName: json['senderName'] as String?,
      senderType: json['senderType'] ?? 'client',
    );
  }
}

/// Модель персонального диалога с конкретным магазином
class PersonalProductDialog {
  final String id;
  final String clientPhone;
  final String clientName;
  final String shopAddress;
  final String? originalQuestionId;
  final String createdAt;
  final bool hasUnreadFromClient;
  final bool hasUnreadFromEmployee;
  final String? lastMessageTime;
  final List<ProductQuestionMessage> messages;

  PersonalProductDialog({
    required this.id,
    required this.clientPhone,
    required this.clientName,
    required this.shopAddress,
    this.originalQuestionId,
    required this.createdAt,
    required this.hasUnreadFromClient,
    required this.hasUnreadFromEmployee,
    this.lastMessageTime,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'clientPhone': clientPhone,
    'clientName': clientName,
    'shopAddress': shopAddress,
    if (originalQuestionId != null) 'originalQuestionId': originalQuestionId,
    'createdAt': createdAt,
    'hasUnreadFromClient': hasUnreadFromClient,
    'hasUnreadFromEmployee': hasUnreadFromEmployee,
    if (lastMessageTime != null) 'lastMessageTime': lastMessageTime,
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory PersonalProductDialog.fromJson(Map<String, dynamic> json) => PersonalProductDialog(
    id: json['id'] ?? '',
    clientPhone: json['clientPhone'] ?? '',
    clientName: json['clientName'] ?? '',
    shopAddress: json['shopAddress'] ?? '',
    originalQuestionId: json['originalQuestionId'] as String?,
    createdAt: json['createdAt'] ?? '',
    hasUnreadFromClient: json['hasUnreadFromClient'] ?? false,
    hasUnreadFromEmployee: json['hasUnreadFromEmployee'] ?? false,
    lastMessageTime: json['lastMessageTime'] as String?,
    messages: (json['messages'] as List<dynamic>?)
        ?.map((m) => ProductQuestionMessage.fromJson(m as Map<String, dynamic>))
        .toList() ?? [],
  );

  /// Получить последнее сообщение
  ProductQuestionMessage? getLastMessage() {
    if (messages.isEmpty) return null;
    return messages[messages.length - 1];
  }

  /// Краткое название для отображения
  String get displayName => 'Поиск товара - $shopAddress';
}

/// Группа вопросов по магазину
class ProductQuestionShopGroup {
  final String shopAddress;
  final List<ProductQuestion> questions;
  final List<PersonalProductDialog> dialogs;
  final int unreadCount;

  ProductQuestionShopGroup({
    required this.shopAddress,
    required this.questions,
    required this.dialogs,
    required this.unreadCount,
  });

  factory ProductQuestionShopGroup.fromJson(Map<String, dynamic> json) {
    return ProductQuestionShopGroup(
      shopAddress: json['shopAddress'] ?? '',
      questions: (json['questions'] as List<dynamic>?)
          ?.map((q) => ProductQuestion.fromJson(q as Map<String, dynamic>))
          .toList() ?? [],
      dialogs: (json['dialogs'] as List<dynamic>?)
          ?.map((d) => PersonalProductDialog.fromJson(d as Map<String, dynamic>))
          .toList() ?? [],
      unreadCount: json['unreadCount'] ?? 0,
    );
  }

  /// Получить последнее сообщение (из вопросов или диалогов)
  ProductQuestionMessage? getLastMessage() {
    ProductQuestionMessage? lastMessage;
    DateTime? lastTime;

    // Проверяем вопросы
    for (final q in questions) {
      final msg = q.getLastMessage();
      if (msg != null) {
        final msgTime = DateTime.tryParse(msg.timestamp);
        if (msgTime != null && (lastTime == null || msgTime.isAfter(lastTime))) {
          lastMessage = msg;
          lastTime = msgTime;
        }
      }
    }

    // Проверяем диалоги
    for (final d in dialogs) {
      final msg = d.getLastMessage();
      if (msg != null) {
        final msgTime = DateTime.tryParse(msg.timestamp);
        if (msgTime != null && (lastTime == null || msgTime.isAfter(lastTime))) {
          lastMessage = msg;
          lastTime = msgTime;
        }
      }
    }

    return lastMessage;
  }
}

/// Группированные данные клиента по поиску товара
class ProductQuestionGroupedData {
  final int totalUnread;
  final List<ProductQuestion> networkWideQuestions;
  final int networkWideUnreadCount;
  final Map<String, ProductQuestionShopGroup> byShop;

  ProductQuestionGroupedData({
    required this.totalUnread,
    required this.networkWideQuestions,
    required this.networkWideUnreadCount,
    required this.byShop,
  });

  factory ProductQuestionGroupedData.fromJson(Map<String, dynamic> json) {
    final byShopJson = json['byShop'] as Map<String, dynamic>? ?? {};
    final byShopMap = <String, ProductQuestionShopGroup>{};

    byShopJson.forEach((key, value) {
      byShopMap[key] = ProductQuestionShopGroup.fromJson(value as Map<String, dynamic>);
    });

    return ProductQuestionGroupedData(
      totalUnread: json['totalUnread'] ?? 0,
      networkWideQuestions: (json['networkWide']?['questions'] as List<dynamic>?)
          ?.map((q) => ProductQuestion.fromJson(q as Map<String, dynamic>))
          .toList() ?? [],
      networkWideUnreadCount: json['networkWide']?['unreadCount'] ?? 0,
      byShop: byShopMap,
    );
  }

  /// Получить список магазинов, отсортированных по последнему сообщению
  List<String> getSortedShops() {
    final entries = byShop.entries.toList();
    entries.sort((a, b) {
      final aMsg = a.value.getLastMessage();
      final bMsg = b.value.getLastMessage();

      if (aMsg == null && bMsg == null) return 0;
      if (aMsg == null) return 1;
      if (bMsg == null) return -1;

      final aTime = DateTime.tryParse(aMsg.timestamp);
      final bTime = DateTime.tryParse(bMsg.timestamp);

      if (aTime == null || bTime == null) return 0;
      return bTime.compareTo(aTime); // Новые сверху
    });

    return entries.map((e) => e.key).toList();
  }
}
