import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import '../widgets/task_common_widgets.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/models/user_role_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница аналитики по задачам за 3 месяца
class TaskAnalyticsPage extends StatefulWidget {
  const TaskAnalyticsPage({super.key});

  @override
  State<TaskAnalyticsPage> createState() => _TaskAnalyticsPageState();
}

class _TaskAnalyticsPageState extends State<TaskAnalyticsPage> {
  bool _isLoading = true;
  String? _error;

  // Данные за 3 месяца [старый, средний, новый]
  List<_MonthData> _monthsData = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final months = <Map<String, int>>[];

      // Собираем 3 месяца: позапрошлый, прошлый, текущий
      for (int i = 2; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        months.add({'year': date.year, 'month': date.month});
      }

      // Загружаем данные и роль параллельно
      final roleDataFuture = UserRoleService.loadUserRole();
      final results = await Future.wait(
        months.map((m) => TaskService.getAllAssignmentsCached(
          year: m['year']!,
          month: m['month']!,
        )),
      );
      final roleData = await roleDataFuture;

      // Фильтрация по мультитенантности — управляющий видит только задачи своих сотрудников
      Set<String>? allowedIds;
      if (roleData != null && roleData.role == UserRole.admin && roleData.managedEmployees.isNotEmpty) {
        final employees = await EmployeeService.getEmployees();
        final managedPhones = roleData.managedEmployees.map(
          (p) => p.replaceAll(RegExp(r'[\s\+]'), ''),
        ).toSet();
        allowedIds = <String>{};
        for (final emp in employees) {
          final phone = emp.phone?.replaceAll(RegExp(r'[\s\+]'), '') ?? '';
          if (phone.isNotEmpty && managedPhones.contains(phone)) {
            allowedIds.add(emp.id);
          }
        }
      }

      // Преобразуем в _MonthData
      final monthsData = <_MonthData>[];
      for (int i = 0; i < results.length; i++) {
        var assignments = results[i];
        final year = months[i]['year']!;
        final month = months[i]['month']!;

        // Применяем фильтр если нужно
        if (allowedIds != null) {
          assignments = assignments.where((a) => allowedIds!.contains(a.assigneeId)).toList();
        }

        monthsData.add(_MonthData(
          year: year,
          month: month,
          name: TaskUtils.getMonthName(month, year),
          shortName: _getShortMonthName(month),
          assignments: assignments,
        ));
      }

