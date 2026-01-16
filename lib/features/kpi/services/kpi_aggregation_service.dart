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

    Logger.debug('📋 НАЧАЛО АГРЕГАЦИИ ДАННЫХ ПО СОТРУДНИКАМ');
    Logger.debug('   Дата: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
    Logger.debug('   Магазин: $shopAddress');

    // Обработка отметок прихода
    _processAttendanceRecords(
      employeesDataMap: employeesDataMap,
      attendanceRecords: attendanceRecords,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    // Обработка пересменок
    _processShifts(
      employeesDataMap: employeesDataMap,
      shifts: shifts,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    // Обработка пересчетов
    _processRecounts(
      employeesDataMap: employeesDataMap,
      recounts: recounts,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    // Обработка РКО
    _processRKOs(
      employeesDataMap: employeesDataMap,
      rkos: rkos,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    // Обработка конвертов
    _processEnvelopes(
      employeesDataMap: employeesDataMap,
      envelopes: envelopes,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    // Обработка сдач смены
    _processShiftHandovers(
      employeesDataMap: employeesDataMap,
      shiftHandovers: shiftHandovers,
      normalizedDate: normalizedDate,
      shopAddress: shopAddress,
    );

    Logger.debug('📊 Всего уникальных сотрудников после агрегации: ${employeesDataMap.length}');
    Logger.debug('   Список сотрудников: ${employeesDataMap.keys.toList()}');

    return employeesDataMap;
  }

  /// Обработать отметки прихода
  static void _processAttendanceRecords({
    required Map<String, KPIDayData> employeesDataMap,
    required List<AttendanceRecord> attendanceRecords,
    required DateTime normalizedDate,
    required String shopAddress,
  }) {
    Logger.debug('📋 НАЧАЛО ОБРАБОТКИ ОТМЕТОК ПРИХОДА: ${attendanceRecords.length} записей');

    for (var record in attendanceRecords) {
      final key = KPINormalizers.normalizeEmployeeName(record.employeeName);
      final recordTime = record.timestamp;
      final isMorning = recordTime.hour < AppConstants.eveningBoundaryHour;
      final isEvening = recordTime.hour >= AppConstants.eveningBoundaryHour;

      Logger.debug('   🔍 Обработка отметки: "$key" (${record.employeeName})');
      Logger.debug('      timestamp: ${recordTime.toIso8601String()}');
      Logger.debug('      час: ${recordTime.hour}, минута: ${recordTime.minute}');
      Logger.debug('      UTC: ${recordTime.isUtc}, локальное: ${recordTime.toLocal().toIso8601String()}');
      Logger.debug('      время: ${recordTime.hour}:${recordTime.minute.toString().padLeft(2, '0')} (${isMorning ? "утро" : "вечер"})');

      if (!employeesDataMap.containsKey(key)) {
        // Создаем новую запись
        final earliestTime = recordTime;
        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: record.employeeName,
          shopAddress: shopAddress,
          attendanceTime: earliestTime,
          hasMorningAttendance: isMorning,
          hasEveningAttendance: isEvening,
        );
        Logger.debug('   ✅ Создана новая запись для "$key" с временем прихода: ${earliestTime.hour}:${earliestTime.minute.toString().padLeft(2, '0')}');
        Logger.debug('      attendanceTime в KPIDayData: ${employeesDataMap[key]!.attendanceTime?.toIso8601String() ?? "null"}');
      } else {
        // Обновляем существующую запись
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
        Logger.debug('   ✅ Обновлена запись для "$key": утро=${existing.hasMorningAttendance || isMorning}, вечер=${existing.hasEveningAttendance || isEvening}');
      }
    }

    Logger.debug('📊 Всего уникальных сотрудников после обработки прихода: ${employeesDataMap.length}');
    Logger.debug('   Список сотрудников: ${employeesDataMap.keys.toList()}');
    Logger.debug('   📋 Детали записей после обработки прихода:');
    for (var entry in employeesDataMap.entries) {
      final timeStr = entry.value.attendanceTime != null
          ? '${entry.value.attendanceTime!.hour.toString().padLeft(2, '0')}:${entry.value.attendanceTime!.minute.toString().padLeft(2, '0')}'
          : 'null';
      Logger.debug('      - ключ: "${entry.key}", имя: "${entry.value.employeeName}", время: $timeStr (${entry.value.attendanceTime?.toIso8601String() ?? "null"})');
    }
  }

  /// Обработать пересменки
  static void _processShifts({
    required Map<String, KPIDayData> employeesDataMap,
    required List<ShiftReport> shifts,
    required DateTime normalizedDate,
    required String shopAddress,
  }) {
    Logger.debug('📋 Обработка пересменок: найдено ${shifts.length}');

    for (var shift in shifts) {
      final key = KPINormalizers.normalizeEmployeeName(shift.employeeName);
      Logger.debug('   🔍 Обработка пересменки: "${shift.employeeName}" -> ключ: "$key"');
      final existing = employeesDataMap[key];
      if (existing != null) {
        Logger.debug('   ✅ Найдена существующая запись для "$key", обновляем hasShift=true');
      } else {
        Logger.debug('   ⚠️ Запись для "$key" не найдена, создаем новую');
      }
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
    Logger.debug('📋 Обработка пересчетов: найдено ${recounts.length}');

    for (var recount in recounts) {
      final key = KPINormalizers.normalizeEmployeeName(recount.employeeName);
      Logger.debug('   🔍 Обработка пересчета: "${recount.employeeName}" -> ключ: "$key"');
      final existing = employeesDataMap[key];
      if (existing != null) {
        Logger.debug('   ✅ Найдена существующая запись для "$key", обновляем hasRecount=true');
      } else {
        Logger.debug('   ⚠️ Запись для "$key" не найдена, создаем новую');
      }
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
    Logger.debug('═══════════════════════════════════════════════════════');
    Logger.debug('📋 ОБРАБОТКА РКО: найдено ${rkos.length}');
    Logger.debug('═══════════════════════════════════════════════════════');
    if (rkos.isEmpty) {
      Logger.debug('   ⚠️ РКО не найдено для даты ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
    } else {
      Logger.debug('   📋 Список всех РКО для обработки:');
      for (var rko in rkos) {
        Logger.debug('      - employeeName: "${rko.employeeName}"');
        Logger.debug('        date: ${rko.date.year}-${rko.date.month}-${rko.date.day}');
        Logger.debug('        shopAddress: "${rko.shopAddress}"');
      }
    }
    Logger.debug('   📋 Доступные ключи в employeesDataMap: ${employeesDataMap.keys.toList()}');
    Logger.debug('   📋 Детали записей в employeesDataMap:');
    for (var entry in employeesDataMap.entries) {
      Logger.debug('      - ключ: "${entry.key}", имя: "${entry.value.employeeName}"');
    }

    for (var rko in rkos) {
      final key = KPINormalizers.normalizeEmployeeName(rko.employeeName);
      Logger.debug('   🔍 Обработка РКО:');
      Logger.debug('      - Оригинальное имя: "${rko.employeeName}"');
      Logger.debug('      - Нормализованный ключ: "$key"');
      final existing = employeesDataMap[key];
      if (existing != null) {
        Logger.debug('      ✅ Найдена существующая запись для "$key"');
        Logger.debug('         Имя в записи: "${existing.employeeName}"');
        Logger.debug('         Обновляем hasRKO=true');
      } else {
        Logger.debug('      ⚠️ Запись для "$key" не найдена, создаем новую');
        Logger.debug('      📋 Попытка найти похожие ключи...');
        bool foundSimilar = false;
        for (var existingKey in employeesDataMap.keys) {
          if (existingKey.toLowerCase().contains(key.toLowerCase()) || key.toLowerCase().contains(existingKey.toLowerCase())) {
            Logger.debug('         - Найден похожий ключ: "$existingKey" (искомый: "$key")');
            foundSimilar = true;
          }
        }
        if (!foundSimilar) {
          Logger.debug('         - Похожих ключей не найдено');
        }
      }
      if (existing == null) {
        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: rko.employeeName,
          shopAddress: shopAddress,
          hasRKO: true,
        );
        Logger.debug('   ✅ Создана новая запись для РКО: "$key"');
      } else {
        // Используем имя из существующей записи, чтобы сохранить оригинальное имя
        employeesDataMap[key] = KPIDayData(
          date: normalizedDate,
          employeeName: existing.employeeName, // Используем имя из существующей записи
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
        Logger.debug('   ✅ Обновлена запись для РКО: "$key", hasRKO=true');
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
    Logger.debug('📋 Обработка конвертов: найдено ${envelopes.length}');

    for (var envelope in envelopes) {
      final key = KPINormalizers.normalizeEmployeeName(envelope.employeeName);
      Logger.debug('   🔍 Обработка конверта: "${envelope.employeeName}" -> ключ: "$key"');
      final existing = employeesDataMap[key];
      if (existing != null) {
        Logger.debug('   ✅ Найдена существующая запись для "$key", обновляем hasEnvelope=true');
      } else {
        Logger.debug('   ⚠️ Запись для "$key" не найдена, создаем новую');
      }
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
    Logger.debug('📋 Обработка сдач смены: найдено ${shiftHandovers.length}');

    for (var handover in shiftHandovers) {
      final key = KPINormalizers.normalizeEmployeeName(handover.employeeName);
      Logger.debug('   🔍 Обработка сдачи смены: "${handover.employeeName}" -> ключ: "$key"');
      final existing = employeesDataMap[key];
      if (existing != null) {
        Logger.debug('   ✅ Найдена существующая запись для "$key", обновляем hasShiftHandover=true');
      } else {
        Logger.debug('   ⚠️ Запись для "$key" не найдена, создаем новую');
      }
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
    Logger.debug('📋 Обработка пересменок: всего ${shifts.length} записей');
    for (var shift in shifts) {
      final date = DateTime(
        shift.createdAt.year,
        shift.createdAt.month,
        shift.createdAt.day,
      );
      final key = createShopDayKey(shift.shopAddress, date);
      Logger.debug('   Пересменка: дата=${date.year}-${date.month}-${date.day}, магазин="${shift.shopAddress}", ключ="$key"');

      if (!shopDaysMap.containsKey(key)) {
        Logger.debug('   Создана новая запись для пересменки');
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: shift.shopAddress,
          employeeName: employeeName,
          hasShift: true,
          shiftReportId: shift.id,
        );
      } else {
        Logger.debug('   Обновлена существующая запись: добавлена пересменка');
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
    Logger.debug('📋 Обработка пересчетов: всего ${recounts.length} записей');
    for (var recount in recounts) {
      final date = DateTime(
        recount.completedAt.year,
        recount.completedAt.month,
        recount.completedAt.day,
      );
      final key = createShopDayKey(recount.shopAddress, date);
      Logger.debug('   Пересчет: дата=${date.year}-${date.month}-${date.day}, магазин="${recount.shopAddress}", ключ="$key"');

      if (!shopDaysMap.containsKey(key)) {
        Logger.debug('   Создана новая запись для пересчета');
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: recount.shopAddress,
          employeeName: employeeName,
          hasRecount: true,
          recountReportId: recount.id,
        );
      } else {
        Logger.debug('   Обновлена существующая запись: добавлен пересчет');
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
    Logger.debug('📋 Обработка РКО: всего ${rkos.length} записей');
    for (var rko in rkos) {
      final date = DateTime(
        rko.date.year,
        rko.date.month,
        rko.date.day,
      );
      // Используем нормализованный ключ (адрес уже нормализован в createShopDayKey)
      final key = createShopDayKey(rko.shopAddress, date);
      final normalizedRkoAddress = KPINormalizers.normalizeShopAddress(rko.shopAddress);
      Logger.debug('   РКО: дата=${date.year}-${date.month}-${date.day}');
      Logger.debug('      магазин (оригинал)="${rko.shopAddress}"');
      Logger.debug('      магазин (нормализован)="$normalizedRkoAddress"');
      Logger.debug('      ключ="$key"');

      // Проверяем, есть ли уже запись с таким ключом (ключ уже нормализован в createShopDayKey)
      Logger.debug('   Поиск существующей записи по ключу: "$key"');
      Logger.debug('   Доступные ключи в map: ${shopDaysMap.keys.toList()}');

      if (shopDaysMap.containsKey(key)) {
        Logger.debug('   ✅ Найдена существующая запись по ключу');
        final existing = shopDaysMap[key]!;
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: existing.date,
          shopAddress: existing.shopAddress, // Сохраняем оригинальный адрес из существующей записи
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
        Logger.debug('   Обновлена существующая запись: добавлено РКО');
      } else {
        // Если не найдено по ключу, ищем по нормализованному адресу и дате (на случай, если адрес немного отличается)
        Logger.debug('   Запись не найдена по ключу, ищем по нормализованному адресу и дате');
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
            Logger.debug('   ✅ Найдена существующая запись по нормализованному адресу: ключ="$existingKey"');
            break;
          }
        }

        if (existingRecord != null) {
          Logger.debug('   Обновлена существующая запись: добавлено РКО');
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
          Logger.debug('   Создана новая запись для РКО');
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
    Logger.debug('📋 Обработка конвертов: всего ${envelopes.length} записей');
    for (var envelope in envelopes) {
      final date = DateTime(
        envelope.createdAt.year,
        envelope.createdAt.month,
        envelope.createdAt.day,
      );
      final key = createShopDayKey(envelope.shopAddress, date);
      Logger.debug('   Конверт: дата=${date.year}-${date.month}-${date.day}, магазин="${envelope.shopAddress}", ключ="$key"');

      if (!shopDaysMap.containsKey(key)) {
        Logger.debug('   Создана новая запись для конверта');
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: envelope.shopAddress,
          employeeName: employeeName,
          hasEnvelope: true,
          envelopeReportId: envelope.id,
        );
      } else {
        Logger.debug('   Обновлена существующая запись: добавлен конверт');
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
    Logger.debug('📋 Обработка сдач смены: всего ${shiftHandovers.length} записей');
    for (var handover in shiftHandovers) {
      final date = DateTime(
        handover.createdAt.year,
        handover.createdAt.month,
        handover.createdAt.day,
      );
      final key = createShopDayKey(handover.shopAddress, date);
      Logger.debug('   Сдача смены: дата=${date.year}-${date.month}-${date.day}, магазин="${handover.shopAddress}", ключ="$key"');

      if (!shopDaysMap.containsKey(key)) {
        Logger.debug('   Создана новая запись для сдачи смены');
        shopDaysMap[key] = KPIEmployeeShopDayData(
          date: date,
          shopAddress: handover.shopAddress,
          employeeName: employeeName,
          hasShiftHandover: true,
          shiftHandoverReportId: handover.id,
        );
      } else {
        Logger.debug('   Обновлена существующая запись: добавлена сдача смены');
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
