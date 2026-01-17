/// Model for test points settings
class TestPointsSettings {
  final String id;
  final String category;
  final double minPoints;     // Penalty for lowest score (e.g., -2)
  final int zeroThreshold;    // Correct answers that give 0 points (e.g., 15)
  final double maxPoints;     // Reward for perfect score (e.g., +1)
  final int totalQuestions;   // Fixed: 20
  final int passingScore;     // Fixed: 16
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TestPointsSettings({
    this.id = 'test_points',
    this.category = 'testing',
    required this.minPoints,
    required this.zeroThreshold,
    required this.maxPoints,
    this.totalQuestions = 20,
    this.passingScore = 16,
    this.createdAt,
    this.updatedAt,
  });

  factory TestPointsSettings.fromJson(Map<String, dynamic> json) {
    return TestPointsSettings(
      id: json['id'] ?? 'test_points',
      category: json['category'] ?? 'testing',
      minPoints: (json['minPoints'] ?? -2).toDouble(),
      zeroThreshold: json['zeroThreshold'] ?? 15,
      maxPoints: (json['maxPoints'] ?? 1).toDouble(),
      totalQuestions: json['totalQuestions'] ?? 20,
      passingScore: json['passingScore'] ?? 16,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'minPoints': minPoints,
    'zeroThreshold': zeroThreshold,
    'maxPoints': maxPoints,
    'totalQuestions': totalQuestions,
    'passingScore': passingScore,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Default settings
  factory TestPointsSettings.defaults() {
    return TestPointsSettings(
      minPoints: -2,
      zeroThreshold: 15,
      maxPoints: 1,
    );
  }

  /// Calculate efficiency points for a given score using linear interpolation
  double calculatePoints(int score) {
    if (score <= 0) return minPoints;
    if (score >= totalQuestions) return maxPoints;

    if (score <= zeroThreshold) {
      // Interpolate from minPoints to 0 (score: 0 -> zeroThreshold)
      return minPoints + (0 - minPoints) * (score / zeroThreshold);
    } else {
      // Interpolate from 0 to maxPoints (score: zeroThreshold -> totalQuestions)
      final range = totalQuestions - zeroThreshold;
      return 0 + (maxPoints - 0) * ((score - zeroThreshold) / range);
    }
  }

  TestPointsSettings copyWith({
    double? minPoints,
    int? zeroThreshold,
    double? maxPoints,
  }) {
    return TestPointsSettings(
      id: id,
      category: category,
      minPoints: minPoints ?? this.minPoints,
      zeroThreshold: zeroThreshold ?? this.zeroThreshold,
      maxPoints: maxPoints ?? this.maxPoints,
      totalQuestions: totalQuestions,
      passingScore: passingScore,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Model for attendance points settings (Я на работе)
class AttendancePointsSettings {
  final String id;
  final String category;
  final double onTimePoints;  // Points for arriving on time
  final double latePoints;    // Points for being late (negative)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AttendancePointsSettings({
    this.id = 'attendance_points',
    this.category = 'attendance',
    required this.onTimePoints,
    required this.latePoints,
    this.createdAt,
    this.updatedAt,
  });

  factory AttendancePointsSettings.fromJson(Map<String, dynamic> json) {
    return AttendancePointsSettings(
      id: json['id'] ?? 'attendance_points',
      category: json['category'] ?? 'attendance',
      onTimePoints: (json['onTimePoints'] ?? 0.5).toDouble(),
      latePoints: (json['latePoints'] ?? -1).toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'onTimePoints': onTimePoints,
    'latePoints': latePoints,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Default settings
  factory AttendancePointsSettings.defaults() {
    return AttendancePointsSettings(
      onTimePoints: 0.5,
      latePoints: -1,
    );
  }

  /// Calculate points based on attendance status
  double calculatePoints(bool isOnTime) {
    return isOnTime ? onTimePoints : latePoints;
  }

  AttendancePointsSettings copyWith({
    double? onTimePoints,
    double? latePoints,
  }) {
    return AttendancePointsSettings(
      id: id,
      category: category,
      onTimePoints: onTimePoints ?? this.onTimePoints,
      latePoints: latePoints ?? this.latePoints,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Model for shift points settings (Пересменка)
class ShiftPointsSettings {
  final String id;
  final String category;
  final double minPoints;     // Points for rating 1 (worst)
  final int zeroThreshold;    // Rating that gives 0 points
  final double maxPoints;     // Points for rating 10 (best)
  final int minRating;        // Fixed: 1
  final int maxRating;        // Fixed: 10
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ShiftPointsSettings({
    this.id = 'shift_points',
    this.category = 'shift',
    required this.minPoints,
    required this.zeroThreshold,
    required this.maxPoints,
    this.minRating = 1,
    this.maxRating = 10,
    this.createdAt,
    this.updatedAt,
  });

  factory ShiftPointsSettings.fromJson(Map<String, dynamic> json) {
    return ShiftPointsSettings(
      id: json['id'] ?? 'shift_points',
      category: json['category'] ?? 'shift',
      minPoints: (json['minPoints'] ?? -3).toDouble(),
      zeroThreshold: json['zeroThreshold'] ?? 7,
      maxPoints: (json['maxPoints'] ?? 2).toDouble(),
      minRating: json['minRating'] ?? 1,
      maxRating: json['maxRating'] ?? 10,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'minPoints': minPoints,
    'zeroThreshold': zeroThreshold,
    'maxPoints': maxPoints,
    'minRating': minRating,
    'maxRating': maxRating,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Default settings
  factory ShiftPointsSettings.defaults() {
    return ShiftPointsSettings(
      minPoints: -3,
      zeroThreshold: 7,
      maxPoints: 2,
    );
  }

  /// Calculate efficiency points for a given rating using linear interpolation
  double calculatePoints(int rating) {
    if (rating <= minRating) return minPoints;
    if (rating >= maxRating) return maxPoints;

    if (rating <= zeroThreshold) {
      // Interpolate from minPoints to 0 (rating: 1 -> zeroThreshold)
      final range = zeroThreshold - minRating;
      return minPoints + (0 - minPoints) * ((rating - minRating) / range);
    } else {
      // Interpolate from 0 to maxPoints (rating: zeroThreshold -> 10)
      final range = maxRating - zeroThreshold;
      return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
    }
  }

  ShiftPointsSettings copyWith({
    double? minPoints,
    int? zeroThreshold,
    double? maxPoints,
  }) {
    return ShiftPointsSettings(
      id: id,
      category: category,
      minPoints: minPoints ?? this.minPoints,
      zeroThreshold: zeroThreshold ?? this.zeroThreshold,
      maxPoints: maxPoints ?? this.maxPoints,
      minRating: minRating,
      maxRating: maxRating,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Model for recount points settings (Пересчет)
class RecountPointsSettings {
  final String id;
  final String category;
  final double minPoints;     // Points for rating 1 (worst)
  final int zeroThreshold;    // Rating that gives 0 points
  final double maxPoints;     // Points for rating 10 (best)
  final int minRating;        // Fixed: 1
  final int maxRating;        // Fixed: 10
  final DateTime? createdAt;
  final DateTime? updatedAt;

  RecountPointsSettings({
    this.id = 'recount_points',
    this.category = 'recount',
    required this.minPoints,
    required this.zeroThreshold,
    required this.maxPoints,
    this.minRating = 1,
    this.maxRating = 10,
    this.createdAt,
    this.updatedAt,
  });

  factory RecountPointsSettings.fromJson(Map<String, dynamic> json) {
    return RecountPointsSettings(
      id: json['id'] ?? 'recount_points',
      category: json['category'] ?? 'recount',
      minPoints: (json['minPoints'] ?? -3).toDouble(),
      zeroThreshold: json['zeroThreshold'] ?? 7,
      maxPoints: (json['maxPoints'] ?? 1).toDouble(),
      minRating: json['minRating'] ?? 1,
      maxRating: json['maxRating'] ?? 10,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'minPoints': minPoints,
    'zeroThreshold': zeroThreshold,
    'maxPoints': maxPoints,
    'minRating': minRating,
    'maxRating': maxRating,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Default settings
  factory RecountPointsSettings.defaults() {
    return RecountPointsSettings(
      minPoints: -3,
      zeroThreshold: 7,
      maxPoints: 1,
    );
  }

  /// Calculate efficiency points for a given rating using linear interpolation
  double calculatePoints(int rating) {
    if (rating <= minRating) return minPoints;
    if (rating >= maxRating) return maxPoints;

    if (rating <= zeroThreshold) {
      // Interpolate from minPoints to 0 (rating: 1 -> zeroThreshold)
      final range = zeroThreshold - minRating;
      return minPoints + (0 - minPoints) * ((rating - minRating) / range);
    } else {
      // Interpolate from 0 to maxPoints (rating: zeroThreshold -> 10)
      final range = maxRating - zeroThreshold;
      return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
    }
  }

  RecountPointsSettings copyWith({
    double? minPoints,
    int? zeroThreshold,
    double? maxPoints,
  }) {
    return RecountPointsSettings(
      id: id,
      category: category,
      minPoints: minPoints ?? this.minPoints,
      zeroThreshold: zeroThreshold ?? this.zeroThreshold,
      maxPoints: maxPoints ?? this.maxPoints,
      minRating: minRating,
      maxRating: maxRating,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Model for RKO points settings (РКО)
class RkoPointsSettings {
  final String id;
  final String category;
  final double hasRkoPoints;  // Points when RKO exists
  final double noRkoPoints;   // Points when no RKO (negative)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  RkoPointsSettings({
    this.id = 'rko_points',
    this.category = 'rko',
    required this.hasRkoPoints,
    required this.noRkoPoints,
    this.createdAt,
    this.updatedAt,
  });

  factory RkoPointsSettings.fromJson(Map<String, dynamic> json) {
    return RkoPointsSettings(
      id: json['id'] ?? 'rko_points',
      category: json['category'] ?? 'rko',
      hasRkoPoints: (json['hasRkoPoints'] ?? 1).toDouble(),
      noRkoPoints: (json['noRkoPoints'] ?? -3).toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'hasRkoPoints': hasRkoPoints,
    'noRkoPoints': noRkoPoints,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Default settings
  factory RkoPointsSettings.defaults() {
    return RkoPointsSettings(
      hasRkoPoints: 1,
      noRkoPoints: -3,
    );
  }

  /// Calculate points based on RKO status
  double calculatePoints(bool hasRko) {
    return hasRko ? hasRkoPoints : noRkoPoints;
  }

  RkoPointsSettings copyWith({
    double? hasRkoPoints,
    double? noRkoPoints,
  }) {
    return RkoPointsSettings(
      id: id,
      category: category,
      hasRkoPoints: hasRkoPoints ?? this.hasRkoPoints,
      noRkoPoints: noRkoPoints ?? this.noRkoPoints,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Model for shift handover points settings (Сдать смену)
class ShiftHandoverPointsSettings {
  final String id;
  final String category;
  final double minPoints;     // Points for rating 1 (worst)
  final int zeroThreshold;    // Rating that gives 0 points
  final double maxPoints;     // Points for rating 10 (best)
  final int minRating;        // Fixed: 1
  final int maxRating;        // Fixed: 10
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ShiftHandoverPointsSettings({
    this.id = 'shift_handover_points',
    this.category = 'shift_handover',
    required this.minPoints,
    required this.zeroThreshold,
    required this.maxPoints,
    this.minRating = 1,
    this.maxRating = 10,
    this.createdAt,
    this.updatedAt,
  });

  factory ShiftHandoverPointsSettings.fromJson(Map<String, dynamic> json) {
    return ShiftHandoverPointsSettings(
      id: json['id'] ?? 'shift_handover_points',
      category: json['category'] ?? 'shift_handover',
      minPoints: (json['minPoints'] ?? -3).toDouble(),
      zeroThreshold: json['zeroThreshold'] ?? 7,
      maxPoints: (json['maxPoints'] ?? 1).toDouble(),
      minRating: json['minRating'] ?? 1,
      maxRating: json['maxRating'] ?? 10,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'minPoints': minPoints,
    'zeroThreshold': zeroThreshold,
    'maxPoints': maxPoints,
    'minRating': minRating,
    'maxRating': maxRating,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Default settings
  factory ShiftHandoverPointsSettings.defaults() {
    return ShiftHandoverPointsSettings(
      minPoints: -3,
      zeroThreshold: 7,
      maxPoints: 1,
    );
  }

  /// Calculate efficiency points for a given rating using linear interpolation
  double calculatePoints(int rating) {
    if (rating <= minRating) return minPoints;
    if (rating >= maxRating) return maxPoints;

    if (rating <= zeroThreshold) {
      // Interpolate from minPoints to 0 (rating: 1 -> zeroThreshold)
      final range = zeroThreshold - minRating;
      return minPoints + (0 - minPoints) * ((rating - minRating) / range);
    } else {
      // Interpolate from 0 to maxPoints (rating: zeroThreshold -> 10)
      final range = maxRating - zeroThreshold;
      return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
    }
  }

  ShiftHandoverPointsSettings copyWith({
    double? minPoints,
    int? zeroThreshold,
    double? maxPoints,
  }) {
    return ShiftHandoverPointsSettings(
      id: id,
      category: category,
      minPoints: minPoints ?? this.minPoints,
      zeroThreshold: zeroThreshold ?? this.zeroThreshold,
      maxPoints: maxPoints ?? this.maxPoints,
      minRating: minRating,
      maxRating: maxRating,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Model for reviews points settings (Отзывы)
class ReviewsPointsSettings {
  final String id;
  final String category;
  final double positivePoints;  // Points for positive review
  final double negativePoints;  // Points for negative review
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ReviewsPointsSettings({
    this.id = 'reviews_points',
    this.category = 'reviews',
    required this.positivePoints,
    required this.negativePoints,
    this.createdAt,
    this.updatedAt,
  });

  factory ReviewsPointsSettings.fromJson(Map<String, dynamic> json) {
    return ReviewsPointsSettings(
      id: json['id'] ?? 'reviews_points',
      category: json['category'] ?? 'reviews',
      positivePoints: (json['positivePoints'] ?? 3).toDouble(),
      negativePoints: (json['negativePoints'] ?? -5).toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'positivePoints': positivePoints,
    'negativePoints': negativePoints,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Default settings
  factory ReviewsPointsSettings.defaults() {
    return ReviewsPointsSettings(
      positivePoints: 3,
      negativePoints: -5,
    );
  }

  /// Calculate points based on review type
  double calculatePoints(bool isPositive) {
    return isPositive ? positivePoints : negativePoints;
  }

  ReviewsPointsSettings copyWith({
    double? positivePoints,
    double? negativePoints,
  }) {
    return ReviewsPointsSettings(
      id: id,
      category: category,
      positivePoints: positivePoints ?? this.positivePoints,
      negativePoints: negativePoints ?? this.negativePoints,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Model for product search points settings (Поиск товара)
class ProductSearchPointsSettings {
  final String id;
  final String category;
  final double answeredPoints;     // Points for answering on time
  final double notAnsweredPoints;  // Points for not answering
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ProductSearchPointsSettings({
    this.id = 'product_search_points',
    this.category = 'product_search',
    required this.answeredPoints,
    required this.notAnsweredPoints,
    this.createdAt,
    this.updatedAt,
  });

  factory ProductSearchPointsSettings.fromJson(Map<String, dynamic> json) {
    return ProductSearchPointsSettings(
      id: json['id'] ?? 'product_search_points',
      category: json['category'] ?? 'product_search',
      answeredPoints: (json['answeredPoints'] ?? 0.2).toDouble(),
      notAnsweredPoints: (json['notAnsweredPoints'] ?? -3).toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'answeredPoints': answeredPoints,
    'notAnsweredPoints': notAnsweredPoints,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Default settings
  factory ProductSearchPointsSettings.defaults() {
    return ProductSearchPointsSettings(
      answeredPoints: 0.2,
      notAnsweredPoints: -3,
    );
  }

  /// Calculate points based on response status
  double calculatePoints(bool answered) {
    return answered ? answeredPoints : notAnsweredPoints;
  }

  ProductSearchPointsSettings copyWith({
    double? answeredPoints,
    double? notAnsweredPoints,
  }) {
    return ProductSearchPointsSettings(
      id: id,
      category: category,
      answeredPoints: answeredPoints ?? this.answeredPoints,
      notAnsweredPoints: notAnsweredPoints ?? this.notAnsweredPoints,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Model for orders points settings (Заказы клиентов)
class OrdersPointsSettings {
  final String id;
  final String category;
  final double acceptedPoints;   // Points for accepting order
  final double rejectedPoints;   // Points for rejecting order
  final DateTime? createdAt;
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'acceptedPoints': acceptedPoints,
    'rejectedPoints': rejectedPoints,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Default settings
  factory OrdersPointsSettings.defaults() {
    return OrdersPointsSettings(
      acceptedPoints: 0.2,
      rejectedPoints: -3,
    );
  }

  /// Calculate points based on order status
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

/// Model for regular task points settings (Обычные задачи)
class RegularTaskPointsSettings {
  final double completionPoints;  // Премия за выполнение
  final double penaltyPoints;     // Штраф за невыполнение

  RegularTaskPointsSettings({
    required this.completionPoints,
    required this.penaltyPoints,
  });

  factory RegularTaskPointsSettings.defaults() {
    return RegularTaskPointsSettings(
      completionPoints: 1.0,
      penaltyPoints: -3.0,
    );
  }

  factory RegularTaskPointsSettings.fromJson(Map<String, dynamic> json) {
    return RegularTaskPointsSettings(
      completionPoints: (json['completionPoints'] as num?)?.toDouble() ?? 1.0,
      penaltyPoints: (json['penaltyPoints'] as num?)?.toDouble() ?? -3.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completionPoints': completionPoints,
      'penaltyPoints': penaltyPoints,
    };
  }
}

/// Model for recurring task points settings (Циклические задачи)
class RecurringTaskPointsSettings {
  final double completionPoints;  // Премия за выполнение
  final double penaltyPoints;     // Штраф за невыполнение

  RecurringTaskPointsSettings({
    required this.completionPoints,
    required this.penaltyPoints,
  });

  factory RecurringTaskPointsSettings.defaults() {
    return RecurringTaskPointsSettings(
      completionPoints: 2.0,
      penaltyPoints: -3.0,  // Текущее значение в recurring_tasks_api.js
    );
  }

  factory RecurringTaskPointsSettings.fromJson(Map<String, dynamic> json) {
    return RecurringTaskPointsSettings(
      completionPoints: (json['completionPoints'] as num?)?.toDouble() ?? 2.0,
      penaltyPoints: (json['penaltyPoints'] as num?)?.toDouble() ?? -3.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'completionPoints': completionPoints,
      'penaltyPoints': penaltyPoints,
    };
  }
}

/// Model for envelope points settings (Конверт)
class EnvelopePointsSettings {
  final String id;
  final String category;
  final double submittedPoints;   // Баллы за сданный конверт
  final double notSubmittedPoints; // Штраф за несданный конверт
  final DateTime? createdAt;
  final DateTime? updatedAt;

  EnvelopePointsSettings({
    this.id = 'envelope_points',
    this.category = 'envelope',
    required this.submittedPoints,
    required this.notSubmittedPoints,
    this.createdAt,
    this.updatedAt,
  });

  factory EnvelopePointsSettings.fromJson(Map<String, dynamic> json) {
    return EnvelopePointsSettings(
      id: json['id'] ?? 'envelope_points',
      category: json['category'] ?? 'envelope',
      submittedPoints: (json['submittedPoints'] ?? 1.0).toDouble(),
      notSubmittedPoints: (json['notSubmittedPoints'] ?? -3.0).toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'submittedPoints': submittedPoints,
    'notSubmittedPoints': notSubmittedPoints,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  /// Default settings
  factory EnvelopePointsSettings.defaults() {
    return EnvelopePointsSettings(
      submittedPoints: 1.0,
      notSubmittedPoints: -3.0,
    );
  }

  /// Calculate points based on envelope submission status
  double calculatePoints(bool submitted) {
    return submitted ? submittedPoints : notSubmittedPoints;
  }

  EnvelopePointsSettings copyWith({
    double? submittedPoints,
    double? notSubmittedPoints,
  }) {
    return EnvelopePointsSettings(
      id: id,
      category: category,
      submittedPoints: submittedPoints ?? this.submittedPoints,
      notSubmittedPoints: notSubmittedPoints ?? this.notSubmittedPoints,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
