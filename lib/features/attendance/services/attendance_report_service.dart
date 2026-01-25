import '../models/attendance_model.dart';
import '../models/shop_attendance_summary.dart';
import '../models/pending_attendance_model.dart';
import '../../shops/models/shop_model.dart';
import '../../employees/pages/employees_page.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/utils/logger.dart';
import 'attendance_service.dart';

/// Модель сводки по сотруднику
class EmployeeAttendanceSummary {
  final String employeeName;
  final String? phone;
  final int totalRecords;
  final int onTimeCount;
  final int lateCount;
  final int todayCount;
  final bool hasTodayAttendance;
  final List<AttendanceRecord> recentRecords;

  EmployeeAttendanceSummary({
    required this.employeeName,
    this.phone,
    required this.totalRecords,
    required this.onTimeCount,
    required this.lateCount,
    required this.todayCount,
    required this.hasTodayAttendance,
    required this.recentRecords,
  });

  double get onTimeRate => totalRecords > 0 ? (onTimeCount / totalRecords) * 100 : 0;
}

/// Сервис для агрегации данных по посещаемости
class AttendanceReportService {
  /// Загрузить сводку по всем магазинам
  static Future<List<ShopAttendanceSummary>> getShopsSummary() async {
    // 1. Загружаем список магазинов
    final shops = await Shop.loadShopsFromServer();

    // 2. Загружаем ВСЕ отметки
    final allRecords = await AttendanceService.getAttendanceRecords();

    // 3. Группируем по магазинам
    final summaries = <ShopAttendanceSummary>[];

    for (final shop in shops) {
      final shopRecords = allRecords
          .where((r) => r.shopAddress == shop.address)
          .toList();

      final summary = _buildShopSummary(shop.address, shopRecords);
      summaries.add(summary);
    }

    // 4. Сортируем: магазины с меньшим количеством отметок сегодня - выше
    summaries.sort((a, b) => a.todayAttendanceCount.compareTo(b.todayAttendanceCount));

    return summaries;
  }

  /// Построить сводку по одному магазину
  static ShopAttendanceSummary _buildShopSummary(
    String shopAddress,
    List<AttendanceRecord> records,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Отметки сегодня
    final todayRecords = records.where((r) {
      final recordDate = DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
      return recordDate == today;
    }).toList();

    // Текущий месяц
    final currentMonthRecords = records.where((r) =>
        r.timestamp.year == now.year && r.timestamp.month == now.month
    ).toList();

    // Прошлый месяц
    final prevMonth = now.month == 1
        ? DateTime(now.year - 1, 12, 1)
        : DateTime(now.year, now.month - 1, 1);
    final prevMonthRecords = records.where((r) =>
        r.timestamp.year == prevMonth.year && r.timestamp.month == prevMonth.month
    ).toList();

    // Считаем приходы вовремя для текущего месяца
    // Плановое количество = дни в месяце * 2 (утро + вечер)
    final daysInCurrentMonth = DateTime(now.year, now.month + 1, 0).day;
    final plannedRecords = daysInCurrentMonth * 2;

    // Приходы вовремя - записи с isOnTime == true
    final onTimeCount = currentMonthRecords.where((r) => r.isOnTime == true).length;

    return ShopAttendanceSummary(
      shopAddress: shopAddress,
      todayAttendanceCount: todayRecords.length,
      currentMonth: _buildMonthSummary(now.year, now.month, currentMonthRecords),
      previousMonth: _buildMonthSummary(prevMonth.year, prevMonth.month, prevMonthRecords),
      totalRecords: plannedRecords,  // Плановое количество (62 для января)
      onTimeRecords: onTimeCount,    // Фактическое количество приходов вовремя
    );
  }

  /// Построить сводку по месяцу
  static MonthAttendanceSummary _buildMonthSummary(
    int year,
    int month,
    List<AttendanceRecord> records,
  ) {
    // Количество дней в месяце
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final plannedCount = daysInMonth * 2; // Утро + ночь каждый день

    // Группируем по дням
    final daysSummary = <DayAttendanceSummary>[];
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final dayRecords = records.where((r) {
        final recordDate = DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
        return recordDate == date;
      }).toList();

      daysSummary.add(_buildDaySummary(date, dayRecords));
    }

