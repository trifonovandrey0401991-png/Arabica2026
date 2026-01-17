import '../models/attendance_model.dart';
import '../models/shop_attendance_summary.dart';
import '../../shops/models/shop_model.dart';
import 'attendance_service.dart';

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

    return ShopAttendanceSummary(
      shopAddress: shopAddress,
      todayAttendanceCount: todayRecords.length,
      currentMonth: _buildMonthSummary(now.year, now.month, currentMonthRecords),
      previousMonth: _buildMonthSummary(prevMonth.year, prevMonth.month, prevMonthRecords),
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
}
