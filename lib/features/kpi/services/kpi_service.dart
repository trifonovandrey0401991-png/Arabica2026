import '../models/kpi_models.dart';
import '../models/kpi_employee_month_stats.dart';
import '../models/kpi_shop_month_stats.dart';
import '../../shops/models/shop_model.dart';
import '../../attendance/services/attendance_service.dart';
import '../../shifts/services/shift_report_service.dart';
import '../../recount/services/recount_service.dart';
import '../../rko/services/rko_reports_service.dart';
import '../../rko/models/rko_report_model.dart';
import '../../envelope/services/envelope_report_service.dart';
import '../../envelope/models/envelope_report_model.dart';
import '../../shift_handover/services/shift_handover_report_service.dart';
import '../../shift_handover/models/shift_handover_report_model.dart';
import '../../../core/utils/logger.dart';
import 'kpi_cache_service.dart';
import 'kpi_filters.dart';
import 'kpi_aggregation_service.dart';
import 'kpi_normalizers.dart';
import 'kpi_schedule_integration_service.dart';
import '../../work_schedule/models/work_schedule_model.dart';

/// Сервис-координатор для получения и агрегации KPI данных
/// Использует модульную архитектуру:
/// - KPICacheService: управление кэшем
/// - KPIFilters: фильтрация данных
/// - KPIAggregationService: агрегация данных
/// - KPINormalizers: нормализация данных
class KPIService {
  /// Получить данные по магазину за день
  static Future<KPIShopDayData> getShopDayData(
    String shopAddress,
    DateTime date,
  ) async {
    try {
      final normalizedDate = KPINormalizers.normalizeDate(date);

      // Проверяем кэш
      final cached = KPICacheService.getShopDayData(shopAddress, normalizedDate);
      if (cached != null) {
        return cached;
      }

      // Получаем отметки прихода за день
      final dateForQuery = KPINormalizers.normalizeDateForQuery(normalizedDate);
      final attendanceRecords = await AttendanceService.getAttendanceRecords(
        shopAddress: shopAddress,
        date: dateForQuery,
      );

      final filteredAttendanceRecords = KPIFilters.filterAttendanceByDateAndShop(
        records: attendanceRecords,
        date: normalizedDate,
        shopAddress: shopAddress,
      );

      // Получаем пересменки за день
      final allShifts = await ShiftReportService.getReports(
        shopAddress: shopAddress,
        date: normalizedDate,
      );
      final dayShifts = KPIFilters.filterShiftsByDateAndShop(
        shifts: allShifts,
        date: normalizedDate,
        shopAddress: shopAddress,
      );

      // Получаем пересчеты за день
      final recounts = await RecountService.getReports(
        shopAddress: shopAddress,
        date: normalizedDate,
      );

      // Получаем РКО за день
      final shopRKOs = await RKOReportsService.getShopRKOs(shopAddress);
      final dayRKOs = <RKOMetadata>[];

      if (shopRKOs != null && shopRKOs['success'] == true) {
        final allRKOs = <RKOMetadata>[];

        // Собираем РКО из currentMonth
        if (shopRKOs['currentMonth'] != null) {
          for (var rkoJson in (shopRKOs['currentMonth'] as List<dynamic>)) {
            try {
              allRKOs.add(RKOMetadata.fromJson(rkoJson as Map<String, dynamic>));
            } catch (_) {}
          }
        }

        // Собираем РКО из months
        if (shopRKOs['months'] != null) {
          for (var monthData in (shopRKOs['months'] as List<dynamic>)) {
            if (monthData is Map<String, dynamic> && monthData['items'] != null) {
              for (var rkoJson in (monthData['items'] as List<dynamic>)) {
                try {
                  allRKOs.add(RKOMetadata.fromJson(rkoJson as Map<String, dynamic>));
                } catch (_) {}
              }
            }
          }
        }

        dayRKOs.addAll(KPIFilters.filterRKOsByDateAndShop(
          rkos: allRKOs,
          date: normalizedDate,
          shopAddress: shopAddress,
        ));
      }

      // Получаем конверты за день
      final allEnvelopes = await EnvelopeReportService.getReports(shopAddress: shopAddress);
      final dayEnvelopes = allEnvelopes.where((envelope) {
        final envelopeDate = envelope.createdAt.toLocal();
        return envelopeDate.year == normalizedDate.year &&
               envelopeDate.month == normalizedDate.month &&
               envelopeDate.day == normalizedDate.day;
      }).toList();

      // Получаем сдачи смены за день
      final dayShiftHandovers = await ShiftHandoverReportService.getReports(
        shopAddress: shopAddress,
        date: normalizedDate,
      );

      // Агрегируем данные по сотрудникам
      final employeesDataMap = KPIAggregationService.aggregateShopDayData(
        attendanceRecords: filteredAttendanceRecords,
        shifts: dayShifts,
        recounts: recounts,
        rkos: dayRKOs,
        envelopes: dayEnvelopes,
        shiftHandovers: dayShiftHandovers,
        date: normalizedDate,
        shopAddress: shopAddress,
      );

      final result = KPIShopDayData(
        date: normalizedDate,
        shopAddress: shopAddress,
        employeesData: employeesDataMap.values.toList(),
      );

      // Сохраняем в кэш
      KPICacheService.saveShopDayData(shopAddress, normalizedDate, result);

      return result;
    } catch (e) {
      Logger.error('Ошибка получения KPI данных магазина за день', e);
      return KPIShopDayData(
        date: date,
        shopAddress: shopAddress,
        employeesData: [],
      );
    }
  }

