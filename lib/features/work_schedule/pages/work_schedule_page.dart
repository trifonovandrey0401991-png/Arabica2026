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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

    Logger.debug('Открываем диалог выбора аббревиатуры...');
    Logger.debug('Магазинов доступно: ${_shops.length}');
    
    try {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AbbreviationSelectionDialog(
          employeeId: employee.id,
          employeeName: employee.name,
          date: date,
          existingEntry: entryToEdit,
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
          final success = await WorkScheduleService.deleteShift(entry.id);
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
                  ],
                ),
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
    
    // Проверяем наличие конфликта для этой ячейки
    bool hasConflict = false;
    if (!isEmpty && _schedule != null && entry != null) {
      hasConflict = WorkScheduleValidator.hasConflictForCell(
        employee.id,
        date,
        _schedule!,
      );
    }

    return InkWell(
      onTap: () {
        Logger.debug('Клик по клетке: ${employee.name}, ${date.day}.${date.month}.${date.year}');
        _editShift(employee, date);
      },
      child: Container(
        constraints: const BoxConstraints(
          minHeight: 40,
          minWidth: 70,
        ),
        padding: const EdgeInsets.all(2.0),
        decoration: BoxDecoration(
          color: isEmpty 
              ? (isEven ? Colors.white : Colors.grey[50])
              : entry!.shiftType.color.withOpacity(0.2),
          border: isEmpty
              ? null
              : Border.all(
                  color: hasConflict ? Colors.red : entry.shiftType.color,
                  width: hasConflict ? 2.0 : 1.5,
                ),
        ),
        child: isEmpty
            ? const SizedBox()
            : Stack(
                children: [
                  Center(
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
                  // Иконка предупреждения для конфликтов
                  if (hasConflict)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning,
                          color: Colors.white,
                          size: 12,
                        ),
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
    if (_schedule == null || _employees.isEmpty || _shops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Необходимо загрузить график, сотрудников и магазины'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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

    if (result != null) {
      await _performAutoFill(result);
    }
  }

  /// Выполняет автозаполнение графика
  Future<void> _performAutoFill(Map<String, dynamic> options) async {
    final startDay = options['startDay'] as int;
    final endDay = options['endDay'] as int;
    final replaceExisting = options['replaceExisting'] as bool;

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

    try {
      // Вычисляем даты начала и конца периода
      final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, startDay);
      final endDate = DateTime(_selectedMonth.year, _selectedMonth.month, endDay);

      // Если режим "Заменить", удаляем существующие смены в периоде
      if (replaceExisting && _schedule != null) {
        final entriesToDelete = _schedule!.entries.where((e) {
          final entryDate = DateTime(e.date.year, e.date.month, e.date.day);
          return entryDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
                 entryDate.isBefore(endDate.add(const Duration(days: 1)));
        }).toList();

        for (var entry in entriesToDelete) {
          if (entry.id.isNotEmpty) {
            await WorkScheduleService.deleteShift(entry.id);
          }
        }
      }

      // Выполняем автозаполнение
      final newEntries = await AutoFillScheduleService.autoFill(
        startDate: startDate,
        endDate: endDate,
        employees: _employees,
        shops: _shops,
        shopSettingsCache: _shopSettingsCache,
        existingSchedule: _schedule,
        replaceExisting: replaceExisting,
      );

      // Сохраняем новые смены батчами по 50 записей
      if (newEntries.isNotEmpty) {
        const batchSize = 50;
        int savedCount = 0;
        
        for (int i = 0; i < newEntries.length; i += batchSize) {
          final batch = newEntries.skip(i).take(batchSize).toList();
          final success = await WorkScheduleService.bulkCreateShifts(batch);
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
      setState(() {
        _isLoading = true;
      });
      
      await _loadData();
      
      // Дополнительная проверка - загружаем график еще раз для уверенности
      try {
        final refreshedSchedule = await WorkScheduleService.getSchedule(_selectedMonth);
        if (mounted) {
          setState(() {
            _schedule = refreshedSchedule;
            _isLoading = false;
          });
        }
      } catch (e) {
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
        content: Text(
          'Смена ${request.shiftDate.day}.${request.shiftDate.month} (${request.shiftType.label}) '
          'будет передана от ${request.fromEmployeeName} к ${request.acceptedByEmployeeName}.\n\n'
          'График будет обновлен автоматически.',
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
        content: Text(
          'Заявка на передачу смены ${request.shiftDate.day}.${request.shiftDate.month} '
          'от ${request.fromEmployeeName} к ${request.acceptedByEmployeeName} будет отклонена.',
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
