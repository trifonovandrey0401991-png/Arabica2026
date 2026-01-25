import '../models/kpi_models.dart';
import '../../attendance/models/attendance_model.dart';
import '../../shifts/models/shift_report_model.dart';
import '../../recount/models/recount_report_model.dart';
import '../../rko/models/rko_report_model.dart';
import '../../envelope/models/envelope_report_model.dart';
import '../../shift_handover/models/shift_handover_report_model.dart';
import '../../../core/utils/logger.dart';
import '../../../core/constants/app_constants.dart';
import 'kpi_normalizers.dart';

/// Сервис для агрегации KPI данных
class KPIAggregationService {
  /// Агрегировать данные по сотрудникам для дня магазина
  static Map<String, KPIDayData> aggregateShopDayData({
    required List<AttendanceRecord> attendanceRecords,
    required List<ShiftReport> shifts,
    required List<RecountReport> recounts,
    required List<RKOMetadata> rkos,
    required List<EnvelopeReport> envelopes,
    required List<ShiftHandoverReport> shiftHandovers,
    required DateTime date,
    required String shopAddress,
  }) {
    final normalizedDate = KPINormalizers.normalizeDate(date);
    final Map<String, KPIDayData> employeesDataMap = {};

    // Обработка всех типов данных
    _processAttendanceRecords(
      employeesDataMap: employeesDataMap,
      attendanceRecords: attendanceRecords,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    _processShifts(
      employeesDataMap: employeesDataMap,
      shifts: shifts,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    _processRecounts(
      employeesDataMap: employeesDataMap,
      recounts: recounts,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    _processRKOs(
      employeesDataMap: employeesDataMap,
      rkos: rkos,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    _processEnvelopes(
      employeesDataMap: employeesDataMap,
      envelopes: envelopes,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    _processShiftHandovers(
      employeesDataMap: employeesDataMap,
      shiftHandovers: shiftHandovers,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    return employeesDataMap;
  }

  /// Обработать отметки прихода
  static void _processAttendanceRecords({
    required Map<String, KPIDayData> employeesDataMap,
    required List<AttendanceRecord> attendanceRecords,
    required DateTime normalizedDate,
    required String shopAddress,
  }) {
    for (var record in attendanceRecords) {
      final key = KPINormalizers.normalizeEmployeeName(record.employeeName);
      final recordTime = record.timestamp;
      final isMorning = recordTime.hour < AppConstants.eveningBoundaryHour;
      final isEvening = recordTime.hour >= AppConstants.eveningBoundaryHour;

      if (!employeesDataMap.containsKey(key)) {
        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: record.employeeName,
          shopAddress: shopAddress,
          attendanceTime: recordTime,
          hasMorningAttendance: isMorning,
          hasEveningAttendance: isEvening,
        );
      } else {
        final existing = employeesDataMap[key]!;
        final earliestTime = existing.attendanceTime == null || recordTime.isBefore(existing.attendanceTime!)
            ? recordTime
            : existing.attendanceTime!;

        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: record.employeeName,
          shopAddress: shopAddress,
          attendanceTime: earliestTime,
          hasMorningAttendance: existing.hasMorningAttendance || isMorning,
          hasEveningAttendance: existing.hasEveningAttendance || isEvening,
          hasShift: existing.hasShift,
          hasRecount: existing.hasRecount,
          hasRKO: existing.hasRKO,
          hasEnvelope: existing.hasEnvelope,
          hasShiftHandover: existing.hasShiftHandover,
        );
      }
    }
  }

  /// Обработать пересменки
  static void _processShifts({
    required Map<String, KPIDayData> employeesDataMap,
    required List<ShiftReport> shifts,
    required DateTime normalizedDate,
    required String shopAddress,
  }) {
    for (var shift in shifts) {
      final key = KPINormalizers.normalizeEmployeeName(shift.employeeName);
      final existing = employeesDataMap[key];

      if (existing == null) {
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
          attendanceTime: existing.attendanceTime,
          hasMorningAttendance: existing.hasMorningAttendance,
          hasEveningAttendance: existing.hasEveningAttendance,
          hasShift: true,
          hasRecount: existing.hasRecount,
          hasRKO: existing.hasRKO,
          hasEnvelope: existing.hasEnvelope,
          hasShiftHandover: existing.hasShiftHandover,
        );
      }
    }
  }

  /// Обработать пересчеты
  static void _processRecounts({
    required Map<String, KPIDayData> employeesDataMap,
    required List<RecountReport> recounts,
    required DateTime normalizedDate,
    required String shopAddress,
  }) {
    for (var recount in recounts) {
      final key = KPINormalizers.normalizeEmployeeName(recount.employeeName);
      final existing = employeesDataMap[key];

      if (existing == null) {
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
          attendanceTime: existing.attendanceTime,
          hasMorningAttendance: existing.hasMorningAttendance,
          hasEveningAttendance: existing.hasEveningAttendance,
          hasShift: existing.hasShift,
          hasRecount: true,
          hasRKO: existing.hasRKO,
          hasEnvelope: existing.hasEnvelope,
          hasShiftHandover: existing.hasShiftHandover,
        );
      }
    }
  }

  /// Обработать РКО
  static void _processRKOs({
    required Map<String, KPIDayData> employeesDataMap,
    required List<RKOMetadata> rkos,
    required DateTime normalizedDate,
    required String shopAddress,
  }) {
    for (var rko in rkos) {
      final key = KPINormalizers.normalizeEmployeeName(rko.employeeName);
      final existing = employeesDataMap[key];

      if (existing == null) {
        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: rko.employeeName,
          shopAddress: shopAddress,
          hasRKO: true,
        );
      } else {
        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: existing.employeeName,
          shopAddress: shopAddress,
          attendanceTime: existing.attendanceTime,
          hasMorningAttendance: existing.hasMorningAttendance,
          hasEveningAttendance: existing.hasEveningAttendance,
          hasShift: existing.hasShift,
          hasRecount: existing.hasRecount,
          hasRKO: true,
          hasEnvelope: existing.hasEnvelope,
          hasShiftHandover: existing.hasShiftHandover,
        );
      }
    }
  }

