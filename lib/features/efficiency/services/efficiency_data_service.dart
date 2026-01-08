import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/efficiency_data_model.dart';
import 'efficiency_calculation_service.dart';
import '../../shifts/services/shift_report_service.dart';
import '../../recount/services/recount_service.dart';
import '../../shift_handover/services/shift_handover_report_service.dart';
import '../../attendance/services/attendance_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/constants/api_constants.dart';

/// Сервис загрузки и агрегации данных эффективности
class EfficiencyDataService {
  /// Загрузить данные эффективности за период
  static Future<EfficiencyData> loadEfficiencyData({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final now = DateTime.now();
    final start = startDate ?? DateTime(now.year, now.month, 1);
    final end = endDate ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    Logger.debug('Loading efficiency data from $start to $end');

    // Загружаем настройки баллов
    await EfficiencyCalculationService.loadAllSettings();

    // Загружаем все отчеты и штрафы параллельно
    final results = await Future.wait([
      _loadShiftRecords(start, end),
      _loadRecountRecords(start, end),
      _loadShiftHandoverRecords(start, end),
      _loadAttendanceRecords(start, end),
      _loadPenaltyRecords(start, end),
      // TODO: Добавить загрузку остальных источников когда будут готовы
      // _loadTestRecords(start, end),
      // _loadReviewRecords(start, end),
      // _loadProductSearchRecords(start, end),
      // _loadRkoRecords(start, end),
      // _loadOrderRecords(start, end),
    ]);

    // Объединяем все записи
    final List<EfficiencyRecord> allRecords = [];
    for (final records in results) {
      allRecords.addAll(records);
    }

    Logger.debug('Total efficiency records loaded: ${allRecords.length}');

    // Агрегируем по магазинам
    final byShop = _aggregateByShop(allRecords);

    // Агрегируем по сотрудникам
    final byEmployee = _aggregateByEmployee(allRecords);

    return EfficiencyData(
      periodStart: start,
      periodEnd: end,
      byShop: byShop,
      byEmployee: byEmployee,
      allRecords: allRecords,
    );
  }

  /// Загрузить записи пересменки
  static Future<List<EfficiencyRecord>> _loadShiftRecords(
    DateTime start,
    DateTime end,
  ) async {
    try {
      Logger.debug('Loading shift reports...');
      final reports = await ShiftReportService.getReports();

      final records = <EfficiencyRecord>[];
      for (final report in reports) {
        // Проверяем период и наличие оценки
        if (report.createdAt.isBefore(start) || report.createdAt.isAfter(end)) {
          continue;
        }

        if (report.rating == null || report.rating! < 1) {
          continue; // Пропускаем неоцененные отчеты
        }

        final record = await EfficiencyCalculationService.createShiftRecord(
          id: report.id,
          shopAddress: report.shopAddress,
          employeeName: report.employeeName,
          date: report.confirmedAt ?? report.createdAt,
          rating: report.rating!,
        );

        if (record != null) {
          records.add(record);
        }
      }

      Logger.debug('Loaded ${records.length} shift efficiency records');
      return records;
    } catch (e) {
      Logger.error('Error loading shift records', e);
      return [];
    }
  }

  /// Загрузить записи пересчета
  static Future<List<EfficiencyRecord>> _loadRecountRecords(
    DateTime start,
    DateTime end,
  ) async {
    try {
      Logger.debug('Loading recount reports...');
      final reports = await RecountService.getReports();

      final records = <EfficiencyRecord>[];
      for (final report in reports) {
        // Проверяем период и наличие оценки
        if (report.completedAt.isBefore(start) || report.completedAt.isAfter(end)) {
          continue;
        }

        if (report.adminRating == null || report.adminRating! < 1) {
          continue; // Пропускаем неоцененные отчеты
        }

        final record = await EfficiencyCalculationService.createRecountRecord(
          id: report.id,
          shopAddress: report.shopAddress,
          employeeName: report.employeeName,
          date: report.ratedAt ?? report.completedAt,
          adminRating: report.adminRating,
        );

        if (record != null) {
          records.add(record);
        }
      }

      Logger.debug('Loaded ${records.length} recount efficiency records');
      return records;
    } catch (e) {
      Logger.error('Error loading recount records', e);
      return [];
    }
  }

  /// Загрузить записи сдачи смены
  static Future<List<EfficiencyRecord>> _loadShiftHandoverRecords(
    DateTime start,
    DateTime end,
  ) async {
    try {
      Logger.debug('Loading shift handover reports...');
      final reports = await ShiftHandoverReportService.getReports();

      final records = <EfficiencyRecord>[];
      for (final report in reports) {
        // Проверяем период и наличие оценки
        if (report.createdAt.isBefore(start) || report.createdAt.isAfter(end)) {
          continue;
        }

        if (report.rating == null || report.rating! < 1) {
          continue; // Пропускаем неоцененные отчеты
        }

        final record = await EfficiencyCalculationService.createShiftHandoverRecord(
          id: report.id,
          shopAddress: report.shopAddress,
          employeeName: report.employeeName,
          date: report.confirmedAt ?? report.createdAt,
          rating: report.rating,
        );

        if (record != null) {
          records.add(record);
        }
      }

      Logger.debug('Loaded ${records.length} shift handover efficiency records');
      return records;
    } catch (e) {
      Logger.error('Error loading shift handover records', e);
      return [];
    }
  }

  /// Загрузить записи посещаемости
  static Future<List<EfficiencyRecord>> _loadAttendanceRecords(
    DateTime start,
    DateTime end,
  ) async {
    try {
      Logger.debug('Loading attendance records...');
      final attendanceRecords = await AttendanceService.getAttendanceRecords();

      final records = <EfficiencyRecord>[];
      for (final attendance in attendanceRecords) {
        // Проверяем период
        if (attendance.timestamp.isBefore(start) || attendance.timestamp.isAfter(end)) {
          continue;
        }

        // isOnTime может быть null если сотрудник отметился вне смены
        if (attendance.isOnTime == null) {
          continue;
        }

        final record = await EfficiencyCalculationService.createAttendanceRecord(
          id: attendance.id,
          shopAddress: attendance.shopAddress,
          employeeName: attendance.employeeName,
          date: attendance.timestamp,
          isOnTime: attendance.isOnTime!,
        );

        records.add(record);
      }

      Logger.debug('Loaded ${records.length} attendance efficiency records');
      return records;
    } catch (e) {
      Logger.error('Error loading attendance records', e);
      return [];
    }
  }

  /// Агрегировать записи по магазинам
  static List<EfficiencySummary> _aggregateByShop(List<EfficiencyRecord> records) {
    final Map<String, List<EfficiencyRecord>> byShop = {};

    for (final record in records) {
      if (record.shopAddress.isEmpty) continue;

      byShop.putIfAbsent(record.shopAddress, () => []);
      byShop[record.shopAddress]!.add(record);
    }

    final summaries = byShop.entries.map((entry) {
      return EfficiencySummary.fromRecords(
        entityId: entry.key,
        entityName: entry.key,
        records: entry.value,
      );
    }).toList();

    // Сортируем по общим баллам (убывание)
    summaries.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));

