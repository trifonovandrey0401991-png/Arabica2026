import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/report_notification_service.dart';
import '../models/test_result_model.dart';
import '../services/test_result_service.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadResults();
    // Отмечаем все уведомления этого типа как просмотренные
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
      final results = await TestResultService.getResults();
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
    final lastMonthEnd = thisMonth.subtract(const Duration(days: 1));

    for (final entry in byEmployee.entries) {
      final employeeName = entry.key;
      final results = entry.value;

      // Результаты за текущий месяц
      final thisMonthResults = results.where((r) =>
          r.completedAt.isAfter(thisMonth) ||
          (r.completedAt.year == thisMonth.year &&
              r.completedAt.month == thisMonth.month &&
              r.completedAt.day == thisMonth.day));

      // Результаты за прошлый месяц
      final lastMonthResults = results.where((r) =>
          r.completedAt.isAfter(lastMonthStart) &&
          (r.completedAt.isBefore(thisMonth) ||
              (r.completedAt.year == lastMonthEnd.year &&
                  r.completedAt.month == lastMonthEnd.month &&
                  r.completedAt.day == lastMonthEnd.day)));

      // Расчёт средних значений
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

      // Находим последний пройденный тест
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
      appBar: AppBar(
        title: const Text('Отчет (Тестирование)'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadResults,
            tooltip: 'Обновить',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Оценка тестирования'),
            Tab(text: 'Все'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStatsTab(),
                _buildAllResultsTab(),
              ],
            ),
    );
  }

  /// Вкладка "Оценка тестирования" - статистика по сотрудникам
  Widget _buildStatsTab() {
    final stats = _getEmployeeStats();

    if (stats.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Нет данных о тестировании',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final sortedStats = stats.values.toList()
      ..sort((a, b) => b.avgThisMonth.compareTo(a.avgThisMonth));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedStats.length,
      itemBuilder: (context, index) {
        final stat = sortedStats[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _showEmployeeDetails(stat),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Аватар с баллами за месяц
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _getScoreColor(stat.avgThisMonth).withOpacity(0.2),
                    child: Text(
                      stat.avgThisMonth > 0 ? stat.avgThisMonth.toStringAsFixed(0) : '-',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _getScoreColor(stat.avgThisMonth),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Информация о сотруднике
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stat.employeeName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Средний балл за месяц: ${stat.avgThisMonth > 0 ? stat.avgThisMonth.toStringAsFixed(1) : "-"}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          'Общий средний балл: ${stat.avgTotal > 0 ? stat.avgTotal.toStringAsFixed(1) : "-"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[600],
                          ),
                        ),
                        Text(
                          'Тестов пройдено: ${stat.totalTests}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Стрелка
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey[400],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Показать детали сотрудника
  void _showEmployeeDetails(EmployeeStats stat) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Заголовок
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Имя сотрудника
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: const Color(0xFF004D40).withOpacity(0.1),
                          child: const Icon(Icons.person, size: 32, color: Color(0xFF004D40)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stat.employeeName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Всего тестов: ${stat.totalTests}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Статистика по месяцам
                    const Text(
                      'Статистика',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Текущий месяц
                    _buildStatRow(
                      'Средний балл за текущий месяц',
                      stat.avgThisMonth,
                      Colors.blue,
                    ),
                    const SizedBox(height: 8),

                    // Прошлый месяц
                    _buildStatRow(
                      'Средний балл за прошлый месяц',
                      stat.avgLastMonth,
                      Colors.orange,
                    ),
                    const SizedBox(height: 8),

                    // Всего
                    _buildStatRow(
                      'Общий средний балл',
                      stat.avgTotal,
                      Colors.green,
                    ),

                    const SizedBox(height: 24),

                    // Последний тест
                    if (stat.lastTest != null) ...[
                      const Text(
                        'Последний пройденный тест',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDate(stat.lastTest!.completedAt),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Результат',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    Text(
                                      '${stat.lastTest!.score}/${stat.lastTest!.totalQuestions}',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: _getScoreColor(stat.lastTest!.percentage.toDouble()),
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text(
                                      'Процент',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    Text(
                                      '${stat.lastTest!.percentage}%',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: _getScoreColor(stat.lastTest!.percentage.toDouble()),
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text(
                                      'Время',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    Text(
                                      stat.lastTest!.formattedTime,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatRow(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14),
          ),
          Text(
            value > 0 ? value.toStringAsFixed(1) : '-',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: value > 0 ? color : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    if (score > 0) return Colors.red;
    return Colors.grey;
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  /// Вкладка "Все" - все результаты тестов
  Widget _buildAllResultsTab() {
    if (_allResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Нет результатов тестирования',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allResults.length,
      itemBuilder: (context, index) {
        final result = _allResults[index];
        final formattedDate = _formatDate(result.completedAt);
        final percentage = result.percentage;

        Color scoreColor;
        if (percentage >= 80) {
          scoreColor = Colors.green;
        } else if (percentage >= 60) {
          scoreColor = Colors.orange;
        } else {
          scoreColor = Colors.red;
        }

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: scoreColor.withOpacity(0.2),
              child: Text(
                '${result.score}',
                style: TextStyle(
                  color: scoreColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              result.employeeName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              formattedDate,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${result.score}/${result.totalQuestions}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                  ),
                ),
                Text(
                  result.formattedTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Модель статистики сотрудника
class EmployeeStats {
  final String employeeName;
  final double avgThisMonth;
  final double avgLastMonth;
  final double avgTotal;
  final int totalTests;
  final TestResult? lastTest; // Последний пройденный тест

  EmployeeStats({
    required this.employeeName,
    required this.avgThisMonth,
    required this.avgLastMonth,
    required this.avgTotal,
    required this.totalTests,
    this.lastTest,
  });
}
