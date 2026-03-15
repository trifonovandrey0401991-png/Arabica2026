import '../../../core/constants/api_constants.dart';
import '../../../core/utils/date_formatter.dart';

/// Модель товара магазина
class ShopProduct {
  final String id;
  final String name;
  final String description;
  final String? groupId;
  final double? priceRetail;     // Розничная цена (руб.)
  final double? priceWholesale;  // Оптовая цена (руб.)
  final int? pricePoints;        // Цена в баллах
  final List<String> photos;     // Массив URL фото
  final bool isActive;
  final bool isWholesale;        // Только для оптовиков
  final int sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ShopProduct({
    required this.id,
    required this.name,
    this.description = '',
    this.groupId,
    this.priceRetail,
    this.priceWholesale,
    this.pricePoints,
    this.photos = const [],
    this.isActive = true,
    this.isWholesale = false,
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) {
    return ShopProduct(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      groupId: json['groupId'],
      priceRetail: json['priceRetail'] != null ? (json['priceRetail'] as num).toDouble() : null,
      priceWholesale: json['priceWholesale'] != null ? (json['priceWholesale'] as num).toDouble() : null,
      pricePoints: json['pricePoints'] != null ? (json['pricePoints'] as num).toInt() : null,
      photos: json['photos'] != null ? List<String>.from(json['photos']) : [],
      isActive: json['isActive'] ?? true,
      isWholesale: json['isWholesale'] ?? false,
      sortOrder: json['sortOrder'] ?? 0,
      createdAt: parseServerDate(json['createdAt']),
      updatedAt: parseServerDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      if (groupId != null) 'groupId': groupId,
      if (priceRetail != null) 'priceRetail': priceRetail,
      if (priceWholesale != null) 'priceWholesale': priceWholesale,
      if (pricePoints != null) 'pricePoints': pricePoints,
      'photos': photos,
      'isActive': isActive,
      'isWholesale': isWholesale,
      'sortOrder': sortOrder,
    };
  }

  /// Get full URL for photo at index
  String? getPhotoUrl(int index) {
    if (index < 0 || index >= photos.length) return null;
    final url = photos[index];
    if (url.startsWith('http')) return url;
    return '${ApiConstants.serverUrl}$url';
  }

  /// First photo URL or null
  String? get firstPhotoUrl => photos.isNotEmpty ? getPhotoUrl(0) : null;
}
