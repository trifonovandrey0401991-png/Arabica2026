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
import '../../shift_handover/services/shift_handover_report_service.dart';
import '../../../core/utils/logger.dart';
import 'kpi_cache_service.dart';
import 'kpi_filters.dart';
import 'kpi_aggregation_service.dart';
import 'kpi_normalizers.dart';

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

      Logger.debug('═══════════════════════════════════════════════════════');
      Logger.debug('🔄 НАЧАЛО ЗАГРУЗКИ KPI данных для магазина "$shopAddress" за ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      Logger.debug('═══════════════════════════════════════════════════════');

      // Получаем отметки прихода за день
      final dateForQuery = KPINormalizers.normalizeDateForQuery(normalizedDate);
      Logger.debug('📥 Запрос отметок прихода для $shopAddress за ${dateForQuery.toIso8601String()}');
      final attendanceRecords = await AttendanceService.getAttendanceRecords(
        shopAddress: shopAddress,
        date: dateForQuery,
      );

      Logger.debug('📊 Загружено отметок прихода: ${attendanceRecords.length}');
      if (attendanceRecords.isNotEmpty) {
        Logger.debug('   📋 Список всех отметок:');
        for (var record in attendanceRecords) {
          final recordDate = DateTime(record.timestamp.year, record.timestamp.month, record.timestamp.day);
          final isSameDate = recordDate == normalizedDate;
          Logger.debug('   ✅ Отметка: ${record.employeeName} в ${record.timestamp} (${record.timestamp.hour}:${record.timestamp.minute.toString().padLeft(2, '0')}), дата записи: ${recordDate.year}-${recordDate.month}-${recordDate.day}, совпадает с запрошенной: $isSameDate, магазин: ${record.shopAddress}');
        }
      } else {
        Logger.debug('   ⚠️ Отметок прихода не найдено для этой даты');
      }

      // Фильтруем отметки по дате и магазину
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
      final isTargetDate = normalizedDate.year == 2025 && normalizedDate.month == 12 && normalizedDate.day == 12;
      if (isTargetDate) {
        Logger.debug('═══════════════════════════════════════════════════════');
        Logger.debug('🔍 СПЕЦИАЛЬНЫЙ АНАЛИЗ ДЛЯ 12.12.2025');
        Logger.debug('═══════════════════════════════════════════════════════');
      }
      Logger.debug('📋 Загрузка РКО для магазина: "$shopAddress"');
      Logger.debug('📋 Запрошенная дата для РКО: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      Logger.debug('📋 normalizedDate объект: ${normalizedDate.toIso8601String()}');
      final shopRKOs = await RKOReportsService.getShopRKOs(shopAddress);
      Logger.debug('📋 Ответ API getShopRKOs: ${shopRKOs != null ? "успешно" : "null"}');

      final dayRKOs = <RKOMetadata>[];
      if (shopRKOs != null && shopRKOs['success'] == true) {
        Logger.debug('📋 Структура ответа: keys=${shopRKOs.keys.toList()}');
        Logger.debug('📋 success=${shopRKOs['success']}, currentMonth=${(shopRKOs['currentMonth'] as List?)?.length ?? 0}, months=${(shopRKOs['months'] as List?)?.length ?? 0}');

        // Собираем все РКО из currentMonth и months
        final allRKOs = <RKOMetadata>[];

        // Добавляем РКО из currentMonth
        if (shopRKOs['currentMonth'] != null) {
          final currentMonthList = shopRKOs['currentMonth'] as List<dynamic>;
          Logger.debug('📋 РКО в currentMonth: ${currentMonthList.length}');
          for (var rkoJson in currentMonthList) {
            try {
              final rko = RKOMetadata.fromJson(rkoJson as Map<String, dynamic>);
              allRKOs.add(rko);
            } catch (e) {
              Logger.debug('⚠️ Ошибка парсинга РКО из currentMonth: $e');
            }
          }
        }

        // Добавляем РКО из всех months
        if (shopRKOs['months'] != null) {
          final monthsList = shopRKOs['months'] as List<dynamic>;
          Logger.debug('📋 Месяцев с РКО: ${monthsList.length}');
          for (var monthData in monthsList) {
            if (monthData is Map<String, dynamic> && monthData['items'] != null) {
              final itemsList = monthData['items'] as List<dynamic>;
              Logger.debug('   📋 РКО в месяце ${monthData['month'] ?? 'unknown'}: ${itemsList.length}');
              for (var rkoJson in itemsList) {
                try {
                  final rko = RKOMetadata.fromJson(rkoJson as Map<String, dynamic>);
                  allRKOs.add(rko);
                } catch (e) {
                  Logger.debug('⚠️ Ошибка парсинга РКО из months: $e');
                }
              }
            }
          }
        }

        Logger.debug('📋 Всего РКО собрано из всех источников: ${allRKOs.length}');

        // Фильтруем по дате и магазину
        dayRKOs.addAll(KPIFilters.filterRKOsByDateAndShop(
          rkos: allRKOs,
          date: normalizedDate,
          shopAddress: shopAddress,
          detailedLogging: true,
        ));
      } else {
        Logger.debug('⚠️ РКО не загружены: shopRKOs=${shopRKOs != null}, success=${shopRKOs?['success']}');
        if (shopRKOs != null && shopRKOs['success'] == false) {
          Logger.debug('   ⚠️ API вернул success=false');
        }
      }

      // Получаем конверты за день
      Logger.debug('📋 Загрузка конвертов для магазина: "$shopAddress"');
      Logger.debug('   Дата для фильтра: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      final allEnvelopes = await EnvelopeReportService.getReports(shopAddress: shopAddress);
      Logger.debug('   Всего конвертов для магазина: ${allEnvelopes.length}');
      if (allEnvelopes.isNotEmpty) {
        Logger.debug('   Примеры конвертов:');
        for (var i = 0; i < allEnvelopes.length && i < 3; i++) {
          final env = allEnvelopes[i];
          Logger.debug('     [$i] ID: ${env.id}');
          Logger.debug('         Сотрудник: ${env.employeeName}');
          Logger.debug('         Магазин: ${env.shopAddress}');
          Logger.debug('         Дата UTC: ${env.createdAt.toIso8601String()}');
          Logger.debug('         Дата Local: ${env.createdAt.toLocal().toIso8601String()}');
        }
      }

      // Фильтруем по дате (учитываем, что createdAt в UTC, конвертируем в локальное время)
      final dayEnvelopes = allEnvelopes.where((envelope) {
        final envelopeDate = envelope.createdAt.toLocal();
        final isSameDate = envelopeDate.year == normalizedDate.year &&
                           envelopeDate.month == normalizedDate.month &&
                           envelopeDate.day == normalizedDate.day;
        if (isSameDate) {
          Logger.debug('   ✅ Найден конверт: ${envelope.employeeName} - ${envelope.createdAt.toIso8601String()} (локально: ${envelopeDate.toIso8601String()})');
        }
        return isSameDate;
      }).toList();
      Logger.debug('📋 Загружено конвертов за ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}: ${dayEnvelopes.length}');

      // Получаем сдачи смены за день
      Logger.debug('📋 Загрузка сдач смены для магазина: "$shopAddress"');
      final dayShiftHandovers = await ShiftHandoverReportService.getReports(
        shopAddress: shopAddress,
        date: normalizedDate,
      );
      Logger.debug('📋 Загружено сдач смены: ${dayShiftHandovers.length}');

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

      // Логирование для отладки
      if (isTargetDate) {
        Logger.debug('🔍 === СПЕЦИАЛЬНАЯ ПРОВЕРКА ДЛЯ 12.12.2025 ===');
        Logger.debug('   📋 Загружено отметок прихода: ${attendanceRecords.length}');
        Logger.debug('   📋 После фильтрации: ${filteredAttendanceRecords.length}');
        Logger.debug('   📋 Пересменок: ${dayShifts.length}');
        Logger.debug('   📋 Пересчетов: ${recounts.length}');
        Logger.debug('   📋 РКО: ${dayRKOs.length}');
        Logger.debug('   📋 Конвертов: ${dayEnvelopes.length}');
        Logger.debug('   📋 Сдач смены: ${dayShiftHandovers.length}');
        Logger.debug('   📋 Всего записей сотрудников в employeesDataMap: ${employeesDataMap.length}');
        for (var entry in employeesDataMap.entries) {
          Logger.debug('      - ${entry.key}: утро=${entry.value.hasMorningAttendance}, вечер=${entry.value.hasEveningAttendance}, время=${entry.value.attendanceTime?.hour}:${entry.value.attendanceTime?.minute.toString().padLeft(2, '0')}');
        }
      }

      Logger.debug('═══════════════════════════════════════════════════════');
      Logger.debug('📊 KPIShopDayData создан: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
      Logger.debug('   Сотрудников: ${result.employeesWorkedCount}');
      Logger.debug('   Утренние отметки: ${result.hasMorningAttendance}');
      Logger.debug('   Вечерние отметки: ${result.hasEveningAttendance}');
      Logger.debug('   Всего записей сотрудников: ${result.employeesData.length}');
      Logger.debug('   📋 Загружено РКО: ${dayRKOs.length}');
      if (result.employeesData.isEmpty) {
        Logger.debug('   ⚠️ ВНИМАНИЕ: Список сотрудников пуст!');
        Logger.debug('   📋 Обработано отметок прихода: ${filteredAttendanceRecords.length}');
        if (filteredAttendanceRecords.isNotEmpty) {
          Logger.debug('   📋 Детали отметок:');
          for (var record in filteredAttendanceRecords) {
            Logger.debug('      - ${record.employeeName} в ${record.timestamp.hour}:${record.timestamp.minute.toString().padLeft(2, '0')}');
          }
        }
      } else {
        Logger.debug('   📋 Детали по сотрудникам:');
        for (var emp in result.employeesData) {
          final timeStr = emp.attendanceTime != null
              ? '${emp.attendanceTime!.hour.toString().padLeft(2, '0')}:${emp.attendanceTime!.minute.toString().padLeft(2, '0')}'
              : 'null';
          Logger.debug('      - ${emp.employeeName}: приход=${emp.attendanceTime != null}, пересменка=${emp.hasShift}, пересчет=${emp.hasRecount}, РКО=${emp.hasRKO}, конверт=${emp.hasEnvelope}, сдача смены=${emp.hasShiftHandover}, время=$timeStr');
          Logger.debug('         attendanceTime объект: ${emp.attendanceTime?.toIso8601String() ?? "null"}');
          Logger.debug('         attendanceTime is null: ${emp.attendanceTime == null}');
        }
      }
      Logger.debug('═══════════════════════════════════════════════════════');

      if (isTargetDate) {
        Logger.debug('🔍 === КОНЕЦ ПРОВЕРКИ ДЛЯ 12.12.2025 ===');
        Logger.debug('   ✅ ИТОГОВЫЕ ФЛАГИ: утро=${result.hasMorningAttendance}, вечер=${result.hasEveningAttendance}');
      }

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

      Logger.debug('Загрузка KPI данных для сотрудника $employeeName');

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
            } catch (e) {
              Logger.debug('⚠️ Ошибка парсинга РКО из latest: $e');
            }
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
                } catch (e) {
                  Logger.debug('⚠️ Ошибка парсинга РКО из months: $e');
                }
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

  /// Получить список всех сотрудников (из регистрации)
  static Future<List<String>> getAllEmployees() async {
    try {
      // Проверяем кэш
      final cached = KPICacheService.getAllEmployees();
      if (cached != null) {
        return cached;
      }

      Logger.debug('Загрузка списка всех сотрудников');

      // Получаем всех сотрудников из отметок прихода
      final attendanceRecords = await AttendanceService.getAttendanceRecords();

      Logger.debug('Загружено записей прихода: ${attendanceRecords.length}');

      final employeesSet = <String>{};
      for (var record in attendanceRecords) {
        if (record.employeeName.isNotEmpty) {
          // Нормализуем имя (убираем лишние пробелы, приводим к единому формату)
          final normalizedName = record.employeeName.trim();
          if (normalizedName.isNotEmpty) {
            employeesSet.add(normalizedName);
            Logger.debug('Добавлен сотрудник: "$normalizedName"');
          }
        }
      }

      Logger.debug('Всего уникальных сотрудников: ${employeesSet.length}');
      final employees = employeesSet.toList()..sort();
      Logger.debug('Список сотрудников: $employees');

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
      Logger.debug('Загрузка месячной статистики для сотрудника $employeeName');

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

      Logger.debug('Текущий месяц: ${currentMonth.year}-${currentMonth.month}');
      Logger.debug('Прошлый месяц: ${previousMonth.year}-${previousMonth.month}');
      Logger.debug('Позапрошлый месяц: ${twoMonthsAgo.year}-${twoMonthsAgo.month}');

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

      Logger.debug('Данные по месяцам:');
      Logger.debug('  Текущий: ${byMonth['${currentMonth.year}-${currentMonth.month}']!.length} дней');
      Logger.debug('  Прошлый: ${byMonth['${previousMonth.year}-${previousMonth.month}']!.length} дней');
      Logger.debug('  Позапрошлый: ${byMonth['${twoMonthsAgo.year}-${twoMonthsAgo.month}']!.length} дней');

      // Агрегировать статистику для каждого месяца
      return [
        _buildMonthStats(employeeName, currentMonth.year, currentMonth.month, byMonth['${currentMonth.year}-${currentMonth.month}']!),
        _buildMonthStats(employeeName, previousMonth.year, previousMonth.month, byMonth['${previousMonth.year}-${previousMonth.month}']!),
        _buildMonthStats(employeeName, twoMonthsAgo.year, twoMonthsAgo.month, byMonth['${twoMonthsAgo.year}-${twoMonthsAgo.month}']!),
      ];
    } catch (e) {
      Logger.error('Ошибка получения месячной статистики сотрудника', e);
      return [];
    }
  }

  /// Построить статистику для одного месяца
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

      Logger.debug('Загрузка KPI данных для сотрудника $employeeName (по магазинам)');

      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      DateTime previousMonth;
      if (now.month == 1) {
        previousMonth = DateTime(now.year - 1, 12, 1);
      } else {
        previousMonth = DateTime(now.year, now.month - 1, 1);
      }

      Logger.debug('Фильтрация по месяцам: текущий=${currentMonth.year}-${currentMonth.month}, предыдущий=${previousMonth.year}-${previousMonth.month}');
      Logger.debug('Текущая дата: ${now.year}-${now.month}-${now.day}');

      // Получаем данные за последние 2 месяца
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

        Logger.debug('📋 Структура ответа РКО для $employeeName: keys=${employeeRKOs.keys.toList()}');

        // Добавляем РКО из latest
        if (employeeRKOs['latest'] != null) {
          final latestList = employeeRKOs['latest'] as List<dynamic>;
          Logger.debug('📋 РКО в latest: ${latestList.length}');
          for (var rkoJson in latestList) {
            try {
              final rko = RKOMetadata.fromJson(rkoJson as Map<String, dynamic>);
              allRKOs.add(rko);
            } catch (e) {
              Logger.debug('⚠️ Ошибка парсинга РКО из latest: $e');
            }
          }
        }

        // Добавляем РКО из всех months
        if (employeeRKOs['months'] != null) {
          final monthsList = employeeRKOs['months'] as List<dynamic>;
          Logger.debug('📋 Месяцев с РКО: ${monthsList.length}');
          for (var monthData in monthsList) {
            if (monthData is Map<String, dynamic> && monthData['items'] != null) {
              final itemsList = monthData['items'] as List<dynamic>;
              Logger.debug('   📋 РКО в месяце ${monthData['monthKey'] ?? 'unknown'}: ${itemsList.length}');
              for (var rkoJson in itemsList) {
                try {
                  final rko = RKOMetadata.fromJson(rkoJson as Map<String, dynamic>);
                  allRKOs.add(rko);
                } catch (e) {
                  Logger.debug('⚠️ Ошибка парсинга РКО из months: $e');
                }
              }
            }
          }
        }

        Logger.debug('📋 Всего РКО собрано для $employeeName: ${allRKOs.length}');

        // Фильтруем по текущему и предыдущему месяцу
        filteredRKOs.addAll(KPIFilters.filterRKOsByMonths(allRKOs, detailedLogging: true));
        Logger.debug('📋 РКО после фильтрации по месяцам: ${filteredRKOs.length}');
      } else {
        Logger.debug('⚠️ РКО не загружены для $employeeName: employeeRKOs=${employeeRKOs != null}, success=${employeeRKOs?['success']}');
      }

      // Получаем конверты сотрудника
      Logger.debug('📋 Загрузка конвертов для сотрудника $employeeName');
      final allEnvelopes = await EnvelopeReportService.getReports();
      final filteredEnvelopes = allEnvelopes.where((envelope) {
        final envelopeDate = envelope.createdAt;
        final isInRange = (envelopeDate.year == currentMonth.year && envelopeDate.month == currentMonth.month) ||
                          (envelopeDate.year == previousMonth.year && envelopeDate.month == previousMonth.month);
        return envelope.employeeName == employeeName && isInRange;
      }).toList();
      Logger.debug('📋 Конвертов после фильтрации: ${filteredEnvelopes.length}');

      // Получаем сдачи смены сотрудника
      Logger.debug('📋 Загрузка сдач смены для сотрудника $employeeName');
      final allShiftHandovers = await ShiftHandoverReportService.getReports(employeeName: employeeName);
      final filteredShiftHandovers = allShiftHandovers.where((handover) {
        final handoverDate = handover.createdAt;
        final isInRange = (handoverDate.year == currentMonth.year && handoverDate.month == currentMonth.month) ||
                          (handoverDate.year == previousMonth.year && handoverDate.month == previousMonth.month);
        return isInRange;
      }).toList();
      Logger.debug('📋 Сдач смены после фильтрации: ${filteredShiftHandovers.length}');

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

      // Сортируем по дате (новые первыми)
      final result = shopDaysMap.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      // Сохраняем в кэш
      final cacheData = KPIEmployeeShopDaysData(
        employeeName: employeeName,
        shopDays: result,
      );
      KPICacheService.saveEmployeeShopDaysData(employeeName, cacheData);

      return result;
    } catch (e) {
      Logger.error('Ошибка получения KPI данных сотрудника (по магазинам)', e);
      return [];
    }
  }

  /// Получить список всех магазинов
  static Future<List<String>> getAllShops() async {
    try {
      // Проверяем кэш
      final cached = KPICacheService.getAllShops();
      if (cached != null) {
        return cached;
      }

      Logger.debug('Загрузка списка всех магазинов');

      final shops = await Shop.loadShopsFromServer();
      final addresses = shops.map((s) => s.address).toList()..sort();

      Logger.debug('Всего магазинов: ${addresses.length}');

      // Сохраняем в кэш
      KPICacheService.saveAllShops(addresses);

      return addresses;
    } catch (e) {
      Logger.error('Ошибка получения списка магазинов', e);
      return [];
    }
  }

  /// Получить месячную статистику магазина (текущий, прошлый, позапрошлый месяц)
  static Future<List<KPIShopMonthStats>> getShopMonthlyStats(String shopAddress) async {
    try {
      Logger.debug('Загрузка месячной статистики для магазина $shopAddress');

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

      Logger.debug('Текущий месяц: ${currentMonth.year}-${currentMonth.month}');
      Logger.debug('Прошлый месяц: ${previousMonth.year}-${previousMonth.month}');
      Logger.debug('Позапрошлый месяц: ${twoMonthsAgo.year}-${twoMonthsAgo.month}');

      // Получить данные по каждому месяцу
      final stats = <KPIShopMonthStats>[];

      for (final monthDate in [currentMonth, previousMonth, twoMonthsAgo]) {
        final monthStats = await _buildShopMonthStats(shopAddress, monthDate.year, monthDate.month);
        stats.add(monthStats);
      }

      return stats;
    } catch (e) {
      Logger.error('Ошибка получения месячной статистики магазина', e);
      return [];
    }
  }

  /// Построить статистику магазина за месяц
  static Future<KPIShopMonthStats> _buildShopMonthStats(
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

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      // Пропускаем будущие даты
      if (date.isAfter(now)) break;

      final dayData = await getShopDayData(shopAddress, date);

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
    );
  }
}
