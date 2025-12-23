import 'package:flutter/material.dart';
import 'work_schedule_model.dart';
import 'work_schedule_service.dart';
import 'employee_service.dart';
import 'shop_model.dart';
import 'abbreviation_selection_dialog.dart';
import 'schedule_bulk_operations_dialog.dart';
import 'employees_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'shop_settings_model.dart';
import 'work_schedule_validator.dart';
import 'schedule_validation_dialog.dart';
import 'employee_schedule_page.dart';
import 'auto_fill_schedule_dialog.dart';
import 'auto_fill_schedule_service.dart';

/// Страница графика работы (для управления графиком сотрудников)
class WorkSchedulePage extends StatefulWidget {
  const WorkSchedulePage({super.key});

  @override
  State<WorkSchedulePage> createState() => _WorkSchedulePageState();
}

class _WorkSchedulePageState extends State<WorkSchedulePage> {
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

  @override
  void initState() {
    super.initState();
    _loadData();
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
    print('🔵 _editShift вызван: ${employee.name}, ${date.day}.${date.month}.${date.year}');
    
    WorkScheduleEntry? entryToEdit;
    if (_schedule != null) {
      try {
        entryToEdit = _schedule!.entries.firstWhere(
          (e) => e.employeeId == employee.id && 
                 e.date.year == date.year &&
                 e.date.month == date.month &&
                 e.date.day == date.day,
        );
        print('✅ Найдена существующая запись: ${entryToEdit.id}');
      } catch (e) {
        entryToEdit = null;
        print('ℹ️ Запись не найдена (это нормально для новой смены)');
      }
    }

    print('📋 Открываем диалог выбора аббревиатуры...');
    print('   Магазинов доступно: ${_shops.length}');
    
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
      
      print('📋 Результат диалога: ${result != null ? result['action'] : 'отменено'}');

      if (result != null) {
        if (result['action'] == 'save') {
          final entry = result['entry'] as WorkScheduleEntry;
          
          // Валидация перед сохранением
          if (entry.employeeId.isEmpty) {
            print('❌ КРИТИЧЕСКАЯ ОШИБКА: employeeId пустой!');
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

          print('💾 Сохранение смены на сервер:');
          print('   employeeId: ${entry.employeeId}');
          print('   employeeName: ${entry.employeeName}');
          print('   shopAddress: ${entry.shopAddress}');
          print('   date: ${entry.date}');
          print('   shiftType: ${entry.shiftType.name}');

          // Проверяем валидацию перед сохранением
          final warnings = _validateShiftBeforeSave(entry);
          
          // Если есть предупреждения, показываем диалог
          if (warnings.isNotEmpty) {
            final shouldSave = await _showValidationWarning(warnings);
            if (!shouldSave) {
              // Пользователь отменил сохранение
              print('❌ Пользователь отменил сохранение из-за предупреждений');
              return;
            }
          }

          final success = await WorkScheduleService.saveShift(entry);
          if (success) {
            print('✅ Смена успешно сохранена на сервер');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Смена сохранена')),
              );
            }
            await _loadData();
          } else {
            print('❌ Ошибка сохранения смены на сервер');
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
          print('🗑️ Удаление смены: ${entry.id}');
          final success = await WorkScheduleService.deleteShift(entry.id);
          if (success) {
            print('✅ Смена успешно удалена');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Смена удалена')),
              );
            }
            await _loadData();
          } else {
            print('❌ Ошибка удаления смены');
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
      print('❌ Ошибка при редактировании смены: $e');
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
        final url = 'https://arabica26.ru/api/shop-settings/${Uri.encodeComponent(shop.address)}';
        final response = await http.get(Uri.parse(url)).timeout(
          const Duration(seconds: 5),
        );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body);
          if (result['success'] == true && result['settings'] != null) {
            settingsCache[shop.address] = ShopSettings.fromJson(result['settings']);
          }
        }
      } catch (e) {
        print('Ошибка загрузки настроек для магазина ${shop.address}: $e');
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
    try {
      return _schedule!.getEntry(employeeId, date);
    } catch (e) {
      // Запись не найдена - это нормально (выходной)
      return null;
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('График работы'),
          backgroundColor: const Color(0xFF004D40),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'График'),
              Tab(text: 'По сотрудникам'),
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
              onPressed: _loadData,
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
                    children: [
                      // Вкладка "График"
                      _schedule == null
                          ? const Center(child: Text('График не загружен'))
                          : _buildCalendarGrid(),
                      // Вкладка "По сотрудникам"
                      _buildByEmployeesTab(),
                    ],
                  ),
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
    if (!isEmpty && _schedule != null) {
      hasConflict = WorkScheduleValidator.hasConflictForCell(
        employee.id,
        date,
        _schedule!,
      );
    }

    return InkWell(
      onTap: () {
        print('🔵 Клик по клетке: ${employee.name}, ${date.day}.${date.month}.${date.year}');
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