  /// Получить данные по сотруднику за период (текущий и предыдущий месяц)
  static Future<KPIEmployeeData> getEmployeeData(
    String employeeName,
  ) async {
    try {
      // Проверяем кэш
      final cached = KPICacheService.getEmployeeData(employeeName);
      if (cached != null) {
        return cached;
      }

      // Получаем данные за текущий и предыдущий месяц
      final attendanceRecords = await AttendanceService.getAttendanceRecords(
        employeeName: employeeName,
      );
      final filteredAttendance = KPIFilters.filterAttendanceByMonths(attendanceRecords);

      final allShifts = await ShiftReportService.getReports(
        employeeName: employeeName,
      );
      final employeeShifts = KPIFilters.filterShiftsByMonths(allShifts);

      final allRecounts = await RecountService.getReports(
        employeeName: employeeName,
      );
      final filteredRecounts = KPIFilters.filterRecountsByMonths(allRecounts);

      final employeeRKOs = await RKOReportsService.getEmployeeRKOs(employeeName);
      final filteredRKOs = <RKOMetadata>[];
      if (employeeRKOs != null && employeeRKOs['success'] == true) {
        final allRKOs = <RKOMetadata>[];

        // Добавляем РКО из latest
        if (employeeRKOs['latest'] != null) {
          final latestList = employeeRKOs['latest'] as List<dynamic>;
          for (var rkoJson in latestList) {
            try {
              final rko = RKOMetadata.fromJson(rkoJson as Map<String, dynamic>);
              allRKOs.add(rko);
            } catch (_) {}
          }
        }

        // Добавляем РКО из всех months
        if (employeeRKOs['months'] != null) {
          final monthsList = employeeRKOs['months'] as List<dynamic>;
          for (var monthData in monthsList) {
            if (monthData is Map<String, dynamic> && monthData['items'] != null) {
              final itemsList = monthData['items'] as List<dynamic>;
              for (var rkoJson in itemsList) {
                try {
                  final rko = RKOMetadata.fromJson(rkoJson as Map<String, dynamic>);
                  allRKOs.add(rko);
                } catch (_) {}
              }
            }
          }
        }

        // Фильтруем по текущему и предыдущему месяцу
        filteredRKOs.addAll(KPIFilters.filterRKOsByMonths(allRKOs));
      }

      // Агрегируем данные по дням
      final daysDataMap = KPIAggregationService.aggregateEmployeeDaysData(
        employeeName: employeeName,
        attendanceRecords: filteredAttendance,
        shifts: employeeShifts,
        recounts: filteredRecounts,
        rkos: filteredRKOs,
      );

      // Подсчитываем статистику
      final stats = KPIAggregationService.calculateEmployeeStats(daysDataMap);

      final result = KPIEmployeeData(
        employeeName: employeeName,
        daysData: daysDataMap,
        totalDaysWorked: stats['totalDaysWorked']!,
        totalShifts: stats['totalShifts']!,
        totalRecounts: stats['totalRecounts']!,
        totalRKOs: stats['totalRKOs']!,
      );

      // Сохраняем в кэш
      KPICacheService.saveEmployeeData(employeeName, result);

      return result;
    } catch (e) {
      Logger.error('Ошибка получения KPI данных сотрудника', e);
      return KPIEmployeeData(
        employeeName: employeeName,
        daysData: {},
        totalDaysWorked: 0,
        totalShifts: 0,
        totalRecounts: 0,
        totalRKOs: 0,
      );
    }
  }

