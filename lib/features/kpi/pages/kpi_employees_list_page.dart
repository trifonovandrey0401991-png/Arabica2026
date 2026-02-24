import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../services/kpi_service.dart';
import '../models/kpi_employee_month_stats.dart';
import 'kpi_employee_detail_page.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

  static const _cacheKey = 'kpi_employees_list';

  Future<void> _loadEmployees() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _employees = cached['employees'] as List<String>;
        _monthlyStatsCache.addAll(
          (cached['stats'] as Map<String, List<KPIEmployeeMonthStats>>),
        );
        _isLoading = false;
      });
    }

    if (_employees.isEmpty && mounted) setState(() => _isLoading = true);

    try {
      // Step 2: Fetch fresh data from server
      final employees = await KPIService.getAllEmployees();

      if (mounted) {
        setState(() {
          _employees = employees;
          _isLoading = false;
        });

        // Загружаем статистику сотрудников ПОСЛЕДОВАТЕЛЬНО (по одному)
        // чтобы не перегружать сервер (каждый сотрудник = 6-9 API вызовов)
        for (var i = 0; i < employees.length; i++) {
          if (!mounted) break;
          await _loadMonthlyStats(employees[i]);
        }

        // Step 3: Save to cache (after all stats loaded)
        if (mounted) {
          CacheManager.set(_cacheKey, {
            'employees': employees,
            'stats': Map<String, List<KPIEmployeeMonthStats>>.from(_monthlyStatsCache),
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки списка сотрудников', e);
      if (mounted && _employees.isEmpty) {
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
            SizedBox(width: 6),
          ],
          _buildIndicatorWithFraction(
            Icons.access_time,
            stats.attendanceFraction,
            stats.attendancePercentage,
          ),
          SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.handshake,
            stats.shiftsFraction,
            stats.shiftsPercentage,
          ),
          SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.calculate,
            stats.recountsFraction,
            stats.recountsPercentage,
          ),
          SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.description,
            stats.rkosFraction,
            stats.rkosPercentage,
          ),
          SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.mail,
            stats.envelopesFraction,
            stats.envelopesPercentage,
          ),
          SizedBox(width: 4),
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
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: hasProblems ? Colors.red.withOpacity(0.15) : Colors.green.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(
          color: hasProblems ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Опоздания
          if (stats.lateArrivals > 0) ...[
            Icon(Icons.schedule, size: 10, color: Colors.orange.shade700),
            SizedBox(width: 2),
            Text(
              '${stats.lateArrivals}',
              style: TextStyle(fontSize: 8.sp, color: Colors.orange.shade700, fontWeight: FontWeight.bold),
            ),
            SizedBox(width: 4),
          ],
          // Пропуски
          if (stats.missedDays > 0) ...[
            Icon(Icons.event_busy, size: 10, color: Colors.red.shade700),
            SizedBox(width: 2),
            Text(
              '${stats.missedDays}',
              style: TextStyle(fontSize: 8.sp, color: Colors.red.shade700, fontWeight: FontWeight.bold),
            ),
          ],
          // Если нет проблем - показываем галочку
          if (!hasProblems)
            Icon(Icons.check_circle, size: 12, color: Colors.green.shade700),
        ],
      ),
    );
  }

  Widget _buildOverallPercentageBadge(double percentage) {
    final percent = (percentage * 100).clamp(0, 100).round();
    Color bgColor;
    Color textColor;
    if (percentage >= 0.8) {
      bgColor = Colors.green.withOpacity(0.2);
      textColor = Colors.green;
    } else if (percentage >= 0.5) {
      bgColor = Colors.orange.withOpacity(0.2);
      textColor = Colors.orange;
    } else {
      bgColor = Colors.red.withOpacity(0.2);
      textColor = Colors.red;
    }

    return Container(
      margin: EdgeInsets.only(left: 6.w),
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        '$percent%',
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
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
      padding: EdgeInsets.symmetric(horizontal: 2.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withOpacity(0.5)),
          SizedBox(height: 2),
          Text(
            fraction,
            style: TextStyle(
              fontSize: 9.sp,
              color: fractionColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthRow(String employeeName, KPIEmployeeMonthStats stats, String label) {
    return Container(
      margin: EdgeInsets.only(left: 40.w, right: 8.w, top: 2.h, bottom: 2.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
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
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.7)),
                    ),
                  ),
                  _buildOverallPercentageBadge(stats.overallPercentage),
                ],
              ),
              SizedBox(height: 2),
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
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'KPI - Сотрудники',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        KPIService.clearCache();
                        _loadEmployees();
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              // Search
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0.w),
                child: TextField(
                  style: TextStyle(color: Colors.white),
                  cursorColor: AppColors.gold,
                  decoration: InputDecoration(
                    hintText: 'Поиск сотрудника...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    prefixIcon: Icon(Icons.search, color: AppColors.gold),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    if (mounted) setState(() => _searchQuery = value);
                  },
                ),
              ),
              SizedBox(height: 8),
              // Content
              _isLoading
                  ? Expanded(
                      child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
                    )
                  : _filteredEmployees.isEmpty
                      ? Expanded(
                          child: Center(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'Нет сотрудников'
                                  : 'Сотрудники не найдены',
                              style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.5)),
                            ),
                          ),
                        )
                      : Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.symmetric(horizontal: 8.w),
                            itemCount: _filteredEmployees.length,
                            itemBuilder: (context, index) {
                              final employee = _filteredEmployees[index];
                              final isExpanded = _expandedEmployees.contains(employee);
                              final monthlyStats = _monthlyStatsCache[employee];

                              return Column(
                                children: [
                                  // Главная строка сотрудника
                                  Container(
                                    margin: EdgeInsets.symmetric(vertical: 2.h),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(14.r),
                                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                                    ),
                                    child: InkWell(
                                      onTap: () {
                                        if (mounted) setState(() {
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
                                      borderRadius: BorderRadius.circular(14.r),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                                        child: Row(
                                          children: [
                                            // Аватар
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: AppColors.emerald,
                                              child: Text(
                                                employee.isNotEmpty
                                                    ? employee[0].toUpperCase()
                                                    : '?',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12.sp,
                                                ),
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            // ФИО и показатели
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // ФИО в одну строку
                                                  Text(
                                                    employee,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 13.sp,
                                                      color: Colors.white.withOpacity(0.9),
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  SizedBox(height: 4),
                                                  // Показатели под ФИО
                                                  monthlyStats != null && monthlyStats.isNotEmpty
                                                      ? _buildMonthIndicators(monthlyStats[0])
                                                      : SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                                                        ),
                                                ],
                                              ),
                                            ),
                                            // Общий процент
                                            if (monthlyStats != null && monthlyStats.isNotEmpty)
                                              _buildOverallPercentageBadge(monthlyStats[0].overallPercentage),
                                            // Стрелка раскрытия
                                            Icon(
                                              isExpanded ? Icons.expand_less : Icons.expand_more,
                                              color: Colors.white.withOpacity(0.4),
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
        ),
      ),
    );
  }
}
