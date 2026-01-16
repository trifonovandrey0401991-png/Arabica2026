import 'package:flutter/material.dart';
import '../services/kpi_service.dart';
import '../models/kpi_employee_month_stats.dart';
import 'kpi_employee_detail_page.dart';
import '../../../core/utils/logger.dart';

/// Страница списка всех сотрудников для KPI
class KPIEmployeesListPage extends StatefulWidget {
  const KPIEmployeesListPage({super.key});

  @override
  State<KPIEmployeesListPage> createState() => _KPIEmployeesListPageState();
}

class _KPIEmployeesListPageState extends State<KPIEmployeesListPage> {
  List<String> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // Отслеживание раскрытых сотрудников
  final Set<String> _expandedEmployees = {};

  // Кэш месячной статистики
  final Map<String, List<KPIEmployeeMonthStats>> _monthlyStatsCache = {};

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);

    try {
      Logger.debug('Загрузка списка сотрудников для KPI...');
      final employees = await KPIService.getAllEmployees();
      Logger.debug('Загружено сотрудников: ${employees.length}');
      Logger.debug('Список: $employees');

      if (mounted) {
        setState(() {
          _employees = employees;
          _isLoading = false;
        });

        if (employees.isEmpty) {
          Logger.debug('⚠️ Список сотрудников пуст!');
        }

        // Предзагрузка статистики текущего месяца для всех сотрудников
        for (final employee in employees) {
          _loadMonthlyStats(employee);
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки списка сотрудников', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMonthlyStats(String employeeName) async {
    try {
      final stats = await KPIService.getEmployeeMonthlyStats(employeeName);
      if (mounted) {
        setState(() {
          _monthlyStatsCache[employeeName] = stats;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки месячной статистики', e);
    }
  }

  List<String> get _filteredEmployees {
    if (_searchQuery.isEmpty) {
      return _employees;
    }
    return _employees
        .where((employee) =>
            employee.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  Widget _buildMonthIndicators(KPIEmployeeMonthStats stats) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIndicatorWithFraction(
            Icons.access_time,
            stats.attendanceFraction,
            stats.attendancePercentage,
          ),
          const SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.handshake,
            stats.shiftsFraction,
            stats.shiftsPercentage,
          ),
          const SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.calculate,
            stats.recountsFraction,
            stats.recountsPercentage,
          ),
          const SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.description,
            stats.rkosFraction,
            stats.rkosPercentage,
          ),
          const SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.mail,
            stats.envelopesFraction,
            stats.envelopesPercentage,
          ),
          const SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.payments,
            stats.shiftHandoversFraction,
            stats.shiftHandoversPercentage,
          ),
        ],
      ),
    );
  }

  Widget _buildIndicatorWithFraction(IconData icon, String fraction, double percentage) {
    Color fractionColor;
    if (percentage >= 1.0) {
      fractionColor = Colors.green;
    } else if (percentage >= 0.5) {
      fractionColor = Colors.orange;
    } else {
      fractionColor = Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(height: 2),
          Text(
            fraction,
            style: TextStyle(
              fontSize: 9,
              color: fractionColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthRow(String employeeName, KPIEmployeeMonthStats stats, String label) {
    return Card(
      margin: const EdgeInsets.only(left: 32, right: 8, top: 4, bottom: 4),
      color: Colors.grey[100],
      child: ListTile(
        dense: true,
        title: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        trailing: _buildMonthIndicators(stats),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => KPIEmployeeDetailPage(
                employeeName: employeeName,
                year: stats.year,
                month: stats.month,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KPI - Сотрудники'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              KPIService.clearCache();
              _loadEmployees();
            },
            tooltip: 'Обновить список',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск сотрудника...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          _isLoading
              ? const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _filteredEmployees.isEmpty
                  ? Expanded(
                      child: Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'Нет сотрудников'
                              : 'Сотрудники не найдены',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    )
                  : Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _filteredEmployees.length,
                        itemBuilder: (context, index) {
                          final employee = _filteredEmployees[index];
                          final isExpanded = _expandedEmployees.contains(employee);
                          final monthlyStats = _monthlyStatsCache[employee];

                          return Column(
                            children: [
                              // Главная строка сотрудника
                              Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF004D40),
                                    child: Text(
                                      employee.isNotEmpty
                                          ? employee[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    employee,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  trailing: monthlyStats != null && monthlyStats.isNotEmpty
                                      ? _buildMonthIndicators(monthlyStats[0])
                                      : const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                  onTap: () {
                                    setState(() {
                                      if (isExpanded) {
                                        _expandedEmployees.remove(employee);
                                      } else {
                                        _expandedEmployees.add(employee);
                                        if (!_monthlyStatsCache.containsKey(employee)) {
                                          _loadMonthlyStats(employee);
                                        }
                                      }
                                    });
                                  },
                                ),
                              ),

                              // Раскрытые месячные строки
                              if (isExpanded && monthlyStats != null && monthlyStats.length >= 3) ...[
                                _buildMonthRow(employee, monthlyStats[1], 'Прошлый месяц'),
                                _buildMonthRow(employee, monthlyStats[2], 'Позапрошлый месяц'),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
        ],
      ),
    );
  }
}







