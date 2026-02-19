import '../models/work_schedule_model.dart';
import '../../employees/pages/employees_page.dart';
import '../../shops/models/shop_model.dart';
import '../../../core/utils/logger.dart';

/// Результат автозаполнения
class AutoFillResult {
  final List<WorkScheduleEntry> entries;
  final List<String> warnings;

  const AutoFillResult({required this.entries, required this.warnings});
}

/// Сервис для автоматического заполнения графика работы
class AutoFillScheduleService {
  /// Автозаполнение графика
  static Future<AutoFillResult> autoFill({
    required DateTime startDate,
    required DateTime endDate,
    required List<Employee> employees,
    required List<Shop> shops,
    required WorkSchedule? existingSchedule,
    required bool replaceExisting,
  }) async {
    final List<WorkScheduleEntry> newEntries = [];
    final List<String> warnings = [];

    Logger.debug('🔄 Начало автозаполнения');
    Logger.debug('   Период: ${startDate.day}.${startDate.month}.${startDate.year} - ${endDate.day}.${endDate.month}.${endDate.year}');
    Logger.debug('   Сотрудников: ${employees.length}');
    Logger.debug('   Магазинов: ${shops.length}');
    Logger.debug('   Режим: ${replaceExisting ? "Заменить все" : "Заполнить пустые"}');

    // 1. Подготовка данных
    final days = _getDaysInPeriod(startDate, endDate);

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

    Logger.debug('🔧 Начинаем заполнение. Рабочий график содержит ${workingSchedule.entries.length} записей');

    // 2. Для каждого дня периода
    for (var day in days) {
      Logger.debug('📅 Обрабатываем день: ${day.day}.${day.month}.${day.year}');
      // Для каждого магазина
      for (var shop in shops) {
        // Всегда заполняем утро и вечер для каждого магазина в каждый день
        final requiredShifts = <ShiftType>[
          ShiftType.morning,
          ShiftType.evening,
        ];
        Logger.debug('🏪 Магазин: ${shop.name}, требуемые смены: ${requiredShifts.map((s) => s.label).join(", ")}');

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
          // КРИТИЧНО: Проверяем, нет ли уже смены для этого магазина+дня+типа
          final existingForThisSlot = workingSchedule.entries.where((e) =>
            e.date.year == day.year &&
            e.date.month == day.month &&
            e.date.day == day.day &&
            e.shopAddress == shop.address &&
            e.shiftType == shiftType
          ).toList();

          if (existingForThisSlot.isNotEmpty) {
            Logger.debug('⏭️ ДУБЛИКАТ ОБНАРУЖЕН! Пропускаем ${shop.name}, ${day.day}.${day.month}, ${shiftType.label}');
            Logger.debug('   Уже существует ${existingForThisSlot.length} смен:');
            for (var e in existingForThisSlot) {
              Logger.debug('     - ID=${e.id}, Сотрудник=${e.employeeName}');
            }
            continue;
          }

          Logger.debug('🆕 Создаём смену: ${shop.name}, ${day.day}.${day.month}, ${shiftType.label}');

          Employee? selectedEmployee;

          // Пытаемся найти сотрудника с 4 уровнями приоритета
          for (int priorityLevel = 0; priorityLevel <= 3; priorityLevel++) {
            selectedEmployee = _selectBestEmployee(
              shop: shop,
              day: day,
              shiftType: shiftType,
              employees: employees,
              schedule: workingSchedule,
              priorityLevel: priorityLevel,
            );

            if (selectedEmployee != null) {
              // Логируем если использовали пониженный приоритет
              if (priorityLevel > 0) {
                final priorityMessage = priorityLevel == 1
                    ? 'игнорируем предпочтения по дням'
                    : priorityLevel == 2
                        ? 'игнорируем предпочтения по магазинам'
                        : 'игнорируем предпочтения по сменам';
                Logger.debug('⚠️ ${shop.name}, ${day.day}.${day.month}, ${shiftType.label}: $priorityMessage');
              }
              break;
            }
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
            Logger.debug('✅ Добавлена смена: ${selectedEmployee.name} → ${shop.name}, ${day.day}.${day.month}.${day.year}, ${shiftType.label}');
            Logger.debug('   Теперь в рабочем графике ${workingSchedule.entries.length} записей');
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

    // 4. Проверка задействования всех сотрудников
    final employeeUsageWarnings = _validateAllEmployeesUsed(workingSchedule, employees, days);
    warnings.addAll(employeeUsageWarnings);

    Logger.debug('✅ Автозаполнение завершено: создано ${newEntries.length} смен');
    if (warnings.isNotEmpty) {
      Logger.debug('⚠️ Предупреждения: ${warnings.length}');
      for (var warning in warnings) {
        Logger.debug('   - $warning');
      }
    }

    return AutoFillResult(entries: newEntries, warnings: warnings);
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
  /// priorityLevel: 0-3 определяет какие предпочтения учитываются
  /// 0 = учитываем ВСЕ предпочтения
  /// 1 = игнорируем предпочтения по дням
  /// 2 = игнорируем дни + магазины
  /// 3 = игнорируем всё (дни + магазины + смены)
  static Employee? _selectBestEmployee({
    required Shop shop,
    required DateTime day,
    required ShiftType shiftType,
    required List<Employee> employees,
    required WorkSchedule schedule,
    required int priorityLevel,
  }) {
    // Сортируем сотрудников по приоритету
    final scoredEmployees = employees.map((employee) {
      int score = 0;

      // Предпочтение магазина (учитываем если priorityLevel < 2)
      if (priorityLevel < 2 && _isPreferredShop(employee, shop)) {
        score += 10;
      }

      // Желаемый день работы (учитываем если priorityLevel < 1)
      if (priorityLevel < 1 && _isPreferredDay(employee, day)) {
        score += 5;
      }

      // Предпочтение смены (учитываем если priorityLevel < 3)
      if (priorityLevel < 3) {
        final grade = _getShiftPreferenceGrade(employee, shiftType);
        if (grade == 1) {
          score += 3; // Всегда хочет
        } else if (grade == 2) {
          score += 1; // Может, но не хочет
        } else if (grade == 3) {
          score -= 100; // Не будет работать (блокирует)
        }
      }

      // Отсутствие конфликтов (+2)
      if (!_hasConflict(employee, day, shiftType, schedule)) {
        score += 2;
      }

      // Балансировка нагрузки
      final assignedShiftsCount = schedule.entries
          .where((e) => e.employeeId == employee.id)
          .length;

      if (assignedShiftsCount == 0) {
        score += 100; // Гарантированный максимальный приоритет
      } else {
        final loadBalanceBonus = (30 - assignedShiftsCount).clamp(0, 30);
        score += loadBalanceBonus;
      }

      return {'employee': employee, 'score': score};
    }).toList();

    // Фильтруем с отрицательным счетом (только если priorityLevel < 3)
    if (priorityLevel < 3) {
      scoredEmployees.removeWhere((item) => item['score'] as int < 0);
    }

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

  /// Проверить, может ли сотрудник работать в эту смену
  static bool _canWorkShift(
    Employee employee,
    DateTime day,
    ShiftType shiftType,
    WorkSchedule schedule,
  ) {
    // Проверяем конфликты
    if (_hasConflict(employee, day, shiftType, schedule)) {
      return false;
    }

    // Проверяем, не занят ли сотрудник в этот день
    final hasShift = schedule.entries.any((e) =>
      e.employeeId == employee.id &&
      e.date.year == day.year &&
      e.date.month == day.month &&
      e.date.day == day.day
    );

    // НЕ разрешаем сотруднику работать несколько смен в один день
    // Это обеспечит равномерное распределение работы между всеми сотрудниками
    if (hasShift) {
      return false;
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

  /// Проверить конфликты (24-часовые ограничения)
  static bool _hasConflict(
    Employee employee,
    DateTime day,
    ShiftType shiftType,
    WorkSchedule schedule,
  ) {
    // Запрет 1: Утро после вечерней смены предыдущего дня
    if (shiftType == ShiftType.morning) {
      final previousDay = day.subtract(const Duration(days: 1));
      final hadEvening = schedule.entries.any((e) =>
        e.employeeId == employee.id &&
        e.date.year == previousDay.year &&
        e.date.month == previousDay.month &&
        e.date.day == previousDay.day &&
        e.shiftType == ShiftType.evening
      );
      if (hadEvening) return true;
    }

    // Запрет 2: Вечерняя в тот же день после утренней (24 часа работы)
    if (shiftType == ShiftType.evening) {
      final hadMorning = schedule.entries.any((e) =>
        e.employeeId == employee.id &&
        e.date.year == day.year &&
        e.date.month == day.month &&
        e.date.day == day.day &&
        e.shiftType == ShiftType.morning
      );
      if (hadMorning) return true;
    }

    // Запрет 3: Дневная на следующий день после вечерней (24 часа работы)
    if (shiftType == ShiftType.day) {
      final previousDay = day.subtract(const Duration(days: 1));
      final hadEvening = schedule.entries.any((e) =>
        e.employeeId == employee.id &&
        e.date.year == previousDay.year &&
        e.date.month == previousDay.month &&
        e.date.day == previousDay.day &&
        e.shiftType == ShiftType.evening
      );
      if (hadEvening) return true;
    }

    return false;
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

  /// Проверка задействования всех сотрудников
  static List<String> _validateAllEmployeesUsed(
    WorkSchedule schedule,
    List<Employee> employees,
    List<DateTime> days,
  ) {
    final warnings = <String>[];

    // Подсчитываем смены для каждого сотрудника
    final employeeShiftCounts = <String, int>{};

    for (var employee in employees) {
      final shiftsCount = schedule.entries
          .where((e) =>
            e.employeeId == employee.id &&
            days.any((day) =>
              e.date.year == day.year &&
              e.date.month == day.month &&
              e.date.day == day.day
            )
          )
          .length;

      employeeShiftCounts[employee.name] = shiftsCount;

      if (shiftsCount == 0) {
        warnings.add('⚠️ Сотрудник ${employee.name} не задействован в графике');
        Logger.debug('⚠️ Сотрудник ${employee.name} не получил ни одной смены');
      }
    }

    // Статистика распределения
    if (employeeShiftCounts.isNotEmpty) {
      final totalShifts = employeeShiftCounts.values.reduce((a, b) => a + b);
      final avgShifts = totalShifts / employeeShiftCounts.length;
      final minShifts = employeeShiftCounts.values.reduce((a, b) => a < b ? a : b);
      final maxShifts = employeeShiftCounts.values.reduce((a, b) => a > b ? a : b);

      Logger.debug('📊 Статистика распределения смен:');
      Logger.debug('   Всего смен: $totalShifts');
      Logger.debug('   Среднее на сотрудника: ${avgShifts.toStringAsFixed(1)}');
      Logger.debug('   Минимум: $minShifts, Максимум: $maxShifts');
      Logger.debug('   Сотрудников с 0 смен: ${employeeShiftCounts.values.where((c) => c == 0).length}');
    }

    return warnings;
  }
}

