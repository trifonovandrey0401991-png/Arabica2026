import 'models/work_schedule_model.dart';
import '../shops/models/shop_model.dart';

/// Статус валидации дня
enum DayValidationStatus {
  valid,   // Все магазины имеют утреннюю и вечернюю смены
  invalid, // Хотя бы один магазин не имеет обеих смен
}

/// Валидатор графика работы
class WorkScheduleValidator {
  /// Проверяет полноту смен для дня (наличие утренней и вечерней смен на всех магазинах)
  static bool isDayComplete(DateTime day, List<Shop> shops, WorkSchedule schedule) {
    if (shops.isEmpty) return false;
    
    // Для каждого магазина проверяем наличие обеих смен
    for (var shop in shops) {
      final hasMorning = schedule.entries.any((entry) =>
          entry.date.year == day.year &&
          entry.date.month == day.month &&
          entry.date.day == day.day &&
          entry.shopAddress == shop.address &&
          entry.shiftType == ShiftType.morning);
      
      final hasEvening = schedule.entries.any((entry) =>
          entry.date.year == day.year &&
          entry.date.month == day.month &&
          entry.date.day == day.day &&
          entry.shopAddress == shop.address &&
          entry.shiftType == ShiftType.evening);
      
      // Если хотя бы для одного магазина нет обеих смен, день неполный
      if (!hasMorning || !hasEvening) {
        return false;
      }
    }
    
    return true;
  }
  
  /// Проверяет конфликт смен для сотрудника
  /// Возвращает список предупреждений (пустой, если конфликтов нет)
  static List<String> checkShiftConflict(WorkScheduleEntry entry, WorkSchedule schedule) {
    final warnings = <String>[];
    
    // Проверяем только для утренних смен
    if (entry.shiftType == ShiftType.morning) {
      // Находим предыдущий день
      final previousDay = entry.date.subtract(const Duration(days: 1));
      
      // Проверяем, был ли сотрудник в вечерней смене в предыдущий день
      final hasEveningPreviousDay = schedule.entries.any((e) =>
          e.employeeId == entry.employeeId &&
          e.date.year == previousDay.year &&
          e.date.month == previousDay.month &&
          e.date.day == previousDay.day &&
          e.shiftType == ShiftType.evening);
      
      if (hasEveningPreviousDay) {
        final previousDayStr = '${previousDay.day}.${previousDay.month}.${previousDay.year}';
        warnings.add(
          'Сотрудник ${entry.employeeName} работал в вечернюю смену $previousDayStr. '
          'Не рекомендуется ставить его в утреннюю смену на следующий день.'
        );
      }
    }
    
    return warnings;
  }
  
  /// Получить статус валидации дня
  static DayValidationStatus getDayStatus(DateTime day, List<Shop> shops, WorkSchedule schedule) {
    return isDayComplete(day, shops, schedule)
        ? DayValidationStatus.valid
        : DayValidationStatus.invalid;
  }
  
  /// Проверяет, есть ли конфликт для конкретной ячейки (сотрудник + дата)
  static bool hasConflictForCell(String employeeId, DateTime date, WorkSchedule schedule) {
    // Находим запись для этой ячейки
    final entry = schedule.entries.firstWhere(
      (e) =>
          e.employeeId == employeeId &&
          e.date.year == date.year &&
          e.date.month == date.month &&
          e.date.day == date.day,
      orElse: () => WorkScheduleEntry(
        id: '',
        employeeId: employeeId,
        employeeName: '',
        shopAddress: '',
        date: date,
        shiftType: ShiftType.morning,
      ),
    );

    // Если записи нет, конфликта нет
    if (entry.id.isEmpty) return false;

    // Проверяем конфликт только для утренних смен
    if (entry.shiftType == ShiftType.morning) {
      final previousDay = date.subtract(const Duration(days: 1));
      return schedule.entries.any((e) =>
          e.employeeId == employeeId &&
          e.date.year == previousDay.year &&
          e.date.month == previousDay.month &&
          e.date.day == previousDay.day &&
          e.shiftType == ShiftType.evening);
    }

    return false;
  }

