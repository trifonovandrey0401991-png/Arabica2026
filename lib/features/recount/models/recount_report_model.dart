import 'recount_answer_model.dart';

/// Статусы отчёта пересчёта (аналог ShiftReportStatus)
enum RecountReportStatus {
  pending,    // Ожидает прохождения (создан scheduler-ом)
  review,     // На проверке у админа (сотрудник отправил)
  confirmed,  // Подтверждён (админ оценил)
  failed,     // Не прошёл вовремя (дедлайн истёк)
  rejected,   // Админ не проверил вовремя (таймаут проверки)
  expired,    // Просрочен (устаревший статус для совместимости)
}

/// Модель отчета пересчета
class RecountReport {
  final String id;
  final String employeeName;
  final String shopAddress;
  final String? employeePhone; // Телефон сотрудника для верификации фото
  final DateTime startedAt;
  final DateTime completedAt;
  final Duration duration;
  final List<RecountAnswer> answers;
  final int? adminRating; // Оценка админа (1-10)
  final String? adminName; // Имя админа, поставившего оценку
  final DateTime? ratedAt; // Время оценки
  final String? status; // "pending" | "review" | "confirmed" | "failed" | "rejected" | "expired"
  final DateTime? expiredAt; // Когда был просрочен
  final List<Map<String, dynamic>>? photoVerifications; // Верификация фото

  // Новые поля (аналогично ShiftReport)
  final String? shiftType; // "morning" | "evening" - тип смены
  final DateTime? submittedAt; // Время отправки отчёта
  final DateTime? reviewDeadline; // Дедлайн проверки админом
  final DateTime? failedAt; // Время перехода в статус failed
  final DateTime? rejectedAt; // Время авто-отклонения (админ не проверил)

  RecountReport({
    required this.id,
    required this.employeeName,
    required this.shopAddress,
    this.employeePhone,
    required this.startedAt,
    required this.completedAt,
    required this.duration,
    required this.answers,
    this.adminRating,
    this.adminName,
    this.ratedAt,
    this.status,
    this.expiredAt,
    this.photoVerifications,
    this.shiftType,
    this.submittedAt,
    this.reviewDeadline,
    this.failedAt,
    this.rejectedAt,
  });

  /// Генерировать уникальный ID
  static String generateId(String employeeName, String shopAddress, DateTime createdAt) {
    final dateStr = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
    final timeStr = '${createdAt.hour.toString().padLeft(2, '0')}-${createdAt.minute.toString().padLeft(2, '0')}-${createdAt.second.toString().padLeft(2, '0')}';
    return 'recount_${employeeName}_${shopAddress}_${dateStr}_$timeStr';
  }

