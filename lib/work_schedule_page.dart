import 'package:flutter/material.dart';
import 'work_schedule_model.dart';
import 'work_schedule_service.dart';
import 'employee_service.dart';
import 'shop_model.dart';
import 'shift_edit_dialog.dart';
import 'schedule_bulk_operations_dialog.dart';
import 'employees_page.dart';

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
    final existingEntry = _schedule?.entries.firstWhere(
      (e) => e.employeeId == employee.id && 
             e.date.year == date.year &&
             e.date.month == date.month &&
             e.date.day == date.day,
      orElse: () => throw StateError('Not found'),
    );

    WorkScheduleEntry? entryToEdit;
    try {
      entryToEdit = existingEntry;
    } catch (e) {
      entryToEdit = null;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ShiftEditDialog(
        employeeId: employee.id,
        employeeName: employee.name,
        date: date,
        existingEntry: entryToEdit,
        shops: _shops,
      ),
    );

    if (result != null) {
      if (result['action'] == 'save') {
        final entry = result['entry'] as WorkScheduleEntry;
        final success = await WorkScheduleService.saveShift(entry);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Смена сохранена')),
          );
          await _loadData();
        }
      } else if (result['action'] == 'delete') {
        final entry = result['entry'] as WorkScheduleEntry;
        final success = await WorkScheduleService.deleteShift(entry.id);
        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Смена удалена')),
          );
          await _loadData();
        }
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
    final days = <DateTime>[];
    for (var i = 1; i <= lastDay.day; i++) {
      days.add(DateTime(_selectedMonth.year, _selectedMonth.month, i));
    }
    return days;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('График работы'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
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
              : _schedule == null
                  ? const Center(child: Text('График не загружен'))
                  : _buildCalendarGrid(),
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
        // Заголовок с месяцем
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[200],
          child: Row(
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
        ),
        // Календарная сетка
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: _buildTable(days, employeesByShop),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(List<DateTime> days, Map<String, List<Employee>> employeesByShop) {
    return Table(
      border: TableBorder.all(color: Colors.grey[300]!),
      columnWidths: {
        0: const FixedColumnWidth(200), // Колонка с именами сотрудников
        for (var i = 0; i < days.length; i++) i + 1: const FixedColumnWidth(80),
      },
      children: [
        // Заголовок с датами
        TableRow(
          decoration: BoxDecoration(color: Colors.grey[200]),
          children: [
            const TableCell(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('Сотрудник', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            ...days.map((day) => TableCell(
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${day.day}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _getWeekdayName(day.weekday),
                          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        ),
        // Строки для каждого сотрудника
        ...employeesByShop.entries.expand((shopEntry) {
          final shopName = shopEntry.key;
          final employees = shopEntry.value;
          
          return [
            // Заголовок магазина
            TableRow(
              decoration: BoxDecoration(color: Colors.grey[100]),
              children: [
                TableCell(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      shopName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
                ...days.map((_) => const TableCell(child: SizedBox())),
              ],
            ),
            // Сотрудники магазина
            ...employees.map((employee) => TableRow(
                  children: [
                    TableCell(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(employee.name),
                      ),
                    ),
                    ...days.map((day) => TableCell(
                          child: _buildCell(employee, day),
                        )),
                  ],
                )),
          ];
        }),
      ],
    );
  }

  Widget _buildCell(Employee employee, DateTime date) {
    final entry = _getEntryForEmployeeAndDate(employee.id, date);
    final isEmpty = entry == null;

    return GestureDetector(
      onTap: () => _editShift(employee, date),
      child: Container(
        padding: const EdgeInsets.all(4.0),
        decoration: BoxDecoration(
          color: isEmpty ? Colors.white : entry!.shiftType.color.withOpacity(0.3),
          border: isEmpty
              ? Border.all(color: Colors.grey[200]!, width: 1)
              : Border.all(color: entry.shiftType.color, width: 2),
        ),
        child: isEmpty
            ? const SizedBox()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.shiftType.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: entry.shiftType.color,
                    ),
                  ),
                  Text(
                    entry.shopAddress.split(',').first,
                    style: TextStyle(fontSize: 8, color: Colors.grey[700]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
}
