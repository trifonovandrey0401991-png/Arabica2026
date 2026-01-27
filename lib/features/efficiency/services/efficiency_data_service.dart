import '../models/efficiency_data_model.dart';
import 'efficiency_calculation_service.dart';
import 'data_loaders/data_loaders.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';
import '../../shops/services/shop_service.dart';

/// Сервис загрузки и агрегации данных эффективности
///
/// Основной публичный метод: loadMonthData()
/// Данные загружаются из 10 источников и агрегируются по магазинам/сотрудникам:
/// - Пересменка, Пересчёт, Сдача смены, Посещаемость
/// - Штрафы, Задачи, Отзывы
/// - Поиск товара, Заказы, РКО
///
/// Структура после рефакторинга:
/// - efficiency_data_service.dart - оркестратор и кэширование (этот файл)
/// - data_loaders/efficiency_batch_parsers.dart - парсеры для batch API
/// - data_loaders/efficiency_record_loaders.dart - загрузчики из отдельных сервисов
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

    // Загружаем все отчеты и штрафы параллельно (10 источников)
    final results = await Future.wait([
      loadShiftRecords(start, end),
      loadRecountRecords(start, end),
      loadShiftHandoverRecords(start, end),
      loadAttendanceRecords(start, end),
      loadPenaltyRecords(start, end),
      loadTaskRecords(start, end),
      loadReviewRecords(start, end),
      loadProductSearchRecords(start, end),
      loadOrderRecords(start, end),
      loadRkoRecords(start, end),
    ]);

    // Объединяем все записи
    final List<EfficiencyRecord> allRecords = [];
    for (final records in results) {
      allRecords.addAll(records);
    }

    Logger.debug('Total efficiency records loaded: ${allRecords.length}');

    // Агрегируем по магазинам (фильтруем по реальным магазинам)
    final byShop = await _aggregateByShop(allRecords);

    // Агрегируем по сотрудникам (фильтруем по реальным магазинам)
    final byEmployee = await _aggregateByEmployee(allRecords);

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

    // Формируем параметр month для API (YYYY-MM)
    final monthParam = '${start.year}-${start.month.toString().padLeft(2, '0')}';

    try {
      // Загружаем ВСЁ параллельно: настройки, batch API, дополнительные источники и магазины
      final parallelResults = await Future.wait([
        EfficiencyCalculationService.loadAllSettings(),           // [0] настройки
        BaseHttpService.getRaw(                                    // [1] batch API
          endpoint: '${ApiConstants.efficiencyReportsBatchEndpoint}?month=$monthParam',
        ),
        loadPenaltyRecords(start, end),                           // [2] штрафы
        loadTaskRecords(start, end),                              // [3] задачи
        loadReviewRecords(start, end),                            // [4] отзывы
        loadProductSearchRecords(start, end),                     // [5] поиск товара
        loadOrderRecords(start, end),                             // [6] заказы
        loadRkoRecords(start, end),                               // [7] РКО
        ShopService.getShops(),                                   // [8] магазины (один раз!)
      ]);

      final result = parallelResults[1] as Map<String, dynamic>?;
      final penaltyRecords = parallelResults[2] as List<EfficiencyRecord>;
      final taskRecords = parallelResults[3] as List<EfficiencyRecord>;
      final reviewRecords = parallelResults[4] as List<EfficiencyRecord>;
      final productSearchRecords = parallelResults[5] as List<EfficiencyRecord>;
      final orderRecords = parallelResults[6] as List<EfficiencyRecord>;
      final rkoRecords = parallelResults[7] as List<EfficiencyRecord>;
      final shops = parallelResults[8] as List<dynamic>;

      if (result == null || result['success'] != true) {
        Logger.warning('Batch API вернул пустой результат, используем fallback');
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

      // Парсим batch данные параллельно
      final batchParseResults = await Future.wait([
        parseShiftReportsFromBatch(result['shifts'] as List<dynamic>? ?? [], start, end),
        parseRecountReportsFromBatch(result['recounts'] as List<dynamic>? ?? [], start, end),
        parseHandoverReportsFromBatch(result['handovers'] as List<dynamic>? ?? [], start, end),
        parseAttendanceFromBatch(result['attendance'] as List<dynamic>? ?? [], start, end),
      ]);

      final shiftRecords = batchParseResults[0];
      final recountRecords = batchParseResults[1];
      final handoverRecords = batchParseResults[2];
      final attendanceRecords = batchParseResults[3];

      // Объединяем все записи (10 источников)
      final List<EfficiencyRecord> allRecords = [
        ...shiftRecords,
        ...recountRecords,
        ...handoverRecords,
        ...attendanceRecords,
        ...penaltyRecords,
        ...taskRecords,
        ...reviewRecords,
        ...productSearchRecords,
        ...orderRecords,
        ...rkoRecords,
      ];

      Logger.debug('Total efficiency records from BATCH API: ${allRecords.length}');

      // Создаём Set валидных адресов (магазины уже загружены!)
      final validAddresses = shops.map((s) => s.address as String).toSet();

      // Агрегируем по магазинам и сотрудникам параллельно
      final aggregationResults = await Future.wait([
        _aggregateByShopWithAddresses(allRecords, validAddresses),
        _aggregateByEmployeeWithAddresses(allRecords, validAddresses),
      ]);

      return EfficiencyData(
        periodStart: start,
        periodEnd: end,
        byShop: aggregationResults[0],
        byEmployee: aggregationResults[1],
        allRecords: allRecords,
      );
    } catch (e) {
      Logger.error('Error loading efficiency data via batch API', e);
      Logger.warning('Используем fallback к старому методу загрузки');
      return loadEfficiencyData(
        startDate: startDate,
        endDate: endDate,
        forceRefresh: forceRefresh,
      );
    }
  }

  /// Агрегировать записи по магазинам
  /// Фильтрует только по реальным магазинам из списка
  static Future<List<EfficiencySummary>> _aggregateByShop(List<EfficiencyRecord> records) async {
    final shops = await ShopService.getShops();
    final validAddresses = shops.map((s) => s.address).toSet();
    return _aggregateByShopWithAddresses(records, validAddresses);
  }

  /// Агрегировать записи по магазинам (с уже загруженными адресами)
  static Future<List<EfficiencySummary>> _aggregateByShopWithAddresses(
    List<EfficiencyRecord> records,
    Set<String> validAddresses,
  ) async {
    Logger.debug('Фильтрация по ${validAddresses.length} реальным магазинам');

    final Map<String, List<EfficiencyRecord>> byShop = {};

    for (final record in records) {
      if (record.shopAddress.isEmpty) continue;
      if (!validAddresses.contains(record.shopAddress)) continue;

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

    summaries.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
    return summaries;
  }

  /// Агрегировать записи по сотрудникам
  /// Фильтрует только записи с реальными магазинами из списка
  static Future<List<EfficiencySummary>> _aggregateByEmployee(List<EfficiencyRecord> records) async {
    final shops = await ShopService.getShops();
    final validAddresses = shops.map((s) => s.address).toSet();
    return _aggregateByEmployeeWithAddresses(records, validAddresses);
  }

  /// Агрегировать записи по сотрудникам (с уже загруженными адресами)
  static Future<List<EfficiencySummary>> _aggregateByEmployeeWithAddresses(
    List<EfficiencyRecord> records,
    Set<String> validAddresses,
  ) async {
    final Map<String, List<EfficiencyRecord>> byEmployee = {};

    for (final record in records) {
      if (record.employeeName.isEmpty) continue;
      if (record.shopAddress.isEmpty || !validAddresses.contains(record.shopAddress)) continue;

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
}
