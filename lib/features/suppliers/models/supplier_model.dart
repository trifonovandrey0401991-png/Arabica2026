/// Модель поставщика
class Supplier {
  final String id;
  final String name;
  final String? inn;
  final String? legalType; // 'ООО', 'ИП'
  final List<String>? deliveryDays;
  final String? phone;
  final String? paymentType; // 'Нал', 'БезНал'
  final DateTime createdAt;
  final DateTime? updatedAt;

  Supplier({
    required this.id,
    required this.name,
    this.inn,
    this.legalType,
    this.deliveryDays,
    this.phone,
    this.paymentType,
    required this.createdAt,
    this.updatedAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    List<String>? deliveryDays;
    if (json['deliveryDays'] != null && json['deliveryDays'] is List) {
      deliveryDays = (json['deliveryDays'] as List).map((e) => e.toString()).toList();
    }

    return Supplier(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      inn: json['inn'],
      legalType: json['legalType'],
      deliveryDays: deliveryDays,
      phone: json['phone'],
      paymentType: json['paymentType'],
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
    'deliveryDays': deliveryDays,
    'phone': phone,
    'paymentType': paymentType,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };

  Supplier copyWith({
    String? id,
    String? name,
    String? inn,
    String? legalType,
    List<String>? deliveryDays,
    String? phone,
    String? paymentType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      inn: inn ?? this.inn,
      legalType: legalType ?? this.legalType,
      deliveryDays: deliveryDays ?? this.deliveryDays,
      phone: phone ?? this.phone,
      paymentType: paymentType ?? this.paymentType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Дни доставки в виде строки
  String get deliveryDaysText {
    if (deliveryDays == null || deliveryDays!.isEmpty) return '';
    return deliveryDays!.join(', ');
  }
}