      if (!mounted) return;
      setState(() {
        _monthsData = monthsData;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка загрузки: $e';
        _isLoading = false;
      });
    }
  }

  String _getShortMonthName(int month) {
    final months = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
    return months[month - 1];
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
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10.r),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Аналитика задач',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadData,
                      child: Container(
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10.r),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.gold),
            SizedBox(height: 16),
            Text(
              'Загрузка аналитики...',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: Colors.white,
              ),
              child: Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_monthsData.isEmpty) {
      return TaskEmptyState(
        message: 'Нет данных',
        subtitle: 'Данные по задачам не найдены',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryChart(),
            SizedBox(height: 16),
            _buildCompletionRateChart(),
            SizedBox(height: 16),
            _buildMonthsTable(),
            SizedBox(height: 16),
            _buildStatusBreakdown(),
          ],
        ),
      ),
    );
  }

  /// График количества задач по месяцам
  Widget _buildSummaryChart() {
    final spots = <FlSpot>[];
    final approvedSpots = <FlSpot>[];

    for (int i = 0; i < _monthsData.length; i++) {
      final data = _monthsData[i];
      spots.add(FlSpot(i.toDouble(), data.total.toDouble()));
      approvedSpots.add(FlSpot(i.toDouble(), data.approved.toDouble()));
    }

    final maxY = _monthsData.map((d) => d.total).reduce((a, b) => a > b ? a : b).toDouble();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Динамика задач',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                _buildLegendItem('Всего', AppColors.gold),
                SizedBox(width: 16),
                _buildLegendItem('Выполнено', AppColors.emerald),
              ],
            ),
            SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Colors.white.withOpacity(0.1),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5)),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < _monthsData.length) {
                            return Padding(
                              padding: EdgeInsets.only(top: 8.h),
                              child: Text(
                                _monthsData[index].shortName,
                                style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5)),
                              ),
                            );
                          }
                          return SizedBox();
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: 2,
                  minY: 0,
                  maxY: maxY > 0 ? maxY * 1.1 : 10,
                  lineBarsData: [
                    // Линия "Всего"
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: AppColors.gold,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.gold.withOpacity(0.15),
                      ),
                    ),
                    // Линия "Выполнено"
                    LineChartBarData(
                      spots: approvedSpots,
                      isCurved: true,
                      color: AppColors.emerald,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.emerald.withOpacity(0.15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2.r),
          ),
        ),
        SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.6))),
      ],
    );
  }

  /// График процента выполнения
  Widget _buildCompletionRateChart() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Процент выполнения',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
              ),
            ),
            SizedBox(height: 16),
            ..._monthsData.map((data) {
              final rate = data.completionRate;
              final color = rate >= 80 ? Colors.green : (rate >= 50 ? Colors.orange : Colors.red);

              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          data.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        Text(
                          '${rate.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4.r),
                      child: LinearProgressIndicator(
                        value: rate / 100,
                        backgroundColor: Colors.white.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Таблица по месяцам
  Widget _buildMonthsTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Сравнение по месяцам',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
              ),
            ),
            SizedBox(height: 12),
            Table(
              columnWidths: {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8.w),
                      child: Text('Месяц', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp, color: Colors.white.withOpacity(0.9))),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8.w),
                      child: Text('Всего', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp, color: Colors.white.withOpacity(0.9)), textAlign: TextAlign.center),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8.w),
                      child: Text('Выполн.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp, color: Colors.white.withOpacity(0.9)), textAlign: TextAlign.center),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8.w),
                      child: Text('Просроч.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.sp, color: Colors.white.withOpacity(0.9)), textAlign: TextAlign.center),
                    ),
                  ],
                ),
                ..._monthsData.reversed.map((data) => TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8.w),
                      child: Text(data.shortName, style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.9))),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8.w),
                      child: Text(data.total.toString(), textAlign: TextAlign.center, style: TextStyle(fontSize: 13.sp, color: Colors.white.withOpacity(0.9))),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8.w),
                      child: Text(
                        data.approved.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.sp, color: Colors.green, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8.w),
                      child: Text(
                        data.expired.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.sp, color: data.expired > 0 ? Colors.red[300] : Colors.white.withOpacity(0.3), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Разбивка по статусам за текущий месяц
  Widget _buildStatusBreakdown() {
    if (_monthsData.isEmpty) return SizedBox();

    final currentMonth = _monthsData.last;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Статусы за ${currentMonth.name}',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
              ),
            ),
            SizedBox(height: 12),
            _buildStatusRow('Ожидают', currentMonth.pending, TaskStyles.orangeGradient[0]),
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            _buildStatusRow('На проверке', currentMonth.submitted, TaskStyles.blueGradient[0]),
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            _buildStatusRow('Выполнено', currentMonth.approved, TaskStyles.greenGradient[0]),
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            _buildStatusRow('Отклонено', currentMonth.rejected, Colors.red),
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            _buildStatusRow('Просрочено', currentMonth.expired, Colors.grey),
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            _buildStatusRow('Отказ', currentMonth.declined, Colors.deepOrange),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, int count, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3.r),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
          ),
          Text(
            count.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: count > 0 ? color : Colors.white.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Данные за один месяц
class _MonthData {
  final int year;
  final int month;
  final String name;
  final String shortName;
  final List<TaskAssignment> assignments;

  _MonthData({
    required this.year,
    required this.month,
    required this.name,
    required this.shortName,
    required this.assignments,
  });

  int get total => assignments.length;
  int get pending => assignments.where((a) => a.status == TaskStatus.pending).length;
  int get submitted => assignments.where((a) => a.status == TaskStatus.submitted).length;
  int get approved => assignments.where((a) => a.status == TaskStatus.approved).length;
  int get rejected => assignments.where((a) => a.status == TaskStatus.rejected).length;
  int get expired => assignments.where((a) => a.status == TaskStatus.expired).length;
  int get declined => assignments.where((a) => a.status == TaskStatus.declined).length;

  double get completionRate {
    if (total == 0) return 0;
    return (approved / total) * 100;
  }
}
