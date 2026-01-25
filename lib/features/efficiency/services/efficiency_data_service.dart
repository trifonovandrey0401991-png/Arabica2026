import '../models/efficiency_data_model.dart';
import 'efficiency_calculation_service.dart';
import '../../shifts/services/shift_report_service.dart';
import '../../recount/services/recount_service.dart';
import '../../shift_handover/services/shift_handover_report_service.dart';
import '../../attendance/services/attendance_service.dart';
import '../../tasks/services/task_service.dart';
import '../../tasks/models/task_model.dart';
import '../../reviews/services/review_service.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';

/// Сервис загрузки и агрегации данных эффективности
class EfficiencyDataService {
  static const String _penaltiesEndpoint = ApiConstants.efficiencyPenaltiesEndpoint;

  /// Префикс для ключей кэша
  static const String _cacheKeyPrefix = 'efficiency_data';

  /// Определить TTL для кэша на основе месяца
  static Duration _getCacheDuration(int year, int month) {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final previousMonth = DateTime(now.year, now.month - 1);
    final requestedMonth = DateTime(year, month);

    // Текущий и предыдущий месяцы - короткий TTL (2 минуты)
    if (requestedMonth.year == currentMonth.year && requestedMonth.month == currentMonth.month) {
      return const Duration(minutes: 2);
    }
    if (requestedMonth.year == previousMonth.year && requestedMonth.month == previousMonth.month) {
      return const Duration(minutes: 2);
    }

    // Старые месяцы - длинный TTL (30 минут)
    return const Duration(minutes: 30);
  }

  /// Создать ключ кэша для месяца
  static String _createCacheKey(int year, int month) {
    return '${_cacheKeyPrefix}_${year}_${month.toString().padLeft(2, '0')}';
  }

