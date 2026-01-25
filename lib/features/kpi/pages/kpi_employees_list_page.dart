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

  // Отслеживание загружаемых сотрудников (для предотвращения дублирования)
  final Set<String> _loadingEmployees = {};

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);

    try {
      final employees = await KPIService.getAllEmployees();

      if (mounted) {
        setState(() {
          _employees = employees;
          _isLoading = false;
        });

        // Ленивая загрузка: предзагружаем только первые 10 видимых сотрудников
        final preloadCount = employees.length > 10 ? 10 : employees.length;
        for (var i = 0; i < preloadCount; i++) {
          _loadMonthlyStats(employees[i]);
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
          _loadingEmployees.remove(employeeName);
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки месячной статистики', e);
      if (mounted) {
        _loadingEmployees.remove(employeeName);
      }
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
          // Индикатор графика (если есть данные из графика)
          if (stats.hasScheduleData) ...[
            _buildScheduleBadge(stats),
            const SizedBox(width: 6),
          ],
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

  /// Бейдж с информацией о графике (опоздания и пропуски)
  Widget _buildScheduleBadge(KPIEmployeeMonthStats stats) {
    final hasProblems = stats.lateArrivals > 0 || stats.missedDays > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: hasProblems ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasProblems ? Colors.red.shade200 : Colors.green.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Опоздания
          if (stats.lateArrivals > 0) ...[
            Icon(Icons.schedule, size: 10, color: Colors.orange.shade700),
            const SizedBox(width: 2),
            Text(
              '${stats.lateArrivals}',
              style: TextStyle(fontSize: 8, color: Colors.orange.shade700, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
          ],
          // Пропуски
          if (stats.missedDays > 0) ...[
            Icon(Icons.event_busy, size: 10, color: Colors.red.shade700),
            const SizedBox(width: 2),
            Text(
              '${stats.missedDays}',
              style: TextStyle(fontSize: 8, color: Colors.red.shade700, fontWeight: FontWeight.bold),
            ),
          ],
          // Если нет проблем - показываем галочку
          if (!hasProblems)
            Icon(Icons.check_circle, size: 12, color: Colors.green.shade700),
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
      margin: const EdgeInsets.only(left: 40, right: 8, top: 2, bottom: 2),
      color: Colors.grey[100],
      child: InkWell(
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
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              _buildMonthIndicators(stats),
            ],
          ),
        ),
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

                          // Ленивая загрузка: загружаем статистику когда элемент становится видимым
                          if (monthlyStats == null && !_loadingEmployees.contains(employee)) {
                            _loadingEmployees.add(employee);
                            _loadMonthlyStats(employee);
                          }

                          return Column(
                            children: [
                              // Главная строка сотрудника
                              Card(
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                child: InkWell(
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
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    child: Row(
                                      children: [
                                        // Аватар
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: const Color(0xFF004D40),
                                          child: Text(
                                            employee.isNotEmpty
                                                ? employee[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // ФИО и показатели
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // ФИО в одну строку
                                              Text(
                                                employee,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              // Показатели под ФИО
                                              monthlyStats != null && monthlyStats.isNotEmpty
                                                  ? _buildMonthIndicators(monthlyStats[0])
                                                  : const SizedBox(
                                                      width: 16,
                                                      height: 16,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    ),
                                            ],
                                          ),
                                        ),
                                        // Стрелка раскрытия
                                        Icon(
                                          isExpanded ? Icons.expand_less : Icons.expand_more,
                                          color: Colors.grey[600],
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
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