  /// Получить список всех сотрудников (из отметок прихода + график работы)
  static Future<List<String>> getAllEmployees() async {
    try {
      // Проверяем кэш
      final cached = KPICacheService.getAllEmployees();
      if (cached != null) {
        return cached;
      }

      final employeesSet = <String>{};
      final now = DateTime.now();
      final prevMonth = now.month == 1 ? DateTime(now.year - 1, 12) : DateTime(now.year, now.month - 1);

      // Загружаем все данные ПАРАЛЛЕЛЬНО
      final results = await Future.wait([
        AttendanceService.getAttendanceRecords(),
        KPIScheduleIntegrationService.getScheduleForMonth(now.year, now.month),
        KPIScheduleIntegrationService.getScheduleForMonth(prevMonth.year, prevMonth.month),
      ]);

      // 1. Сотрудники из отметок прихода
      final attendanceRecords = results[0] as List<dynamic>;
      for (var record in attendanceRecords) {
        if (record.employeeName.isNotEmpty) {
          final normalizedName = record.employeeName.trim();
          if (normalizedName.isNotEmpty) {
            employeesSet.add(normalizedName);
          }
        }
      }

      // 2. Сотрудники из графика работы (текущий месяц)
      final currentSchedule = results[1] as WorkSchedule;
      for (var entry in currentSchedule.entries) {
        if (entry.employeeName.isNotEmpty) {
          final normalizedName = entry.employeeName.trim();
          if (normalizedName.isNotEmpty) {
            employeesSet.add(normalizedName);
          }
        }
      }

      // 3. Сотрудники из графика работы (прошлый месяц)
      final prevSchedule = results[2] as WorkSchedule;
      for (var entry in prevSchedule.entries) {
        if (entry.employeeName.isNotEmpty) {
          final normalizedName = entry.employeeName.trim();
          if (normalizedName.isNotEmpty) {
            employeesSet.add(normalizedName);
          }
        }
      }

      final employees = employeesSet.toList()..sort();

      // Сохраняем в кэш
      KPICacheService.saveAllEmployees(employees);

      return employees;
    } catch (e) {
      Logger.error('Ошибка получения списка сотрудников', e);
      return [];
    }
  }

  /// Очистить кэш KPI данных
  static void clearCache() {
    KPICacheService.clearAll();
  }

  /// Очистить кэш для конкретной даты и магазина
  static void clearCacheForDate(String shopAddress, DateTime date) {
    KPICacheService.clearForDate(shopAddress, date);
  }

  /// Очистить весь кэш KPI для магазина
  static void clearCacheForShop(String shopAddress) {
    KPICacheService.clearForShop(shopAddress);
  }

