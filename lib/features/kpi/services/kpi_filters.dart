import '../../attendance/models/attendance_model.dart';
import '../../shifts/models/shift_report_model.dart';
import '../../recount/models/recount_report_model.dart';
import '../../rko/models/rko_report_model.dart';
import 'kpi_normalizers.dart';

/// Фильтры для KPI данных
class KPIFilters {
  /// Фильтровать отметки прихода по дате и магазину
  static List<AttendanceRecord> filterAttendanceByDateAndShop({
    required List<AttendanceRecord> records,
    required DateTime date,
    required String shopAddress,
  }) {
    final normalizedDate = KPINormalizers.normalizeDate(date);
    final normalizedShopAddress = KPINormalizers.normalizeShopAddress(shopAddress);

    return records.where((record) {
      final recordDate = DateTime(record.timestamp.year, record.timestamp.month, record.timestamp.day);
      final isSameDate = recordDate.year == normalizedDate.year &&
                        recordDate.month == normalizedDate.month &&
                        recordDate.day == normalizedDate.day;
      final normalizedRecordAddress = KPINormalizers.normalizeShopAddress(record.shopAddress);
      final isSameShop = normalizedRecordAddress == normalizedShopAddress;

      return isSameDate && isSameShop;
    }).toList();
  }

  /// Фильтровать пересменки по дате и магазину
  static List<ShiftReport> filterShiftsByDateAndShop({
    required List<ShiftReport> shifts,
    required DateTime date,
    required String shopAddress,
  }) {
    final normalizedDate = KPINormalizers.normalizeDate(date);

    return shifts.where((shift) {
      final shiftDate = DateTime(
        shift.createdAt.year,
        shift.createdAt.month,
        shift.createdAt.day,
      );
      return shiftDate == normalizedDate &&
             shift.shopAddress.toLowerCase() == shopAddress.toLowerCase();
    }).toList();
  }

  /// Фильтровать РКО по дате и магазину
  static List<RKOMetadata> filterRKOsByDateAndShop({
    required List<RKOMetadata> rkos,
    required DateTime date,
    required String shopAddress,
    bool detailedLogging = false,
  }) {
    final normalizedDate = KPINormalizers.normalizeDate(date);
    final normalizedShopAddress = KPINormalizers.normalizeShopAddress(shopAddress);

    return rkos.where((rko) {
      final rkoDate = DateTime(
        rko.date.year,
        rko.date.month,
        rko.date.day,
      );
      final rkoShopAddress = KPINormalizers.normalizeShopAddress(rko.shopAddress);
      final isDateMatch = rkoDate == normalizedDate;
      final isShopMatch = rkoShopAddress == normalizedShopAddress;

      return isDateMatch && isShopMatch;
    }).toList();
  }

  /// Фильтровать записи по месяцам (текущий и предыдущий)
  static List<T> filterByCurrentAndPreviousMonth<T>({
    required List<T> records,
    required DateTime Function(T) getDate,
  }) {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    DateTime previousMonth;
    if (now.month == 1) {
      previousMonth = DateTime(now.year - 1, 12, 1);
    } else {
      previousMonth = DateTime(now.year, now.month - 1, 1);
    }

    return records.where((record) {
      final recordDate = getDate(record);
      final recordMonth = DateTime(recordDate.year, recordDate.month, 1);
      return recordMonth == currentMonth || recordMonth == previousMonth;
    }).toList();
  }

  /// Фильтровать отметки прихода по месяцам
  static List<AttendanceRecord> filterAttendanceByMonths(List<AttendanceRecord> records) {
    return filterByCurrentAndPreviousMonth<AttendanceRecord>(
      records: records,
      getDate: (record) => record.timestamp,
    );
  }

  /// Фильтровать пересменки по месяцам
  static List<ShiftReport> filterShiftsByMonths(List<ShiftReport> shifts) {
    return filterByCurrentAndPreviousMonth<ShiftReport>(
      records: shifts,
      getDate: (shift) => shift.createdAt,
    );
  }

  /// Фильтровать пересчеты по месяцам
  static List<RecountReport> filterRecountsByMonths(List<RecountReport> recounts) {
    return filterByCurrentAndPreviousMonth<RecountReport>(
      records: recounts,
      getDate: (recount) => recount.completedAt,
    );
  }

  /// Фильтровать РКО по месяцам
  static List<RKOMetadata> filterRKOsByMonths(List<RKOMetadata> rkos, {bool detailedLogging = false}) {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    DateTime previousMonth;
    if (now.month == 1) {
      previousMonth = DateTime(now.year - 1, 12, 1);
    } else {
      previousMonth = DateTime(now.year, now.month - 1, 1);
    }

    return rkos.where((rko) {
      final rkoMonth = DateTime(rko.date.year, rko.date.month, 1);
      return rkoMonth == currentMonth || rkoMonth == previousMonth;
    }).toList();
  }
}
