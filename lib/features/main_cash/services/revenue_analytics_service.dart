import '../models/shop_revenue_model.dart';
import '../../envelope/models/envelope_report_model.dart';
import '../../envelope/services/envelope_report_service.dart';
import '../../../core/utils/logger.dart';

/// Сервис аналитики выручки на основе данных конвертов
class RevenueAnalyticsService {
  /// Получить выручку по всем магазинам за текущий месяц
  static Future<List<ShopRevenue>> getCurrentMonthRevenues({
    String? shopAddress,
  }) async {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, 1);
    final endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return getShopRevenues(
      startDate: startDate,
      endDate: endDate,
      shopAddress: shopAddress,
    );
  }

  /// Получить выручку по магазинам за произвольный период
  static Future<List<ShopRevenue>> getShopRevenues({
    required DateTime startDate,
    required DateTime endDate,
    String? shopAddress,
  }) async {
    try {
      Logger.debug('📊 Загрузка аналитики выручки за период: ${_formatDate(startDate)} - ${_formatDate(endDate)}');

      // 1. Загрузить отчеты конвертов за период
      final reports = await EnvelopeReportService.getReports(
        fromDate: startDate,
        toDate: endDate,
      );

      Logger.debug('Загружено отчетов: ${reports.length}');

      if (reports.isEmpty) {
        Logger.debug('Нет отчетов за период');
        return [];
      }

      // 2. Группировать по магазинам (все отчеты, не только подтвержденные)
      final Map<String, List<EnvelopeReport>> byShop = {};
      for (final report in reports) {
        // Фильтр по магазину если указан
        if (shopAddress != null && report.shopAddress != shopAddress) {
          continue;
        }
        byShop.putIfAbsent(report.shopAddress, () => []).add(report);
      }

      Logger.debug('Магазинов с данными: ${byShop.length}');

      // 4. Агрегировать данные и рассчитать сравнения
      final result = <ShopRevenue>[];
      for (final entry in byShop.entries) {
        final shopReports = entry.value;
        final shopName = entry.key;

        // Рассчитать выручку за текущий период
        double totalRevenue = 0.0;
        double oooRevenue = 0.0;
        double ipRevenue = 0.0;

        for (final report in shopReports) {
          oooRevenue += report.oooRevenue;
          ipRevenue += report.ipRevenue;
          totalRevenue += report.oooRevenue + report.ipRevenue;
        }

        // Загрузить данные за прошлый период для сравнения
        final prevPeriodRevenue = await _getPrevPeriodRevenue(
          shopAddress: shopName,
          currentStart: startDate,
          currentEnd: endDate,
        );

        // Рассчитать изменения
        double? changeAmount;
        double? changePercent;
        if (prevPeriodRevenue != null && prevPeriodRevenue > 0) {
          changeAmount = totalRevenue - prevPeriodRevenue;
          changePercent = (changeAmount / prevPeriodRevenue) * 100;
        }

        // Рассчитать тренд
        final trend = prevPeriodRevenue.calculateTrend(totalRevenue);

        // Средняя выручка за смену
        final avgPerShift = shopReports.isEmpty ? 0.0 : totalRevenue / shopReports.length;

        result.add(ShopRevenue(
          shopAddress: shopName,
          startDate: startDate,
          endDate: endDate,
          totalRevenue: totalRevenue,
          oooRevenue: oooRevenue,
          ipRevenue: ipRevenue,
          shiftsCount: shopReports.length,
          avgPerShift: avgPerShift,
          prevPeriodRevenue: prevPeriodRevenue,
          changeAmount: changeAmount,
          changePercent: changePercent,
          trend: trend,
        ));

        Logger.debug('Магазин: $shopName, Выручка: $totalRevenue, Смен: ${shopReports.length}, Тренд: $trend');
      }

      // 5. Сортировка по убыванию выручки
      result.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

      Logger.debug('✅ Сформировано записей аналитики: ${result.length}');
      return result;
    } catch (e, stackTrace) {
      Logger.error('❌ Ошибка загрузки аналитики выручки', e);
      Logger.debug('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Получить данные за прошлый период для сравнения
  static Future<double?> _getPrevPeriodRevenue({
    required String shopAddress,
    required DateTime currentStart,
    required DateTime currentEnd,
  }) async {
    try {
      final duration = currentEnd.difference(currentStart);
      final prevStart = currentStart.subtract(duration);
      final prevEnd = currentStart.subtract(const Duration(seconds: 1));

      final prevReports = await EnvelopeReportService.getReports(
        fromDate: prevStart,
        toDate: prevEnd,
      );

      final shopReports = prevReports.where(
        (r) => r.shopAddress == shopAddress,
      );

      if (shopReports.isEmpty) return null;

      return shopReports.fold<double>(
        0.0,
        (sum, r) => sum + r.oooRevenue + r.ipRevenue,
      );
    } catch (e) {
      Logger.debug('Не удалось загрузить данные за прошлый период: $e');
      return null;
    }
  }

  /// Получить топ магазинов по росту
  static List<ShopRevenue> getTopGrowers(List<ShopRevenue> revenues, {int limit = 3}) {
    return revenues
        .where((r) => r.changePercent != null && r.changePercent! > 0)
        .toList()
      ..sort((a, b) => (b.changePercent ?? 0).compareTo(a.changePercent ?? 0))
      ..take(limit).toList();
  }

  /// Получить магазины с падением выручки
  static List<ShopRevenue> getDecliners(List<ShopRevenue> revenues, {int limit = 3}) {
    return revenues
        .where((r) => r.changePercent != null && r.changePercent! < -5)
        .toList()
      ..sort((a, b) => (a.changePercent ?? 0).compareTo(b.changePercent ?? 0))
      ..take(limit).toList();
  }

  /// Получить общую выручку за период
  static double getTotalRevenue(List<ShopRevenue> revenues) {
    return revenues.fold(0.0, (sum, r) => sum + r.totalRevenue);
  }

  /// Получить средний процент изменения
  static double? getAverageChangePercent(List<ShopRevenue> revenues) {
    final withChanges = revenues.where((r) => r.changePercent != null).toList();
    if (withChanges.isEmpty) return null;

    final sum = withChanges.fold(0.0, (sum, r) => sum + r.changePercent!);
    return sum / withChanges.length;
  }

  /// Форматировать дату для логов
  static String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  /// Получить выручку за конкретный день
  static Future<double> getDayRevenue({
    required String shopAddress,
    required DateTime date,
  }) async {
    try {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

      final reports = await EnvelopeReportService.getReports(
        fromDate: startOfDay,
        toDate: endOfDay,
        shopAddress: shopAddress,
      );

      double total = 0.0;
      for (final report in reports) {
        if (report.shopAddress == shopAddress) {
          total += report.oooRevenue + report.ipRevenue;
        }
      }

      Logger.debug('Выручка за ${_formatDate(date)}: $total');
      return total;
    } catch (e) {
      Logger.error('Ошибка загрузки выручки за день', e);
      return 0.0;
    }
  }

  /// Получить выручку за период для одного магазина
  static Future<double> getPeriodRevenue({
    required String shopAddress,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final reports = await EnvelopeReportService.getReports(
        fromDate: startDate,
        toDate: endDate,
        shopAddress: shopAddress,
      );

      double total = 0.0;
      for (final report in reports) {
        if (report.shopAddress == shopAddress) {
          total += report.oooRevenue + report.ipRevenue;
        }
      }

      Logger.debug('Выручка за период ${_formatDate(startDate)}-${_formatDate(endDate)}: $total');
      return total;
    } catch (e) {
      Logger.error('Ошибка загрузки выручки за период', e);
      return 0.0;
    }
  }

  /// Получить выручку по дням для графика
  static Future<List<DailyRevenue>> getDailyRevenues({
    required String shopAddress,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      Logger.debug('Загрузка выручки по дням для $shopAddress');

      final reports = await EnvelopeReportService.getReports(
        fromDate: startDate,
        toDate: endDate,
        shopAddress: shopAddress,
      );

      // Группируем по дням
      final Map<String, DailyRevenue> byDay = {};

      for (final report in reports) {
        if (report.shopAddress != shopAddress) continue;

        final dateKey = '${report.createdAt.year}-${report.createdAt.month}-${report.createdAt.day}';

        if (byDay.containsKey(dateKey)) {
          final existing = byDay[dateKey]!;
          byDay[dateKey] = DailyRevenue(
            date: DateTime(report.createdAt.year, report.createdAt.month, report.createdAt.day),
            oooRevenue: existing.oooRevenue + report.oooRevenue,
            ipRevenue: existing.ipRevenue + report.ipRevenue,
          );
        } else {
          byDay[dateKey] = DailyRevenue(
            date: DateTime(report.createdAt.year, report.createdAt.month, report.createdAt.day),
            oooRevenue: report.oooRevenue,
            ipRevenue: report.ipRevenue,
          );
        }
      }

      // Сортируем по дате
      final result = byDay.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      Logger.debug('Загружено дней с выручкой: ${result.length}');
      return result;
    } catch (e) {
      Logger.error('Ошибка загрузки выручки по дням', e);
      return [];
    }
  }

  /// Получить выручку всех магазинов по дням (для таблицы)
  static Future<Map<String, List<DailyRevenue>>> getAllShopsDailyRevenues({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      Logger.debug('Загрузка выручки всех магазинов по дням');

      final reports = await EnvelopeReportService.getReports(
        fromDate: startDate,
        toDate: endDate,
      );

      // Группируем по магазинам и дням
      final Map<String, Map<String, DailyRevenue>> byShopAndDay = {};

      for (final report in reports) {
        final shopAddress = report.shopAddress;
        final dateKey = '${report.createdAt.year}-${report.createdAt.month}-${report.createdAt.day}';

        byShopAndDay.putIfAbsent(shopAddress, () => {});

        if (byShopAndDay[shopAddress]!.containsKey(dateKey)) {
          final existing = byShopAndDay[shopAddress]![dateKey]!;
          byShopAndDay[shopAddress]![dateKey] = DailyRevenue(
            date: DateTime(report.createdAt.year, report.createdAt.month, report.createdAt.day),
            oooRevenue: existing.oooRevenue + report.oooRevenue,
            ipRevenue: existing.ipRevenue + report.ipRevenue,
          );
        } else {
          byShopAndDay[shopAddress]![dateKey] = DailyRevenue(
            date: DateTime(report.createdAt.year, report.createdAt.month, report.createdAt.day),
            oooRevenue: report.oooRevenue,
            ipRevenue: report.ipRevenue,
          );
        }
      }

      // Конвертируем в финальный формат
      final Map<String, List<DailyRevenue>> result = {};
      for (final entry in byShopAndDay.entries) {
        final dailyList = entry.value.values.toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        result[entry.key] = dailyList;
      }

      Logger.debug('Загружено магазинов: ${result.length}');
      return result;
    } catch (e) {
      Logger.error('Ошибка загрузки выручки всех магазинов по дням', e);
      return {};
    }
  }

  /// Получить список всех адресов магазинов
  static Future<List<String>> getShopAddresses() async {
    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 2, 1); // За последние 2 месяца
      final endDate = now;

      final reports = await EnvelopeReportService.getReports(
        fromDate: startDate,
        toDate: endDate,
      );

      final addresses = <String>{};
      for (final report in reports) {
        addresses.add(report.shopAddress);
      }

      final result = addresses.toList()..sort();
      Logger.debug('Найдено магазинов: ${result.length}');
      return result;
    } catch (e) {
      Logger.error('Ошибка загрузки списка магазинов', e);
      return [];
    }
  }

  /// Получить выручку по неделям для одного магазина за все месяцы
  static Future<List<MonthlyRevenueTable>> getWeeklyRevenuesAllMonths({
    required String shopAddress,
  }) async {
    try {
      Logger.debug('🔵 getWeeklyRevenuesAllMonths() для: $shopAddress');

      // Загружаем ВСЕ отчеты (за последний год) - API не поддерживает фильтр shopAddress
      final now = DateTime.now();
      final startDate = DateTime(now.year - 1, now.month, 1);
      final endDate = now;

      Logger.debug('📅 Период загрузки: ${_formatDate(startDate)} - ${_formatDate(endDate)}');

      final allReports = await EnvelopeReportService.getReports(
        fromDate: startDate,
        toDate: endDate,
        // НЕ передаём shopAddress - API его не поддерживает
      );

      Logger.debug('📦 Загружено всех отчетов: ${allReports.length}');

      // Фильтруем по магазину на клиенте
      final reports = allReports.where((r) => r.shopAddress == shopAddress).toList();
      Logger.debug('📦 Отчетов для магазина "$shopAddress": ${reports.length}');

      // Группируем по месяцам (уже отфильтровано по магазину)
      final Map<String, List<DailyRevenue>> byMonth = {};

      for (final report in reports) {
        // Уже отфильтровано выше

        final monthKey = '${report.createdAt.year}-${report.createdAt.month.toString().padLeft(2, '0')}';
        final dateKey = '${report.createdAt.year}-${report.createdAt.month}-${report.createdAt.day}';

        byMonth.putIfAbsent(monthKey, () => []);

        // Проверяем, есть ли уже запись за этот день
        final existingIndex = byMonth[monthKey]!.indexWhere(
          (r) => '${r.date.year}-${r.date.month}-${r.date.day}' == dateKey
        );

        if (existingIndex >= 0) {
          final existing = byMonth[monthKey]![existingIndex];
          byMonth[monthKey]![existingIndex] = DailyRevenue(
            date: existing.date,
            oooRevenue: existing.oooRevenue + report.oooRevenue,
            ipRevenue: existing.ipRevenue + report.ipRevenue,
          );
        } else {
          byMonth[monthKey]!.add(DailyRevenue(
            date: DateTime(report.createdAt.year, report.createdAt.month, report.createdAt.day),
            oooRevenue: report.oooRevenue,
            ipRevenue: report.ipRevenue,
          ));
        }
      }

      // Сортируем ключи месяцев (новые сверху)
      final sortedMonthKeys = byMonth.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      // Формируем результат
      final result = <MonthlyRevenueTable>[];

      for (final monthKey in sortedMonthKeys) {
        final parts = monthKey.split('-');
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);

        final dailyRevenues = byMonth[monthKey]!;
        if (dailyRevenues.isEmpty) continue;

        // Группируем по неделям
        final weeks = _groupByWeeks(dailyRevenues, year, month);

        // Считаем итого и среднюю
        double totalRevenue = 0;
        int daysWithRevenue = 0;

        for (final day in dailyRevenues) {
          totalRevenue += day.totalRevenue;
          if (day.totalRevenue > 0) daysWithRevenue++;
        }

        final averageRevenue = daysWithRevenue > 0 ? totalRevenue / daysWithRevenue : 0.0;

        result.add(MonthlyRevenueTable(
          year: year,
          month: month,
          weeks: weeks,
          totalRevenue: totalRevenue,
          averageRevenue: averageRevenue,
          daysWithRevenue: daysWithRevenue,
        ));
      }

      Logger.debug('Сформировано месяцев: ${result.length}');
      return result;
    } catch (e, stackTrace) {
      Logger.error('Ошибка загрузки недельной выручки', e);
      Logger.debug('Stack trace: $stackTrace');
      return [];
    }
  }

  /// Группировка дневных данных по неделям (ПН-ВС)
  static List<WeeklyRevenue> _groupByWeeks(List<DailyRevenue> daily, int year, int month) {
    final weeks = <WeeklyRevenue>[];

    // Первый день месяца
    final firstDay = DateTime(year, month, 1);
    // Последний день месяца
    final lastDay = DateTime(year, month + 1, 0);

    // Находим понедельник недели, в которую входит первый день месяца
    var weekStart = firstDay.subtract(Duration(days: firstDay.weekday - 1));

    // Карта дата -> выручка
    final Map<String, double> revenueByDay = {};
    for (final d in daily) {
      final key = '${d.date.year}-${d.date.month}-${d.date.day}';
      revenueByDay[key] = (revenueByDay[key] ?? 0) + d.totalRevenue;
    }

    // Итерируем по неделям
    while (weekStart.isBefore(lastDay) ||
           (weekStart.month == month && weekStart.year == year)) {
      final dailyRevenues = List<double>.filled(7, 0.0);  // ПН-ВС
      bool hasDataInMonth = false;

      for (int i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        final key = '${day.year}-${day.month}-${day.day}';
        dailyRevenues[i] = revenueByDay[key] ?? 0.0;

        // Проверяем, есть ли в этой неделе дни из текущего месяца
        if (day.month == month && day.year == year) {
          hasDataInMonth = true;
        }
      }

      // Добавляем неделю только если она содержит дни из текущего месяца
      if (hasDataInMonth) {
        weeks.add(WeeklyRevenue(
          weekStart: weekStart,
          dailyRevenues: dailyRevenues,
        ));
      }

      weekStart = weekStart.add(const Duration(days: 7));

      // Выходим если вышли за пределы месяца
      if (weekStart.month != month && weekStart.isAfter(lastDay)) break;
    }

    // Сортируем недели (новые сверху)
    weeks.sort((a, b) => b.weekStart.compareTo(a.weekStart));

    return weeks;
  }

  /// Получить выручку по неделям для ВСЕХ магазинов за текущий месяц
  static Future<Map<String, List<MonthlyRevenueTable>>> getWeeklyRevenuesAllShops() async {
    try {
      Logger.debug('🔵 getWeeklyRevenuesAllShops() - загрузка для всех магазинов');

      final now = DateTime.now();
      // Загружаем только за текущий месяц
      final startDate = DateTime(now.year, now.month, 1);
      final endDate = now;

      Logger.debug('📅 Период: ${_formatDate(startDate)} - ${_formatDate(endDate)}');

      final allReports = await EnvelopeReportService.getReports(
        fromDate: startDate,
        toDate: endDate,
      );

      Logger.debug('📦 Загружено всех отчетов: ${allReports.length}');

      // Группируем по магазинам
      final Map<String, List<DailyRevenue>> byShop = {};

      for (final report in allReports) {
        if (report.shopAddress.isEmpty) continue;

        byShop.putIfAbsent(report.shopAddress, () => []);

        final dateKey = '${report.createdAt.year}-${report.createdAt.month}-${report.createdAt.day}';

        // Проверяем, есть ли уже запись за этот день
        final existingIndex = byShop[report.shopAddress]!.indexWhere(
          (r) => '${r.date.year}-${r.date.month}-${r.date.day}' == dateKey
        );

        if (existingIndex >= 0) {
          final existing = byShop[report.shopAddress]![existingIndex];
          byShop[report.shopAddress]![existingIndex] = DailyRevenue(
            date: existing.date,
            oooRevenue: existing.oooRevenue + report.oooRevenue,
            ipRevenue: existing.ipRevenue + report.ipRevenue,
          );
        } else {
          byShop[report.shopAddress]!.add(DailyRevenue(
            date: DateTime(report.createdAt.year, report.createdAt.month, report.createdAt.day),
            oooRevenue: report.oooRevenue,
            ipRevenue: report.ipRevenue,
          ));
        }
      }

      Logger.debug('📦 Магазинов с данными: ${byShop.length}');

      // Формируем результат для каждого магазина
      final result = <String, List<MonthlyRevenueTable>>{};

      for (final shopEntry in byShop.entries) {
        final shopAddress = shopEntry.key;
        final dailyRevenues = shopEntry.value;

        if (dailyRevenues.isEmpty) continue;

        // Группируем по неделям для текущего месяца
        final weeks = _groupByWeeks(dailyRevenues, now.year, now.month);

        // Считаем итого и среднюю
        double totalRevenue = 0;
        int daysWithRevenue = 0;

        for (final day in dailyRevenues) {
          totalRevenue += day.totalRevenue;
          if (day.totalRevenue > 0) daysWithRevenue++;
        }

        final averageRevenue = daysWithRevenue > 0 ? totalRevenue / daysWithRevenue : 0.0;

        result[shopAddress] = [
          MonthlyRevenueTable(
            year: now.year,
            month: now.month,
            weeks: weeks,
            totalRevenue: totalRevenue,
            averageRevenue: averageRevenue,
            daysWithRevenue: daysWithRevenue,
          ),
        ];
      }

      Logger.debug('✅ Сформировано данных для ${result.length} магазинов');
      return result;
    } catch (e, stackTrace) {
      Logger.error('Ошибка загрузки недельной выручки для всех магазинов', e);
      Logger.debug('Stack trace: $stackTrace');
      return {};
    }
  }
}
