/// Модель баллов сотрудника для пересчёта
/// Используется для расчёта требуемого количества фотографий
class RecountPoints {
  final String id;
  final String employeeId;
  final String employeeName;
  final String phone;
  final double points;
  final DateTime updatedAt;
  final String? updatedBy;

  RecountPoints({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.phone,
    required this.points,
    required this.updatedAt,
    this.updatedBy,
  });

  factory RecountPoints.fromJson(Map<String, dynamic> json) {
    return RecountPoints(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      phone: json['phone'] ?? '',
      points: (json['points'] is int)
          ? (json['points'] as int).toDouble()
          : (json['points'] ?? 85.0).toDouble(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
      updatedBy: json['updatedBy'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'phone': phone,
      'points': points,
      'updatedAt': updatedAt.toIso8601String(),
      'updatedBy': updatedBy,
    };
  }

  /// Расчёт требуемого количества фото по баллам
  /// Формула: photos = 3 + max(0, min(17, floor((85 - points) / 5)))
  /// 85-100 = 3 фото, 80-84 = 4 фото, ..., 0-4 = 20 фото
  int calculateRequiredPhotos({
    int basePhotos = 3,
    double stepPoints = 5,
    int maxPhotos = 20,
  }) {
    if (points >= 85) return basePhotos;

    final stepsDown = ((85 - points) / stepPoints).floor();
    final additionalPhotos = stepsDown.clamp(0, maxPhotos - basePhotos);

    return basePhotos + additionalPhotos;
  }

  RecountPoints copyWith({
    String? id,
    String? employeeId,
    String? employeeName,
    String? phone,
    double? points,
    DateTime? updatedAt,
    String? updatedBy,
  }) {
    return RecountPoints(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      phone: phone ?? this.phone,
      points: points ?? this.points,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }
}
