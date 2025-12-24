import 'work_schedule_model.dart';
import 'employees_page.dart';
import 'shop_model.dart';
import 'shop_settings_model.dart';

/// Сервис для автоматического заполнения графика работы
class AutoFillScheduleService {
  /// Автозаполнение графика
  static Future<List<WorkScheduleEntry>> autoFill({
    required DateTime startDate,
    required DateTime endDate,
    required List<Employee> employees,
    required List<Shop> shops,
    required Map<String, ShopSettings> shopSettingsCache,
    required WorkSchedule? existingSchedule,
    required bool replaceExisting,
  }) async {
    final List<WorkScheduleEntry> newEntries = [];
    final List<String> warnings = [];

    // 1. Подготовка данных
    final days = _getDaysInPeriod(startDate, endDate);
    
    // Разделяем сотрудников на группы
    final employeesWithPreferences = employees.where((e) =>
      e.preferredWorkDays.isNotEmpty ||
      e.preferredShops.isNotEmpty ||
      e.shiftPreferences.isNotEmpty
    ).toList();
    
    final employeesWithoutPreferences = employees.where((e) =>
      e.preferredWorkDays.isEmpty &&
      e.preferredShops.isEmpty &&
      e.shiftPreferences.isEmpty
    ).toList();

    // Создаем копию существующего графика для работы
    final workingSchedule = existingSchedule != null
        ? WorkSchedule(
            month: existingSchedule.month,
            entries: replaceExisting
                ? existingSchedule.entries.where((e) =>
                    !days.contains(DateTime(e.date.year, e.date.month, e.date.day))
                  ).toList()
                : List.from(existingSchedule.entries),
          )
        : WorkSchedule(month: startDate, entries: []);

    // 2. Для каждого дня периода
    for (var day in days) {
      // Для каждого магазина
      for (var shop in shops) {
        final settings = shopSettingsCache[shop.address];
        if (settings == null) continue;

        // Всегда заполняем утро и вечер для каждого магазина в каждый день
        final requiredShifts = <ShiftType>[
          ShiftType.morning,
          ShiftType.evening,
        ];
        
        // Если режим "Заполнить пустые", проверяем существующие смены
        if (!replaceExisting) {
          final existingShifts = workingSchedule.entries.where((e) =>
            e.date.year == day.year &&
            e.date.month == day.month &&
            e.date.day == day.day &&
            e.shopAddress == shop.address
          ).toList();

          final hasMorning = existingShifts.any((e) => e.shiftType == ShiftType.morning);
          final hasEvening = existingShifts.any((e) => e.shiftType == ShiftType.evening);

          // Убираем смены, которые уже есть
          if (hasMorning) {
            requiredShifts.remove(ShiftType.morning);
          }
          if (hasEvening) {
            requiredShifts.remove(ShiftType.evening);
          }
        }

        // Заполняем необходимые смены
        for (var shiftType in requiredShifts) {
          // Сначала пытаемся найти сотрудника с предпочтениями
          Employee? selectedEmployee = _selectBestEmployee(
            shop: shop,
            day: day,
            shiftType: shiftType,
            employees: employeesWithPreferences,
            schedule: workingSchedule,
          );

          // Если не нашли с предпочтениями, используем без предпочтений
          if (selectedEmployee == null) {
            selectedEmployee = _selectBestEmployee(
              shop: shop,
              day: day,
              shiftType: shiftType,
              employees: employeesWithoutPreferences,
              schedule: workingSchedule,
            );
          }

          // Если все еще не нашли, используем любого доступного
          if (selectedEmployee == null) {
            selectedEmployee = _selectAnyAvailableEmployee(
              shop: shop,
              day: day,
              shiftType: shiftType,
              employees: employees,
              schedule: workingSchedule,
            );
          }

          if (selectedEmployee != null) {
            final entry = WorkScheduleEntry(
              id: '',
              employeeId: selectedEmployee.id,
              employeeName: selectedEmployee.name,
              shopAddress: shop.address,
              date: day,
              shiftType: shiftType,
            );
            newEntries.add(entry);
            workingSchedule.entries.add(entry);
          } else {
            warnings.add(
              'Не удалось найти сотрудника для ${shop.name}, ${day.day}.${day.month}, ${shiftType.label}'
            );
          }
        }
      }
    }

    // 3. Валидация результата
    final validationWarnings = _validateSchedule(workingSchedule, shops, days);
    warnings.addAll(validationWarnings);

    print('✅ Автозаполнение завершено: создано ${newEntries.length} смен');
    if (warnings.isNotEmpty) {
      print('⚠️ Предупреждения: ${warnings.length}');
    }

    return newEntries;
  }

  /// Получить список дней периода
  static List<DateTime> _getDaysInPeriod(DateTime start, DateTime end) {
    final days = <DateTime>[];
    var current = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    
    while (current.isBefore(endDate) || current.isAtSameMomentAs(endDate)) {
      days.add(current);
      current = current.add(const Duration(days: 1));
    }
    
    return days;
  }

