import 'package:uuid/uuid.dart';

/// Модель выемки денег из кассы
class Withdrawal {
  final String id;
  final String shopAddress;
  final String type; // "ooo" или "ip"
  final double amount;
  final String comment;
  final String adminName;
  final DateTime createdAt;

  Withdrawal({
    String? id,
    required this.shopAddress,
    required this.type,
    required this.amount,
    required this.comment,
    required this.adminName,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory Withdrawal.fromJson(Map<String, dynamic> json) {
    return Withdrawal(
      id: json['id'] as String,
      shopAddress: json['shopAddress'] as String,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      comment: json['comment'] as String? ?? '',
      adminName: json['adminName'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shopAddress': shopAddress,
      'type': type,
      'amount': amount,
      'comment': comment,
      'adminName': adminName,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Withdrawal copyWith({
    String? id,
    String? shopAddress,
    String? type,
    double? amount,
    String? comment,
    String? adminName,
    DateTime? createdAt,
  }) {
    return Withdrawal(
      id: id ?? this.id,
      shopAddress: shopAddress ?? this.shopAddress,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      comment: comment ?? this.comment,
      adminName: adminName ?? this.adminName,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get typeDisplayName => type == 'ooo' ? 'ООО' : 'ИП';

  String get formattedDate {
    return '${createdAt.day.toString().padLeft(2, '0')}.'
        '${createdAt.month.toString().padLeft(2, '0')}.'
        '${createdAt.year}';
  }

  String get formattedTime {
    return '${createdAt.hour.toString().padLeft(2, '0')}:'
        '${createdAt.minute.toString().padLeft(2, '0')}';
  }

  String get formattedDateTime => '$formattedDate, $formattedTime';
}
