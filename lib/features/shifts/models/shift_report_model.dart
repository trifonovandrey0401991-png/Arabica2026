import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';

/// Статусы отчёта пересменки
enum ShiftReportStatus {
  pending,    // Ожидает (сотрудник должен пройти пересменку)
  review,     // На проверке (отправлен, ожидает оценки админа)
  confirmed,  // Подтверждён (админ оценил)
  failed,     // Не пройден (сотрудник не прошёл до дедлайна)
  rejected,   // Отклонён (админ не оценил вовремя → автоматический отказ)
  expired,    // Устаревший (> 7 дней)
}

extension ShiftReportStatusExtension on ShiftReportStatus {
  String get name {
    switch (this) {
      case ShiftReportStatus.pending:
        return 'pending';
      case ShiftReportStatus.review:
        return 'review';
      case ShiftReportStatus.confirmed:
        return 'confirmed';
      case ShiftReportStatus.failed:
        return 'failed';
      case ShiftReportStatus.rejected:
        return 'rejected';
      case ShiftReportStatus.expired:
        return 'expired';
    }
  }

  String get label {
    switch (this) {
      case ShiftReportStatus.pending:
        return 'Ожидает';
      case ShiftReportStatus.review:
        return 'На проверке';
      case ShiftReportStatus.confirmed:
        return 'Подтверждён';
      case ShiftReportStatus.failed:
        return 'Не пройден';
      case ShiftReportStatus.rejected:
        return 'Отклонён';
      case ShiftReportStatus.expired:
        return 'Истёк';
    }
  }

  static ShiftReportStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'pending':
        return ShiftReportStatus.pending;
      case 'review':
        return ShiftReportStatus.review;
      case 'confirmed':
        return ShiftReportStatus.confirmed;
      case 'failed':
        return ShiftReportStatus.failed;
      case 'rejected':
        return ShiftReportStatus.rejected;
      case 'expired':
        return ShiftReportStatus.expired;
      default:
        return ShiftReportStatus.pending;
    }
  }
}

/// Модель ответа на вопрос
class ShiftAnswer {
  final String question;
  final String? textAnswer;
  final double? numberAnswer;
  final String? photoPath; // Путь к локальному фото
  final String? photoDriveId; // ID фото в Google Drive после загрузки
  final String? referencePhotoUrl; // URL эталонного фото, которое было показано сотруднику

  ShiftAnswer({
    required this.question,
    this.textAnswer,
    this.numberAnswer,
    this.photoPath,
    this.photoDriveId,
    this.referencePhotoUrl,
  });

  Map<String, dynamic> toJson() => {
    'question': question,
    'textAnswer': textAnswer,
    'numberAnswer': numberAnswer,
    'photoPath': photoPath,
    'photoDriveId': photoDriveId,
    if (referencePhotoUrl != null) 'referencePhotoUrl': referencePhotoUrl,
  };

  factory ShiftAnswer.fromJson(Map<String, dynamic> json) => ShiftAnswer(
    question: json['question'] ?? '',
    textAnswer: json['textAnswer'],
    numberAnswer: json['numberAnswer']?.toDouble(),
    photoPath: json['photoPath'],
    photoDriveId: json['photoDriveId'],
    referencePhotoUrl: json['referencePhotoUrl'],
  );
}

/// Модель отчета пересменки
class ShiftReport {
  final String id;
  final String employeeName;
  final String? employeeId; // ID сотрудника для связи с графиком
  final String shopAddress;
  final String? shopName; // Название магазина
  final DateTime createdAt;
  final List<ShiftAnswer> answers;
  final bool isSynced; // Синхронизирован ли с облаком
  final DateTime? confirmedAt; // Время подтверждения отчета
  final int? rating; // Оценка от 1 до 10
  final String? confirmedByAdmin; // Имя админа, который подтвердил
  final String? status; // "pending" | "review" | "confirmed" | "failed" | "rejected" | "expired"
  final DateTime? expiredAt; // Когда был просрочен

