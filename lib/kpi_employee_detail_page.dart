import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'kpi_service.dart';
import 'kpi_models.dart';
import 'utils/logger.dart';

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Детальная страница сотрудника с календарем и списком смен
class KPIEmployeeDetailPage extends StatefulWidget {
  final String employeeName;

  const KPIEmployeeDetailPage({
    super.key,
    required this.employeeName,
  });

  @override
  State<KPIEmployeeDetailPage> createState() => _KPIEmployeeDetailPageState();
}

class _KPIEmployeeDetailPageState extends State<KPIEmployeeDetailPage> {
  KPIEmployeeData? _employeeData;
  bool _isLoading = true;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _loadEmployeeData();
  }

  Future<void> _loadEmployeeData() async {
    setState(() => _isLoading = true);

    try {
      final data = await KPIService.getEmployeeData(widget.employeeName);
      if (mounted) {
        setState(() {
          _employeeData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки данных сотрудника', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<KPIDayData> get _currentMonthData {
    if (_employeeData == null) return [];
    final now = DateTime.now();
    return _employeeData!.getMonthData(now.year, now.month);
  }

  List<KPIDayData> get _previousMonthData {
    if (_employeeData == null) return [];
    final now = DateTime.now();
    DateTime previousMonth;
    if (now.month == 1) {
      previousMonth = DateTime(now.year - 1, 12, 1);
    } else {
      previousMonth = DateTime(now.year, now.month - 1, 1);
    }
    return _employeeData!.getMonthData(previousMonth.year, previousMonth.month);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employeeName),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              KPIService.clearCache();
              _loadEmployeeData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _employeeData == null
              ? const Center(child: Text('Нет данных'))
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Статистика
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        color: const Color(0xFF004D40).withOpacity(0.1),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatCard(
                              'Дней отработано',
                              _employeeData!.totalDaysWorked.toString(),
                              Icons.calendar_today,
                            ),
                            _buildStatCard(
                              'Пересменок',
                              _employeeData!.totalShifts.toString(),
                              Icons.work_history,
                            ),
                            _buildStatCard(
                              'Пересчетов',
                              _employeeData!.totalRecounts.toString(),
                              Icons.inventory,
                            ),
                            _buildStatCard(
                              'РКО',
                              _employeeData!.totalRKOs.toString(),
                              Icons.receipt_long,
                            ),
                          ],
                        ),
                      ),
                      // Календарь
                      TableCalendar<KPIDayData>(
                        firstDay: DateTime.utc(2020, 1, 1),
                        lastDay: DateTime.utc(2030, 12, 31),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) {
                          return isSameDay(_selectedDay, day);
                        },
                        eventLoader: (day) {
                          final dayData = _employeeData!.getDayData(day);
                          if (dayData != null && dayData.workedToday) {
                            return [dayData];
                          }
                          return [];
                        },
                        calendarFormat: _calendarFormat,
                        startingDayOfWeek: StartingDayOfWeek.monday,
                        calendarStyle: CalendarStyle(
                          todayDecoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: const BoxDecoration(
                            color: Color(0xFF004D40),
                            shape: BoxShape.circle,
                          ),
                          markerDecoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          outsideDaysVisible: false,
                        ),
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: true,
                          titleCentered: true,
                        ),
                        onDaySelected: (selectedDay, focusedDay) {
                          setState(() {
                            _selectedDay = selectedDay;
                            _focusedDay = focusedDay;
                          });
                        },
                        onFormatChanged: (format) {
                          setState(() => _calendarFormat = format);
                        },
                        onPageChanged: (focusedDay) {
                          setState(() => _focusedDay = focusedDay);
                        },
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('Рабочий день'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Список смен
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Текущий месяц',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildShiftsList(_currentMonthData),
                            const SizedBox(height: 24),
                            const Text(
                              'Предыдущий месяц',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildShiftsList(_previousMonthData),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF004D40)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF004D40),
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildShiftsList(List<KPIDayData> daysData) {
    if (daysData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Нет данных за этот период',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: daysData.length,
      itemBuilder: (context, index) {
        final dayData = daysData[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${dayData.date.day}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _getMonthName(dayData.date.month),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            title: Text(dayData.shopAddress),
            subtitle: dayData.attendanceTime != null
                ? Text(
                    'Приход: ${dayData.attendanceTime!.hour.toString().padLeft(2, '0')}:${dayData.attendanceTime!.minute.toString().padLeft(2, '0')}')
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  dayData.hasShift ? Icons.check : Icons.close,
                  color: dayData.hasShift ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Icon(
                  dayData.hasRecount ? Icons.check : Icons.close,
                  color: dayData.hasRecount ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Icon(
                  dayData.hasRKO ? Icons.check : Icons.close,
                  color: dayData.hasRKO ? Colors.green : Colors.red,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Янв',
      'Фев',
      'Мар',
      'Апр',
      'Май',
      'Июн',
      'Июл',
      'Авг',
      'Сен',
      'Окт',
      'Ноя',
      'Дек'
    ];
    return months[month - 1];
  }
}

