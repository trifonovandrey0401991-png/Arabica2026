import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../models/work_schedule_model.dart';
import '../models/shift_transfer_model.dart';
import '../services/work_schedule_service.dart';
import '../services/shift_transfer_service.dart';
import '../../employees/services/employee_service.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/models/shop_settings_model.dart';
import '../../shops/services/shop_service.dart';
import '../../../shared/dialogs/abbreviation_selection_dialog.dart';
import '../../../shared/dialogs/schedule_bulk_operations_dialog.dart';
import '../../employees/pages/employees_page.dart';
import '../work_schedule_validator.dart';
import '../../../shared/dialogs/schedule_validation_dialog.dart';
import '../../employees/pages/employee_schedule_page.dart';
import '../../../shared/dialogs/auto_fill_schedule_dialog.dart';
import '../services/auto_fill_schedule_service.dart';
import '../../../shared/dialogs/shift_edit_dialog.dart';
import '../../../shared/dialogs/schedule_errors_dialog.dart';

/// Страница графика работы (для управления графиком сотрудников)
class WorkSchedulePage extends StatefulWidget {
  const WorkSchedulePage({super.key});

  @override
  State<WorkSchedulePage> createState() => _WorkSchedulePageState();
}

class _WorkSchedulePageState extends State<WorkSchedulePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = DateTime.now();
  WorkSchedule? _schedule;
  List<Employee> _employees = [];
  List<Shop> _shops = [];
  bool _isLoading = false;
  String? _error;

  // Выбор периода (числа месяца)
  int _startDay = 1;
  int _endDay = 31;

  // Кэш настроек магазинов для быстрого доступа к аббревиатурам
  Map<String, ShopSettings> _shopSettingsCache = {};

  // Уведомления для админа
  List<ShiftTransferRequest> _adminNotifications = [];
  int _adminUnreadCount = 0;
  bool _isLoadingNotifications = false;

  // Валидация графика
  bool _hasErrors = false;
  int _errorCount = 0;
  ScheduleValidationResult? _validationResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
    _loadAdminUnreadCount();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 2) {
      _loadAdminNotifications();
    }
  }

  Future<void> _loadAdminNotifications() async {
    setState(() {
      _isLoadingNotifications = true;
    });

    try {
      final notifications = await ShiftTransferService.getAdminRequests();
      if (mounted) {
        setState(() {
          _adminNotifications = notifications;
          _isLoadingNotifications = false;
        });
      }
      await _loadAdminUnreadCount();
    } catch (e) {
      Logger.error('Ошибка загрузки уведомлений админа', e);
      if (mounted) {
        setState(() {
          _isLoadingNotifications = false;
        });
      }
    }
  }

  Future<void> _loadAdminUnreadCount() async {
    try {
      final count = await ShiftTransferService.getAdminUnreadCount();
      if (mounted) {
        setState(() {
          _adminUnreadCount = count;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика админа', e);
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final employees = await EmployeeService.getEmployees();
      final shops = await Shop.loadShopsFromGoogleSheets();
      final schedule = await WorkScheduleService.getSchedule(_selectedMonth);
      
      // Загружаем настройки магазинов для получения аббревиатур
      await _loadShopSettings(shops);

      if (mounted) {
        setState(() {
          _employees = employees;
          _shops = shops;
          _schedule = schedule;
          _isLoading = false;
        });
        // Валидация графика после загрузки
        _validateCurrentSchedule();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectMonth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Выберите месяц',
      initialDatePickerMode: DatePickerMode.year,
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
      });
      await _loadData();
    }
  }

  /// Показывает диалог подтверждения очистки графика
  Future<void> _confirmClearSchedule() async {
    Logger.info('🔵 _confirmClearSchedule вызван');

    if (_schedule == null || _schedule!.entries.isEmpty) {
      Logger.warning('График пуст или не загружен');
      return;
    }

    final entryCount = _schedule!.entries.length;
    final monthName = _getMonthName(_selectedMonth.month);

    Logger.info('Запрос подтверждения очистки. Записей: $entryCount, Месяц: $monthName ${_selectedMonth.year}');

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text('Подтвердите очистку'),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Вы уверены, что хотите удалить ВСЕ смены из графика?',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Месяц: $monthName ${_selectedMonth.year}',
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Будет удалено смен: $entryCount',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '⚠️ Это действие НЕОБРАТИМО!',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              Logger.info('🔴 Кнопка "Да, очистить график" в диалоге нажата!');
              Navigator.of(context).pop(true);
              Logger.info('🔴 Navigator.pop(true) вызван');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Да, очистить график'),
          ),
        ],
      ),
    );

    Logger.info('Результат подтверждения: $confirmed');

    if (confirmed == true) {
      Logger.info('Пользователь подтвердил очистку, вызываем _clearSchedule');
      await _clearSchedule();
    } else {
      Logger.info('Пользователь отменил очистку');
    }
  }

  /// Очищает график работы (удаляет все смены)
  Future<void> _clearSchedule() async {
    if (_schedule == null) return;

    try {
      // Показываем индикатор загрузки
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Очистка графика...'),
                ],
              ),
            ),
          ),
        ),
      );

      Logger.info('Начинаем очистку графика за ${_selectedMonth.month}.${_selectedMonth.year}');

      // Используем новый API для быстрой очистки всего месяца
      final result = await WorkScheduleService.clearMonth(_selectedMonth);

      if (result['success'] == true) {
        final deletedCount = result['deletedCount'] ?? 0;
        Logger.info('График успешно очищен. Удалено смен: $deletedCount');
      } else {
        throw Exception(result['message'] ?? 'Ошибка очистки графика');
      }

      // Закрываем диалог загрузки
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Перезагружаем данные
      await _loadData();

      // Показываем сообщение об успехе
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('График успешно очищен'),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 3),
          ),
        );

        // Переключаемся на первую вкладку (График)
        _tabController.animateTo(0);
      }
    } catch (e) {
      Logger.error('Ошибка при очистке графика', e);

      // Закрываем диалог загрузки
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Показываем ошибку
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Ошибка при очистке графика: $e'),
                ),
              ],
            ),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _editShift(Employee employee, DateTime date) async {
    Logger.debug('_editShift вызван: ${employee.name}, ${date.day}.${date.month}.${date.year}');
    
    WorkScheduleEntry? entryToEdit;
    if (_schedule != null) {
      try {
        entryToEdit = _schedule!.entries.firstWhere(
          (e) => e.employeeId == employee.id &&
                 e.date.year == date.year &&
                 e.date.month == date.month &&
                 e.date.day == date.day,
        );
        Logger.debug('Найдена существующая запись: ${entryToEdit.id}');
      } catch (e) {
        entryToEdit = null;
        Logger.info('Запись не найдена (это нормально для новой смены)');
      }
    }

    Logger.debug('Открываем диалог редактирования смены...');
    Logger.debug('Магазинов доступно: ${_shops.length}');

    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ShiftEditDialog(
          existingEntry: entryToEdit,
          date: date,
          employee: employee,
          schedule: _schedule!,
          allEmployees: _employees,
          shops: _shops,
        ),
      );
      
      Logger.debug('Результат диалога: ${result != null ? result['action'] : 'отменено'}');

      if (result != null) {
        if (result['action'] == 'save') {
          final entry = result['entry'] as WorkScheduleEntry;

          // Валидация перед сохранением
          if (entry.employeeId.isEmpty) {
            Logger.error('КРИТИЧЕСКАЯ ОШИБКА: employeeId пустой!', null);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ошибка: не указан сотрудник'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }

          Logger.debug('Сохранение смены на сервер:');
          Logger.debug('employeeId: ${entry.employeeId}, employeeName: ${entry.employeeName}');
          Logger.debug('shopAddress: ${entry.shopAddress}, date: ${entry.date}, shiftType: ${entry.shiftType.name}');

          // Проверяем валидацию перед сохранением
          final warnings = _validateShiftBeforeSave(entry);

          // Если есть предупреждения, показываем диалог
          if (warnings.isNotEmpty) {
            final shouldSave = await _showValidationWarning(warnings);
            if (!shouldSave) {
              // Пользователь отменил сохранение
              Logger.info('Пользователь отменил сохранение из-за предупреждений');
              return;
            }
          }

          final success = await WorkScheduleService.saveShift(entry);
          if (success) {
            Logger.success('Смена успешно сохранена на сервер');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Смена сохранена')),
              );
            }
            await _loadData();
          } else {
            Logger.error('Ошибка сохранения смены на сервер', null);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ошибка сохранения смены'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } else if (result['action'] == 'delete') {
          final entry = result['entry'] as WorkScheduleEntry;
          Logger.debug('Удаление смены: ${entry.id}');
          final success = await WorkScheduleService.deleteShift(entry.id, entry.date);
          if (success) {
            Logger.success('Смена успешно удалена');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Смена удалена')),
              );
            }
            await _loadData();
          } else {
            Logger.error('Ошибка удаления смены', null);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ошибка удаления смены'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      Logger.error('Ошибка при редактировании смены', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showBulkOperations() async {
    await showDialog(
      context: context,
      builder: (context) => ScheduleBulkOperationsDialog(
        schedule: _schedule!,
        employees: _employees,
        shops: _shops,
        selectedMonth: _selectedMonth,
        onOperationComplete: () => _loadData(),
      ),
    );
  }

  /// Валидация текущего графика
  void _validateCurrentSchedule() {
    if (_schedule == null || _shops.isEmpty) {
      setState(() {
        _hasErrors = false;
        _errorCount = 0;
        _validationResult = null;
      });
      return;
    }

    final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, _startDay);
    final lastDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final actualEndDay = _endDay > lastDayOfMonth ? lastDayOfMonth : _endDay;
    final endDate = DateTime(_selectedMonth.year, _selectedMonth.month, actualEndDay);

    _validationResult = WorkScheduleValidator.validateSchedule(
      _schedule!,
      startDate,
      endDate,
      _shops,
    );

    setState(() {
      _hasErrors = _validationResult!.hasErrors;
      _errorCount = _validationResult!.totalCount;
    });

    Logger.debug('Валидация графика: найдено $_errorCount ошибок');
  }

  /// Показать диалог ошибок
  Future<void> _showErrorsDialog() async {
    if (_validationResult == null) {
      _validateCurrentSchedule();
    }

    if (!_hasErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибок в графике не найдено! ✓'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => ScheduleErrorsDialog(
        validationResult: _validationResult!,
        onErrorTap: (error) => _handleErrorTap(error),
      ),
    );
  }

  /// Обработка клика на ошибку в диалоге
  Future<void> _handleErrorTap(ScheduleError error) async {
    Employee? employee;

    if (error.employeeName != null) {
      // Находим сотрудника по имени
      try {
        employee = _employees.firstWhere(
          (e) => e.name == error.employeeName,
        );
      } catch (e) {
        employee = _employees.isNotEmpty ? _employees.first : null;
      }
    } else {
      // Для отсутствующих смен - выбираем первого сотрудника
      employee = _employees.isNotEmpty ? _employees.first : null;
    }

    if (employee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось найти сотрудника'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Определяем требуемый тип смены на основе ошибки
    ShiftType? requiredShiftType;
    switch (error.type) {
      case ScheduleErrorType.missingMorning:
        requiredShiftType = ShiftType.morning;
        break;
      case ScheduleErrorType.missingEvening:
        requiredShiftType = ShiftType.evening;
        break;
      case ScheduleErrorType.duplicateMorning:
        requiredShiftType = ShiftType.morning;
        break;
      case ScheduleErrorType.duplicateEvening:
        requiredShiftType = ShiftType.evening;
        break;
      case ScheduleErrorType.morningAfterEvening:
      case ScheduleErrorType.eveningAfterMorning:
      case ScheduleErrorType.dayAfterEvening:
        // Для конфликтов используем тип смены из ошибки, если указан
        requiredShiftType = error.shiftType;
        break;
    }

    // Находим магазин по адресу из ошибки
    Shop? requiredShop;
    try {
      requiredShop = _shops.firstWhere(
        (shop) => shop.address == error.shopAddress,
      );
    } catch (e) {
      Logger.error('Магазин не найден по адресу: ${error.shopAddress}', e);
      requiredShop = null;
    }

    // Открываем диалог редактирования с заблокированными полями
    await _editShiftNew(
      employee,
      error.date,
      requiredShiftType: requiredShiftType,
      requiredShop: requiredShop,
    );
  }

  /// Новый метод редактирования смены с использованием ShiftEditDialog
  Future<void> _editShiftNew(
    Employee employee,
    DateTime date, {
    ShiftType? requiredShiftType,
    Shop? requiredShop,
  }) async {
    WorkScheduleEntry? existingEntry;
    if (_schedule != null) {
      try {
        // Если указан требуемый тип смены, ищем запись с этим типом
        if (requiredShiftType != null) {
          existingEntry = _schedule!.entries.firstWhere(
            (e) => e.employeeId == employee.id &&
                   e.date.year == date.year &&
                   e.date.month == date.month &&
                   e.date.day == date.day &&
                   e.shiftType == requiredShiftType,
          );
        } else {
          // Если тип смены не указан, ищем любую запись этого сотрудника на эту дату
          existingEntry = _schedule!.entries.firstWhere(
            (e) => e.employeeId == employee.id &&
                   e.date.year == date.year &&
                   e.date.month == date.month &&
                   e.date.day == date.day,
          );
        }
      } catch (e) {
        existingEntry = null;
      }
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ShiftEditDialog(
        existingEntry: existingEntry,
        date: date,
        employee: employee,
        schedule: _schedule!,
        allEmployees: _employees,
        shops: _shops,
        requiredShiftType: requiredShiftType,
        requiredShop: requiredShop,
      ),
    );

    if (result == null) return;

    final action = result['action'] as String?;
    final entry = result['entry'] as WorkScheduleEntry?;

    if (action == 'save' && entry != null) {
      // Проверяем валидацию перед сохранением
      final warnings = _validateShiftBeforeSave(entry);
      if (warnings.isNotEmpty) {
        final shouldSave = await _showValidationWarning(warnings);
        if (!shouldSave) {
          return;
        }
      }

      final success = await WorkScheduleService.saveShift(entry);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Смена сохранена')),
          );
        }
        await _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка сохранения смены'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (action == 'delete' && entry != null) {
      // Проверяем что ID не пустой
      if (entry.id.isEmpty) {
        Logger.error('Попытка удалить смену с пустым ID', null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка: ID смены не найден'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      Logger.debug('Удаление смены: ID=${entry.id}, сотрудник=${entry.employeeName}, дата=${entry.date}');
      final success = await WorkScheduleService.deleteShift(entry.id, entry.date);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Смена удалена')),
          );
        }
        await _loadData();
      } else {
        Logger.error('Не удалось удалить смену: ID=${entry.id}', null);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка удаления смены'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Получить ошибку для конкретной ячейки
  ScheduleError? _getCellError(String employeeId, DateTime day) {
    if (_validationResult == null) return null;

    // Проверяем критичные ошибки
    for (var error in _validationResult!.criticalErrors) {
      if (error.date.year == day.year &&
          error.date.month == day.month &&
          error.date.day == day.day &&
          error.employeeName != null) {
        // Проверяем, относится ли ошибка к этому сотруднику
        final emp = _employees.firstWhere(
          (e) => e.id == employeeId,
          orElse: () => Employee(id: '', name: ''),
        );
        if (emp.name == error.employeeName) {
          return error;
        }
      }
    }

    // Проверяем предупреждения
    for (var warning in _validationResult!.warnings) {
      if (warning.date.year == day.year &&
          warning.date.month == day.month &&
          warning.date.day == day.day &&
          warning.employeeName != null) {
        final emp = _employees.firstWhere(
          (e) => e.id == employeeId,
          orElse: () => Employee(id: '', name: ''),
        );
        if (emp.name == warning.employeeName) {
          return warning;
        }
      }
    }

    return null;
  }

  List<DateTime> _getDaysInMonth() {
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final maxDay = lastDay.day;
    final actualStartDay = _startDay.clamp(1, maxDay);
    final actualEndDay = _endDay.clamp(actualStartDay, maxDay);
    
    final days = <DateTime>[];
    for (var i = actualStartDay; i <= actualEndDay; i++) {
      days.add(DateTime(_selectedMonth.year, _selectedMonth.month, i));
    }
    return days;
  }
  
  Future<void> _loadShopSettings(List<Shop> shops) async {
    final Map<String, ShopSettings> settingsCache = {};

    for (var shop in shops) {
      try {
        final settings = await ShopService.getShopSettings(shop.address);
        if (settings != null) {
          settingsCache[shop.address] = settings;
        }
      } catch (e) {
        Logger.error('Ошибка загрузки настроек для магазина ${shop.address}', e);
      }
    }

    if (mounted) {
      setState(() {
        _shopSettingsCache = settingsCache;
      });
    }
  }
  
  String? _getAbbreviationForEntry(WorkScheduleEntry entry) {
    final settings = _shopSettingsCache[entry.shopAddress];
    if (settings == null) return null;
    
    switch (entry.shiftType) {
      case ShiftType.morning:
        return settings.morningAbbreviation;
      case ShiftType.day:
        return settings.dayAbbreviation;
      case ShiftType.evening:
        return settings.nightAbbreviation;
    }
  }
  
  Future<void> _selectPeriod() async {
    final maxDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => _PeriodSelectionDialog(
        startDay: _startDay,
        endDay: _endDay,
        maxDay: maxDay,
      ),
    );
    
    if (result != null) {
      setState(() {
        _startDay = result['startDay'] ?? 1;
        _endDay = result['endDay'] ?? maxDay;
      });
    }
  }

  WorkScheduleEntry? _getEntryForEmployeeAndDate(String employeeId, DateTime date) {
    if (_schedule == null) return null;
    
    // Используем hasEntry для проверки, чтобы избежать исключений
    if (!_schedule!.hasEntry(employeeId, date)) {
      return null;
    }
    
    try {
      return _schedule!.getEntry(employeeId, date);
    } catch (e) {
      // Если все же произошла ошибка, ищем вручную
      try {
        final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        return _schedule!.entries.firstWhere(
          (e) => e.employeeId == employeeId && 
                 e.date.toIso8601String().split('T')[0] == dateStr,
        );
      } catch (e2) {
        return null;
      }
    }
  }

  /// Проверяет валидность дня по правилу 1 (наличие утренней и вечерней смен на всех магазинах)
  bool _isDayValid(DateTime day) {
    if (_schedule == null || _shops.isEmpty) return false;
    return WorkScheduleValidator.isDayComplete(day, _shops, _schedule!);
  }

  /// Проверяет конфликты перед сохранением смены
  List<String> _validateShiftBeforeSave(WorkScheduleEntry entry) {
    if (_schedule == null) return [];
    return WorkScheduleValidator.checkShiftConflict(entry, _schedule!);
  }

  /// Показывает диалог с предупреждениями валидации
  Future<bool> _showValidationWarning(List<String> warnings) async {
    if (warnings.isEmpty) return true;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ScheduleValidationDialog(warnings: warnings),
    );
    
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('График работы'),
        backgroundColor: const Color(0xFF004D40),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(text: 'График'),
            const Tab(text: 'По сотрудникам'),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notifications, size: 18),
                  const SizedBox(width: 4),
                  const Text('Заявки'),
                  if (_adminUnreadCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_adminUnreadCount',
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.delete_sweep, size: 18),
                  SizedBox(width: 4),
                  Text('Очистить график'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _selectPeriod,
            tooltip: 'Выбрать период',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectMonth,
            tooltip: 'Выбрать месяц',
          ),
          if (_schedule != null)
            IconButton(
              icon: const Icon(Icons.copy_all),
              onPressed: _showBulkOperations,
              tooltip: 'Массовые операции',
            ),
          if (_schedule != null)
            IconButton(
              icon: const Icon(Icons.auto_fix_high),
              onPressed: _showAutoFillDialog,
              tooltip: 'Автозаполнение графика',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadData();
              if (_tabController.index == 2) {
                _loadAdminNotifications();
              }
            },
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Ошибка: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    // Вкладка "График"
                    _schedule == null
                        ? const Center(child: Text('График не загружен'))
                        : _buildCalendarGrid(),
                    // Вкладка "По сотрудникам"
                    _buildByEmployeesTab(),
                    // Вкладка "Заявки на передачу смен"
                    _buildAdminNotificationsTab(),
                    // Вкладка "Очистить график"
                    _buildClearScheduleTab(),
                  ],
                ),
      floatingActionButton: _schedule != null
          ? FloatingActionButton(
              onPressed: _showErrorsDialog,
              backgroundColor: _hasErrors ? Colors.red : Colors.grey,
              foregroundColor: Colors.white,
              child: Badge(
                label: Text('$_errorCount'),
                isLabelVisible: _hasErrors,
                child: const Icon(Icons.error_outline),
              ),
            )
          : null,
    );
  }

  Widget _buildCalendarGrid() {
    final days = _getDaysInMonth();
    final employeesByShop = <String, List<Employee>>{};

    // Группируем сотрудников по магазинам (если есть информация о магазине)
    // Пока просто группируем всех вместе
    employeesByShop['Все сотрудники'] = _employees;

    return Column(
      children: [
        // Заголовок с месяцем и периодом
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[200],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_employees.length} сотрудников',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Период: $_startDay - $_endDay число',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
        // Календарная сетка
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: _buildTable(days, employeesByShop),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(List<DateTime> days, Map<String, List<Employee>> employeesByShop) {
    // Получаем всех сотрудников в один список
    final allEmployees = employeesByShop.values.expand((list) => list).toList();
    
    return Table(
      border: TableBorder(
        top: BorderSide(color: Colors.grey[400]!, width: 1.5),
        bottom: BorderSide(color: Colors.grey[400]!, width: 1.5),
        left: BorderSide(color: Colors.grey[400]!, width: 1.5),
        right: BorderSide(color: Colors.grey[400]!, width: 1.5),
        horizontalInside: BorderSide(color: Colors.grey[300]!, width: 1),
        verticalInside: BorderSide(color: Colors.grey[300]!, width: 1),
      ),
      columnWidths: {
        0: const FixedColumnWidth(180), // Колонка с именами сотрудников
        for (var i = 0; i < days.length; i++) i + 1: const FixedColumnWidth(70),
      },
      children: [
        // Заголовок с датами
        TableRow(
          decoration: BoxDecoration(
            color: Colors.grey[300],
            border: Border(
              bottom: BorderSide(color: Colors.grey[400]!, width: 2),
            ),
          ),
          children: [
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  border: Border(
                    right: BorderSide(color: Colors.grey[400]!, width: 2),
                  ),
                ),
                child: const Text(
                  'Сотрудник',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            ...days.map((day) {
              final isValid = _isDayValid(day);
              return TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  decoration: BoxDecoration(
                    color: isValid ? Colors.green[100] : Colors.grey[300],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getWeekdayName(day.weekday),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
        // Строки для каждого сотрудника
        ...allEmployees.asMap().entries.map((entry) {
          final index = entry.key;
          final employee = entry.value;
          final isEven = index % 2 == 0;
          
          return TableRow(
            decoration: BoxDecoration(
              color: isEven ? Colors.white : Colors.grey[50],
            ),
            children: [
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: isEven ? Colors.white : Colors.grey[50],
                    border: Border(
                      right: BorderSide(color: Colors.grey[400]!, width: 2),
                    ),
                  ),
                  child: Text(
                    employee.name,
                    style: const TextStyle(
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ...days.map((day) => TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: _buildCell(employee, day),
                  )),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildCell(Employee employee, DateTime date) {
    final entry = _getEntryForEmployeeAndDate(employee.id, date);
    final isEmpty = entry == null;
    final abbreviation = entry != null ? _getAbbreviationForEntry(entry) : null;
    final employeeIndex = _employees.indexWhere((e) => e.id == employee.id);
    final isEven = employeeIndex % 2 == 0;

    // Получаем ошибку для ячейки из результата валидации
    final cellError = _getCellError(employee.id, date);
    final hasError = cellError != null;

    Color? borderColor;
    Widget? errorIcon;

    if (hasError) {
      if (cellError!.isCritical) {
        // Критичная ошибка: красная рамка
        borderColor = Colors.red;
        errorIcon = const Icon(Icons.error, color: Colors.red, size: 12);
      } else {
        // Предупреждение: оранжевая рамка
        borderColor = Colors.orange;
        errorIcon = const Icon(Icons.warning, color: Colors.orange, size: 12);
      }
    }

    return InkWell(
      onTap: () {
        Logger.debug('Клик по клетке: ${employee.name}, ${date.day}.${date.month}.${date.year}');
        _editShift(employee, date);
      },
      child: Container(
        width: 70,
        height: 40,
        decoration: BoxDecoration(
          color: isEmpty
              ? (isEven ? Colors.white : Colors.grey[50])
              : entry!.shiftType.color.withOpacity(0.2),
          border: Border.all(
            color: hasError
                ? borderColor!
                : (isEmpty ? Colors.grey[300]! : entry.shiftType.color),
            width: hasError ? 2.0 : (isEmpty ? 0.5 : 1.0),
          ),
        ),
        child: isEmpty
            ? const SizedBox()
            : Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Text(
                        abbreviation ?? entry.shiftType.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: entry.shiftType.color,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Иконка ошибки/предупреждения
                  if (errorIcon != null)
                    Positioned(
                      top: 1,
                      right: 1,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: errorIcon,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];
    return months[month - 1];
  }

  String _getWeekdayName(int weekday) {
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return weekdays[weekday - 1];
  }

  /// Показывает диалог автозаполнения
  Future<void> _showAutoFillDialog() async {
    Logger.info('📋 Нажата кнопка автозаполнения');
    Logger.debug('   График: ${_schedule != null ? "загружен (${_schedule!.entries.length} записей)" : "не загружен"}');
    Logger.debug('   Сотрудников: ${_employees.length}');
    Logger.debug('   Магазинов: ${_shops.length}');

    if (_schedule == null || _employees.isEmpty || _shops.isEmpty) {
      Logger.warning('⚠️ Недостаточно данных для автозаполнения');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Необходимо загрузить график, сотрудников и магазины'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    Logger.info('✅ Все данные загружены, показываем диалог автозаполнения');
    print('🔵 ПЕРЕД showDialog');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AutoFillScheduleDialog(
        selectedMonth: _selectedMonth,
        startDay: _startDay,
        endDay: _endDay,
        schedule: _schedule,
        employees: _employees,
        shops: _shops,
        shopSettingsCache: _shopSettingsCache,
      ),
    );

    print('🔵 ПОСЛЕ showDialog, result: $result');
    print('🔵 result != null: ${result != null}');
    Logger.info('📥 Диалог закрыт, результат: ${result != null ? "получен" : "null"}');

    if (result != null) {
      print('🔵 Внутри if, вызываем _performAutoFill');
      Logger.debug('   startDay: ${result['startDay']}, endDay: ${result['endDay']}, replace: ${result['replaceExisting']}');
      await _performAutoFill(result);
      print('🔵 _performAutoFill завершен');
    } else {
      print('🔵 result == null, пропускаем');
      Logger.warning('⚠️ Результат диалога = null, автозаполнение не выполнено');
    }
  }

  /// Выполняет автозаполнение графика
  Future<void> _performAutoFill(Map<String, dynamic> options) async {
    print('🟢 _performAutoFill НАЧАЛО');
    final startDay = options['startDay'] as int;
    final endDay = options['endDay'] as int;
    final replaceExisting = options['replaceExisting'] as bool;

    print('🔄 Начало автозаполнения: с $startDay по $endDay, заменить=$replaceExisting');
    print('   Сотрудников: ${_employees.length}, Магазинов: ${_shops.length}');
    Logger.info('🔄 Начало автозаполнения: с $startDay по $endDay, заменить=$replaceExisting');
    Logger.debug('   Сотрудников: ${_employees.length}, Магазинов: ${_shops.length}');

    print('🔵 Показываем диалог загрузки...');
    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Выполняется автозаполнение...'),
              ],
            ),
          ),
        ),
      ),
    );
    print('🔵 Диалог загрузки показан');

    try {
      print('🔵 В блоке try, вычисляем даты...');
      // Вычисляем даты начала и конца периода
      final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, startDay);
      final endDate = DateTime(_selectedMonth.year, _selectedMonth.month, endDay);
      print('🔵 Даты: $startDate - $endDate');

      // ОПТИМИЗАЦИЯ: Не удаляем смены здесь, AutoFillScheduleService сам фильтрует существующие
      // при replaceExisting=true (строки 35-40 в auto_fill_schedule_service.dart)

      // Выполняем автозаполнение
      print('🟢 Вызываем AutoFillScheduleService.autoFill...');
      final newEntries = await AutoFillScheduleService.autoFill(
        startDate: startDate,
        endDate: endDate,
        employees: _employees,
        shops: _shops,
        shopSettingsCache: _shopSettingsCache,
        existingSchedule: _schedule,
        replaceExisting: replaceExisting,
      );

      print('🟢 AutoFillScheduleService.autoFill вернул ${newEntries.length} записей');
      Logger.info('🔄 Автозаполнение создало ${newEntries.length} записей');

      // Сохраняем новые смены батчами по 50 записей
      if (newEntries.isNotEmpty) {
        const batchSize = 50;
        int savedCount = 0;

        for (int i = 0; i < newEntries.length; i += batchSize) {
          final batch = newEntries.skip(i).take(batchSize).toList();

          // В первый батч передаём параметры замены
          final success = i == 0 && replaceExisting
              ? await WorkScheduleService.bulkCreateShifts(
                  batch,
                  replaceMode: 'all',
                  startDate: startDate,
                  endDate: endDate,
                )
              : await WorkScheduleService.bulkCreateShifts(batch);

          if (success) {
            savedCount += batch.length;
          } else {
            // Если батч не сохранился, пробуем сохранить по одной
            for (var entry in batch) {
              await WorkScheduleService.saveShift(entry);
              savedCount++;
            }
          }

          // Небольшая задержка между батчами
          await Future.delayed(const Duration(milliseconds: 100));
        }

        Logger.success('Сохранено смен: $savedCount из ${newEntries.length}');
      }

      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Обновляем график - принудительно перезагружаем данные
      print('🟢 Обновляем график после автозаполнения...');
      setState(() {
        _isLoading = true;
      });

      await _loadData();
      print('🟢 _loadData завершен, график содержит ${_schedule?.entries.length ?? 0} записей');

      // Дополнительная проверка - загружаем график еще раз для уверенности
      try {
        print('🟢 Повторная загрузка графика...');
        final refreshedSchedule = await WorkScheduleService.getSchedule(_selectedMonth);
        print('🟢 Повторная загрузка вернула ${refreshedSchedule.entries.length} записей');
        if (mounted) {
          setState(() {
            _schedule = refreshedSchedule;
            _isLoading = false;
          });
          print('🟢 setState вызван, таблица должна обновиться');
        }
      } catch (e) {
        print('❌ Ошибка при повторной загрузке: $e');
        Logger.error('Ошибка при обновлении графика', e);
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }

      // Показываем результаты
      if (mounted) {
        _showAutoFillResults(newEntries.length);
      }
    } catch (e) {
      // Закрываем индикатор загрузки
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка автозаполнения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Показывает результаты автозаполнения
  void _showAutoFillResults(int entriesCount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Автозаполнение завершено'),
        content: Text('Создано смен: $entriesCount'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  /// Строит вкладку "Заявки на передачу смен" для администратора
  Widget _buildAdminNotificationsTab() {
    if (_isLoadingNotifications) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_adminNotifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет заявок на передачу смен',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Здесь появятся заявки, требующие вашего одобрения',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAdminNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _adminNotifications.length,
        itemBuilder: (context, index) {
          final request = _adminNotifications[index];
          return _buildAdminNotificationCard(request);
        },
      ),
    );
  }

  /// Карточка заявки на передачу смены для администратора
  Widget _buildAdminNotificationCard(ShiftTransferRequest request) {
    final isUnread = !request.isReadByAdmin;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isUnread ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isUnread
            ? const BorderSide(color: Colors.orange, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (isUnread) {
            await ShiftTransferService.markAsRead(request.id, isAdmin: true);
            _loadAdminNotifications();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок с индикатором непрочитанного
              Row(
                children: [
                  if (isUnread)
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      'Заявка на передачу смены',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isUnread ? Colors.orange[800] : Colors.black87,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Ожидает одобрения',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Информация о передаче
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Передаёт:',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          request.fromEmployeeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward, color: Colors.grey),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Принимает:',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          request.acceptedByEmployeeName ?? 'Неизвестно',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Детали смены
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      Icons.calendar_today,
                      'Дата:',
                      '${request.shiftDate.day}.${request.shiftDate.month.toString().padLeft(2, '0')}.${request.shiftDate.year}',
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      Icons.access_time,
                      'Смена:',
                      request.shiftType.label,
                    ),
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      Icons.store,
                      'Магазин:',
                      request.shopName.isNotEmpty ? request.shopName : request.shopAddress,
                    ),
                  ],
                ),
              ),

              // Комментарий
              if (request.comment != null && request.comment!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.comment, size: 18, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          request.comment!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue[900],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Кнопки действий
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _declineRequest(request),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Отклонить'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _approveRequest(request),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Одобрить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  /// Одобрить заявку на передачу смены
  Future<void> _approveRequest(ShiftTransferRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Одобрить заявку?'),
        content: SingleChildScrollView(
          child: Text(
            'Смена ${request.shiftDate.day}.${request.shiftDate.month} (${request.shiftType.label}) '
            'будет передана от ${request.fromEmployeeName} к ${request.acceptedByEmployeeName}.\n\n'
            'График будет обновлен автоматически.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Одобрить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ShiftTransferService.approveRequest(request.id);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Заявка одобрена, график обновлен'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadAdminNotifications();
        await _loadData(); // Обновляем график
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка одобрения заявки'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Отклонить заявку на передачу смены
  Future<void> _declineRequest(ShiftTransferRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отклонить заявку?'),
        content: SingleChildScrollView(
          child: Text(
            'Заявка на передачу смены ${request.shiftDate.day}.${request.shiftDate.month} '
            'от ${request.fromEmployeeName} к ${request.acceptedByEmployeeName} будет отклонена.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Отклонить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ShiftTransferService.declineRequest(request.id);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Заявка отклонена'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        await _loadAdminNotifications();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка отклонения заявки'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Строит вкладку "Очистить график"
  Widget _buildClearScheduleTab() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 80,
              color: Colors.orange[700],
            ),
            const SizedBox(height: 24),
            const Text(
              'Очистка графика работы',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Выбранный месяц: ${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Это действие удалит ВСЕ смены из текущего месяца',
                            style: TextStyle(fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: const [
                        Icon(Icons.warning, color: Colors.red),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Это действие НЕОБРАТИМО',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            if (_schedule != null && _schedule!.entries.isNotEmpty) ...[
              Text(
                'Текущих смен в графике: ${_schedule!.entries.length}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
            ],
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _schedule != null && _schedule!.entries.isNotEmpty
                    ? () {
                        Logger.info('🔴 КНОПКА ОЧИСТИТЬ ГРАФИК НАЖАТА!');
                        Logger.info('   Записей в графике: ${_schedule!.entries.length}');
                        _confirmClearSchedule();
                      }
                    : null,
                icon: const Icon(Icons.delete_forever, size: 28),
                label: const Text(
                  'Очистить график',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_schedule == null || _schedule!.entries.isEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'График уже пуст',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Строит вкладку "По сотрудникам"
  Widget _buildByEmployeesTab() {
    if (_employees.isEmpty) {
      return const Center(
        child: Text('Нет сотрудников'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _employees.length,
      itemBuilder: (context, index) {
        final employee = _employees[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF004D40),
              child: Text(
                employee.name.isNotEmpty
                    ? employee.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(
              employee.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: employee.phone != null
                ? Text(employee.phone!)
                : null,
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EmployeeSchedulePage(
                    employee: employee,
                    selectedMonth: _selectedMonth,
                    startDay: _startDay,
                    endDay: _endDay,
                    shops: _shops,
                    schedule: _schedule,
                    shopSettingsCache: _shopSettingsCache,
                    onScheduleUpdated: () => _loadData(),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// Диалог для выбора периода (числа месяца)
class _PeriodSelectionDialog extends StatefulWidget {
  final int startDay;
  final int endDay;
  final int maxDay;

  const _PeriodSelectionDialog({
    required this.startDay,
    required this.endDay,
    required this.maxDay,
  });

  @override
  State<_PeriodSelectionDialog> createState() => _PeriodSelectionDialogState();
}

class _PeriodSelectionDialogState extends State<_PeriodSelectionDialog> {
  late int _startDay;
  late int _endDay;

  @override
  void initState() {
    super.initState();
    _startDay = widget.startDay;
    _endDay = widget.endDay;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Выберите период'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('С: '),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _startDay,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(widget.maxDay, (i) => i + 1).map((day) {
                    return DropdownMenuItem<int>(
                      value: day,
                      child: Text('$day'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _startDay = value;
                        if (_endDay < _startDay) {
                          _endDay = _startDay;
                        }
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('По: '),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _endDay,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(widget.maxDay - _startDay + 1, (i) => _startDay + i).map((day) {
                    return DropdownMenuItem<int>(
                      value: day,
                      child: Text('$day'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _endDay = value;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop({
              'startDay': _startDay,
              'endDay': _endDay,
            });
          },
          child: const Text('Применить'),
        ),
      ],
    );
  }
}
