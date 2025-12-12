import 'dart:convert';
import 'kpi_models.dart';
import 'attendance_service.dart';
import 'attendance_model.dart';
import 'shift_report_model.dart';
import 'recount_service.dart';
import 'recount_report_model.dart';
import 'rko_reports_service.dart';
import 'rko_report_model.dart';
import 'employee_registration_service.dart';
import 'utils/logger.dart';
import 'utils/cache_manager.dart';

/// Сервис для получения и агрегации KPI данных
class KPIService {
  static const String serverUrl = 'https://arabica26.ru';
  static const Duration cacheDuration = Duration(minutes: 5);

  /// Получить данные по магазину за день
  static Future<KPIShopDayData> getShopDayData(
    String shopAddress,
    DateTime date,
  ) async {
    try {
      // Нормализуем дату (убираем время)
      final normalizedDate = DateTime(date.year, date.month, date.day);
      
      // Проверяем кэш
      final cacheKey = 'kpi_shop_day_${shopAddress}_${normalizedDate.year}_${normalizedDate.month}_${normalizedDate.day}';
      final cached = CacheManager.get<KPIShopDayData>(cacheKey);
      if (cached != null) {
        Logger.debug('KPI данные магазина загружены из кэша');
        return cached;
      }

      Logger.debug('Загрузка KPI данных для магазина $shopAddress за ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');

      // Получаем отметки прихода за день
      final attendanceRecords = await AttendanceService.getAttendanceRecords(
        shopAddress: shopAddress,
        date: normalizedDate,
      );

      // Получаем пересменки за день (из локальных данных)
      // Пересменки хранятся локально, но нужно проверить, есть ли API endpoint
      // Пока используем локальные данные
      final allShifts = await ShiftReport.loadAllReports();
      final dayShifts = allShifts.where((shift) {
        final shiftDate = DateTime(
          shift.createdAt.year,
          shift.createdAt.month,
          shift.createdAt.day,
        );
        return shiftDate == normalizedDate && 
               shift.shopAddress.toLowerCase() == shopAddress.toLowerCase();
      }).toList();

      // Получаем пересчеты за день
      final recounts = await RecountService.getReports(
        shopAddress: shopAddress,
        date: normalizedDate,
      );

      // Получаем РКО за день (нужно получить список и отфильтровать)
      final shopRKOs = await RKOReportsService.getShopRKOs(shopAddress);
      final dayRKOs = <RKOMetadata>[];
      if (shopRKOs != null && shopRKOs['items'] != null) {
        final rkoList = RKOMetadataList.fromJson(shopRKOs);
        dayRKOs.addAll(rkoList.items.where((rko) {
          final rkoDate = DateTime(
            rko.date.year,
            rko.date.month,
            rko.date.day,
          );
          return rkoDate == normalizedDate;
        }));
      }

      // Агрегируем данные по сотрудникам
      final Map<String, KPIDayData> employeesDataMap = {};

      // Добавляем данные из отметок прихода
      for (var record in attendanceRecords) {
        final key = record.employeeName;
        if (!employeesDataMap.containsKey(key)) {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: record.employeeName,
            shopAddress: shopAddress,
            attendanceTime: record.timestamp,
          );
        } else {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: record.employeeName,
            shopAddress: shopAddress,
            attendanceTime: record.timestamp,
            hasShift: employeesDataMap[key]!.hasShift,
            hasRecount: employeesDataMap[key]!.hasRecount,
            hasRKO: employeesDataMap[key]!.hasRKO,
          );
        }
      }