  /// Выбрать лучшего сотрудника для смены
  static Employee? _selectBestEmployee({
    required Shop shop,
    required DateTime day,
    required ShiftType shiftType,
    required List<Employee> employees,
    required WorkSchedule schedule,
  }) {
    // Сортируем сотрудников по приоритету
    final scoredEmployees = employees.map((employee) {
      int score = 0;

      // Приоритет 1: Предпочтение магазина (+10)
      if (_isPreferredShop(employee, shop)) {
        score += 10;
      }

      // Приоритет 2: Желаемый день работы (+5)
      if (_isPreferredDay(employee, day)) {
        score += 5;
      }

      // Приоритет 3: Предпочтение смены
      final grade = _getShiftPreferenceGrade(employee, shiftType);
      if (grade == 1) {
        score += 3; // Всегда хочет
      } else if (grade == 2) {
        score += 1; // Может, но не хочет
      } else if (grade == 3) {
        score -= 10; // Не будет работать
      }

      // Приоритет 4: Отсутствие конфликтов (+2)
      if (!_hasConflict(employee, day, shiftType, schedule)) {
        score += 2;
      }

      return {'employee': employee, 'score': score};
    }).toList();

    // Фильтруем сотрудников с отрицательным счетом (не будут работать)
    scoredEmployees.removeWhere((item) => item['score'] as int < 0);

    // Сортируем по счету (больше = лучше)
    scoredEmployees.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    // Выбираем сотрудника с наивысшим счетом, который может работать
    for (var item in scoredEmployees) {
      final employee = item['employee'] as Employee;
      if (_canWorkShift(employee, day, shiftType, schedule)) {
        return employee;
      }
    }

    return null;
  }

  /// Выбрать любого доступного сотрудника
  static Employee? _selectAnyAvailableEmployee({
    required Shop shop,
    required DateTime day,
    required ShiftType shiftType,
    required List<Employee> employees,
    required WorkSchedule schedule,
  }) {
    for (var employee in employees) {
      if (_canWorkShift(employee, day, shiftType, schedule)) {
        return employee;
      }
    }
    return null;
  }

  /// Проверить, может ли сотрудник работать в эту смену
  static bool _canWorkShift(
    Employee employee,
    DateTime day,
    ShiftType shiftType,
    WorkSchedule schedule,
  ) {
    // Проверяем конфликты (утро после вечера предыдущего дня)
    if (_hasConflict(employee, day, shiftType, schedule)) {
      return false;
    }

    // Проверяем, не занят ли сотрудник в эту конкретную смену (утро/вечер) в этот день
    final hasThisShift = schedule.entries.any((e) =>
      e.employeeId == employee.id &&
      e.date.year == day.year &&
      e.date.month == day.month &&
      e.date.day == day.day &&
      e.shiftType == shiftType
    );

    // Если уже есть такая же смена, нельзя назначить еще раз
    if (hasThisShift) {
      return false;
    }

    // Разрешаем утреннюю и вечернюю смены в один день для одного сотрудника
    // Но проверяем правило "утро после вечера предыдущего дня"
    if (shiftType == ShiftType.morning) {
      final previousDay = day.subtract(const Duration(days: 1));
      final workedEvening = schedule.entries.any((e) =>
        e.employeeId == employee.id &&
        e.date.year == previousDay.year &&
        e.date.month == previousDay.month &&
        e.date.day == previousDay.day &&
        e.shiftType == ShiftType.evening
      );
      if (workedEvening) {
        return false;
      }
    }

    return true;
  }

  /// Получить градацию предпочтения смены
  static int _getShiftPreferenceGrade(Employee employee, ShiftType shiftType) {
    final prefs = employee.shiftPreferences;
    final key = shiftType.name; // 'morning', 'day', 'evening'
    return prefs[key] ?? 2; // По умолчанию 2 (может, но не хочет)
  }

  /// Проверить, является ли день желаемым для сотрудника
  static bool _isPreferredDay(Employee employee, DateTime day) {
    if (employee.preferredWorkDays.isEmpty) return true; // Если нет предпочтений, считаем что подходит

    final weekday = day.weekday;
    final dayNames = {
      1: 'monday',
      2: 'tuesday',
      3: 'wednesday',
      4: 'thursday',
      5: 'friday',
      6: 'saturday',
      7: 'sunday',
    };

    final dayName = dayNames[weekday];
    return dayName != null && employee.preferredWorkDays.contains(dayName);
  }

  /// Проверить, является ли магазин предпочтительным для сотрудника
  static bool _isPreferredShop(Employee employee, Shop shop) {
    if (employee.preferredShops.isEmpty) return false;

    return employee.preferredShops.contains(shop.id) ||
           employee.preferredShops.contains(shop.address);
  }

  /// Проверить конфликты (утро после вечера)
  static bool _hasConflict(
    Employee employee,
    DateTime day,
    ShiftType shiftType,
    WorkSchedule schedule,
  ) {
    if (shiftType != ShiftType.morning) return false;

    final previousDay = day.subtract(const Duration(days: 1));
    return schedule.entries.any((e) =>
      e.employeeId == employee.id &&
      e.date.year == previousDay.year &&
      e.date.month == previousDay.month &&
      e.date.day == previousDay.day &&
      e.shiftType == ShiftType.evening
    );
  }

  /// Валидация графика
  static List<String> _validateSchedule(
    WorkSchedule schedule,
    List<Shop> shops,
    List<DateTime> days,
  ) {
    final warnings = <String>[];

    for (var day in days) {
      for (var shop in shops) {
        final dayShifts = schedule.entries.where((e) =>
          e.date.year == day.year &&
          e.date.month == day.month &&
          e.date.day == day.day &&
          e.shopAddress == shop.address
        ).toList();

        final hasMorning = dayShifts.any((e) => e.shiftType == ShiftType.morning);
        final hasEvening = dayShifts.any((e) => e.shiftType == ShiftType.evening);

        if (!hasMorning) {
          warnings.add('${shop.name}, ${day.day}.${day.month}: отсутствует утренняя смена');
        }
        if (!hasEvening) {
          warnings.add('${shop.name}, ${day.day}.${day.month}: отсутствует вечерняя смена');
        }
      }
    }

    return warnings;
  }
}