  // Новые поля для автоматизации
  final String? shiftType; // "morning" | "evening" - тип смены
  final DateTime? submittedAt; // Время отправки отчёта сотрудником
  final DateTime? reviewDeadline; // Дедлайн для проверки админом
  final DateTime? failedAt; // Время когда был отмечен как failed
  final DateTime? rejectedAt; // Время автоматического отклонения

  ShiftReport({
    required this.id,
    required this.employeeName,
    this.employeeId,
    required this.shopAddress,
    this.shopName,
    required this.createdAt,
    required this.answers,
    this.isSynced = false,
    this.confirmedAt,
    this.rating,
    this.confirmedByAdmin,
    this.status,
    this.expiredAt,
    this.shiftType,
    this.submittedAt,
    this.reviewDeadline,
    this.failedAt,
    this.rejectedAt,
  });

  /// Генерировать уникальный ID на основе комбинации
  static String generateId(String employeeName, String shopAddress, DateTime createdAt) {
    final dateStr = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
    final timeStr = '${createdAt.hour.toString().padLeft(2, '0')}-${createdAt.minute.toString().padLeft(2, '0')}-${createdAt.second.toString().padLeft(2, '0')}';
    return '${employeeName}_${shopAddress}_${dateStr}_$timeStr';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeName': employeeName,
    'employeeId': employeeId,
    'shopAddress': shopAddress,
    'shopName': shopName,
    'createdAt': createdAt.toIso8601String(),
    'answers': answers.map((a) => a.toJson()).toList(),
    'isSynced': isSynced,
    'confirmedAt': confirmedAt?.toIso8601String(),
    'rating': rating,
    'confirmedByAdmin': confirmedByAdmin,
    'status': status,
    'expiredAt': expiredAt?.toIso8601String(),
    'shiftType': shiftType,
    'submittedAt': submittedAt?.toIso8601String(),
    'reviewDeadline': reviewDeadline?.toIso8601String(),
    'failedAt': failedAt?.toIso8601String(),
    'rejectedAt': rejectedAt?.toIso8601String(),
  };

  factory ShiftReport.fromJson(Map<String, dynamic> json) => ShiftReport(
    id: json['id'] ?? '',
    employeeName: json['employeeName'] ?? '',
    employeeId: json['employeeId'],
    shopAddress: json['shopAddress'] ?? '',
    shopName: json['shopName'],
    createdAt: DateTime.parse(json['createdAt']),
    answers: (json['answers'] as List<dynamic>?)
        ?.map((a) => ShiftAnswer.fromJson(a))
        .toList() ?? [],
    isSynced: json['isSynced'] ?? false,
    confirmedAt: json['confirmedAt'] != null
        ? DateTime.parse(json['confirmedAt'])
        : null,
    rating: json['rating'],
    confirmedByAdmin: json['confirmedByAdmin'],
    status: json['status'],
    expiredAt: json['expiredAt'] != null
        ? DateTime.parse(json['expiredAt'])
        : null,
    shiftType: json['shiftType'],
    submittedAt: json['submittedAt'] != null
        ? DateTime.parse(json['submittedAt'])
        : null,
    reviewDeadline: json['reviewDeadline'] != null
        ? DateTime.parse(json['reviewDeadline'])
        : null,
    failedAt: json['failedAt'] != null
        ? DateTime.parse(json['failedAt'])
        : null,
    rejectedAt: json['rejectedAt'] != null
        ? DateTime.parse(json['rejectedAt'])
        : null,
  );

  /// Проверить, старше ли недели
  bool get isOlderThanWeek {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inDays > 7;
  }

  /// Проверить, подтвержден ли отчет
  bool get isConfirmed => confirmedAt != null;

  /// Проверить, просрочен ли отчет (> 24ч без подтверждения)
  bool get isExpired => status == 'expired' || expiredAt != null;

  /// Проверить, не подтвержден ли отчет в течение 6 часов
  bool get isNotVerified {
    if (isConfirmed) return false;
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inHours >= 6;
  }

  /// Получить статус проверки
  /// Возвращает: 'confirmed' - подтвержден, 'not_verified' - не проверен (6+ часов), 'pending' - ожидает проверки
  String get verificationStatus {
    if (isConfirmed) return 'confirmed';
    if (isNotVerified) return 'not_verified';
    return 'pending';
  }

