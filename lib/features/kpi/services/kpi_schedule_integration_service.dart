import '../../work_schedule/models/work_schedule_model.dart';
import '../../work_schedule/services/work_schedule_service.dart';
import '../../../core/utils/logger.dart';

/// Сервис интеграции KPI с графиком работы
/// Обеспечивает связь между KPI и WorkSchedule модулями
class KPIScheduleIntegrationService {
  // Кэш графиков по месяцам
  static final Map<String, WorkSchedule> _scheduleCache = {};
  static DateTime? _lastCacheUpdate;
  static const Duration _cacheTTL = Duration(minutes: 10);

  /// Получить график на месяц (с кэшированием)
  static Future<WorkSchedule> getScheduleForMonth(int year, int month) async {
    final cacheKey = '$year-$month';
    final now = DateTime.now();

    // Проверяем кэш
    if (_scheduleCache.containsKey(cacheKey) &&
        _lastCacheUpdate != null &&
        now.difference(_lastCacheUpdate!) < _cacheTTL) {
      return _scheduleCache[cacheKey]!;
    }

    // Загружаем график
    final schedule = await WorkScheduleService.getSchedule(DateTime(year, month));
    _scheduleCache[cacheKey] = schedule;
    _lastCacheUpdate = now;

    return schedule;
  }

  /// Проверить, была ли запланирована смена для сотрудника в конкретный день
  static Future<ScheduleCheckResult> checkEmployeeSchedule({
    required String employeeName,
    required String shopAddress,
    required DateTime date,
  }) async {
    try {
      final schedule = await getScheduleForMonth(date.year, date.month);

      // Ищем запись для сотрудника на эту дату
      final entries = schedule.entries.where((entry) {
        final isSameDate = entry.date.year == date.year &&
            entry.date.month == date.month &&
            entry.date.day == date.day;
        final isSameEmployee = entry.employeeName == employeeName;
        return isSameDate && isSameEmployee;
      }).toList();

      if (entries.isEmpty) {
        return ScheduleCheckResult(
          isScheduled: false,
          shopAddress: null,
          shiftType: null,
          scheduledStartTime: null,
        );
      }

      // Берём первую подходящую запись (для указанного магазина, если есть)
      WorkScheduleEntry? matchingEntry;
      for (final entry in entries) {
        if (entry.shopAddress == shopAddress) {
          matchingEntry = entry;
          break;
        }
      }
      matchingEntry ??= entries.first;

      // Получаем время начала смены
      final shiftTimeInfo = await WorkScheduleService.getShiftTimeFromSettings(
        matchingEntry.shopAddress,
        matchingEntry.shiftType,
      );

      final scheduledStartTime = DateTime(
        date.year,
        date.month,
        date.day,
        shiftTimeInfo.startTime.hour,
        shiftTimeInfo.startTime.minute,
      );

      return ScheduleCheckResult(
        isScheduled: true,
        shopAddress: matchingEntry.shopAddress,
        shiftType: matchingEntry.shiftType.name,
        scheduledStartTime: scheduledStartTime,
      );
    } catch (e) {
      Logger.error('Ошибка проверки графика сотрудника', e);
      return ScheduleCheckResult(
        isScheduled: false,
        shopAddress: null,
        shiftType: null,
        scheduledStartTime: null,
      );
    }
  }

  /// Рассчитать опоздание
  static LatenessInfo calculateLateness({
    required DateTime? attendanceTime,
    required DateTime? scheduledStartTime,
    int gracePeriodMinutes = 5, // 5 минут допустимое опоздание
  }) {
    if (attendanceTime == null || scheduledStartTime == null) {
      return LatenessInfo(isLate: false, lateMinutes: 0);
    }

    final diff = attendanceTime.difference(scheduledStartTime).inMinutes;

    if (diff > gracePeriodMinutes) {
      return LatenessInfo(isLate: true, lateMinutes: diff);
    }

    return LatenessInfo(isLate: false, lateMinutes: 0);
  }

