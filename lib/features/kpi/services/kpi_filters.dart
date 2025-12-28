import '../../attendance/models/attendance_model.dart';
import '../../shifts/models/shift_report_model.dart';
import '../../recount/models/recount_report_model.dart';
import '../../rko/models/rko_report_model.dart';
import '../../../core/utils/logger.dart';
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

    Logger.debug('═══════════════════════════════════════════════════════');
    Logger.debug('🔍 ФИЛЬТРАЦИЯ ОТМЕТОК ПРИХОДА');
    Logger.debug('   Запрошенный магазин: "$shopAddress"');
    Logger.debug('   Нормализованный адрес: "$normalizedShopAddress"');
    Logger.debug('   Запрошенная дата: ${normalizedDate.year}-${normalizedDate.month.toString().padLeft(2, '0')}-${normalizedDate.day.toString().padLeft(2, '0')}');
    Logger.debug('   Всего отметок до фильтрации: ${records.length}');
    Logger.debug('═══════════════════════════════════════════════════════');

    final filtered = records.where((record) {
      // Нормализуем дату отметки (убираем время)
      final recordDate = DateTime(record.timestamp.year, record.timestamp.month, record.timestamp.day);
      final isSameDate = recordDate.year == normalizedDate.year &&
                        recordDate.month == normalizedDate.month &&
                        recordDate.day == normalizedDate.day;
      final normalizedRecordAddress = KPINormalizers.normalizeShopAddress(record.shopAddress);
      final isSameShop = normalizedRecordAddress == normalizedShopAddress;

      // Детальное логирование для каждой отметки
      Logger.debug('   🔍 Проверка отметки:');
      Logger.debug('      - Сотрудник: "${record.employeeName}"');
      Logger.debug('      - Время: ${record.timestamp.hour}:${record.timestamp.minute.toString().padLeft(2, '0')}');
      Logger.debug('      - Дата отметки: ${recordDate.year}-${recordDate.month.toString().padLeft(2, '0')}-${recordDate.day.toString().padLeft(2, '0')}');
      Logger.debug('      - Запрошенная дата: ${normalizedDate.year}-${normalizedDate.month.toString().padLeft(2, '0')}-${normalizedDate.day.toString().padLeft(2, '0')}');
      Logger.debug('      - Даты совпадают: $isSameDate (год: ${recordDate.year == normalizedDate.year}, месяц: ${recordDate.month == normalizedDate.month}, день: ${recordDate.day == normalizedDate.day})');
      Logger.debug('      - Магазин (оригинал): "${record.shopAddress}"');
      Logger.debug('      - Магазин (нормализован): "$normalizedRecordAddress"');
      Logger.debug('      - Запрошенный магазин (нормализован): "$normalizedShopAddress"');
      Logger.debug('      - Магазины совпадают: $isSameShop');

      if (!isSameDate || !isSameShop) {
        final reasons = <String>[];
        if (!isSameDate) {
          reasons.add('дата не совпадает');
        }
        if (!isSameShop) {
          reasons.add('магазин не совпадает');
        }
        Logger.debug('      ⚠️ ОТМЕТКА ОТФИЛЬТРОВАНА: ${reasons.join(', ')}');
      } else {
        Logger.debug('      ✅ ОТМЕТКА ПРОШЛА ФИЛЬТРАЦИЮ');
      }

      return isSameDate && isSameShop;
    }).toList();

    Logger.debug('📊 После фильтрации осталось отметок: ${filtered.length}');
    return filtered;
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

    final isTargetDate = normalizedDate.year == 2025 && normalizedDate.month == 12 && normalizedDate.day == 12;
    if (isTargetDate) {
      Logger.debug('═══════════════════════════════════════════════════════');
      Logger.debug('🔍 СПЕЦИАЛЬНЫЙ АНАЛИЗ ДЛЯ 12.12.2025');
      Logger.debug('═══════════════════════════════════════════════════════');
    }

    Logger.debug('📋 Фильтрация РКО для магазина: "$shopAddress"');
    Logger.debug('📋 Запрошенная дата: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
    Logger.debug('📋 Всего РКО до фильтрации: ${rkos.length}');
    Logger.debug('   🔍 Нормализованный адрес магазина: "$normalizedShopAddress"');

    if (rkos.isNotEmpty) {
      Logger.debug('   📋 Первые 10 РКО (для анализа):');
      for (var i = 0; i < (rkos.length > 10 ? 10 : rkos.length); i++) {
        final rko = rkos[i];
        final rkoDateNormalized = DateTime(rko.date.year, rko.date.month, rko.date.day);
        Logger.debug('      ${i + 1}. ${rko.employeeName}');
        Logger.debug('         - date (оригинал из API): ${rko.date.toIso8601String()}');
        Logger.debug('         - date (нормализован): ${rkoDateNormalized.year}-${rkoDateNormalized.month.toString().padLeft(2, '0')}-${rkoDateNormalized.day.toString().padLeft(2, '0')}');
        Logger.debug('         - магазин: "${rko.shopAddress}"');
      }
    }

    final filtered = rkos.where((rko) {
      final rkoDate = DateTime(
        rko.date.year,
        rko.date.month,
        rko.date.day,
      );
      final rkoShopAddress = KPINormalizers.normalizeShopAddress(rko.shopAddress);
      final rkoEmployeeName = KPINormalizers.normalizeEmployeeName(rko.employeeName);
      final isDateMatch = rkoDate == normalizedDate;
      final isShopMatch = rkoShopAddress == normalizedShopAddress;

      // Логируем для всех РКО, но более детально для целевой даты
      final shouldLogDetail = isTargetDate || isDateMatch || detailedLogging;
      if (shouldLogDetail) {
        Logger.debug('   🔍 РКО:');
        Logger.debug('      - employeeName (оригинал): "${rko.employeeName}"');
        Logger.debug('      - employeeName (нормализован): "$rkoEmployeeName"');
        Logger.debug('      - date (оригинал из объекта): ${rko.date.toIso8601String()}');
        Logger.debug('      - date (год/месяц/день): ${rko.date.year}/${rko.date.month}/${rko.date.day}');
        Logger.debug('      - date (нормализован): ${rkoDate.year}-${rkoDate.month.toString().padLeft(2, '0')}-${rkoDate.day.toString().padLeft(2, '0')}');
        Logger.debug('      - rkoDate объект: ${rkoDate.toIso8601String()}');
        Logger.debug('      - shopAddress (оригинал): "${rko.shopAddress}"');
        Logger.debug('      - shopAddress (нормализован): "$rkoShopAddress"');
        Logger.debug('      - Запрошенная дата: ${normalizedDate.year}-${normalizedDate.month.toString().padLeft(2, '0')}-${normalizedDate.day.toString().padLeft(2, '0')}');
        Logger.debug('      - normalizedDate объект: ${normalizedDate.toIso8601String()}');
        Logger.debug('      - Запрошенный магазин (нормализован): "$normalizedShopAddress"');
        Logger.debug('      - Сравнение дат: rkoDate == normalizedDate: ${rkoDate == normalizedDate}');
        Logger.debug('      - Сравнение по компонентам: год=${rkoDate.year == normalizedDate.year}, месяц=${rkoDate.month == normalizedDate.month}, день=${rkoDate.day == normalizedDate.day}');
        Logger.debug('      - Дата совпадает: $isDateMatch');
        Logger.debug('      - Магазин совпадает: $isShopMatch');
        Logger.debug('      - ПРОЙДЕТ ФИЛЬТРАЦИЮ: ${isDateMatch && isShopMatch}');
      }

      return isDateMatch && isShopMatch;
    }).toList();

    Logger.debug('📋 РКО после фильтрации: ${filtered.length}');
    if (filtered.isEmpty && rkos.isNotEmpty) {
      Logger.debug('   ⚠️ ВНИМАНИЕ: РКО загружены, но ни одно не прошло фильтрацию!');
      Logger.debug('   🔍 Проверка: запрошенная дата=${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}, нормализованный адрес="$normalizedShopAddress"');
    }

    return filtered;
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

    if (detailedLogging) {
      Logger.debug('Фильтрация РКО по месяцам: текущий=${currentMonth.year}-${currentMonth.month}, предыдущий=${previousMonth.year}-${previousMonth.month}');
    }

    final filtered = rkos.where((rko) {
      final rkoMonth = DateTime(rko.date.year, rko.date.month, 1);
      final matches = rkoMonth == currentMonth || rkoMonth == previousMonth;
      if (detailedLogging && !matches) {
        Logger.debug('   РКО отфильтровано: дата=${rko.date.year}-${rko.date.month}-${rko.date.day}, месяц=${rkoMonth.year}-${rkoMonth.month}');
      } else if (detailedLogging) {
        Logger.debug('   ✅ РКО прошло фильтр: дата=${rko.date.year}-${rko.date.month}-${rko.date.day}, магазин=${rko.shopAddress}');
      }
      return matches;
    }).toList();

    if (detailedLogging) {
      Logger.debug('📋 РКО после фильтрации по месяцам: ${filtered.length}');
    }

    return filtered;
  }
}