  /// Обработать конверты
  static void _processEnvelopes({
    required Map<String, KPIDayData> employeesDataMap,
    required List<EnvelopeReport> envelopes,
    required DateTime normalizedDate,
    required String shopAddress,
  }) {
    for (var envelope in envelopes) {
      final key = KPINormalizers.normalizeEmployeeName(envelope.employeeName);
      final existing = employeesDataMap[key];

      if (existing == null) {
        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: envelope.employeeName,
          shopAddress: shopAddress,
          hasEnvelope: true,
        );
      } else {
        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: existing.employeeName,
          shopAddress: shopAddress,
          attendanceTime: existing.attendanceTime,
          hasMorningAttendance: existing.hasMorningAttendance,
          hasEveningAttendance: existing.hasEveningAttendance,
          hasShift: existing.hasShift,
          hasRecount: existing.hasRecount,
          hasRKO: existing.hasRKO,
          hasEnvelope: true,
          hasShiftHandover: existing.hasShiftHandover,
        );
      }
    }
  }

  /// Обработать сдачи смены
  static void _processShiftHandovers({
    required Map<String, KPIDayData> employeesDataMap,
    required List<ShiftHandoverReport> shiftHandovers,
    required DateTime normalizedDate,
    required String shopAddress,
  }) {
    for (var handover in shiftHandovers) {
      final key = KPINormalizers.normalizeEmployeeName(handover.employeeName);
      final existing = employeesDataMap[key];

      if (existing == null) {
        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: handover.employeeName,
          shopAddress: shopAddress,
          hasShiftHandover: true,
        );
      } else {
        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: existing.employeeName,
          shopAddress: shopAddress,
          attendanceTime: existing.attendanceTime,
          hasMorningAttendance: existing.hasMorningAttendance,
          hasEveningAttendance: existing.hasEveningAttendance,
          hasShift: existing.hasShift,
          hasRecount: existing.hasRecount,
          hasRKO: existing.hasRKO,
          hasEnvelope: existing.hasEnvelope,
          hasShiftHandover: true,
        );
      }
    }
  }

  /// Агрегировать данные сотрудника по дням
  static Map<String, KPIDayData> aggregateEmployeeDaysData({
    required String employeeName,
    required List<AttendanceRecord> attendanceRecords,
    required List<ShiftReport> shifts,
    required List<RecountReport> recounts,
    required List<RKOMetadata> rkos,
  }) {
    final Map<String, KPIDayData> daysDataMap = {};

    // Добавляем данные из отметок прихода
    for (var record in attendanceRecords) {
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
    for (var shift in shifts) {
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
    for (var recount in recounts) {
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
    for (var rko in rkos) {
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

    return daysDataMap;
  }

  /// Агрегировать данные сотрудника по магазинам и датам
  static Map<String, KPIEmployeeShopDayData> aggregateEmployeeShopDaysData({
    required String employeeName,
    required List<AttendanceRecord> attendanceRecords,
    required List<ShiftReport> shifts,
    required List<RecountReport> recounts,
    required List<RKOMetadata> rkos,
    required List<EnvelopeReport> envelopes,
    required List<ShiftHandoverReport> shiftHandovers,
  }) {
    final Map<String, KPIEmployeeShopDayData> shopDaysMap = {};

    // Функция для создания ключа магазин+дата (с нормализацией адреса)
    String createShopDayKey(String shopAddress, DateTime date) {
      final normalizedAddress = KPINormalizers.normalizeShopAddress(shopAddress);
      final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      return '$normalizedAddress|$dateKey';
    }

    // Добавляем данные из отметок прихода
    for (var record in attendanceRecords) {
      final date = DateTime(
        record.timestamp.year,
        record.timestamp.month,
        record.timestamp.day,
      );
      final key = createShopDayKey(record.shopAddress, date);

      if (!shopDaysMap.containsKey(key)) {
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: record.shopAddress,
          employeeName: employeeName,
          attendanceTime: record.timestamp.isUtc ? record.timestamp.toLocal() : record.timestamp,
        );
      } else {
        // Обновляем время прихода, если текущее раньше
        final existing = shopDaysMap[key]!;
        final recordTime = record.timestamp.isUtc ? record.timestamp.toLocal() : record.timestamp;
        final earliestTime = existing.attendanceTime == null ||
            (recordTime.isBefore(existing.attendanceTime!))
            ? recordTime
            : existing.attendanceTime!;

        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: record.shopAddress,
          employeeName: employeeName,
          attendanceTime: earliestTime,
          hasShift: existing.hasShift,
          hasRecount: existing.hasRecount,
          hasRKO: existing.hasRKO,
          hasEnvelope: existing.hasEnvelope,
          hasShiftHandover: existing.hasShiftHandover,
          rkoFileName: existing.rkoFileName,
          recountReportId: existing.recountReportId,
          shiftReportId: existing.shiftReportId,
          envelopeReportId: existing.envelopeReportId,
          shiftHandoverReportId: existing.shiftHandoverReportId,
        );
      }
    }

    // Добавляем данные из пересменок
    for (var shift in shifts) {
      final date = DateTime(shift.createdAt.year, shift.createdAt.month, shift.createdAt.day);
      final key = createShopDayKey(shift.shopAddress, date);

      if (!shopDaysMap.containsKey(key)) {
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: shift.shopAddress,
          employeeName: employeeName,
          hasShift: true,
          shiftReportId: shift.id,
        );
      } else {
        final existing = shopDaysMap[key]!;
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: shift.shopAddress,
          employeeName: employeeName,
          attendanceTime: existing.attendanceTime,
          hasShift: true,
          hasRecount: existing.hasRecount,
          hasRKO: existing.hasRKO,
          hasEnvelope: existing.hasEnvelope,
          hasShiftHandover: existing.hasShiftHandover,
          rkoFileName: existing.rkoFileName,
          recountReportId: existing.recountReportId,
          shiftReportId: shift.id,
          envelopeReportId: existing.envelopeReportId,
          shiftHandoverReportId: existing.shiftHandoverReportId,
        );
      }
    }

    // Добавляем данные из пересчетов
    for (var recount in recounts) {
      final date = DateTime(recount.completedAt.year, recount.completedAt.month, recount.completedAt.day);
      final key = createShopDayKey(recount.shopAddress, date);

      if (!shopDaysMap.containsKey(key)) {
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: recount.shopAddress,
          employeeName: employeeName,
          hasRecount: true,
          recountReportId: recount.id,
        );
      } else {
        final existing = shopDaysMap[key]!;
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: recount.shopAddress,
          employeeName: employeeName,
          attendanceTime: existing.attendanceTime,
          hasShift: existing.hasShift,
          hasRecount: true,
          hasRKO: existing.hasRKO,
          hasEnvelope: existing.hasEnvelope,
          hasShiftHandover: existing.hasShiftHandover,
          rkoFileName: existing.rkoFileName,
          recountReportId: recount.id,
          shiftReportId: existing.shiftReportId,
          envelopeReportId: existing.envelopeReportId,
          shiftHandoverReportId: existing.shiftHandoverReportId,
        );
      }
    }

    // Добавляем данные из РКО
    for (var rko in rkos) {
      final date = DateTime(rko.date.year, rko.date.month, rko.date.day);
      final key = createShopDayKey(rko.shopAddress, date);
      final normalizedRkoAddress = KPINormalizers.normalizeShopAddress(rko.shopAddress);

      if (shopDaysMap.containsKey(key)) {
        final existing = shopDaysMap[key]!;
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: existing.date,
          shopAddress: existing.shopAddress,
          employeeName: employeeName,
          attendanceTime: existing.attendanceTime,
          hasShift: existing.hasShift,
          hasRecount: existing.hasRecount,
          hasRKO: true,
          hasEnvelope: existing.hasEnvelope,
          hasShiftHandover: existing.hasShiftHandover,
          rkoFileName: rko.fileName,
          recountReportId: existing.recountReportId,
          shiftReportId: existing.shiftReportId,
          envelopeReportId: existing.envelopeReportId,
          shiftHandoverReportId: existing.shiftHandoverReportId,
        );
      } else {
        // Поиск по нормализованному адресу
        KPIEmployeeShopDayData? existingRecord;
        String? existingKey;

        for (var entry in shopDaysMap.entries) {
          final existingNormalized = KPINormalizers.normalizeShopAddress(entry.value.shopAddress);
          if (existingNormalized == normalizedRkoAddress &&
              entry.value.date.year == date.year &&
              entry.value.date.month == date.month &&
              entry.value.date.day == date.day) {
            existingRecord = entry.value;
            existingKey = entry.key;
            break;
          }
        }

        if (existingRecord != null) {
          shopDaysMap[existingKey!] = KPIEmployeeShopDayData(
            date: existingRecord.date,
            shopAddress: existingRecord.shopAddress,
            employeeName: employeeName,
            attendanceTime: existingRecord.attendanceTime,
            hasShift: existingRecord.hasShift,
            hasRecount: existingRecord.hasRecount,
            hasRKO: true,
            hasEnvelope: existingRecord.hasEnvelope,
            hasShiftHandover: existingRecord.hasShiftHandover,
            rkoFileName: rko.fileName,
            recountReportId: existingRecord.recountReportId,
            shiftReportId: existingRecord.shiftReportId,
            envelopeReportId: existingRecord.envelopeReportId,
            shiftHandoverReportId: existingRecord.shiftHandoverReportId,
          );
        } else {
          shopDaysMap[key] = KPIEmployeeShopDayData(
            date: date,
            shopAddress: rko.shopAddress,
            employeeName: employeeName,
            hasRKO: true,
            rkoFileName: rko.fileName,
          );
        }
      }
    }

    // Добавляем данные из конвертов
    for (var envelope in envelopes) {
      final date = DateTime(envelope.createdAt.year, envelope.createdAt.month, envelope.createdAt.day);
      final key = createShopDayKey(envelope.shopAddress, date);

      if (!shopDaysMap.containsKey(key)) {
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: envelope.shopAddress,
          employeeName: employeeName,
          hasEnvelope: true,
          envelopeReportId: envelope.id,
        );
      } else {
        final existing = shopDaysMap[key]!;
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: envelope.shopAddress,
          employeeName: employeeName,
          attendanceTime: existing.attendanceTime,
          hasShift: existing.hasShift,
          hasRecount: existing.hasRecount,
          hasRKO: existing.hasRKO,
          hasEnvelope: true,
          hasShiftHandover: existing.hasShiftHandover,
          rkoFileName: existing.rkoFileName,
          recountReportId: existing.recountReportId,
          shiftReportId: existing.shiftReportId,
          envelopeReportId: envelope.id,
          shiftHandoverReportId: existing.shiftHandoverReportId,
        );
      }
    }

    // Добавляем данные из сдач смены
    for (var handover in shiftHandovers) {
      final date = DateTime(handover.createdAt.year, handover.createdAt.month, handover.createdAt.day);
      final key = createShopDayKey(handover.shopAddress, date);

      if (!shopDaysMap.containsKey(key)) {
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: handover.shopAddress,
          employeeName: employeeName,
          hasShiftHandover: true,
          shiftHandoverReportId: handover.id,
        );
      } else {
        final existing = shopDaysMap[key]!;
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: handover.shopAddress,
          employeeName: employeeName,
          attendanceTime: existing.attendanceTime,
          hasShift: existing.hasShift,
          hasRecount: existing.hasRecount,
          hasRKO: existing.hasRKO,
          hasEnvelope: existing.hasEnvelope,
          hasShiftHandover: true,
          rkoFileName: existing.rkoFileName,
          recountReportId: existing.recountReportId,
          shiftReportId: existing.shiftReportId,
          envelopeReportId: existing.envelopeReportId,
          shiftHandoverReportId: handover.id,
        );
      }
    }

    return shopDaysMap;
  }

  /// Подсчитать статистику по дням сотрудника
  static Map<String, int> calculateEmployeeStats(Map<String, KPIDayData> daysData) {
    final totalDaysWorked = daysData.values.where((day) => day.workedToday).length;
    final totalShifts = daysData.values.where((day) => day.hasShift).length;
    final totalRecounts = daysData.values.where((day) => day.hasRecount).length;
    final totalRKOs = daysData.values.where((day) => day.hasRKO).length;

    return {
      'totalDaysWorked': totalDaysWorked,
      'totalShifts': totalShifts,
      'totalRecounts': totalRecounts,
      'totalRKOs': totalRKOs,
    };
  }
}