  /// Валидация всего графика за период
  static ScheduleValidationResult validateSchedule(
    WorkSchedule schedule,
    DateTime startDate,
    DateTime endDate,
    List<Shop> shops,
  ) {
    final criticalErrors = <ScheduleError>[];
    final warnings = <ScheduleError>[];

    // Проходим по каждому дню периода
    var currentDay = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);

    while (currentDay.isBefore(end.add(const Duration(days: 1)))) {
      // Для каждого магазина проверяем обязательные смены
      for (var shop in shops) {
        // Проверка 1: Есть ли утренняя смена?
        final hasMorning = schedule.entries.any((e) =>
            e.date.year == currentDay.year &&
            e.date.month == currentDay.month &&
            e.date.day == currentDay.day &&
            e.shopAddress == shop.address &&
            e.shiftType == ShiftType.morning);

        if (!hasMorning) {
          criticalErrors.add(ScheduleError(
            type: ScheduleErrorType.missingMorning,
            date: currentDay,
            shopAddress: shop.address,
            shopName: shop.name,
          ));
        }

        // Проверка 2: Есть ли вечерняя смена?
        final hasEvening = schedule.entries.any((e) =>
            e.date.year == currentDay.year &&
            e.date.month == currentDay.month &&
            e.date.day == currentDay.day &&
            e.shopAddress == shop.address &&
            e.shiftType == ShiftType.evening);

        if (!hasEvening) {
          criticalErrors.add(ScheduleError(
            type: ScheduleErrorType.missingEvening,
            date: currentDay,
            shopAddress: shop.address,
            shopName: shop.name,
          ));
        }

        // Проверка 3: Дубликаты утренних смен
        final morningShifts = schedule.entries.where((e) =>
            e.date.year == currentDay.year &&
            e.date.month == currentDay.month &&
            e.date.day == currentDay.day &&
            e.shopAddress == shop.address &&
            e.shiftType == ShiftType.morning).toList();

        if (morningShifts.length > 1) {
          criticalErrors.add(ScheduleError(
            type: ScheduleErrorType.duplicateMorning,
            date: currentDay,
            shopAddress: shop.address,
            shopName: shop.name,
          ));
        }

        // Проверка 4: Дубликаты вечерних смен
        final eveningShifts = schedule.entries.where((e) =>
            e.date.year == currentDay.year &&
            e.date.month == currentDay.month &&
            e.date.day == currentDay.day &&
            e.shopAddress == shop.address &&
            e.shiftType == ShiftType.evening).toList();

        if (eveningShifts.length > 1) {
          criticalErrors.add(ScheduleError(
            type: ScheduleErrorType.duplicateEvening,
            date: currentDay,
            shopAddress: shop.address,
            shopName: shop.name,
          ));
        }
      }

      // Проверка 5: Конфликты 24ч для каждого сотрудника
      final employeeIds = schedule.entries
          .where((e) =>
              e.date.year == currentDay.year &&
              e.date.month == currentDay.month &&
              e.date.day == currentDay.day)
          .map((e) => e.employeeId)
          .toSet();

      for (var empId in employeeIds) {
        final todayEntries = schedule.entries
            .where((e) =>
                e.employeeId == empId &&
                e.date.year == currentDay.year &&
                e.date.month == currentDay.month &&
                e.date.day == currentDay.day)
            .toList();

        for (var entry in todayEntries) {
          // Конфликт: Утро после вечера
          if (entry.shiftType == ShiftType.morning) {
            final yesterday = currentDay.subtract(const Duration(days: 1));
            final hadEvening = schedule.entries.any((e) =>
                e.employeeId == empId &&
                e.date.year == yesterday.year &&
                e.date.month == yesterday.month &&
                e.date.day == yesterday.day &&
                e.shiftType == ShiftType.evening);

            if (hadEvening) {
              warnings.add(ScheduleError(
                type: ScheduleErrorType.morningAfterEvening,
                date: currentDay,
                shopAddress: entry.shopAddress,
                employeeName: entry.employeeName,
                shiftType: ShiftType.morning,
              ));
            }
          }

          // Конфликт: Вечер после утра (в тот же день)
          if (entry.shiftType == ShiftType.evening) {
            final hadMorning = todayEntries.any((e) => e.shiftType == ShiftType.morning);
            if (hadMorning) {
              warnings.add(ScheduleError(
                type: ScheduleErrorType.eveningAfterMorning,
                date: currentDay,
                shopAddress: entry.shopAddress,
                employeeName: entry.employeeName,
                shiftType: ShiftType.evening,
              ));
            }
          }

          // Конфликт: День после вечера
          if (entry.shiftType == ShiftType.day) {
            final yesterday = currentDay.subtract(const Duration(days: 1));
            final hadEvening = schedule.entries.any((e) =>
                e.employeeId == empId &&
                e.date.year == yesterday.year &&
                e.date.month == yesterday.month &&
                e.date.day == yesterday.day &&
                e.shiftType == ShiftType.evening);

            if (hadEvening) {
              warnings.add(ScheduleError(
                type: ScheduleErrorType.dayAfterEvening,
                date: currentDay,
                shopAddress: entry.shopAddress,
                employeeName: entry.employeeName,
                shiftType: ShiftType.day,
              ));
            }
          }
        }
      }

      currentDay = currentDay.add(const Duration(days: 1));
    }