  /// Получить месячную статистику сотрудника (текущий, прошлый, позапрошлый месяц)
  static Future<List<KPIEmployeeMonthStats>> getEmployeeMonthlyStats(
    String employeeName,
  ) async {
    try {
      // Получить все данные сотрудника
      final allData = await getEmployeeShopDaysData(employeeName);

      // Определить текущий, прошлый и позапрошлый месяцы
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);

      DateTime previousMonth;
      if (now.month == 1) {
        previousMonth = DateTime(now.year - 1, 12);
      } else {
        previousMonth = DateTime(now.year, now.month - 1);
      }

      DateTime twoMonthsAgo;
      if (now.month <= 2) {
        twoMonthsAgo = DateTime(now.year - 1, 12 + now.month - 2);
      } else {
        twoMonthsAgo = DateTime(now.year, now.month - 2);
      }

      // Группировать по месяцам
      final Map<String, List<KPIEmployeeShopDayData>> byMonth = {
        '${currentMonth.year}-${currentMonth.month}': [],
        '${previousMonth.year}-${previousMonth.month}': [],
        '${twoMonthsAgo.year}-${twoMonthsAgo.month}': [],
      };

      for (final day in allData) {
        final key = '${day.date.year}-${day.date.month}';
        if (byMonth.containsKey(key)) {
          byMonth[key]!.add(day);
        }
      }

      // Агрегировать статистику для каждого месяца (с данными графика)
      final results = await Future.wait([
        _buildMonthStatsWithSchedule(employeeName, currentMonth.year, currentMonth.month, byMonth['${currentMonth.year}-${currentMonth.month}']!),
        _buildMonthStatsWithSchedule(employeeName, previousMonth.year, previousMonth.month, byMonth['${previousMonth.year}-${previousMonth.month}']!),
        _buildMonthStatsWithSchedule(employeeName, twoMonthsAgo.year, twoMonthsAgo.month, byMonth['${twoMonthsAgo.year}-${twoMonthsAgo.month}']!),
      ]);

      return results;
    } catch (e) {
      Logger.error('Ошибка получения месячной статистики сотрудника', e);
      return [];
    }
  }

  /// Построить статистику для одного месяца (синхронная версия без графика)
  static KPIEmployeeMonthStats _buildMonthStats(
    String employeeName,
    int year,
    int month,
    List<KPIEmployeeShopDayData> monthData,
  ) {
    return KPIEmployeeMonthStats(
      employeeName: employeeName,
      year: year,
      month: month,
      daysWorked: monthData.length,
      attendanceCount: monthData.where((d) => d.attendanceTime != null).length,
      shiftsCount: monthData.where((d) => d.hasShift).length,
      recountsCount: monthData.where((d) => d.hasRecount).length,
      rkosCount: monthData.where((d) => d.hasRKO).length,
      envelopesCount: monthData.where((d) => d.hasEnvelope).length,
      shiftHandoversCount: monthData.where((d) => d.hasShiftHandover).length,
    );
  }

  /// Построить статистику для одного месяца с данными графика (ОПТИМИЗИРОВАНО)
  /// Использует уже обогащённые данные из monthData вместо повторных запросов
  static Future<KPIEmployeeMonthStats> _buildMonthStatsWithSchedule(
    String employeeName,
    int year,
    int month,
    List<KPIEmployeeShopDayData> monthData,
  ) async {
    // Получаем данные графика (используется кэш)
    final scheduleStats = await KPIScheduleIntegrationService.getEmployeeMonthScheduleStats(
      employeeName: employeeName,
      year: year,
      month: month,
    );

    // Используем уже вычисленные данные из monthData (они уже обогащены в _enrichWithScheduleData)
    // Это избавляет от N+1 запросов!
    int lateArrivals = 0;
    int totalLateMinutes = 0;
    int missedDays = 0;

    // Создаём карту фактических данных по датам для быстрого поиска
    final dataByDate = <String, List<KPIEmployeeShopDayData>>{};
    for (final data in monthData) {
      final key = '${data.date.year}-${data.date.month}-${data.date.day}';
      dataByDate.putIfAbsent(key, () => []).add(data);
    }

    // Проверяем каждый запланированный день
    for (final entry in scheduleStats.entries) {
      final key = '${entry.date.year}-${entry.date.month}-${entry.date.day}';
      final dayDataList = dataByDate[key];

      if (dayDataList == null || dayDataList.isEmpty) {
        // Сотрудник не пришёл в запланированный день
        missedDays++;
      } else {
        // Используем уже вычисленные данные об опоздании
        for (final data in dayDataList) {
          if (data.isScheduled && data.isLate) {
            lateArrivals++;
            totalLateMinutes += data.lateMinutes ?? 0;
          }
        }
      }
    }

    return KPIEmployeeMonthStats(
      employeeName: employeeName,
      year: year,
      month: month,
      daysWorked: monthData.length,
      attendanceCount: monthData.where((d) => d.attendanceTime != null).length,
      shiftsCount: monthData.where((d) => d.hasShift).length,
      recountsCount: monthData.where((d) => d.hasRecount).length,
      rkosCount: monthData.where((d) => d.hasRKO).length,
      envelopesCount: monthData.where((d) => d.hasEnvelope).length,
      shiftHandoversCount: monthData.where((d) => d.hasShiftHandover).length,
      // Данные графика
      scheduledDays: scheduleStats.scheduledDays,
      missedDays: missedDays,
      lateArrivals: lateArrivals,
      totalLateMinutes: totalLateMinutes,
    );
  }

  /// Получить данные по сотруднику, сгруппированные по магазинам и датам
  static Future<List<KPIEmployeeShopDayData>> getEmployeeShopDaysData(
    String employeeName,
  ) async {
    try {
      // Проверяем кэш
      final cached = KPICacheService.getEmployeeShopDaysData(employeeName);
      if (cached != null) {
        return cached.shopDays;
      }

      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      DateTime previousMonth;
      if (now.month == 1) {
        previousMonth = DateTime(now.year - 1, 12, 1);
      } else {
        previousMonth = DateTime(now.year, now.month - 1, 1);
      }

      // Получаем данные за последние 2 месяца ПАРАЛЛЕЛЬНО
      final results = await Future.wait([
        AttendanceService.getAttendanceRecords(employeeName: employeeName),
        ShiftReportService.getReports(employeeName: employeeName),
        RecountService.getReports(employeeName: employeeName),
        RKOReportsService.getEmployeeRKOs(employeeName),
        EnvelopeReportService.getReports(),
        ShiftHandoverReportService.getReports(employeeName: employeeName),
      ]);

      final attendanceRecords = results[0] as List<dynamic>;
      final filteredAttendance = KPIFilters.filterAttendanceByMonths(
        attendanceRecords.cast(),
      );

      final allShifts = results[1] as List<dynamic>;
      final employeeShifts = KPIFilters.filterShiftsByMonths(allShifts.cast());

      final allRecounts = results[2] as List<dynamic>;
      final filteredRecounts = KPIFilters.filterRecountsByMonths(allRecounts.cast());

      // Обрабатываем РКО
      final employeeRKOs = results[3] as Map<String, dynamic>?;
      final filteredRKOs = <RKOMetadata>[];
      if (employeeRKOs != null && employeeRKOs['success'] == true) {
        final allRKOs = <RKOMetadata>[];

        // Добавляем РКО из latest
        if (employeeRKOs['latest'] != null) {
          for (var rkoJson in (employeeRKOs['latest'] as List<dynamic>)) {
            try {
              allRKOs.add(RKOMetadata.fromJson(rkoJson as Map<String, dynamic>));
            } catch (_) {}
          }
        }

        // Добавляем РКО из months
        if (employeeRKOs['months'] != null) {
          for (var monthData in (employeeRKOs['months'] as List<dynamic>)) {
            if (monthData is Map<String, dynamic> && monthData['items'] != null) {
              for (var rkoJson in (monthData['items'] as List<dynamic>)) {
                try {
                  allRKOs.add(RKOMetadata.fromJson(rkoJson as Map<String, dynamic>));
                } catch (_) {}
              }
            }
          }
        }

        filteredRKOs.addAll(KPIFilters.filterRKOsByMonths(allRKOs));
      }

      // Фильтруем конверты сотрудника
      final allEnvelopes = results[4] as List<dynamic>;
      final filteredEnvelopes = allEnvelopes.cast<EnvelopeReport>().where((envelope) {
        final envelopeDate = envelope.createdAt;
        final isInRange = (envelopeDate.year == currentMonth.year && envelopeDate.month == currentMonth.month) ||
                          (envelopeDate.year == previousMonth.year && envelopeDate.month == previousMonth.month);
        return envelope.employeeName == employeeName && isInRange;
      }).toList();

      // Фильтруем сдачи смены сотрудника
      final allShiftHandovers = results[5] as List<dynamic>;
      final filteredShiftHandovers = allShiftHandovers.cast<ShiftHandoverReport>().where((handover) {
        final handoverDate = handover.createdAt;
        final isInRange = (handoverDate.year == currentMonth.year && handoverDate.month == currentMonth.month) ||
                          (handoverDate.year == previousMonth.year && handoverDate.month == previousMonth.month);
        return isInRange;
      }).toList();

      // Агрегируем данные по магазинам и датам
      final shopDaysMap = KPIAggregationService.aggregateEmployeeShopDaysData(
        employeeName: employeeName,
        attendanceRecords: filteredAttendance,
        shifts: employeeShifts,
        recounts: filteredRecounts,
        rkos: filteredRKOs,
        envelopes: filteredEnvelopes,
        shiftHandovers: filteredShiftHandovers,
      );

      // Обогащаем данными из графика работы
      final enrichedDays = await _enrichWithScheduleData(
        employeeName: employeeName,
        shopDaysMap: shopDaysMap,
      );

      // Сортируем по дате (новые первыми)
      enrichedDays.sort((a, b) => b.date.compareTo(a.date));

      // Сохраняем в кэш
      final cacheData = KPIEmployeeShopDaysData(
        employeeName: employeeName,
        shopDays: enrichedDays,
      );
      KPICacheService.saveEmployeeShopDaysData(employeeName, cacheData);

      return enrichedDays;
    } catch (e) {
      Logger.error('Ошибка получения KPI данных сотрудника (по магазинам)', e);
      return [];
    }
  }

  /// Обогатить данные по дням информацией из графика работы (ОПТИМИЗИРОВАНО)
  static Future<List<KPIEmployeeShopDayData>> _enrichWithScheduleData({
    required String employeeName,
    required Map<String, KPIEmployeeShopDayData> shopDaysMap,
  }) async {
    if (shopDaysMap.isEmpty) return [];

    // Собираем уникальные месяцы для предзагрузки графиков
    final months = <String>{};
    for (final entry in shopDaysMap.entries) {
      months.add('${entry.value.date.year}-${entry.value.date.month}');
    }

    // Предзагружаем все нужные графики ПАРАЛЛЕЛЬНО
    await Future.wait(months.map((m) {
      final parts = m.split('-');
      return KPIScheduleIntegrationService.getScheduleForMonth(
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
    }));

    // Теперь все графики в кэше - обрабатываем ПАРАЛЛЕЛЬНО
    final entries = shopDaysMap.entries.toList();
    final scheduleChecks = await Future.wait(
      entries.map((entry) => KPIScheduleIntegrationService.checkEmployeeSchedule(
        employeeName: employeeName,
        shopAddress: entry.value.shopAddress,
        date: entry.value.date,
      )),
    );

    // Собираем результат
    final enrichedList = <KPIEmployeeShopDayData>[];
    for (var i = 0; i < entries.length; i++) {
      final dayData = entries[i].value;
      final scheduleCheck = scheduleChecks[i];

      if (scheduleCheck.isScheduled) {
        final latenessInfo = KPIScheduleIntegrationService.calculateLateness(
          attendanceTime: dayData.attendanceTime,
          scheduledStartTime: scheduleCheck.scheduledStartTime,
        );

        enrichedList.add(KPIEmployeeShopDayData(
          date: dayData.date,
          shopAddress: dayData.shopAddress,
          employeeName: dayData.employeeName,
          attendanceTime: dayData.attendanceTime,
          hasShift: dayData.hasShift,
          hasRecount: dayData.hasRecount,
          hasRKO: dayData.hasRKO,
          hasEnvelope: dayData.hasEnvelope,
          hasShiftHandover: dayData.hasShiftHandover,
          rkoFileName: dayData.rkoFileName,
          recountReportId: dayData.recountReportId,
          shiftReportId: dayData.shiftReportId,
          envelopeReportId: dayData.envelopeReportId,
          shiftHandoverReportId: dayData.shiftHandoverReportId,
          isScheduled: true,
          scheduledShiftType: scheduleCheck.shiftType,
          scheduledStartTime: scheduleCheck.scheduledStartTime,
          isLate: latenessInfo.isLate,
          lateMinutes: latenessInfo.lateMinutes,
        ));
      } else {
        enrichedList.add(dayData);
      }
    }

    return enrichedList;
  }

  /// Получить список всех магазинов
  static Future<List<String>> getAllShops() async {
    try {
      // Проверяем кэш
      final cached = KPICacheService.getAllShops();
      if (cached != null) {
        return cached;
      }

      final shops = await Shop.loadShopsFromServer();
      final addresses = shops.map((s) => s.address).toList()..sort();

      // Сохраняем в кэш
      KPICacheService.saveAllShops(addresses);

      return addresses;
    } catch (e) {
      Logger.error('Ошибка получения списка магазинов', e);
      return [];
    }
  }

  /// Получить месячную статистику магазина (текущий, прошлый, позапрошлый месяц)
  /// Получить месячную статистику магазина (ОПТИМИЗИРОВАНО)
  /// Загружает все данные одним пакетом вместо множества запросов
  static Future<List<KPIShopMonthStats>> getShopMonthlyStats(String shopAddress) async {
    try {
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);

      DateTime previousMonth;
      if (now.month == 1) {
        previousMonth = DateTime(now.year - 1, 12);
      } else {
        previousMonth = DateTime(now.year, now.month - 1);
      }

      DateTime twoMonthsAgo;
      if (now.month <= 2) {
        twoMonthsAgo = DateTime(now.year - 1, 12 + now.month - 2);
      } else {
        twoMonthsAgo = DateTime(now.year, now.month - 2);
      }

      // Загружаем ВСЕ данные одним пакетом ПАРАЛЛЕЛЬНО
      final results = await Future.wait([
        AttendanceService.getAttendanceRecords(shopAddress: shopAddress),
        ShiftReportService.getReports(shopAddress: shopAddress),
        RecountService.getReports(shopAddress: shopAddress),
        RKOReportsService.getShopRKOs(shopAddress),
        EnvelopeReportService.getReports(),
        ShiftHandoverReportService.getReports(shopAddress: shopAddress),
        KPIScheduleIntegrationService.getShopMonthScheduleStats(shopAddress: shopAddress, year: currentMonth.year, month: currentMonth.month),
        KPIScheduleIntegrationService.getShopMonthScheduleStats(shopAddress: shopAddress, year: previousMonth.year, month: previousMonth.month),
        KPIScheduleIntegrationService.getShopMonthScheduleStats(shopAddress: shopAddress, year: twoMonthsAgo.year, month: twoMonthsAgo.month),
      ]);

      final allAttendance = results[0] as List<dynamic>;
      final allShifts = results[1] as List<dynamic>;
      final allRecounts = results[2] as List<dynamic>;
      // RKO может вернуть Map или null, проверяем тип
      Map<String, dynamic>? shopRKOs;
      if (results[3] is Map<String, dynamic>) {
        shopRKOs = results[3] as Map<String, dynamic>;
      }
      final allEnvelopes = results[4] as List<dynamic>;
      final allShiftHandovers = results[5] as List<dynamic>;
      final currentScheduleStats = results[6] as ShopMonthScheduleStats;
      final prevScheduleStats = results[7] as ShopMonthScheduleStats;
      final twoMonthsScheduleStats = results[8] as ShopMonthScheduleStats;

      // Парсим РКО с защитой от неверных типов
      final allRKOs = <RKOMetadata>[];
      if (shopRKOs != null && shopRKOs['success'] == true) {
        // Парсим currentMonth
        final currentMonthData = shopRKOs['currentMonth'];
        if (currentMonthData is List) {
          for (var rkoJson in currentMonthData) {
            try {
              if (rkoJson is Map<String, dynamic>) {
                allRKOs.add(RKOMetadata.fromJson(rkoJson));
              }
            } catch (_) {}
          }
        }
        // Парсим months
        final monthsData = shopRKOs['months'];
        if (monthsData is Map<String, dynamic>) {
          for (var monthData in monthsData.values) {
            if (monthData is List) {
              for (var rkoJson in monthData) {
                try {
                  if (rkoJson is Map<String, dynamic>) {
                    allRKOs.add(RKOMetadata.fromJson(rkoJson));
                  }
                } catch (_) {}
              }
            }
          }
        } else if (monthsData is List) {
          // Если months - это List вместо Map
          for (var rkoJson in monthsData) {
            try {
              if (rkoJson is Map<String, dynamic>) {
                allRKOs.add(RKOMetadata.fromJson(rkoJson));
              }
            } catch (_) {}
          }
        }
      }

      // Строим статистику для каждого месяца из уже загруженных данных
      final stats = <KPIShopMonthStats>[];

      stats.add(_buildShopMonthStatsFromData(
        shopAddress: shopAddress,
        year: currentMonth.year,
        month: currentMonth.month,
        allAttendance: allAttendance,
        allShifts: allShifts,
        allRecounts: allRecounts,
        allRKOs: allRKOs,
        allEnvelopes: allEnvelopes,
        allShiftHandovers: allShiftHandovers,
        scheduleStats: currentScheduleStats,
      ));

      stats.add(_buildShopMonthStatsFromData(
        shopAddress: shopAddress,
        year: previousMonth.year,
        month: previousMonth.month,
        allAttendance: allAttendance,
        allShifts: allShifts,
        allRecounts: allRecounts,
        allRKOs: allRKOs,
        allEnvelopes: allEnvelopes,
        allShiftHandovers: allShiftHandovers,
        scheduleStats: prevScheduleStats,
      ));

      stats.add(_buildShopMonthStatsFromData(
        shopAddress: shopAddress,
        year: twoMonthsAgo.year,
        month: twoMonthsAgo.month,
        allAttendance: allAttendance,
        allShifts: allShifts,
        allRecounts: allRecounts,
        allRKOs: allRKOs,
        allEnvelopes: allEnvelopes,
        allShiftHandovers: allShiftHandovers,
        scheduleStats: twoMonthsScheduleStats,
      ));

      return stats;
    } catch (e) {
      Logger.error('Ошибка получения месячной статистики магазина', e);
      return [];
    }
  }

  /// Построить статистику магазина за месяц из уже загруженных данных (без дополнительных запросов)
  static KPIShopMonthStats _buildShopMonthStatsFromData({
    required String shopAddress,
    required int year,
    required int month,
    required List<dynamic> allAttendance,
    required List<dynamic> allShifts,
    required List<dynamic> allRecounts,
    required List<RKOMetadata> allRKOs,
    required List<dynamic> allEnvelopes,
    required List<dynamic> allShiftHandovers,
    required ShopMonthScheduleStats scheduleStats,
  }) {
    // Фильтруем данные по месяцу
    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 0, 23, 59, 59);

    bool isInMonth(DateTime date) {
      return date.year == year && date.month == month;
    }

    // Считаем отметки прихода
    final monthAttendance = allAttendance.where((record) {
      try {
        final timestamp = record.timestamp as DateTime;
        return isInMonth(timestamp);
      } catch (_) {
        return false;
      }
    }).toList();

    // Считаем пересменки
    final monthShifts = allShifts.where((shift) {
      try {
        final date = shift.date ?? shift.createdAt as DateTime;
        return isInMonth(date);
      } catch (_) {
        return false;
      }
    }).toList();

    // Считаем пересчёты
    final monthRecounts = allRecounts.where((recount) {
      try {
        final date = recount.date ?? recount.createdAt as DateTime;
        return isInMonth(date);
      } catch (_) {
        return false;
      }
    }).toList();

    // Считаем РКО
    final monthRKOs = allRKOs.where((rko) {
      try {
        return isInMonth(rko.date);
      } catch (_) {
        return false;
      }
    }).toList();

    // Считаем конверты
    final monthEnvelopes = allEnvelopes.where((envelope) {
      try {
        final date = envelope.createdAt as DateTime;
        return isInMonth(date) && envelope.shopAddress == shopAddress;
      } catch (_) {
        return false;
      }
    }).toList();

    // Считаем сдачи смены
    final monthShiftHandovers = allShiftHandovers.where((handover) {
      try {
        final date = handover.createdAt as DateTime;
        return isInMonth(date);
      } catch (_) {
        return false;
      }
    }).toList();

    // Собираем уникальные дни с активностью
    final activeDays = <String>{};
    for (final record in monthAttendance) {
      try {
        final date = record.timestamp as DateTime;
        activeDays.add('${date.year}-${date.month}-${date.day}');
      } catch (_) {}
    }
    for (final shift in monthShifts) {
      try {
        final date = shift.date ?? shift.createdAt as DateTime;
        activeDays.add('${date.year}-${date.month}-${date.day}');
      } catch (_) {}
    }

    return KPIShopMonthStats(
      shopAddress: shopAddress,
      year: year,
      month: month,
      daysWorked: activeDays.length,
      attendanceCount: monthAttendance.length,
      shiftsCount: monthShifts.length,
      recountsCount: monthRecounts.length,
      rkosCount: monthRKOs.length,
      envelopesCount: monthEnvelopes.length,
      shiftHandoversCount: monthShiftHandovers.length,
      scheduledDays: scheduleStats.scheduledDays,
      missedDays: 0, // Упрощаем - не считаем пропуски
      lateArrivals: 0, // Упрощаем - не считаем опоздания
      totalEmployeesScheduled: scheduleStats.totalEmployeesScheduled,
    );
  }

  /// Построить статистику магазина за месяц (СТАРАЯ ВЕРСИЯ - НЕ ИСПОЛЬЗУЕТСЯ)
  /// Оставлена для совместимости с getShopDayData
  static Future<KPIShopMonthStats> _buildShopMonthStatsLegacy(
    String shopAddress,
    int year,
    int month,
  ) async {
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final now = DateTime.now();

    int attendanceCount = 0;
    int shiftsCount = 0;
    int recountsCount = 0;
    int rkosCount = 0;
    int envelopesCount = 0;
    int shiftHandoversCount = 0;
    int daysWithActivity = 0;
    int lateArrivals = 0;

    // Получаем данные графика для магазина
    final scheduleStats = await KPIScheduleIntegrationService.getShopMonthScheduleStats(
      shopAddress: shopAddress,
      year: year,
      month: month,
    );

    // Собираем данные по дням
    final Map<String, KPIShopDayData> dayDataCache = {};
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      // Пропускаем будущие даты
      if (date.isAfter(now)) break;

      final dayData = await getShopDayData(shopAddress, date);
      dayDataCache['$year-$month-$day'] = dayData;

      if (dayData.employeesData.isNotEmpty) {
        daysWithActivity++;
        attendanceCount += dayData.employeesData.where((e) => e.hasMorningAttendance || e.hasEveningAttendance).length;
        shiftsCount += dayData.employeesData.where((e) => e.hasShift).length;
        recountsCount += dayData.employeesData.where((e) => e.hasRecount).length;
        rkosCount += dayData.employeesData.where((e) => e.hasRKO).length;
        envelopesCount += dayData.employeesData.where((e) => e.hasEnvelope).length;
        shiftHandoversCount += dayData.employeesData.where((e) => e.hasShiftHandover).length;
      }
    }

    // Считаем пропуски и опоздания по графику
    int missedDays = 0;
    for (final entry in scheduleStats.entries) {
      final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
      final dayKey = '${entryDate.year}-${entryDate.month}-${entryDate.day}';
      final dayData = dayDataCache[dayKey];

      if (dayData == null || dayData.employeesData.isEmpty) {
        // Сотрудник должен был работать, но данных нет
        missedDays++;
      } else {
        // Ищем запись конкретного сотрудника
        final employeeData = dayData.employeesData.where((e) => e.employeeName == entry.employeeName).toList();
        if (employeeData.isEmpty) {
          missedDays++;
        } else {
          // Проверяем опоздание
          for (final data in employeeData) {
            if (data.attendanceTime != null) {
              final scheduleCheck = await KPIScheduleIntegrationService.checkEmployeeSchedule(
                employeeName: entry.employeeName,
                shopAddress: shopAddress,
                date: entryDate,
              );

              if (scheduleCheck.isScheduled && scheduleCheck.scheduledStartTime != null) {
                final latenessInfo = KPIScheduleIntegrationService.calculateLateness(
                  attendanceTime: data.attendanceTime,
                  scheduledStartTime: scheduleCheck.scheduledStartTime,
                );

                if (latenessInfo.isLate) {
                  lateArrivals++;
                }
              }
            }
          }
        }
      }
    }

    return KPIShopMonthStats(
      shopAddress: shopAddress,
      year: year,
      month: month,
      daysWorked: daysWithActivity,
      attendanceCount: attendanceCount,
      shiftsCount: shiftsCount,
      recountsCount: recountsCount,
      rkosCount: rkosCount,
      envelopesCount: envelopesCount,
      shiftHandoversCount: shiftHandoversCount,
      // Данные графика
      scheduledDays: scheduleStats.scheduledDays,
      missedDays: missedDays,
      lateArrivals: lateArrivals,
      totalEmployeesScheduled: scheduleStats.totalEmployeesScheduled,
    );
  }
}
