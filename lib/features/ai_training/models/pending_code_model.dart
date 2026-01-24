/// Источник pending-кода (из какого магазина пришёл)
class PendingCodeSource {
  final String shopId;
  final String shopName;
  final String name;
  final String group;
  final DateTime firstSeenAt;

  PendingCodeSource({
    required this.shopId,
    required this.shopName,
    required this.name,
    required this.group,
    required this.firstSeenAt,
  });

  factory PendingCodeSource.fromJson(Map<String, dynamic> json) {
    return PendingCodeSource(
      shopId: json['shopId'] ?? '',
      shopName: json['shopName'] ?? '',
      name: json['name'] ?? '',
      group: json['group'] ?? '',
      firstSeenAt: json['firstSeenAt'] != null
          ? DateTime.parse(json['firstSeenAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'shopId': shopId,
    'shopName': shopName,
    'name': name,
    'group': group,
    'firstSeenAt': firstSeenAt.toIso8601String(),
  };
}

/// Код товара ожидающий подтверждения
class PendingCode {
  final String kod;
  final List<PendingCodeSource> sources;
  final DateTime createdAt;
  final bool notificationSent;

  PendingCode({
    required this.kod,
    required this.sources,
    required this.createdAt,
    this.notificationSent = false,
  });

  factory PendingCode.fromJson(Map<String, dynamic> json) {
    return PendingCode(
      kod: json['kod'] ?? '',
      sources: (json['sources'] as List?)
          ?.map((s) => PendingCodeSource.fromJson(s))
          .toList() ?? [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      notificationSent: json['notificationSent'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'kod': kod,
    'sources': sources.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'notificationSent': notificationSent,
  };

  /// Первое название товара (от первого магазина)
  String get primaryName => sources.isNotEmpty ? sources.first.name : '';

  /// Первая группа товара
  String get primaryGroup => sources.isNotEmpty ? sources.first.group : '';

  /// Количество магазинов где встречается этот код
  int get shopCount => sources.length;

  /// Все уникальные названия товара из разных магазинов
  List<String> get allNames =>
      sources.map((s) => s.name).toSet().toList();

  /// Все уникальные группы
  List<String> get allGroups =>
      sources.map((s) => s.group).where((g) => g.isNotEmpty).toSet().toList();

  /// Форматированная дата создания
  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inDays == 0) {
      return 'Сегодня';
    } else if (diff.inDays == 1) {
      return 'Вчера';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} дн. назад';
    } else {
      return '${createdAt.day}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.year}';
    }
  }
}
