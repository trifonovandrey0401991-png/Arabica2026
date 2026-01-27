/// Статус заявки на трудоустройство
enum ApplicationStatus {
  newStatus,   // Новая (не просмотрена)
  viewed,      // Просмотрена
  contacted,   // Связались с кандидатом
  interview,   // Назначено собеседование
  accepted,    // Принят на работу
  rejected,    // Отказ
}

extension ApplicationStatusExtension on ApplicationStatus {
  String get displayName {
    switch (this) {
      case ApplicationStatus.newStatus:
        return 'Новая';
      case ApplicationStatus.viewed:
        return 'Просмотрена';
      case ApplicationStatus.contacted:
        return 'Связались';
      case ApplicationStatus.interview:
        return 'Собеседование';
      case ApplicationStatus.accepted:
        return 'Принят';
      case ApplicationStatus.rejected:
        return 'Отказ';
    }
  }

  String get code {
    switch (this) {
      case ApplicationStatus.newStatus:
        return 'new';
      case ApplicationStatus.viewed:
        return 'viewed';
      case ApplicationStatus.contacted:
        return 'contacted';
      case ApplicationStatus.interview:
        return 'interview';
      case ApplicationStatus.accepted:
        return 'accepted';
      case ApplicationStatus.rejected:
        return 'rejected';
    }
  }

  static ApplicationStatus fromCode(String code) {
    switch (code) {
      case 'new':
        return ApplicationStatus.newStatus;
      case 'viewed':
        return ApplicationStatus.viewed;
      case 'contacted':
        return ApplicationStatus.contacted;
      case 'interview':
        return ApplicationStatus.interview;
      case 'accepted':
        return ApplicationStatus.accepted;
      case 'rejected':
        return ApplicationStatus.rejected;
      default:
        return ApplicationStatus.newStatus;
    }
  }

  /// Цвет статуса для отображения
  int get colorValue {
    switch (this) {
      case ApplicationStatus.newStatus:
        return 0xFFFF5252; // Красный
      case ApplicationStatus.viewed:
        return 0xFF2196F3; // Синий
      case ApplicationStatus.contacted:
        return 0xFFFF9800; // Оранжевый
      case ApplicationStatus.interview:
        return 0xFF9C27B0; // Фиолетовый
      case ApplicationStatus.accepted:
        return 0xFF4CAF50; // Зеленый
      case ApplicationStatus.rejected:
        return 0xFF757575; // Серый
    }
  }
}

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
  final ApplicationStatus status;
  final String? adminNotes; // Комментарии админа

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
    this.status = ApplicationStatus.newStatus,
    this.adminNotes,
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
      status: ApplicationStatusExtension.fromCode(json['status'] ?? 'new'),
      adminNotes: json['adminNotes'],
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
      'status': status.code,
      if (adminNotes != null) 'adminNotes': adminNotes,
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
    ApplicationStatus? status,
    String? adminNotes,
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
      status: status ?? this.status,
      adminNotes: adminNotes ?? this.adminNotes,
    );
  }
}
