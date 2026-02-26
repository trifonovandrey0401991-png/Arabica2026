/// Модель группы товаров магазина
class ShopProductGroup {
  final String id;
  final String name;
  final String visibility; // 'all' | 'wholesale_only'
  final int sortOrder;
  final bool isActive;
  final DateTime? createdAt;

  ShopProductGroup({
    required this.id,
    required this.name,
    this.visibility = 'all',
    this.sortOrder = 0,
    this.isActive = true,
    this.createdAt,
  });

  factory ShopProductGroup.fromJson(Map<String, dynamic> json) {
    return ShopProductGroup(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      visibility: json['visibility'] ?? 'all',
      sortOrder: json['sortOrder'] ?? 0,
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'visibility': visibility,
      'sortOrder': sortOrder,
      'isActive': isActive,
    };
  }

  /// Visible only to wholesale clients
  bool get isWholesaleOnly => visibility == 'wholesale_only';
}
