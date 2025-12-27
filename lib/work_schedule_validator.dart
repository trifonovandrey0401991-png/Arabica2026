import 'work_schedule_model.dart';
import 'shop_model.dart';

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
}