  /// Получить статистику по графику за месяц для сотрудника
  static Future<EmployeeMonthScheduleStats> getEmployeeMonthScheduleStats({
    required String employeeName,
    required int year,
    required int month,
  }) async {
    try {
      final schedule = await getScheduleForMonth(year, month);

      final employeeEntries = schedule.entries.where((entry) {
        final isSameMonth = entry.date.year == year && entry.date.month == month;
        return isSameMonth && entry.employeeName == employeeName;
      }).toList();

      // Уникальные дни со сменами
      final scheduledDates = <DateTime>{};
      for (final entry in employeeEntries) {
        scheduledDates.add(DateTime(entry.date.year, entry.date.month, entry.date.day));
      }

      return EmployeeMonthScheduleStats(
        employeeName: employeeName,
        year: year,
        month: month,
        scheduledDays: scheduledDates.length,
        entries: employeeEntries,
      );
    } catch (e) {
      Logger.error('Ошибка получения статистики графика сотрудника', e);
      return EmployeeMonthScheduleStats(
        employeeName: employeeName,
        year: year,
        month: month,
        scheduledDays: 0,
        entries: [],
      );
    }
  }

  /// Получить статистику по графику за месяц для магазина
  static Future<ShopMonthScheduleStats> getShopMonthScheduleStats({
    required String shopAddress,
    required int year,
    required int month,
  }) async {
    try {
      final schedule = await getScheduleForMonth(year, month);

      final shopEntries = schedule.entries.where((entry) {
        final isSameMonth = entry.date.year == year && entry.date.month == month;
        return isSameMonth && entry.shopAddress == shopAddress;
      }).toList();

      // Уникальные дни со сменами
      final scheduledDates = <DateTime>{};
      final uniqueEmployees = <String>{};
      for (final entry in shopEntries) {
        scheduledDates.add(DateTime(entry.date.year, entry.date.month, entry.date.day));
        uniqueEmployees.add(entry.employeeName);
      }

      return ShopMonthScheduleStats(
        shopAddress: shopAddress,
        year: year,
        month: month,
        scheduledDays: shopEntries.length, // Общее количество смен
        totalEmployeesScheduled: uniqueEmployees.length,
        entries: shopEntries,
      );
    } catch (e) {
      Logger.error('Ошибка получения статистики графика магазина', e);
      return ShopMonthScheduleStats(
        shopAddress: shopAddress,
        year: year,
        month: month,
        scheduledDays: 0,
        totalEmployeesScheduled: 0,
        entries: [],
      );
    }
  }

  /// Очистить кэш
  static void clearCache() {
    _scheduleCache.clear();
    _lastCacheUpdate = null;
  }
}

/// Результат проверки графика
class ScheduleCheckResult {
  final bool isScheduled;
  final String? shopAddress;
  final String? shiftType;
  final DateTime? scheduledStartTime;

  ScheduleCheckResult({
    required this.isScheduled,
    required this.shopAddress,
    required this.shiftType,
    required this.scheduledStartTime,
  });
}

/// Информация об опоздании
class LatenessInfo {
  final bool isLate;
  final int lateMinutes;

  LatenessInfo({
    required this.isLate,
    required this.lateMinutes,
  });
}

/// Статистика графика сотрудника за месяц
class EmployeeMonthScheduleStats {
  final String employeeName;
  final int year;
  final int month;
  final int scheduledDays;
  final List<WorkScheduleEntry> entries;

  EmployeeMonthScheduleStats({
    required this.employeeName,
    required this.year,
    required this.month,
    required this.scheduledDays,
    required this.entries,
  });
}

/// Статистика графика магазина за месяц
class ShopMonthScheduleStats {
  final String shopAddress;
  final int year;
  final int month;
  final int scheduledDays; // Общее количество смен
  final int totalEmployeesScheduled; // Уникальных сотрудников
  final List<WorkScheduleEntry> entries;

  ShopMonthScheduleStats({
    required this.shopAddress,
    required this.year,
    required this.month,
    required this.scheduledDays,
    required this.totalEmployeesScheduled,
    required this.entries,
  });
}