    return ScheduleValidationResult(
      criticalErrors: criticalErrors,
      warnings: warnings,
    );
  }
}

/// Типы ошибок в графике
enum ScheduleErrorType {
  missingMorning,       // Критичная: отсутствует утренняя смена
  missingEvening,       // Критичная: отсутствует вечерняя смена
  duplicateMorning,     // Критичная: дубликат утренней смены
  duplicateEvening,     // Критичная: дубликат вечерней смены
  morningAfterEvening,  // Предупреждение: утро после вечера
  eveningAfterMorning,  // Предупреждение: вечер после утра
  dayAfterEvening,      // Предупреждение: день после вечера
}

/// Ошибка в графике
class ScheduleError {
  final ScheduleErrorType type;
  final DateTime date;
  final String shopAddress;
  final String? shopName;
  final String? employeeName;
  final ShiftType? shiftType;

  ScheduleError({
    required this.type,
    required this.date,
    required this.shopAddress,
    this.shopName,
    this.employeeName,
    this.shiftType,
  });

  /// Получить текст сообщения об ошибке
  String get displayMessage {
    final dateStr = '${date.day}.${date.month}.${date.year}';
    final shopNameStr = shopName ?? shopAddress;

    switch (type) {
      case ScheduleErrorType.missingMorning:
        return 'Нет утренней смены в $shopNameStr ($dateStr)';
      case ScheduleErrorType.missingEvening:
        return 'Нет вечерней смены в $shopNameStr ($dateStr)';
      case ScheduleErrorType.duplicateMorning:
        return 'Дубликат утренней смены в $shopNameStr ($dateStr)';
      case ScheduleErrorType.duplicateEvening:
        return 'Дубликат вечерней смены в $shopNameStr ($dateStr)';
      case ScheduleErrorType.morningAfterEvening:
        return 'Утро после вечерней смены: $employeeName ($dateStr)';
      case ScheduleErrorType.eveningAfterMorning:
        return 'Вечер после утренней смены: $employeeName ($dateStr)';
      case ScheduleErrorType.dayAfterEvening:
        return 'День после вечерней смены: $employeeName ($dateStr)';
    }
  }

  /// Является ли ошибка критичной
  bool get isCritical =>
      type == ScheduleErrorType.missingMorning ||
      type == ScheduleErrorType.missingEvening ||
      type == ScheduleErrorType.duplicateMorning ||
      type == ScheduleErrorType.duplicateEvening;

  /// Является ли ошибка предупреждением
  bool get isWarning => !isCritical;
}

/// Результат валидации графика
class ScheduleValidationResult {
  final List<ScheduleError> criticalErrors;
  final List<ScheduleError> warnings;

  ScheduleValidationResult({
    required this.criticalErrors,
    required this.warnings,
  });

  /// Есть ли ошибки или предупреждения
  bool get hasErrors => criticalErrors.isNotEmpty || warnings.isNotEmpty;

  /// Есть ли критичные ошибки
  bool get hasCritical => criticalErrors.isNotEmpty;

  /// Общее количество ошибок
  int get totalCount => criticalErrors.length + warnings.length;
}