      // Добавляем данные из пересменок
      for (var shift in dayShifts) {
        final key = shift.employeeName;
        if (!employeesDataMap.containsKey(key)) {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: shift.employeeName,
            shopAddress: shopAddress,
            hasShift: true,
          );
        } else {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: shift.employeeName,
            shopAddress: shopAddress,
            attendanceTime: employeesDataMap[key]!.attendanceTime,
            hasShift: true,
            hasRecount: employeesDataMap[key]!.hasRecount,
            hasRKO: employeesDataMap[key]!.hasRKO,
          );
        }
      }

      // Добавляем данные из пересчетов
      for (var recount in recounts) {
        final key = recount.employeeName;
        if (!employeesDataMap.containsKey(key)) {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: recount.employeeName,
            shopAddress: shopAddress,
            hasRecount: true,
          );
        } else {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: recount.employeeName,
            shopAddress: shopAddress,
            attendanceTime: employeesDataMap[key]!.attendanceTime,
            hasShift: employeesDataMap[key]!.hasShift,
            hasRecount: true,
            hasRKO: employeesDataMap[key]!.hasRKO,
          );
        }
      }

      // Добавляем данные из РКО
      for (var rko in dayRKOs) {
        final key = rko.employeeName;
        if (!employeesDataMap.containsKey(key)) {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: rko.employeeName,
            shopAddress: shopAddress,
            hasRKO: true,
          );
        } else {
          employeesDataMap[key] = KPIDayData(
            date: normalizedDate,
            employeeName: rko.employeeName,
            shopAddress: shopAddress,
            attendanceTime: employeesDataMap[key]!.attendanceTime,
            hasShift: employeesDataMap[key]!.hasShift,
            hasRecount: employeesDataMap[key]!.hasRecount,
            hasRKO: true,
          );
        }
      }

      final result = KPIShopDayData(
        date: normalizedDate,
        shopAddress: shopAddress,
        employeesData: employeesDataMap.values.toList(),
      );

      // Сохраняем в кэш
      CacheManager.set(cacheKey, result, duration: cacheDuration);

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
      final cacheKey = 'kpi_employee_$employeeName';
      final cached = CacheManager.get<KPIEmployeeData>(cacheKey);
      if (cached != null) {
        Logger.debug('KPI данные сотрудника загружены из кэша');
        return cached;
      }

      Logger.debug('Загрузка KPI данных для сотрудника $employeeName');

      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      DateTime previousMonth;
      if (now.month == 1) {
        previousMonth = DateTime(now.year - 1, 12, 1);
      } else {
        previousMonth = DateTime(now.year, now.month - 1, 1);
      }

      // Получаем отметки прихода за период
      final attendanceRecords = await AttendanceService.getAttendanceRecords(
        employeeName: employeeName,
      );

      // Фильтруем по текущему и предыдущему месяцу
      final filteredAttendance = attendanceRecords.where((record) {
        final recordMonth = DateTime(record.timestamp.year, record.timestamp.month, 1);
        return recordMonth == currentMonth || recordMonth == previousMonth;
      }).toList();

      // Получаем пересменки за период (из локальных данных)
      final allShifts = await ShiftReport.loadAllReports();
      final employeeShifts = allShifts.where((shift) {
        if (shift.employeeName.toLowerCase() != employeeName.toLowerCase()) {
          return false;
        }
        final shiftMonth = DateTime(shift.createdAt.year, shift.createdAt.month, 1);
        final prevMonth = previousMonth;
        return shiftMonth == currentMonth || shiftMonth == prevMonth;
      }).toList();

      // Получаем пересчеты за период
      final allRecounts = await RecountService.getReports(
        employeeName: employeeName,
      );
      final filteredRecounts = allRecounts.where((recount) {
        final recountMonth = DateTime(recount.completedAt.year, recount.completedAt.month, 1);
        return recountMonth == currentMonth || recountMonth == previousMonth;
      }).toList();

      // Получаем РКО за период
      final employeeRKOs = await RKOReportsService.getEmployeeRKOs(employeeName);
      final filteredRKOs = <RKOMetadata>[];
      if (employeeRKOs != null && employeeRKOs['items'] != null) {
        final rkoList = RKOMetadataList.fromJson(employeeRKOs);
        filteredRKOs.addAll(rkoList.items.where((rko) {
          final rkoMonth = DateTime(rko.date.year, rko.date.month, 1);
          return rkoMonth == currentMonth || rkoMonth == previousMonth;
        }));
      }

      // Агрегируем данные по дням
      final Map<String, KPIDayData> daysDataMap = {};

      // Добавляем данные из отметок прихода
      for (var record in filteredAttendance) {
        final date = DateTime(
          record.timestamp.year,
          record.timestamp.month,
          record.timestamp.day,
        );
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        if (!daysDataMap.containsKey(key)) {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: record.shopAddress,
            attendanceTime: record.timestamp,
          );
        } else {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: daysDataMap[key]!.shopAddress,
            attendanceTime: record.timestamp,
            hasShift: daysDataMap[key]!.hasShift,
            hasRecount: daysDataMap[key]!.hasRecount,
            hasRKO: daysDataMap[key]!.hasRKO,
          );
        }
      }

      // Добавляем данные из пересменок
      for (var shift in employeeShifts) {
        final date = DateTime(
          shift.createdAt.year,
          shift.createdAt.month,
          shift.createdAt.day,
        );
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        if (!daysDataMap.containsKey(key)) {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: shift.shopAddress,
            hasShift: true,
          );
        } else {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: daysDataMap[key]!.shopAddress,
            attendanceTime: daysDataMap[key]!.attendanceTime,
            hasShift: true,
            hasRecount: daysDataMap[key]!.hasRecount,
            hasRKO: daysDataMap[key]!.hasRKO,
          );
        }
      }

      // Добавляем данные из пересчетов
      for (var recount in filteredRecounts) {
        final date = DateTime(
          recount.completedAt.year,
          recount.completedAt.month,
          recount.completedAt.day,
        );
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        if (!daysDataMap.containsKey(key)) {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: recount.shopAddress,
            hasRecount: true,
          );
        } else {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: daysDataMap[key]!.shopAddress,
            attendanceTime: daysDataMap[key]!.attendanceTime,
            hasShift: daysDataMap[key]!.hasShift,
            hasRecount: true,
            hasRKO: daysDataMap[key]!.hasRKO,
          );
        }
      }

      // Добавляем данные из РКО
      for (var rko in filteredRKOs) {
        final date = DateTime(
          rko.date.year,
          rko.date.month,
          rko.date.day,
        );
        final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        
        if (!daysDataMap.containsKey(key)) {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: rko.shopAddress,
            hasRKO: true,
          );
        } else {
          daysDataMap[key] = KPIDayData(
            date: date,
            employeeName: employeeName,
            shopAddress: daysDataMap[key]!.shopAddress,
            attendanceTime: daysDataMap[key]!.attendanceTime,
            hasShift: daysDataMap[key]!.hasShift,
            hasRecount: daysDataMap[key]!.hasRecount,
            hasRKO: true,
          );
        }
      }

      // Подсчитываем статистику
      final totalDaysWorked = daysDataMap.values.where((day) => day.workedToday).length;
      final totalShifts = daysDataMap.values.where((day) => day.hasShift).length;
      final totalRecounts = daysDataMap.values.where((day) => day.hasRecount).length;
      final totalRKOs = daysDataMap.values.where((day) => day.hasRKO).length;

      final result = KPIEmployeeData(
        employeeName: employeeName,
        daysData: daysDataMap,
        totalDaysWorked: totalDaysWorked,
        totalShifts: totalShifts,
        totalRecounts: totalRecounts,
        totalRKOs: totalRKOs,
      );

      // Сохраняем в кэш
      CacheManager.set(cacheKey, result, duration: cacheDuration);

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
      const cacheKey = 'kpi_all_employees';
      final cached = CacheManager.get<List<String>>(cacheKey);
      if (cached != null) {
        Logger.debug('Список сотрудников загружен из кэша');
        return cached;
      }

      Logger.debug('Загрузка списка всех сотрудников');

      // Получаем всех сотрудников из регистрации
      // Используем метод из EmployeeRegistrationService или Google Sheets
      // Пока используем упрощенный подход - получаем из отметок прихода
      final attendanceRecords = await AttendanceService.getAttendanceRecords();
      
      final employeesSet = <String>{};
      for (var record in attendanceRecords) {
        if (record.employeeName.isNotEmpty) {
          employeesSet.add(record.employeeName);
        }
      }

      final employees = employeesSet.toList()..sort();
      
      // Сохраняем в кэш
      CacheManager.set(cacheKey, employees, duration: cacheDuration);

      return employees;
    } catch (e) {
      Logger.error('Ошибка получения списка сотрудников', e);
      return [];
    }
  }

  /// Очистить кэш KPI данных
  static void clearCache() {
    CacheManager.clear();
    Logger.debug('Кэш KPI данных очищен');
  }
}