  /// Форматировать длительность в "X минут Y секунд"
  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '$minutes минут${minutes == 1 ? 'а' : minutes < 5 ? 'ы' : ''} $seconds секунд${seconds == 1 ? 'а' : seconds < 5 ? 'ы' : ''}';
    } else {
      return '$seconds секунд${seconds == 1 ? 'а' : seconds < 5 ? 'ы' : ''}';
    }
  }

  /// Проверить, оценен ли отчет
  bool get isRated => adminRating != null || status == 'confirmed';

  /// Проверить, просрочен ли отчет
  bool get isExpired => status == 'expired' || expiredAt != null;

  /// Проверить, ожидает ли прохождения
  bool get isPending => status == 'pending';

  /// Проверить, на проверке ли у админа
  bool get isInReview => status == 'review';

  /// Проверить, не прошёл ли вовремя
  bool get isFailed => status == 'failed' || failedAt != null;

  /// Проверить, отклонён ли (админ не проверил вовремя)
  bool get isRejected => status == 'rejected' || rejectedAt != null;

  /// Проверить, подтверждён ли
  bool get isConfirmed => status == 'confirmed';

  /// Получить статус как enum
  RecountReportStatus get statusEnum {
    switch (status) {
      case 'pending':
        return RecountReportStatus.pending;
      case 'review':
        return RecountReportStatus.review;
      case 'confirmed':
        return RecountReportStatus.confirmed;
      case 'failed':
        return RecountReportStatus.failed;
      case 'rejected':
        return RecountReportStatus.rejected;
      case 'expired':
        return RecountReportStatus.expired;
      case 'rated': // Для обратной совместимости
        return RecountReportStatus.confirmed;
      default:
        // Определяем статус по полям
        if (adminRating != null) return RecountReportStatus.confirmed;
        if (failedAt != null) return RecountReportStatus.failed;
        if (rejectedAt != null) return RecountReportStatus.rejected;
        if (expiredAt != null) return RecountReportStatus.expired;
        if (submittedAt != null) return RecountReportStatus.review;
        return RecountReportStatus.pending;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeName': employeeName,
    'shopAddress': shopAddress,
    'employeePhone': employeePhone,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'duration': duration.inSeconds,
    'answers': answers.map((a) => a.toJson()).toList(),
    'adminRating': adminRating,
    'adminName': adminName,
    'ratedAt': ratedAt?.toIso8601String(),
    'status': status,
    'expiredAt': expiredAt?.toIso8601String(),
    'photoVerifications': photoVerifications,
    'shiftType': shiftType,
    'submittedAt': submittedAt?.toIso8601String(),
    'reviewDeadline': reviewDeadline?.toIso8601String(),
    'failedAt': failedAt?.toIso8601String(),
    'rejectedAt': rejectedAt?.toIso8601String(),
  };

  factory RecountReport.fromJson(Map<String, dynamic> json) {
    // Обрабатываем даты с fallback на createdAt/savedAt
    DateTime parseDateTime(dynamic value, DateTime? fallback) {
      if (value == null) {
        if (fallback != null) return fallback;
        return DateTime.now(); // Последний fallback
      }
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return fallback ?? DateTime.now();
        }
      }
      return fallback ?? DateTime.now();
    }

    final createdAt = json['createdAt'] != null 
        ? (json['createdAt'] is String ? DateTime.parse(json['createdAt']) : null)
        : null;
    final savedAt = json['savedAt'] != null
        ? (json['savedAt'] is String ? DateTime.parse(json['savedAt']) : null)
        : null;

    final startedAt = parseDateTime(json['startedAt'], createdAt);
    final completedAt = parseDateTime(json['completedAt'], savedAt ?? createdAt);

    // Вычисляем duration, если его нет
    Duration duration;
    if (json['duration'] != null) {
      duration = Duration(seconds: json['duration'] is int ? json['duration'] : 0);
    } else if (startedAt != null && completedAt != null) {
      duration = completedAt.difference(startedAt);
    } else {
      duration = Duration.zero;
    }

    return RecountReport(
      id: json['id']?.toString() ?? '',
      employeeName: json['employeeName']?.toString() ?? '',
      shopAddress: json['shopAddress']?.toString() ?? '',
      employeePhone: json['employeePhone']?.toString(),
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      answers: (json['answers'] as List<dynamic>?)
          ?.map((a) => RecountAnswer.fromJson(a as Map<String, dynamic>))
          .toList() ?? [],
      adminRating: json['adminRating'] is int ? json['adminRating'] : null,
      adminName: json['adminName']?.toString(),
      ratedAt: json['ratedAt'] != null && json['ratedAt'] is String
          ? DateTime.tryParse(json['ratedAt'])
          : null,
      status: json['status']?.toString(),
      expiredAt: json['expiredAt'] != null && json['expiredAt'] is String
          ? DateTime.tryParse(json['expiredAt'])
          : null,
      photoVerifications: (json['photoVerifications'] as List<dynamic>?)
          ?.map((v) => v as Map<String, dynamic>)
          .toList(),
      shiftType: json['shiftType']?.toString(),
      submittedAt: json['submittedAt'] != null && json['submittedAt'] is String
          ? DateTime.tryParse(json['submittedAt'])
          : null,
      reviewDeadline: json['reviewDeadline'] != null && json['reviewDeadline'] is String
          ? DateTime.tryParse(json['reviewDeadline'])
          : null,
      failedAt: json['failedAt'] != null && json['failedAt'] is String
          ? DateTime.tryParse(json['failedAt'])
          : null,
      rejectedAt: json['rejectedAt'] != null && json['rejectedAt'] is String
          ? DateTime.tryParse(json['rejectedAt'])
          : null,
    );
  }

  /// Создать копию с обновленными полями
  RecountReport copyWith({
    int? adminRating,
    String? adminName,
    DateTime? ratedAt,
    String? status,
    DateTime? expiredAt,
    String? shiftType,
    DateTime? submittedAt,
    DateTime? reviewDeadline,
    DateTime? failedAt,
    DateTime? rejectedAt,
  }) {
    return RecountReport(
      id: id,
      employeeName: employeeName,
      shopAddress: shopAddress,
      employeePhone: employeePhone,
      startedAt: startedAt,
      completedAt: completedAt,
      duration: duration,
      answers: answers,
      adminRating: adminRating ?? this.adminRating,
      adminName: adminName ?? this.adminName,
      ratedAt: ratedAt ?? this.ratedAt,
      status: status ?? this.status,
      expiredAt: expiredAt ?? this.expiredAt,
      photoVerifications: photoVerifications,
      shiftType: shiftType ?? this.shiftType,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewDeadline: reviewDeadline ?? this.reviewDeadline,
      failedAt: failedAt ?? this.failedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
    );
  }
}

