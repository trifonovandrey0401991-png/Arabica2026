import '../models/kpi_models.dart';
import '../../attendance/services/attendance_service.dart';
import '../../shifts/services/shift_report_service.dart';
import '../../recount/services/recount_service.dart';
import '../../rko/services/rko_reports_service.dart';
import '../../rko/models/rko_report_model.dart';
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

      // Агрегируем данные по сотрудникам
      final employeesDataMap = KPIAggregationService.aggregateShopDayData(
        attendanceRecords: filteredAttendanceRecords,
        shifts: dayShifts,
        recounts: recounts,
        rkos: dayRKOs,
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
          Logger.debug('      - ${emp.employeeName}: приход=${emp.attendanceTime != null}, пересменка=${emp.hasShift}, пересчет=${emp.hasRecount}, РКО=${emp.hasRKO}, время=$timeStr');
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

      // Агрегируем данные по магазинам и датам
      final shopDaysMap = KPIAggregationService.aggregateEmployeeShopDaysData(
        employeeName: employeeName,
        attendanceRecords: filteredAttendance,
        shifts: employeeShifts,
        recounts: filteredRecounts,
        rkos: filteredRKOs,
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
}