    return MonthAttendanceSummary(
      year: year,
      month: month,
      actualCount: records.length,
      plannedCount: plannedCount,
      days: daysSummary,
    );
  }

  /// Построить сводку по дню
  static DayAttendanceSummary _buildDaySummary(
    DateTime date,
    List<AttendanceRecord> records,
  ) {
    bool hasMorning = false;
    bool hasNight = false;
    bool hasDay = false;

    for (final record in records) {
      if (record.shiftType == 'morning') {
        hasMorning = true;
      } else if (record.shiftType == 'night') {
        hasNight = true;
      } else if (record.shiftType == 'day') {
        hasDay = true;
      } else {
        // Если shiftType не указан, определяем по времени
        final hour = record.timestamp.hour;
        if (hour >= 6 && hour < 10) {
          hasMorning = true;
        } else if (hour >= 18 && hour < 22) {
          hasNight = true;
        } else if (hour >= 10 && hour < 18) {
          hasDay = true;
        }
      }
    }

    return DayAttendanceSummary(
      date: date,
      attendanceCount: records.length,
      hasMorning: hasMorning,
      hasNight: hasNight,
      hasDay: hasDay,
      records: records,
    );
  }

  /// Загрузить сводку по сотрудникам
  static Future<List<EmployeeAttendanceSummary>> getEmployeesSummary() async {
    // 1. Загружаем список сотрудников
    final employees = await EmployeesPage.loadEmployeesForNotifications();

    // 2. Загружаем ВСЕ отметки
    final allRecords = await AttendanceService.getAttendanceRecords();

    // 3. Текущая дата
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 4. Группируем по сотрудникам
    final summaries = <EmployeeAttendanceSummary>[];

    for (final employee in employees) {
      final empName = employee.name.toLowerCase().trim();
      final empRecords = allRecords.where((r) =>
          r.employeeName.toLowerCase().trim() == empName
      ).toList();

      // Сегодняшние отметки
      final todayRecords = empRecords.where((r) {
        final recordDate = DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
        return recordDate == today;
      }).toList();

      // Подсчёт вовремя / опоздания
      final onTimeCount = empRecords.where((r) => r.isOnTime == true).length;
      final lateCount = empRecords.where((r) => r.isOnTime == false).length;

      // Последние 10 записей
      final sortedRecords = List<AttendanceRecord>.from(empRecords)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      summaries.add(EmployeeAttendanceSummary(
        employeeName: employee.name,
        phone: employee.phone,
        totalRecords: empRecords.length,
        onTimeCount: onTimeCount,
        lateCount: lateCount,
        todayCount: todayRecords.length,
        hasTodayAttendance: todayRecords.isNotEmpty,
        recentRecords: sortedRecords.take(10).toList(),
      ));
    }

    // 5. Сортируем: сотрудники без отметок сегодня - выше
    summaries.sort((a, b) {
      if (a.hasTodayAttendance && !b.hasTodayAttendance) return 1;
      if (!a.hasTodayAttendance && b.hasTodayAttendance) return -1;
      return a.employeeName.compareTo(b.employeeName);
    });

    return summaries;
  }

  /// Получить опоздавших за сегодня
  static Future<List<AttendanceRecord>> getTodayLateRecords() async {
    final allRecords = await AttendanceService.getAttendanceRecords();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return allRecords.where((r) {
      final recordDate = DateTime(r.timestamp.year, r.timestamp.month, r.timestamp.day);
      return recordDate == today && r.isOnTime == false;
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Получить сотрудников, которые не отметились сегодня
  static Future<List<Employee>> getNotMarkedToday() async {
    final employees = await EmployeesPage.loadEmployeesForNotifications();
    final allRecords = await AttendanceService.getAttendanceRecords();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Собираем имена тех, кто отметился
    final markedNames = <String>{};
    for (final record in allRecords) {
      final recordDate = DateTime(record.timestamp.year, record.timestamp.month, record.timestamp.day);
      if (recordDate == today) {
        markedNames.add(record.employeeName.toLowerCase().trim());
      }
    }

    // Фильтруем сотрудников
    return employees.where((e) =>
        !markedNames.contains(e.name.toLowerCase().trim())
    ).toList();
  }

  /// Получить отметки сотрудника за период
  static Future<List<AttendanceRecord>> getEmployeeRecords(String employeeName, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final allRecords = await AttendanceService.getAttendanceRecords(
      employeeName: employeeName,
    );

    var filtered = allRecords;

    if (startDate != null) {
      filtered = filtered.where((r) => r.timestamp.isAfter(startDate)).toList();
    }
    if (endDate != null) {
      filtered = filtered.where((r) => r.timestamp.isBefore(endDate)).toList();
    }

    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return filtered;
  }

  // ========== PENDING/FAILED REPORTS ==========

  /// Получить pending (ожидающие) отчёты посещаемости
  static Future<List<PendingAttendanceReport>> getPendingReports() async {
    Logger.debug('Fetching pending attendance reports...');

    final result = await BaseHttpService.getList<PendingAttendanceReport>(
      endpoint: '/api/attendance/pending',
      fromJson: (json) => PendingAttendanceReport.fromJson(json),
      itemKey: 'items',
    );

    return result ?? [];
  }

  /// Получить failed (пропущенные) отчёты посещаемости
  static Future<List<PendingAttendanceReport>> getFailedReports() async {
    Logger.debug('Fetching failed attendance reports...');

    final result = await BaseHttpService.getList<PendingAttendanceReport>(
      endpoint: '/api/attendance/failed',
      fromJson: (json) => PendingAttendanceReport.fromJson(json),
      itemKey: 'items',
    );

    return result ?? [];
  }

  /// Проверить, можно ли отметиться на магазине
  static Future<bool> canMarkAttendance(String shopAddress) async {
    Logger.debug('Checking if can mark attendance for $shopAddress...');

    try {
      final result = await BaseHttpService.get<Map<String, dynamic>>(
        endpoint: '/api/attendance/can-mark?shopAddress=${Uri.encodeComponent(shopAddress)}',
        fromJson: (json) => json,
      );

      return result?['canMark'] == true;
    } catch (e) {
      Logger.error('Error checking can-mark attendance', e);
      return false;
    }
  }
}
