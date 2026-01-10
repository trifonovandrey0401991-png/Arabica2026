import 'package:flutter/material.dart';
import '../models/work_schedule_model.dart';
import '../../shops/models/shop_settings_model.dart';
import '../../rko/services/rko_service.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/utils/logger.dart';

class WorkScheduleService {
  static const String _baseEndpoint = ApiConstants.workScheduleEndpoint;

  /// Получить график на месяц
  static Future<WorkSchedule> getSchedule(DateTime month) async {
    try {
      final monthStr = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      Logger.debug('Загрузка графика на месяц: $monthStr');

      final result = await BaseHttpService.get<WorkSchedule>(
        endpoint: _baseEndpoint,
        fromJson: (json) => WorkSchedule.fromJson(json),
        itemKey: 'schedule',
      );

      if (result != null) {
        Logger.debug('Загружен график: ${result.entries.length} записей');
        return result;
      }
      return WorkSchedule(month: month, entries: []);
    } catch (e) {
      Logger.error('Ошибка загрузки графика', e);
      return WorkSchedule(month: month, entries: []);
    }
  }

  /// Получить график конкретного сотрудника
  static Future<WorkSchedule> getEmployeeSchedule(String employeeId, DateTime month) async {
    try {
      final monthStr = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      Logger.debug('Загрузка графика сотрудника: $employeeId, месяц: $monthStr');

      final result = await BaseHttpService.getRaw(
        endpoint: '$_baseEndpoint/employee/$employeeId',
        queryParams: {'month': monthStr},
      );

      if (result != null && result['schedule'] != null) {
        final schedule = WorkSchedule.fromJson(result['schedule']);
        Logger.debug('Загружен график сотрудника: ${schedule.entries.length} записей');
        return schedule;
      }
      return WorkSchedule(month: month, entries: []);
    } catch (e) {
      Logger.error('Ошибка загрузки графика сотрудника', e);
      return WorkSchedule(month: month, entries: []);
    }
  }

  /// Сохранить смену (создать или обновить)
  static Future<bool> saveShift(WorkScheduleEntry entry) async {
    try {
      Logger.debug('Сохранение смены: ${entry.employeeName}, ${entry.date.toIso8601String().split('T')[0]}, ${entry.shiftType.label}');

      // Добавляем месяц в формат YYYY-MM
      final monthStr = '${entry.date.year}-${entry.date.month.toString().padLeft(2, '0')}';
      final entryJson = entry.toJson();
      entryJson['month'] = monthStr;

      return await BaseHttpService.simplePost(
        endpoint: _baseEndpoint,
        body: entryJson,
      );
    } catch (e) {
      Logger.error('Ошибка сохранения смены', e);
      return false;
    }
  }

  /// Удалить смену
  static Future<bool> deleteShift(String entryId) async {
    try {
      Logger.debug('Удаление смены: $entryId');
      return await BaseHttpService.delete(endpoint: '$_baseEndpoint/$entryId');
    } catch (e) {
      Logger.error('Ошибка удаления смены', e);
      return false;
    }
  }

  /// Массовое создание смен
  static Future<bool> bulkCreateShifts(List<WorkScheduleEntry> entries) async {
    try {
      Logger.debug('Массовое создание смен: ${entries.length} записей');

      return await BaseHttpService.simplePost(
        endpoint: '$_baseEndpoint/bulk',
        body: {
          'entries': entries.map((e) => e.toJson()).toList(),
        },
        timeout: ApiConstants.longTimeout,
      );
    } catch (e) {
      Logger.error('Ошибка массового создания смен', e);
      return false;
    }
  }

  /// Копировать неделю
  static Future<bool> copyWeek({
    required DateTime sourceWeekStart,
    required DateTime targetWeekStart,
    required List<String> employeeIds,
  }) async {
    try {
      // Получаем график на месяц источника
      final sourceMonth = DateTime(sourceWeekStart.year, sourceWeekStart.month);
      final sourceSchedule = await getSchedule(sourceMonth);

      // Фильтруем записи за неделю источника
      final sourceEntries = sourceSchedule.entries.where((entry) {
        final entryDate = DateTime(entry.date.year, entry.date.month, entry.date.day);
        final weekStart = sourceWeekStart;
        final weekEnd = weekStart.add(const Duration(days: 6));
        return entryDate.isAfter(weekStart.subtract(const Duration(days: 1))) &&
               entryDate.isBefore(weekEnd.add(const Duration(days: 1))) &&
               employeeIds.contains(entry.employeeId);
      }).toList();

      // Создаем новые записи для целевой недели
      final daysDiff = targetWeekStart.difference(sourceWeekStart).inDays;
      final targetEntries = sourceEntries.map((entry) {
        final newDate = entry.date.add(Duration(days: daysDiff));
        return entry.copyWith(
          id: '', // Новый ID будет создан на сервере
          date: newDate,
        );
      }).toList();

      // Сохраняем массово
      return await bulkCreateShifts(targetEntries);
    } catch (e) {
      Logger.error('Ошибка копирования недели', e);
      return false;
    }
  }

