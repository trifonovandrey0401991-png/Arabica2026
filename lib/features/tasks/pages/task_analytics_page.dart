import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import '../widgets/task_common_widgets.dart';

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
    setState(() {
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

      // Загружаем данные параллельно
      final results = await Future.wait(
        months.map((m) => TaskService.getAllAssignmentsCached(
          year: m['year']!,
          month: m['month']!,
        )),
      );

      // Преобразуем в _MonthData
      final monthsData = <_MonthData>[];
      for (int i = 0; i < results.length; i++) {
        final assignments = results[i];
        final year = months[i]['year']!;
        final month = months[i]['month']!;

        monthsData.add(_MonthData(
          year: year,
          month: month,
          name: TaskUtils.getMonthName(month, year),
          shortName: _getShortMonthName(month),
          assignments: assignments,
        ));
      }

      setState(() {
        _monthsData = monthsData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки: $e';
        _isLoading = false;
      });
    }
  }

  String _getShortMonthName(int month) {
    const months = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Аналитика задач'),
        backgroundColor: TaskStyles.primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: TaskStyles.primaryColor),
            SizedBox(height: 16),
            Text('Загрузка аналитики...'),
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
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_monthsData.isEmpty) {
      return const TaskEmptyState(
        message: 'Нет данных',
        subtitle: 'Данные по задачам не найдены',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryChart(),
            const SizedBox(height: 16),
            _buildCompletionRateChart(),
            const SizedBox(height: 16),
            _buildMonthsTable(),
            const SizedBox(height: 16),
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

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Динамика задач',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: TaskStyles.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildLegendItem('Всего', Colors.blue),
                const SizedBox(width: 16),
                _buildLegendItem('Выполнено', Colors.green),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _monthsData[index].shortName,
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withOpacity(0.1),
                      ),
                    ),
                    // Линия "Выполнено"
                    LineChartBarData(
                      spots: approvedSpots,
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.green.withOpacity(0.1),
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
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  /// График процента выполнения
  Widget _buildCompletionRateChart() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Процент выполнения',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: TaskStyles.primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            ..._monthsData.map((data) {
              final rate = data.completionRate;
              final color = rate >= 80 ? Colors.green : (rate >= 50 ? Colors.orange : Colors.red);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(data.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text(
                          '${rate.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: rate / 100,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(color),
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
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Сравнение по месяцам',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: TaskStyles.primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey[100]),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Месяц', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Всего', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Выполн.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('Просроч.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
                    ),
                  ],
                ),
                ..._monthsData.reversed.map((data) => TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(data.shortName, style: const TextStyle(fontSize: 13)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(data.total.toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        data.approved.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.green[700], fontWeight: FontWeight.w500),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        data.expired.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: data.expired > 0 ? Colors.red[700] : Colors.grey, fontWeight: FontWeight.w500),
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
    if (_monthsData.isEmpty) return const SizedBox();

    final currentMonth = _monthsData.last;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Статусы за ${currentMonth.name}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: TaskStyles.primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatusRow('Ожидают', currentMonth.pending, TaskStyles.orangeGradient[0]),
            _buildStatusRow('На проверке', currentMonth.submitted, TaskStyles.blueGradient[0]),
            _buildStatusRow('Выполнено', currentMonth.approved, TaskStyles.greenGradient[0]),
            _buildStatusRow('Отклонено', currentMonth.rejected, Colors.red),
            _buildStatusRow('Просрочено', currentMonth.expired, Colors.grey),
            _buildStatusRow('Отказ', currentMonth.declined, Colors.deepOrange),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            count.toString(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: count > 0 ? color : Colors.grey,
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
