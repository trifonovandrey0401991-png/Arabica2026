import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'work_schedule_model.dart';
import 'work_schedule_service.dart';
import 'employee_service.dart';
import 'employees_page.dart';

/// Страница моего графика (для просмотра личного графика сотрудника)
class MySchedulePage extends StatefulWidget {
  const MySchedulePage({super.key});

  @override
  State<MySchedulePage> createState() => _MySchedulePageState();
}

class _MySchedulePageState extends State<MySchedulePage> {
  DateTime _selectedMonth = DateTime.now();
  WorkSchedule? _schedule;
  String? _employeeId;
  String? _employeeName;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEmployeeId();
  }

  Future<void> _loadEmployeeId() async {
    try {
      // Получаем имя сотрудника из системы
      final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
      if (systemEmployeeName == null) {
        setState(() {
          _error = 'Не удалось определить сотрудника';
          _isLoading = false;
        });
        return;
      }

      // Загружаем список сотрудников и находим ID по имени
      final employees = await EmployeeService.getEmployees();
      final employee = employees.firstWhere(
        (e) => e.name == systemEmployeeName,
        orElse: () => throw StateError('Employee not found'),
      );

      setState(() {
        _employeeId = employee.id;
        _employeeName = employee.name;
      });

      await _loadSchedule();
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки данных: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSchedule() async {
    if (_employeeId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final schedule = await WorkScheduleService.getEmployeeSchedule(
        _employeeId!,
        _selectedMonth,
      );

      if (mounted) {
        setState(() {
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
      await _loadSchedule();
    }
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

  WorkScheduleEntry? _getEntryForDate(DateTime date) {
    if (_schedule == null) return null;
    try {
      return _schedule!.getEntry(_employeeId!, date);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой график'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectMonth,
            tooltip: 'Выбрать месяц',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSchedule,
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
                        onPressed: _loadEmployeeId,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : _schedule == null
                  ? const Center(child: Text('График не загружен'))
                  : _buildCalendarView(),
    );
  }

  Widget _buildCalendarView() {
    final days = _getDaysInMonth();
    final entriesByDate = <DateTime, WorkScheduleEntry>{};
    
    for (var entry in _schedule!.entries) {
      final date = DateTime(entry.date.year, entry.date.month, entry.date.day);
      entriesByDate[date] = entry;
    }

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
              if (_employeeName != null)
                Text(
                  _employeeName!,
                  style: TextStyle(color: Colors.grey[700]),
                ),
            ],
          ),
        ),
        // Календарь с событиями
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              final entry = entriesByDate[day];
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: entry != null 
                        ? entry.shiftType.color.withOpacity(0.3)
                        : Colors.grey[300],
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: entry != null ? entry.shiftType.color : Colors.grey[700],
                      ),
                    ),
                  ),
                  title: Text(
                    '${day.day} ${_getMonthName(day.month)} ${_getWeekdayName(day.weekday)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: entry != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.shiftType.label} (${entry.shiftType.timeRange})',
                              style: TextStyle(
                                color: entry.shiftType.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(entry.shopAddress),
                          ],
                        )
                      : const Text('Выходной', style: TextStyle(color: Colors.grey)),
                  trailing: entry != null
                      ? Icon(Icons.work, color: entry.shiftType.color)
                      : const Icon(Icons.event_busy, color: Colors.grey),
                ),
              );
            },
          ),
        ),
        // Статистика
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Всего смен', '${_schedule!.entries.length}'),
              _buildStatItem('Утро', '${_schedule!.entries.where((e) => e.shiftType == ShiftType.morning).length}'),
              _buildStatItem('День', '${_schedule!.entries.where((e) => e.shiftType == ShiftType.day).length}'),
              _buildStatItem('Вечер', '${_schedule!.entries.where((e) => e.shiftType == ShiftType.evening).length}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
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
    const weekdays = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
    return weekdays[weekday - 1];
  }
}