  /// Создать копию отчета с обновленными полями
  ShiftReport copyWith({
    DateTime? confirmedAt,
    int? rating,
    String? confirmedByAdmin,
    String? status,
    DateTime? expiredAt,
    String? shiftType,
    DateTime? submittedAt,
    DateTime? reviewDeadline,
    DateTime? failedAt,
    DateTime? rejectedAt,
  }) {
    return ShiftReport(
      id: id,
      employeeName: employeeName,
      employeeId: employeeId,
      shopAddress: shopAddress,
      shopName: shopName,
      createdAt: createdAt,
      answers: answers,
      isSynced: isSynced,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      rating: rating ?? this.rating,
      confirmedByAdmin: confirmedByAdmin ?? this.confirmedByAdmin,
      status: status ?? this.status,
      expiredAt: expiredAt ?? this.expiredAt,
      shiftType: shiftType ?? this.shiftType,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewDeadline: reviewDeadline ?? this.reviewDeadline,
      failedAt: failedAt ?? this.failedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
    );
  }

  /// Получить статус как enum
  ShiftReportStatus get statusEnum => ShiftReportStatusExtension.fromString(status);

  /// Отчёт ожидает прохождения
  bool get isPending => status == 'pending' || status == null;

  /// Отчёт на проверке у админа
  bool get isInReview => status == 'review';

  /// Отчёт не пройден (сотрудник не успел)
  bool get isFailed => status == 'failed';

  /// Отчёт отклонён (админ не успел проверить)
  bool get isRejected => status == 'rejected';

  /// Сохранить отчет локально
  static Future<void> saveReport(ShiftReport report) async {
    final prefs = await SharedPreferences.getInstance();
    final reportsJson = prefs.getStringList('shift_reports') ?? [];
    
    // Удаляем старый отчет с таким же ID, если есть
    reportsJson.removeWhere((jsonStr) {
      try {
        final existing = ShiftReport.fromJson(jsonDecode(jsonStr));
        return existing.id == report.id;
      } catch (e) {
        return false;
      }
    });
    
    reportsJson.add(jsonEncode(report.toJson()));
    await prefs.setStringList('shift_reports', reportsJson);
  }

  /// Загрузить все отчеты
  static Future<List<ShiftReport>> loadAllReports() async {
    final prefs = await SharedPreferences.getInstance();
    final reportsJson = prefs.getStringList('shift_reports') ?? [];
    
    final reports = reportsJson.map((jsonStr) {
      try {
        return ShiftReport.fromJson(jsonDecode(jsonStr));
      } catch (e) {
        Logger.warning('Ошибка парсинга отчета: $e');
        return null;
      }
    }).whereType<ShiftReport>().toList();
    
    // Удаляем отчеты старше недели
    final validReports = reports.where((r) => !r.isOlderThanWeek).toList();
    
    // Если были удалены старые отчеты, сохраняем обновленный список
    if (validReports.length != reports.length) {
      await _saveAllReports(validReports);
    }
    
    validReports.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // Сначала новые
    return validReports;
  }

  /// Сохранить все отчеты
  static Future<void> _saveAllReports(List<ShiftReport> reports) async {
    final prefs = await SharedPreferences.getInstance();
    final reportsJson = reports.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList('shift_reports', reportsJson);
  }

  /// Получить отчеты по магазину
  static Future<List<ShiftReport>> getReportsByShop(String shopAddress) async {
    final allReports = await loadAllReports();
    return allReports.where((r) => r.shopAddress == shopAddress).toList();
  }

  /// Получить уникальные адреса магазинов из отчетов
  static Future<List<String>> getUniqueShopAddresses() async {
    final allReports = await loadAllReports();
    final addresses = allReports.map((r) => r.shopAddress).toSet().toList();
    addresses.sort();
    return addresses;
  }

  /// Удалить отчет
  static Future<void> deleteReport(String reportId) async {
    final allReports = await loadAllReports();
    final updatedReports = allReports.where((r) => r.id != reportId).toList();
    await _saveAllReports(updatedReports);
  }

  /// Обновить отчет (после синхронизации)
  static Future<void> updateReport(ShiftReport report) async {
    await saveReport(report);
  }
}


