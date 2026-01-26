import 'points_settings_base.dart';

/// Настройки баллов за заказы клиентов
///
/// Использует бинарную логику (принят / отклонён).
class OrdersPointsSettings extends PointsSettingsBase {
  @override
  final String id;

  @override
  final String category;

  /// Баллы за принятый заказ
  final double acceptedPoints;

  /// Баллы за отклонённый заказ (штраф)
  final double rejectedPoints;

  @override
  final DateTime? createdAt;

  @override
  final DateTime? updatedAt;

  OrdersPointsSettings({
    this.id = 'orders_points',
    this.category = 'orders',
    required this.acceptedPoints,
    required this.rejectedPoints,
    this.createdAt,
    this.updatedAt,
  });

  factory OrdersPointsSettings.fromJson(Map<String, dynamic> json) {
    return OrdersPointsSettings(
      id: json['id'] ?? 'orders_points',
      category: json['category'] ?? 'orders',
      acceptedPoints: (json['acceptedPoints'] ?? 0.2).toDouble(),
      rejectedPoints: (json['rejectedPoints'] ?? -3).toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'acceptedPoints': acceptedPoints,
    'rejectedPoints': rejectedPoints,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Настройки по умолчанию
  factory OrdersPointsSettings.defaults() {
    return OrdersPointsSettings(
      acceptedPoints: 0.2,
      rejectedPoints: -3,
    );
  }

  /// Расчёт баллов на основе статуса заказа
  double calculatePoints(bool accepted) {
    return accepted ? acceptedPoints : rejectedPoints;
  }

  OrdersPointsSettings copyWith({
    double? acceptedPoints,
    double? rejectedPoints,
  }) {
    return OrdersPointsSettings(
      id: id,
      category: category,
      acceptedPoints: acceptedPoints ?? this.acceptedPoints,
      rejectedPoints: rejectedPoints ?? this.rejectedPoints,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
