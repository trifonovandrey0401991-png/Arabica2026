import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import '../models/test_result_model.dart';
import '../services/test_result_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница отчёта по тестированию
class TestReportPage extends StatefulWidget {
  const TestReportPage({super.key});

  @override
  State<TestReportPage> createState() => _TestReportPageState();
}

class _TestReportPageState extends State<TestReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<TestResult> _allResults = [];
  bool _isLoading = true;

  static final Color _goldLight = Color(0xFFE8C860);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadResults();
    ReportNotificationService.markAllAsViewed(reportType: ReportType.test);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadResults() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final allResults = await TestResultService.getResults();
      // Фильтрация по мультитенантности — управляющий видит только свои магазины
      final results = await MultitenancyFilterService.filterByShopAddress(
        allResults,
        (result) => result.shopAddress ?? '',
      );
      setState(() {
        _allResults = results;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки результатов', e);
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        );
      }
    }
  }

  /// Группировка по сотрудникам с расчётом статистики
  Map<String, EmployeeStats> _getEmployeeStats() {
    final Map<String, List<TestResult>> byEmployee = {};

    for (final result in _allResults) {
      final key = result.employeeName;
      byEmployee.putIfAbsent(key, () => []);
      byEmployee[key]!.add(result);
    }

    final Map<String, EmployeeStats> stats = {};
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = thisMonth.subtract(Duration(days: 1));

    for (final entry in byEmployee.entries) {
      final employeeName = entry.key;
      final results = entry.value;

      final thisMonthResults = results.where((r) =>
          r.completedAt.isAfter(thisMonth) ||
          (r.completedAt.year == thisMonth.year &&
              r.completedAt.month == thisMonth.month &&
              r.completedAt.day == thisMonth.day));

      final lastMonthResults = results.where((r) =>
          r.completedAt.isAfter(lastMonthStart) &&
          (r.completedAt.isBefore(thisMonth) ||
              (r.completedAt.year == lastMonthEnd.year &&
                  r.completedAt.month == lastMonthEnd.month &&
                  r.completedAt.day == lastMonthEnd.day)));

      double avgThisMonth = 0;
      double avgLastMonth = 0;
      double avgTotal = 0;

      if (thisMonthResults.isNotEmpty) {
        avgThisMonth =
            thisMonthResults.map((r) => r.score).reduce((a, b) => a + b) /
                thisMonthResults.length;
      }

      if (lastMonthResults.isNotEmpty) {
        avgLastMonth =
            lastMonthResults.map((r) => r.score).reduce((a, b) => a + b) /
                lastMonthResults.length;
      }

      if (results.isNotEmpty) {
        avgTotal =
            results.map((r) => r.score).reduce((a, b) => a + b) / results.length;
      }

      TestResult? lastTest;
      if (results.isNotEmpty) {
        final sortedResults = results.toList()
          ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
        lastTest = sortedResults.first;
      }

      stats[employeeName] = EmployeeStats(
        employeeName: employeeName,
        avgThisMonth: avgThisMonth,
        avgLastMonth: avgLastMonth,
        avgTotal: avgTotal,
        totalTests: results.length,
        lastTest: lastTest,
      );
    }

    return stats;
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
              // AppBar
              _buildAppBar(),
              // Табы
              _buildTabs(),
              // Контент
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildStatsTab(),
                          _buildAllResultsTab(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Отчёт тестирования',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.7), size: 22),
              onPressed: _loadResults,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppColors.gold.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.gold.withOpacity(0.4)),
        ),
        indicatorPadding: EdgeInsets.all(3.w),
        labelColor: _goldLight,
        unselectedLabelColor: Colors.white.withOpacity(0.4),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13.sp,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 13.sp,
        ),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(text: 'По сотрудникам'),
          Tab(text: 'Все результаты'),
        ],
      ),
    );
  }

  // ─────────── ВКЛАДКА СТАТИСТИКИ ───────────

  Widget _buildStatsTab() {
    final stats = _getEmployeeStats();

    if (stats.isEmpty) {
      return _buildEmptyState('Нет данных о тестировании', Icons.quiz_rounded);
    }

    final sortedStats = stats.values.toList()
      ..sort((a, b) => b.avgThisMonth.compareTo(a.avgThisMonth));

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 20.h),
      itemCount: sortedStats.length,
      itemBuilder: (context, index) {
        final stat = sortedStats[index];
        return _buildEmployeeCard(stat, index);
      },
    );
  }

  Widget _buildEmployeeCard(EmployeeStats stat, int index) {
    final scoreColor = _getScoreColor(stat.avgThisMonth);

    return GestureDetector(
      onTap: () => _showEmployeeDetails(stat),
      child: Container(
        margin: EdgeInsets.only(bottom: 10.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            // Аватар с баллом
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(color: scoreColor.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  stat.avgThisMonth > 0 ? stat.avgThisMonth.toStringAsFixed(0) : '-',
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                    color: scoreColor,
                  ),
                ),
              ),
            ),
            SizedBox(width: 14),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.employeeName,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      _buildMiniStat('Месяц', stat.avgThisMonth, AppColors.gold),
                      SizedBox(width: 16),
                      _buildMiniStat('Всего', stat.avgTotal, Colors.white.withOpacity(0.5)),
                    ],
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Тестов: ${stat.totalTests}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.25),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, double value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12.sp,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
        Text(
          value > 0 ? value.toStringAsFixed(1) : '-',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  /// Показать детали сотрудника
  void _showEmployeeDetails(EmployeeStats stat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppColors.emeraldDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: EdgeInsets.all(22.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ручка
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                        ),
                      ),
                      SizedBox(height: 22),

                      // Имя сотрудника
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.gold.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(16.r),
                              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                            ),
                            child: Icon(Icons.person_rounded, size: 28, color: AppColors.gold),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stat.employeeName,
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Всего тестов: ${stat.totalTests}',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 24),

                      // Заголовок статистики
                      Text(
                        'Статистика',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.gold.withOpacity(0.8),
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 12),

                      // Три карточки статистики
                      _buildStatCard(
                        'Средний балл за месяц',
                        stat.avgThisMonth,
                        AppColors.gold,
                        Icons.calendar_month_rounded,
                      ),
                      SizedBox(height: 8),
                      _buildStatCard(
                        'Прошлый месяц',
                        stat.avgLastMonth,
                        Colors.orange,
                        Icons.history_rounded,
                      ),
                      SizedBox(height: 8),
                      _buildStatCard(
                        'Общий средний балл',
                        stat.avgTotal,
                        AppColors.success,
                        Icons.bar_chart_rounded,
                      ),

                      // Последний тест
                      if (stat.lastTest != null) ...[
                        SizedBox(height: 24),
                        Text(
                          'Последний тест',
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.gold.withOpacity(0.8),
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 12),
                        _buildLastTestCard(stat.lastTest!),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatCard(String label, double value, Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color.withOpacity(0.7)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ),
          Text(
            value > 0 ? value.toStringAsFixed(1) : '-',
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: value > 0 ? color : Colors.white.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastTestCard(TestResult test) {
    final scoreColor = _getScoreColor(test.percentage.toDouble());

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white.withOpacity(0.4)),
              SizedBox(width: 8),
              Text(
                _formatDate(test.completedAt),
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildLastTestStat('Результат', '${test.score}/${test.totalQuestions}', scoreColor),
              ),
              Expanded(
                child: _buildLastTestStat('Процент', '${test.percentage}%', scoreColor),
              ),
              Expanded(
                child: _buildLastTestStat('Время', test.formattedTime, Colors.white.withOpacity(0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLastTestStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.sp,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  // ─────────── ВКЛАДКА ВСЕ РЕЗУЛЬТАТЫ ───────────

  Widget _buildAllResultsTab() {
    if (_allResults.isEmpty) {
      return _buildEmptyState('Нет результатов тестирования', Icons.assignment_rounded);
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 20.h),
      itemCount: _allResults.length,
      itemBuilder: (context, index) {
        final result = _allResults[index];
        return _buildResultCard(result);
      },
    );
  }

  Widget _buildResultCard(TestResult result) {
    final percentage = result.percentage;
    final scoreColor = _getScoreColor(percentage.toDouble());

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          // Аватар-балл
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scoreColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: scoreColor.withOpacity(0.3)),
            ),
            child: Center(
              child: Text(
                '${result.score}',
                style: TextStyle(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w700,
                  color: scoreColor,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          // Имя и дата
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.employeeName,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  _formatDate(result.completedAt),
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.white.withOpacity(0.35),
                  ),
                ),
              ],
            ),
          ),
          // Результат
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${result.score}/${result.totalQuestions}',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  color: scoreColor,
                ),
              ),
              SizedBox(height: 2),
              Text(
                result.formattedTime,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.white.withOpacity(0.35),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────── ОБЩИЕ ВИДЖЕТЫ ───────────

  Widget _buildEmptyState(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(
              icon,
              size: 30,
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          SizedBox(height: 18),
          Text(
            text,
            style: TextStyle(
              fontSize: 15.sp,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return AppColors.success;
    if (score >= 60) return Colors.orange;
    if (score > 0) return Color(0xFFEF5350);
    return Colors.white.withOpacity(0.3);
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }
}

/// Модель статистики сотрудника
class EmployeeStats {
  final String employeeName;
  final double avgThisMonth;
  final double avgLastMonth;
  final double avgTotal;
  final int totalTests;
  final TestResult? lastTest;

  EmployeeStats({
    required this.employeeName,
    required this.avgThisMonth,
    required this.avgLastMonth,
    required this.avgTotal,
    required this.totalTests,
    this.lastTest,
  });
}