  /// Загрузить данные эффективности за период
  static Future<EfficiencyData> loadEfficiencyData({
    DateTime? startDate,
    DateTime? endDate,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final start = startDate ?? DateTime(now.year, now.month, 1);
    final end = endDate ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    Logger.debug('Loading efficiency data from $start to $end (forceRefresh: $forceRefresh)');

    // Загружаем настройки баллов
    await EfficiencyCalculationService.loadAllSettings();

    // Загружаем все отчеты и штрафы параллельно
    final results = await Future.wait([
      _loadShiftRecords(start, end),
      _loadRecountRecords(start, end),
      _loadShiftHandoverRecords(start, end),
      _loadAttendanceRecords(start, end),
      _loadPenaltyRecords(start, end),
      _loadTaskRecords(start, end),
      _loadReviewRecords(start, end),
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

  /// Загрузить данные эффективности за период используя batch API (ОПТИМИЗИРОВАННЫЙ МЕТОД)
  ///
  /// Этот метод делает один запрос вместо 6 для загрузки всех типов отчётов
  /// Снижает сетевой трафик и ускоряет загрузку
  static Future<EfficiencyData> loadEfficiencyDataBatch({
    DateTime? startDate,
    DateTime? endDate,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final start = startDate ?? DateTime(now.year, now.month, 1);
    final end = endDate ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    Logger.debug('Loading efficiency data via BATCH API from $start to $end (forceRefresh: $forceRefresh)');

    // Загружаем настройки баллов
    await EfficiencyCalculationService.loadAllSettings();

    // Формируем параметр month для API (YYYY-MM)
    final monthParam = '${start.year}-${start.month.toString().padLeft(2, '0')}';

    try {
      // Делаем один batch запрос для всех отчётов
      final result = await BaseHttpService.getRaw(
        endpoint: '${ApiConstants.efficiencyReportsBatchEndpoint}?month=$monthParam',
      );

      if (result == null || result['success'] != true) {
        Logger.warning('Batch API вернул пустой результат, используем fallback');
        // Fallback к старому методу
        return loadEfficiencyData(
          startDate: startDate,
          endDate: endDate,
          forceRefresh: forceRefresh,
        );
      }

      Logger.debug('✅ Batch API вернул данные:');
      Logger.debug('   - shifts: ${(result['shifts'] as List?)?.length ?? 0}');
      Logger.debug('   - recounts: ${(result['recounts'] as List?)?.length ?? 0}');
      Logger.debug('   - handovers: ${(result['handovers'] as List?)?.length ?? 0}');
      Logger.debug('   - attendance: ${(result['attendance'] as List?)?.length ?? 0}');

      // Загружаем остальные типы отдельно (пока не добавлены в batch API)
      final penaltyRecords = await _loadPenaltyRecords(start, end);
      final taskRecords = await _loadTaskRecords(start, end);
      final reviewRecords = await _loadReviewRecords(start, end);

      // Парсим отчёты и конвертируем в EfficiencyRecord
      final shiftRecords = await _parseShiftReportsFromBatch(result['shifts'] as List<dynamic>? ?? [], start, end);
      final recountRecords = await _parseRecountReportsFromBatch(result['recounts'] as List<dynamic>? ?? [], start, end);
      final handoverRecords = await _parseHandoverReportsFromBatch(result['handovers'] as List<dynamic>? ?? [], start, end);
      final attendanceRecords = await _parseAttendanceFromBatch(result['attendance'] as List<dynamic>? ?? [], start, end);

      // Объединяем все записи
      final List<EfficiencyRecord> allRecords = [
        ...shiftRecords,
        ...recountRecords,
        ...handoverRecords,
        ...attendanceRecords,
        ...penaltyRecords,
        ...taskRecords,
        ...reviewRecords,
      ];

      Logger.debug('Total efficiency records from BATCH API: ${allRecords.length}');

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
    } catch (e) {
      Logger.error('Error loading efficiency data via batch API', e);
      // Fallback к старому методу при ошибке
      Logger.warning('Используем fallback к старому методу загрузки');
      return loadEfficiencyData(
        startDate: startDate,
        endDate: endDate,
        forceRefresh: forceRefresh,
      );
    }
  }

  /// Парсинг shift reports из batch API
  static Future<List<EfficiencyRecord>> _parseShiftReportsFromBatch(
    List<dynamic> rawReports,
    DateTime start,
    DateTime end,
  ) async {
    final records = <EfficiencyRecord>[];

    for (final json in rawReports) {
      try {
        final createdAt = json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null;
        final timestamp = json['timestamp'] != null ? DateTime.parse(json['timestamp']) : null;
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
          date: json['confirmedAt'] != null ? DateTime.parse(json['confirmedAt']) : reportDate,
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
  static Future<List<EfficiencyRecord>> _parseRecountReportsFromBatch(
    List<dynamic> rawReports,
    DateTime start,
    DateTime end,
  ) async {
    final records = <EfficiencyRecord>[];

    for (final json in rawReports) {
      try {
        final completedAt = json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null;
        final createdAt = json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null;
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
          date: json['ratedAt'] != null ? DateTime.parse(json['ratedAt']) : reportDate,
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
  static Future<List<EfficiencyRecord>> _parseHandoverReportsFromBatch(
    List<dynamic> rawReports,
    DateTime start,
    DateTime end,
  ) async {
    final records = <EfficiencyRecord>[];

    for (final json in rawReports) {
      try {
        final createdAt = json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null;

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
          date: json['confirmedAt'] != null ? DateTime.parse(json['confirmedAt']) : createdAt,
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
  static Future<List<EfficiencyRecord>> _parseAttendanceFromBatch(
    List<dynamic> rawRecords,
    DateTime start,
    DateTime end,
  ) async {
    final records = <EfficiencyRecord>[];

    for (final json in rawRecords) {
      try {
        final timestamp = json['timestamp'] != null ? DateTime.parse(json['timestamp']) : null;
        final createdAt = json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null;
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

  /// Получить данные за предыдущий месяц (с кэшированием)
  static Future<EfficiencyData> loadPreviousMonthData({
    bool forceRefresh = false,
    bool useBatchAPI = true,
  }) async {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 1);

    return loadMonthData(
      previousMonth.year,
      previousMonth.month,
      forceRefresh: forceRefresh,
      useBatchAPI: useBatchAPI,
    );
  }

  /// Очистить весь кэш эффективности
  static void clearCache() {
    CacheManager.clearByPattern(_cacheKeyPrefix);
    Logger.debug('🗑️ Весь кэш эффективности очищен');
  }

  /// Очистить кэш для конкретного месяца
  static void clearCacheForMonth(int year, int month) {
    final cacheKey = _createCacheKey(year, month);
    CacheManager.remove(cacheKey);
    Logger.debug('🗑️ Кэш очищен для месяца $year-$month');
  }

  /// Получить данные за конкретный месяц (с кэшированием)
  ///
  /// [useBatchAPI] - использовать оптимизированный batch API endpoint (по умолчанию true)
  /// При useBatchAPI=true делается 1 HTTP запрос вместо 6, что снижает трафик и ускоряет загрузку
  static Future<EfficiencyData> loadMonthData(
    int year,
    int month, {
    bool forceRefresh = false,
    bool useBatchAPI = true,
  }) async {
    final cacheKey = _createCacheKey(year, month);

    // Если forceRefresh - очищаем кэш
    if (forceRefresh) {
      CacheManager.remove(cacheKey);
      Logger.debug('🗑️ Кэш очищен для месяца $year-$month (force refresh)');
    }

    // Пытаемся получить из кэша или загрузить
    return await CacheManager.getOrFetch<EfficiencyData>(
      cacheKey,
      () async {
        Logger.debug('📥 Загрузка данных эффективности за $year-$month с сервера...');
        final start = DateTime(year, month, 1);
        final end = DateTime(year, month + 1, 0, 23, 59, 59);

        // Используем batch API если включен флаг
        final data = useBatchAPI
            ? await loadEfficiencyDataBatch(
                startDate: start,
                endDate: end,
                forceRefresh: false, // Внутренний вызов без forceRefresh
              )
            : await loadEfficiencyData(
                startDate: start,
                endDate: end,
                forceRefresh: false, // Внутренний вызов без forceRefresh
              );

        Logger.debug('💾 Данные эффективности за $year-$month сохранены в кэш');
        return data;
      },
      duration: _getCacheDuration(year, month),
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

      final result = await BaseHttpService.getRaw(
        endpoint: '$_penaltiesEndpoint?month=$monthKey',
      );

      if (result != null) {
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

      final result = await BaseHttpService.getRaw(
        endpoint: _penaltiesEndpoint,
        queryParams: queryParams.isNotEmpty ? queryParams : null,
      );

      if (result != null) {
        return (result['penalties'] as List<dynamic>)
            .map((json) => EfficiencyPenalty.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      return [];
    } catch (e) {
      Logger.error('Error loading penalties', e);
      return [];
    }
  }

  /// Загрузить записи по задачам
  static Future<List<EfficiencyRecord>> _loadTaskRecords(
    DateTime start,
    DateTime end,
  ) async {
    try {
      Logger.debug('Loading task assignments...');
      final assignments = await TaskService.getAllAssignments();

      final records = <EfficiencyRecord>[];
      for (final assignment in assignments) {
        // Проверяем период (по времени ответа или проверки)
        DateTime? recordDate;
        if (assignment.status == TaskStatus.approved ||
            assignment.status == TaskStatus.rejected) {
          recordDate = assignment.reviewedAt;
        } else if (assignment.status == TaskStatus.declined) {
          recordDate = assignment.respondedAt ?? assignment.deadline;
        } else if (assignment.status == TaskStatus.expired) {
          recordDate = assignment.deadline;
        }

        if (recordDate == null) continue;
        if (recordDate.isBefore(start) || recordDate.isAfter(end)) continue;

        // Определяем баллы по статусу
        double points;
        switch (assignment.status) {
          case TaskStatus.approved:
            points = 1.0; // +1 за выполненную задачу
            break;
          case TaskStatus.rejected:
            points = -3.0; // -3 за отклоненную админом
            break;
          case TaskStatus.expired:
            points = -3.0; // -3 за просроченную
            break;
          case TaskStatus.declined:
            points = -3.0; // -3 за отказ
            break;
          default:
            continue; // Пропускаем pending/submitted
        }

        records.add(EfficiencyRecord(
          id: assignment.id,
          category: EfficiencyCategory.tasks,
          shopAddress: '', // Задачи не привязаны к магазинам
          employeeName: assignment.assigneeName,
          date: recordDate,
          points: points,
          rawValue: {
            'status': assignment.status.name,
            'taskTitle': assignment.task?.title ?? 'Задача',
          },
          sourceId: assignment.taskId,
        ));
      }

      Logger.debug('Loaded ${records.length} task efficiency records');
      return records;
    } catch (e) {
      Logger.error('Error loading task records', e);
      return [];
    }
  }

  /// Загрузить записи по отзывам
  static Future<List<EfficiencyRecord>> _loadReviewRecords(
    DateTime start,
    DateTime end,
  ) async {
    try {
      Logger.debug('Loading review records...');
      final reviews = await ReviewService.getAllReviews();

      final records = <EfficiencyRecord>[];
      for (final review in reviews) {
        // Проверяем период
        if (review.createdAt.isBefore(start) || review.createdAt.isAfter(end)) {
          continue;
        }

        final isPositive = review.reviewType == 'positive';
        final record = await EfficiencyCalculationService.createReviewRecord(
          id: review.id,
          shopAddress: review.shopAddress,
          date: review.createdAt,
          isPositive: isPositive,
        );

        records.add(record);
      }

      Logger.debug('Loaded ${records.length} review efficiency records');
      return records;
    } catch (e) {
      Logger.error('Error loading review records', e);
      return [];
    }
  }
}
