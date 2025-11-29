import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Модель ответа на вопрос
class ShiftAnswer {
  final String question;
  final String? textAnswer;
  final double? numberAnswer;
  final String? photoPath; // Путь к локальному фото
  final String? photoDriveId; // ID фото в Google Drive после загрузки

  ShiftAnswer({
    required this.question,
    this.textAnswer,
    this.numberAnswer,
    this.photoPath,
    this.photoDriveId,
  });

  Map<String, dynamic> toJson() => {
    'question': question,
    'textAnswer': textAnswer,
    'numberAnswer': numberAnswer,
    'photoPath': photoPath,
    'photoDriveId': photoDriveId,
  };

  factory ShiftAnswer.fromJson(Map<String, dynamic> json) => ShiftAnswer(
    question: json['question'] ?? '',
    textAnswer: json['textAnswer'],
    numberAnswer: json['numberAnswer']?.toDouble(),
    photoPath: json['photoPath'],
    photoDriveId: json['photoDriveId'],
  );
}

/// Модель отчета пересменки
class ShiftReport {
  final String id;
  final String employeeName;
  final String shopAddress;
  final DateTime createdAt;
  final List<ShiftAnswer> answers;
  final bool isSynced; // Синхронизирован ли с облаком

  ShiftReport({
    required this.id,
    required this.employeeName,
    required this.shopAddress,
    required this.createdAt,
    required this.answers,
    this.isSynced = false,
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
    'shopAddress': shopAddress,
    'createdAt': createdAt.toIso8601String(),
    'answers': answers.map((a) => a.toJson()).toList(),
    'isSynced': isSynced,
  };

  factory ShiftReport.fromJson(Map<String, dynamic> json) => ShiftReport(
    id: json['id'] ?? '',
    employeeName: json['employeeName'] ?? '',
    shopAddress: json['shopAddress'] ?? '',
    createdAt: DateTime.parse(json['createdAt']),
    answers: (json['answers'] as List<dynamic>?)
        ?.map((a) => ShiftAnswer.fromJson(a))
        .toList() ?? [],
    isSynced: json['isSynced'] ?? false,
  );

  /// Проверить, старше ли недели
  bool get isOlderThanWeek {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inDays > 7;
  }

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
        print('⚠️ Ошибка парсинга отчета: $e');
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

