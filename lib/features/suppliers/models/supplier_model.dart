/// Модель доставки поставщика в конкретный магазин
class SupplierShopDelivery {
  final String shopId;
  final String shopName;
  final List<String> days;
  final List<String>? managerIds;    // ID заведующих
  final List<String>? managerNames;  // Имена заведующих (для отображения)

  SupplierShopDelivery({
    required this.shopId,
    required this.shopName,
    required this.days,
    this.managerIds,
    this.managerNames,
  });

  factory SupplierShopDelivery.fromJson(Map<String, dynamic> json) {
    List<String> days = [];
    if (json['days'] != null && json['days'] is List) {
      days = (json['days'] as List).map((e) => e.toString()).toList();
    }

    List<String>? managerIds;
    if (json['managerIds'] != null && json['managerIds'] is List) {
      managerIds = (json['managerIds'] as List).map((e) => e.toString()).toList();
    }

    List<String>? managerNames;
    if (json['managerNames'] != null && json['managerNames'] is List) {
      managerNames = (json['managerNames'] as List).map((e) => e.toString()).toList();
    }

    return SupplierShopDelivery(
      shopId: json['shopId'] ?? '',
      shopName: json['shopName'] ?? '',
      days: days,
      managerIds: managerIds,
      managerNames: managerNames,
    );
  }

  Map<String, dynamic> toJson() => {
    'shopId': shopId,
    'shopName': shopName,
    'days': days,
    'managerIds': managerIds,
    'managerNames': managerNames,
  };

  SupplierShopDelivery copyWith({
    String? shopId,
    String? shopName,
    List<String>? days,
    List<String>? managerIds,
    List<String>? managerNames,
  }) {
    return SupplierShopDelivery(
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      days: days ?? this.days,
      managerIds: managerIds ?? this.managerIds,
      managerNames: managerNames ?? this.managerNames,
    );
  }

  /// Дни доставки в виде короткой строки (Пн, Ср, Пт)
  String get daysShortText {
    if (days.isEmpty) return '';
    return days.map((d) => d.length >= 2 ? d.substring(0, 2) : d).join(', ');
  }

  /// Заведующие в виде строки
  String get managersText {
    if (managerNames == null || managerNames!.isEmpty) return '';
    return managerNames!.join(', ');
  }

  /// Есть ли заведующие
  bool get hasManagers => managerIds != null && managerIds!.isNotEmpty;
}

/// Модель поставщика
class Supplier {
  final String id;
  final String name;
  final String? inn;
  final String? legalType; // 'ООО', 'ИП'
  final String? phone;
  final String? email;
  final String? contactPerson;
  final String? paymentType; // 'Нал', 'БезНал'
  final List<SupplierShopDelivery>? shopDeliveries;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Устаревшее поле для обратной совместимости
  final List<String>? deliveryDays;

  Supplier({
    required this.id,
    required this.name,
    this.inn,
    this.legalType,
    this.phone,
    this.email,
    this.contactPerson,
    this.paymentType,
    this.shopDeliveries,
    this.deliveryDays,
    required this.createdAt,
    this.updatedAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    // Парсим shopDeliveries
    List<SupplierShopDelivery>? shopDeliveries;
    if (json['shopDeliveries'] != null && json['shopDeliveries'] is List) {
      shopDeliveries = (json['shopDeliveries'] as List)
          .map((e) => SupplierShopDelivery.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // Парсим старый формат deliveryDays для обратной совместимости
    List<String>? deliveryDays;
    if (json['deliveryDays'] != null && json['deliveryDays'] is List) {
      deliveryDays = (json['deliveryDays'] as List).map((e) => e.toString()).toList();
    }

    return Supplier(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      inn: json['inn'],
      legalType: json['legalType'],
      phone: json['phone'],
      email: json['email'],
      contactPerson: json['contactPerson'],
      paymentType: json['paymentType'],
      shopDeliveries: shopDeliveries,
      deliveryDays: deliveryDays,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'inn': inn,
    'legalType': legalType,
    'phone': phone,
    'email': email,
    'contactPerson': contactPerson,
    'paymentType': paymentType,
    'shopDeliveries': shopDeliveries?.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  Supplier copyWith({
    String? id,
    String? name,
    String? inn,
    String? legalType,
    String? phone,
    String? email,
    String? contactPerson,
    String? paymentType,
    List<SupplierShopDelivery>? shopDeliveries,
    List<String>? deliveryDays,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      inn: inn ?? this.inn,
      legalType: legalType ?? this.legalType,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      contactPerson: contactPerson ?? this.contactPerson,
      paymentType: paymentType ?? this.paymentType,
      shopDeliveries: shopDeliveries ?? this.shopDeliveries,
      deliveryDays: deliveryDays ?? this.deliveryDays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Количество магазинов с днями доставки
  int get shopsWithDeliveryCount {
    if (shopDeliveries == null) return 0;
    return shopDeliveries!.where((sd) => sd.days.isNotEmpty).length;
  }

  /// Краткое описание доставки для списка
  String get deliveryInfoText {
    if (shopDeliveries != null && shopDeliveries!.isNotEmpty) {
      final count = shopsWithDeliveryCount;
      if (count == 0) return 'Нет доставок';
      return 'Доставка в $count магазин${_getShopEnding(count)}';
    }
    // Обратная совместимость со старым форматом
    if (deliveryDays != null && deliveryDays!.isNotEmpty) {
      return deliveryDays!.join(', ');
    }
    return '';
  }

  String _getShopEnding(int count) {
    if (count == 1) return '';
    if (count >= 2 && count <= 4) return 'а';
    return 'ов';
  }

  /// Дни доставки в виде строки (для обратной совместимости)
  @Deprecated('Используйте shopDeliveries вместо deliveryDays')
  String get deliveryDaysText {
    if (deliveryDays == null || deliveryDays!.isEmpty) return '';
    return deliveryDays!.join(', ');
  }
}
