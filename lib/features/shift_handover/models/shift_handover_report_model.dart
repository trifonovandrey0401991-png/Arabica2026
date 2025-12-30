import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Модель ответа на вопрос сдачи смены
class ShiftHandoverAnswer {
  final String question;
  final String? textAnswer;
  final double? numberAnswer;
  final String? photoPath; // Путь к локальному фото
  final String? photoUrl; // URL фото на сервере после загрузки
  final String? photoDriveId; // ID фото в Google Drive
  final String? referencePhotoUrl; // URL эталонного фото, которое было показано

  ShiftHandoverAnswer({
    required this.question,
    this.textAnswer,
    this.numberAnswer,
    this.photoPath,
    this.photoUrl,
    this.photoDriveId,
    this.referencePhotoUrl,
  });

  Map<String, dynamic> toJson() => {
    'question': question,
    'textAnswer': textAnswer,
    'numberAnswer': numberAnswer,
    'photoPath': photoPath,
    'photoUrl': photoUrl,
    if (photoDriveId != null) 'photoDriveId': photoDriveId,
    if (referencePhotoUrl != null) 'referencePhotoUrl': referencePhotoUrl,
  };

  factory ShiftHandoverAnswer.fromJson(Map<String, dynamic> json) => ShiftHandoverAnswer(
    question: json['question'] ?? '',
    textAnswer: json['textAnswer'],
    numberAnswer: json['numberAnswer']?.toDouble(),
    photoPath: json['photoPath'],
    photoUrl: json['photoUrl'],
    photoDriveId: json['photoDriveId'],
    referencePhotoUrl: json['referencePhotoUrl'],
  );
}

/// Модель отчета сдачи смены
class ShiftHandoverReport {
  final String id;
  final String employeeName;
  final String shopAddress;
  final DateTime createdAt;
  final List<ShiftHandoverAnswer> answers;
  final bool isSynced; // Синхронизирован ли с сервером
  final DateTime? confirmedAt; // Время подтверждения отчета

  ShiftHandoverReport({
    required this.id,
    required this.employeeName,
    required this.shopAddress,
    required this.createdAt,
    required this.answers,
    this.isSynced = false,
    this.confirmedAt,
  });

  /// Генерировать уникальный ID
  static String generateId(String employeeName, String shopAddress, DateTime createdAt) {
    final dateStr = '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
    final timeStr = '${createdAt.hour.toString().padLeft(2, '0')}-${createdAt.minute.toString().padLeft(2, '0')}-${createdAt.second.toString().padLeft(2, '0')}';
    return 'handover_${employeeName}_${shopAddress}_${dateStr}_$timeStr';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeName': employeeName,
    'shopAddress': shopAddress,
    'createdAt': createdAt.toIso8601String(),
    'answers': answers.map((a) => a.toJson()).toList(),
    'isSynced': isSynced,
    'confirmedAt': confirmedAt?.toIso8601String(),
  };

  factory ShiftHandoverReport.fromJson(Map<String, dynamic> json) => ShiftHandoverReport(
    id: json['id'] ?? '',
    employeeName: json['employeeName'] ?? '',
    shopAddress: json['shopAddress'] ?? '',
    createdAt: DateTime.parse(json['createdAt']),
    answers: (json['answers'] as List<dynamic>?)
        ?.map((a) => ShiftHandoverAnswer.fromJson(a))
        .toList() ?? [],
    isSynced: json['isSynced'] ?? false,
    confirmedAt: json['confirmedAt'] != null
        ? DateTime.parse(json['confirmedAt'])
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

  /// Локальное хранилище
  static const String _storageKey = 'shift_handover_reports';

  /// Сохранить отчет локально
  static Future<void> saveLocal(ShiftHandoverReport report) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reports = await loadAllLocal();

      // Обновляем или добавляем отчет
      final index = reports.indexWhere((r) => r.id == report.id);
      if (index >= 0) {
        reports[index] = report;
      } else {
        reports.add(report);
      }

      final jsonList = reports.map((r) => r.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      print('❌ Ошибка сохранения отчета сдачи смены: $e');
    }
  }

  /// Загрузить все локальные отчеты
  static Future<List<ShiftHandoverReport>> loadAllLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString == null) return [];

      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => ShiftHandoverReport.fromJson(json)).toList();
    } catch (e) {
      print('❌ Ошибка загрузки локальных отчетов сдачи смены: $e');
      return [];
    }
  }

  /// Удалить отчет локально
  static Future<void> deleteLocal(String reportId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reports = await loadAllLocal();

      reports.removeWhere((r) => r.id == reportId);

      final jsonList = reports.map((r) => r.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      print('❌ Ошибка удаления отчета сдачи смены: $e');
    }
  }

  /// Получить несинхронизированные отчеты
  static Future<List<ShiftHandoverReport>> getUnsyncedReports() async {
    final reports = await loadAllLocal();
    return reports.where((r) => !r.isSynced).toList();
  }
}
