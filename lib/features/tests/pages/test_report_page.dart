import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
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

      stats[employeeName] = EmployeeStats(
        employeeName: employeeName,
        avgThisMonth: avgThisMonth,
        avgLastMonth: avgLastMonth,
        avgTotal: avgTotal,
        totalTests: results.length,
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
      ..sort((a, b) => b.avgTotal.compareTo(a.avgTotal));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedStats.length,
      itemBuilder: (context, index) {
        final stat = sortedStats[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, color: Color(0xFF004D40)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stat.employeeName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${stat.totalTests} тест.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn(
                      'Месяц',
                      stat.avgThisMonth,
                      Colors.blue,
                    ),
                    _buildStatColumn(
                      'Пр. месяц',
                      stat.avgLastMonth,
                      Colors.orange,
                    ),
                    _buildStatColumn(
                      'Итого',
                      stat.avgTotal,
                      Colors.green,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatColumn(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value > 0 ? value.toStringAsFixed(1) : '-',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: value > 0 ? color : Colors.grey,
          ),
        ),
      ],
    );
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

  EmployeeStats({
    required this.employeeName,
    required this.avgThisMonth,
    required this.avgLastMonth,
    required this.avgTotal,
    required this.totalTests,
  });
}