  /// Сохранить шаблон
  static Future<bool> saveTemplate(ScheduleTemplate template) async {
    try {
      Logger.debug('Сохранение шаблона: ${template.name}');

      return await BaseHttpService.simplePost(
        endpoint: '$_baseEndpoint/template',
        body: {
          'action': 'save',
          'template': template.toJson(),
        },
      );
    } catch (e) {
      Logger.error('Ошибка сохранения шаблона', e);
      return false;
    }
  }

  /// Получить список шаблонов
  static Future<List<ScheduleTemplate>> getTemplates() async {
    try {
      Logger.debug('Загрузка шаблонов');

      return await BaseHttpService.getList<ScheduleTemplate>(
        endpoint: '$_baseEndpoint/template',
        fromJson: (json) => ScheduleTemplate.fromJson(json),
        listKey: 'templates',
      );
    } catch (e) {
      Logger.error('Ошибка загрузки шаблонов', e);
      return [];
    }
  }

  /// Применить шаблон
  static Future<bool> applyTemplate(ScheduleTemplate template, DateTime targetWeekStart) async {
    try {
      Logger.debug('Применение шаблона: ${template.name}');

      // Создаем записи на основе шаблона, начиная с targetWeekStart
      final targetEntries = <WorkScheduleEntry>[];
      final templateDays = template.entries.map((e) => e.date.day).toSet().toList()..sort();
      final firstTemplateDay = templateDays.isNotEmpty ? templateDays.first : 1;

      for (var entry in template.entries) {
        final daysOffset = entry.date.day - firstTemplateDay;
        final newDate = targetWeekStart.add(Duration(days: daysOffset));
        targetEntries.add(entry.copyWith(
          id: '',
          date: newDate,
        ));
      }

      return await bulkCreateShifts(targetEntries);
    } catch (e) {
      Logger.error('Ошибка применения шаблона', e);
      return false;
    }
  }

  /// Получить время смены из настроек магазина
  /// Возвращает (startTime, endTime, timeRange) для указанного типа смены
  static Future<ShiftTimeInfo> getShiftTimeFromSettings(
    String shopAddress,
    ShiftType shiftType,
  ) async {
    try {
      final settings = await RKOService.getShopSettings(shopAddress);
      if (settings != null) {
        return ShiftTimeInfo.fromSettings(settings, shiftType);
      }
    } catch (e) {
      Logger.error('Ошибка получения времени смены из настроек', e);
    }
    // Возвращаем дефолтные значения из enum
    return ShiftTimeInfo.fromDefault(shiftType);
  }

  /// Получить время смен для нескольких записей графика
  /// Возвращает Map<shopAddress, Map<ShiftType, ShiftTimeInfo>>
  static Future<Map<String, Map<ShiftType, ShiftTimeInfo>>> getShiftTimesForEntries(
    List<WorkScheduleEntry> entries,
  ) async {
    final result = <String, Map<ShiftType, ShiftTimeInfo>>{};
    final uniqueShops = entries.map((e) => e.shopAddress).toSet();

    for (final shopAddress in uniqueShops) {
      result[shopAddress] = {};
      for (final shiftType in ShiftType.values) {
        result[shopAddress]![shiftType] = await getShiftTimeFromSettings(shopAddress, shiftType);
      }
    }

    return result;
  }
}

/// Информация о времени смены
class ShiftTimeInfo {
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String timeRange;
  final bool isFromSettings; // true если из настроек магазина, false если дефолт

  ShiftTimeInfo({
    required this.startTime,
    required this.endTime,
    required this.timeRange,
    this.isFromSettings = false,
  });

  /// Создать из настроек магазина
  factory ShiftTimeInfo.fromSettings(ShopSettings settings, ShiftType shiftType) {
    TimeOfDay? start;
    TimeOfDay? end;

    switch (shiftType) {
      case ShiftType.morning:
        start = settings.morningShiftStart;
        end = settings.morningShiftEnd;
        break;
      case ShiftType.day:
        start = settings.dayShiftStart;
        end = settings.dayShiftEnd;
        break;
      case ShiftType.evening:
        start = settings.nightShiftStart;
        end = settings.nightShiftEnd;
        break;
    }

    // Если настройки магазина есть - используем их
    if (start != null && end != null) {
      final startStr = _formatTime(start);
      final endStr = _formatTime(end);
      return ShiftTimeInfo(
        startTime: start,
        endTime: end,
        timeRange: '$startStr-$endStr',
        isFromSettings: true,
      );
    }

    // Иначе - дефолтные значения из enum
    return ShiftTimeInfo.fromDefault(shiftType);
  }

  /// Создать из дефолтных значений enum
  factory ShiftTimeInfo.fromDefault(ShiftType shiftType) {
    return ShiftTimeInfo(
      startTime: shiftType.startTime,
      endTime: shiftType.endTime,
      timeRange: shiftType.timeRange,
      isFromSettings: false,
    );
  }

  static String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
