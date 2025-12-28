import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/work_schedule_model.dart';
import '../services/work_schedule_service.dart';
import '../../employees/services/employee_service.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Автоматическое обновление при открытии страницы
    if (_employeeId != null && _schedule == null && !_isLoading) {
      _loadSchedule();
    }
  }

  Future<void> _loadEmployeeId() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('🔍 Начало загрузки данных сотрудника...');
      
      // Используем новый метод для получения employeeId (основной способ)
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      
      if (employeeId == null) {
        print('❌ Не удалось определить ID сотрудника');
        setState(() {
          _error = 'Не удалось определить сотрудника. Убедитесь, что вы вошли в систему.';
          _isLoading = false;
        });
        return;
      }

      print('✅ Получен employeeId: $employeeId');

      // Получаем имя сотрудника
      final employeeName = await EmployeesPage.getCurrentEmployeeName();
      
      // Если имя не получено, загружаем из списка сотрудников
      String? name = employeeName;
      if (name == null) {
        print('⚠️ Имя не получено, загружаем из списка сотрудников...');
        final employees = await EmployeeService.getEmployees();
        try {
          final employee = employees.firstWhere((e) => e.id == employeeId);
          name = employee.name;
          print('✅ Имя получено из списка: $name');
        } catch (e) {
          print('❌ Сотрудник не найден в списке: $e');
        }
      }

      if (mounted) {
        setState(() {
          _employeeId = employeeId;
          _employeeName = name ?? 'Неизвестно';
        });
        print('✅ Данные сотрудника загружены: ID=$employeeId, имя=$name');
      }

      await _loadSchedule();
    } catch (e) {
      print('❌ Ошибка загрузки данных сотрудника: $e');
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки данных: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSchedule() async {
    if (_employeeId == null) {
      print('⚠️ _loadSchedule: employeeId равен null');
      return;
    }

    print('📅 Загрузка графика для сотрудника: $_employeeId');
    print('   Месяц: ${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final schedule = await WorkScheduleService.getEmployeeSchedule(
        _employeeId!,
        _selectedMonth,
      );

      print('✅ График загружен: ${schedule.entries.length} записей');

      if (mounted) {
        setState(() {
          _schedule = schedule;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Ошибка загрузки графика: $e');
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки графика: ${e.toString()}';
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
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_today, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            'График не загружен',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _loadSchedule,
                            child: const Text('Обновить'),
                          ),
                        ],
                      ),
                    )
                  : _schedule!.entries.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.event_busy, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                'На ${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year} смен не назначено',
                                style: const TextStyle(fontSize: 18, color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _loadSchedule,
                                child: const Text('Обновить'),
                              ),
                            ],
                          ),
                        )
                      : _buildCalendarView(),
    );
  }

  Widget _buildCalendarView() {
    // Получаем только дни со сменами (сортируем по дате)
    final entriesWithDates = List<WorkScheduleEntry>.from(_schedule!.entries);
    entriesWithDates.sort((a, b) => a.date.compareTo(b.date));

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
        // Календарь с событиями (только дни со сменами)
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: entriesWithDates.length,
            itemBuilder: (context, index) {
              final entry = entriesWithDates[index];
              final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: entry.shiftType.color.withOpacity(0.3),
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: entry.shiftType.color,
                      ),
                    ),
                  ),
                  title: Text(
                    '${day.day} ${_getMonthName(day.month)} ${_getWeekdayName(day.weekday)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: entry.shiftType.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${entry.shiftType.label} (${entry.shiftType.timeRange})',
                            style: TextStyle(
                              color: entry.shiftType.color,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.store,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              entry.shopAddress,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: Icon(Icons.work, color: entry.shiftType.color),
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
