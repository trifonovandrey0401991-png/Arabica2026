/// Модель заявки на трудоустройство
class JobApplication {
  final String id;
  final String fullName;
  final String phone;
  final String preferredShift; // 'day' или 'night'
  final List<String> shopAddresses;
  final DateTime createdAt;
  final bool isViewed;
  final DateTime? viewedAt;
  final String? viewedBy;

  JobApplication({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.preferredShift,
    required this.shopAddresses,
    required this.createdAt,
    this.isViewed = false,
    this.viewedAt,
    this.viewedBy,
  });

  /// Желаемая смена для отображения
  String get shiftDisplayName {
    switch (preferredShift) {
      case 'day':
        return 'День';
      case 'night':
        return 'Ночь';
      default:
        return preferredShift;
    }
  }

  factory JobApplication.fromJson(Map<String, dynamic> json) {
    return JobApplication(
      id: json['id'] ?? '',
      fullName: json['fullName'] ?? '',
      phone: json['phone'] ?? '',
      preferredShift: json['preferredShift'] ?? 'day',
      shopAddresses: (json['shopAddresses'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      isViewed: json['isViewed'] ?? false,
      viewedAt: json['viewedAt'] != null
          ? DateTime.parse(json['viewedAt'])
          : null,
      viewedBy: json['viewedBy'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'phone': phone,
      'preferredShift': preferredShift,
      'shopAddresses': shopAddresses,
      'createdAt': createdAt.toIso8601String(),
      'isViewed': isViewed,
      'viewedAt': viewedAt?.toIso8601String(),
      'viewedBy': viewedBy,
    };
  }

  JobApplication copyWith({
    String? id,
    String? fullName,
    String? phone,
    String? preferredShift,
    List<String>? shopAddresses,
    DateTime? createdAt,
    bool? isViewed,
    DateTime? viewedAt,
    String? viewedBy,
  }) {
    return JobApplication(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      preferredShift: preferredShift ?? this.preferredShift,
      shopAddresses: shopAddresses ?? this.shopAddresses,
      createdAt: createdAt ?? this.createdAt,
      isViewed: isViewed ?? this.isViewed,
      viewedAt: viewedAt ?? this.viewedAt,
      viewedBy: viewedBy ?? this.viewedBy,
    );
  }
}
