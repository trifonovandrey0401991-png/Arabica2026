import 'package:arabica_app/core/utils/date_formatter.dart';
import '../../models/efficiency_data_model.dart';
import '../efficiency_calculation_service.dart';
import '../../../../core/utils/logger.dart';

/// Парсеры для batch API ответов
///
/// Эти функции преобразуют сырые данные из batch API в EfficiencyRecord.
/// Извлечены из efficiency_data_service.dart для лучшей организации кода.

/// Парсинг shift reports из batch API
Future<List<EfficiencyRecord>> parseShiftReportsFromBatch(
  List<dynamic> rawReports,
  DateTime start,
  DateTime end,
) async {
  final records = <EfficiencyRecord>[];

  for (final json in rawReports) {
    try {
      final createdAt = parseServerDate(json['createdAt']);
      final timestamp = parseServerDate(json['timestamp']);
      final reportDate = createdAt ?? timestamp;

      if (reportDate == null) continue;

      // Проверяем период
      if (reportDate.isBefore(start) || reportDate.isAfter(end)) {
        continue;
      }

      final rating = json['rating'] as int?;
      if (rating == null || rating < 1) {
        continue; // Пропускаем неоцененные отчеты
      }

      final record = await EfficiencyCalculationService.createShiftRecord(
        id: json['id'] ?? 'unknown',
        shopAddress: json['shopAddress'] ?? '',
        employeeName: json['employeeName'] ?? '',
        employeePhone: json['employeePhone'] ?? '',
        date: parseServerDate(json['confirmedAt']) ?? reportDate,
        rating: rating,
      );

      if (record != null) {
        records.add(record);
      }
    } catch (e) {
      Logger.error('Error parsing shift report from batch', e);
    }
  }

  return records;
}

/// Парсинг recount reports из batch API
Future<List<EfficiencyRecord>> parseRecountReportsFromBatch(
  List<dynamic> rawReports,
  DateTime start,
  DateTime end,
) async {
  final records = <EfficiencyRecord>[];

  for (final json in rawReports) {
    try {
      final completedAt = parseServerDate(json['completedAt']);
      final createdAt = parseServerDate(json['createdAt']);
      final reportDate = completedAt ?? createdAt;

      if (reportDate == null) continue;

      // Проверяем период
      if (reportDate.isBefore(start) || reportDate.isAfter(end)) {
        continue;
      }

      final adminRating = json['adminRating'] as int?;
      if (adminRating == null || adminRating < 1) {
        continue; // Пропускаем неоцененные отчеты
      }

      final record = await EfficiencyCalculationService.createRecountRecord(
        id: json['id'] ?? 'unknown',
        shopAddress: json['shopAddress'] ?? '',
        employeeName: json['employeeName'] ?? '',
        employeePhone: json['employeePhone'] ?? '',
        date: parseServerDate(json['ratedAt']) ?? reportDate,
        adminRating: adminRating,
      );

      if (record != null) {
        records.add(record);
      }
    } catch (e) {
      Logger.error('Error parsing recount report from batch', e);
    }
  }

  return records;
}

/// Парсинг shift handover reports из batch API
Future<List<EfficiencyRecord>> parseHandoverReportsFromBatch(
  List<dynamic> rawReports,
  DateTime start,
  DateTime end,
) async {
  final records = <EfficiencyRecord>[];

  for (final json in rawReports) {
    try {
      final createdAt = parseServerDate(json['createdAt']);

      if (createdAt == null) continue;

      // Проверяем период
      if (createdAt.isBefore(start) || createdAt.isAfter(end)) {
        continue;
      }

      final rating = json['rating'] as int?;
      if (rating == null || rating < 1) {
        continue; // Пропускаем неоцененные отчеты
      }

      final record = await EfficiencyCalculationService.createShiftHandoverRecord(
        id: json['id'] ?? 'unknown',
        shopAddress: json['shopAddress'] ?? '',
        employeeName: json['employeeName'] ?? '',
        employeePhone: json['employeePhone'] ?? '',
        date: parseServerDate(json['confirmedAt']) ?? createdAt,
        rating: rating,
      );

      if (record != null) {
        records.add(record);
      }
    } catch (e) {
      Logger.error('Error parsing shift handover report from batch', e);
    }
  }

  return records;
}

/// Парсинг attendance records из batch API
Future<List<EfficiencyRecord>> parseAttendanceFromBatch(
  List<dynamic> rawRecords,
  DateTime start,
  DateTime end,
) async {
  final records = <EfficiencyRecord>[];

  for (final json in rawRecords) {
    try {
      final timestamp = parseServerDate(json['timestamp']);
      final createdAt = parseServerDate(json['createdAt']);
      final recordDate = timestamp ?? createdAt;

      if (recordDate == null) continue;

      // Проверяем период
      if (recordDate.isBefore(start) || recordDate.isAfter(end)) {
        continue;
      }

      // isOnTime может быть null если сотрудник отметился вне смены
      final isOnTime = json['isOnTime'] as bool?;
      if (isOnTime == null) {
        continue;
      }

      final record = await EfficiencyCalculationService.createAttendanceRecord(
        id: json['id'] ?? 'unknown',
        shopAddress: json['shopAddress'] ?? '',
        employeeName: json['employeeName'] ?? '',
        employeePhone: json['employeePhone'] ?? '',
        date: recordDate,
        isOnTime: isOnTime,
      );

      records.add(record);
    } catch (e) {
      Logger.error('Error parsing attendance record from batch', e);
    }
  }

  return records;
}