    return summaries;
  }

  /// Агрегировать записи по сотрудникам
  static List<EfficiencySummary> _aggregateByEmployee(List<EfficiencyRecord> records) {
    final Map<String, List<EfficiencyRecord>> byEmployee = {};

    for (final record in records) {
      if (record.employeeName.isEmpty) continue;

      byEmployee.putIfAbsent(record.employeeName, () => []);
      byEmployee[record.employeeName]!.add(record);
    }

    final summaries = byEmployee.entries.map((entry) {
      return EfficiencySummary.fromRecords(
        entityId: entry.key,
        entityName: entry.key,
        records: entry.value,
      );
    }).toList();

    // Сортируем по общим баллам (убывание)
    summaries.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));

    return summaries;
  }

  /// Получить данные за предыдущий месяц
  static Future<EfficiencyData> loadPreviousMonthData() async {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 1);
    final endOfPreviousMonth = DateTime(now.year, now.month, 0, 23, 59, 59);

    return loadEfficiencyData(
      startDate: previousMonth,
      endDate: endOfPreviousMonth,
    );
  }

  /// Получить данные за конкретный месяц
  static Future<EfficiencyData> loadMonthData(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);

    return loadEfficiencyData(
      startDate: start,
      endDate: end,
    );
  }

  /// Загрузить штрафы с сервера
  static Future<List<EfficiencyRecord>> _loadPenaltyRecords(
    DateTime start,
    DateTime end,
  ) async {
    try {
      Logger.debug('Loading penalty records from server...');

      // Формируем месяц для запроса (YYYY-MM)
      final monthKey = '${start.year}-${start.month.toString().padLeft(2, '0')}';

      final response = await http.get(
        Uri.parse('${ApiConstants.serverUrl}/api/efficiency-penalties?month=$monthKey'),
      ).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          final penalties = (result['penalties'] as List<dynamic>)
              .map((json) => EfficiencyPenalty.fromJson(json as Map<String, dynamic>))
              .toList();

          Logger.debug('Loaded ${penalties.length} penalties from server');

          // Преобразуем штрафы в записи эффективности
          final records = <EfficiencyRecord>[];
          for (final penalty in penalties) {
            records.add(penalty.toRecord());
          }

          return records;
        }
      }

      Logger.error('Failed to load penalties: HTTP ${response.statusCode}');
      return [];
    } catch (e) {
      Logger.error('Error loading penalty records', e);
      return [];
    }
  }

  /// Получить штрафы с сервера напрямую
  static Future<List<EfficiencyPenalty>> loadPenalties({
    String? month,
    String? shopAddress,
    String? employeeName,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (month != null) queryParams['month'] = month;
      if (shopAddress != null) queryParams['shopAddress'] = shopAddress;
      if (employeeName != null) queryParams['employeeName'] = employeeName;

      final uri = Uri.parse('${ApiConstants.serverUrl}/api/efficiency-penalties')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri).timeout(ApiConstants.defaultTimeout);

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          return (result['penalties'] as List<dynamic>)
              .map((json) => EfficiencyPenalty.fromJson(json as Map<String, dynamic>))
              .toList();
        }
      }

      return [];
    } catch (e) {
      Logger.error('Error loading penalties', e);
      return [];
    }
  }
}
