import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/efficiency_data_model.dart';
import '../services/efficiency_data_service.dart';

/// Страница аналитики эффективности за 3 месяца
class EfficiencyAnalyticsPage extends StatefulWidget {
  const EfficiencyAnalyticsPage({super.key});

  @override
  State<EfficiencyAnalyticsPage> createState() => _EfficiencyAnalyticsPageState();
}

class _EfficiencyAnalyticsPageState extends State<EfficiencyAnalyticsPage> {
  /// Режим отображения: 'shops' или 'employees'
  String _mode = 'shops';

  /// Данные за 3 месяца (от старого к новому)
  List<EfficiencyData> _monthsData = [];

  /// Состояние загрузки
  bool _isLoading = true;

  /// Ошибка загрузки
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Загрузить данные за последние 3 месяца
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();

      // Вычисляем год и месяц для каждого из 3 месяцев
      final months = <Map<String, int>>[];
      for (int i = 2; i >= 0; i--) {
        var year = now.year;
        var month = now.month - i;
        while (month <= 0) {
          month += 12;
          year--;
        }
        months.add({'year': year, 'month': month});
      }

      // Загружаем данные параллельно
      final data = await Future.wait(
        months.map((m) => EfficiencyDataService.loadMonthData(m['year']!, m['month']!)),
      );

      setState(() {
        _monthsData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Получить итого баллов для месяца
  double _getTotalForMonth(EfficiencyData data) {
    if (_mode == 'shops') {
      return data.byShop.fold(0.0, (sum, s) => sum + s.totalPoints);
    } else {
      return data.byEmployee.fold(0.0, (sum, s) => sum + s.totalPoints);
    }
  }

  /// Получить список сущностей (магазины или сотрудники)
  List<EfficiencySummary> _getEntities(EfficiencyData data) {
    return _mode == 'shops' ? data.byShop : data.byEmployee;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Аналитика'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) => setState(() => _mode = value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'shops',
                child: Row(
                  children: [
                    Icon(
                      Icons.store,
                      color: _mode == 'shops' ? const Color(0xFF004D40) : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'По магазинам',
                      style: TextStyle(
                        fontWeight: _mode == 'shops' ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'employees',
                child: Row(
                  children: [
                    Icon(
                      Icons.person,
                      color: _mode == 'employees' ? const Color(0xFF004D40) : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'По сотрудникам',
                      style: TextStyle(
                        fontWeight: _mode == 'employees' ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
            CircularProgressIndicator(color: Color(0xFF004D40)),
            SizedBox(height: 16),
            Text('Загрузка данных за 3 месяца...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Ошибка: $_error'),
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
      return const Center(child: Text('Нет данных'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildModeIndicator(),
            const SizedBox(height: 16),
            _buildSummaryChart(),
            const SizedBox(height: 24),
            _buildMonthsTable(),
            const SizedBox(height: 24),
            _buildEntitiesTrends(),
          ],
        ),
      ),
    );
  }

  /// Индикатор текущего режима
  Widget _buildModeIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _mode == 'shops' ? Icons.store : Icons.person,
            color: const Color(0xFF004D40),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            _mode == 'shops' ? 'По магазинам' : 'По сотрудникам',
            style: const TextStyle(
              color: Color(0xFF004D40),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// График динамики
  Widget _buildSummaryChart() {
    // Подготовка данных для графика
    final spots = <FlSpot>[];
    double minY = 0;
    double maxY = 0;

    for (int i = 0; i < _monthsData.length; i++) {
      final total = _getTotalForMonth(_monthsData[i]);
      spots.add(FlSpot(i.toDouble(), total));
      if (total < minY) minY = total;
      if (total > maxY) maxY = total;
    }

    // Добавляем отступы к min/max для лучшего отображения
    final range = maxY - minY;
    final padding = range * 0.1;
    minY -= padding;
    maxY += padding;

    // Если все значения одинаковые
    if (minY == maxY) {
      minY -= 100;
      maxY += 100;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Динамика эффективности',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (maxY - minY) / 4,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.shade200,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(0),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < _monthsData.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _getShortMonthName(_monthsData[index].periodStart),
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (_monthsData.length - 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      color: const Color(0xFF004D40),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 6,
                            color: Colors.white,
                            strokeWidth: 3,
                            strokeColor: const Color(0xFF004D40),
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF004D40).withOpacity(0.1),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (touchedSpot) => const Color(0xFF004D40),
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final index = spot.x.toInt();
                          final monthName = index < _monthsData.length
                              ? _monthsData[index].periodName
                              : '';
                          return LineTooltipItem(
                            '$monthName\n${spot.y.toStringAsFixed(1)} баллов',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Таблица по месяцам
  Widget _buildMonthsTable() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Сравнение по месяцам',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 16),
            // Заголовок таблицы
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(flex: 3, child: Text('Месяц', style: TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(flex: 2, child: Text('Итого', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                  Expanded(flex: 2, child: Text('Изменение', style: TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Строки таблицы (от нового к старому)
            for (int i = _monthsData.length - 1; i >= 0; i--)
              _buildMonthRow(i),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthRow(int index) {
    final data = _monthsData[index];
    final total = _getTotalForMonth(data);

    // Вычисляем изменение (сравниваем с предыдущим месяцем)
    double? change;
    if (index > 0) {
      final prevTotal = _getTotalForMonth(_monthsData[index - 1]);
      change = total - prevTotal;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              data.periodName,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatPoints(total),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: total >= 0 ? Colors.green.shade700 : Colors.red.shade700,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: change != null
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        change >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16,
                        color: change >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _formatPoints(change.abs()),
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: change >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ],
                  )
                : const Text('—', textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  /// Тренды по сущностям (магазинам/сотрудникам)
  Widget _buildEntitiesTrends() {
    if (_monthsData.length < 2) {
      return const SizedBox.shrink();
    }

    // Берём последний и предпоследний месяцы для сравнения
    final currentMonth = _monthsData.last;
    final previousMonth = _monthsData[_monthsData.length - 2];

    // Собираем все сущности из всех месяцев
    final allEntitiesMap = <String, EfficiencySummary>{};
    final previousMap = <String, double>{};

    // Сначала добавляем из предыдущего месяца
    for (final entity in _getEntities(previousMonth)) {
      previousMap[entity.entityId] = entity.totalPoints;
      allEntitiesMap[entity.entityId] = entity;
    }

    // Потом из текущего месяца (перезаписывает если есть)
    for (final entity in _getEntities(currentMonth)) {
      allEntitiesMap[entity.entityId] = entity;
    }

    // Также добавляем из первого месяца если есть
    if (_monthsData.length > 2) {
      for (final entity in _getEntities(_monthsData.first)) {
        if (!allEntitiesMap.containsKey(entity.entityId)) {
          allEntitiesMap[entity.entityId] = entity;
        }
      }
    }

    // Сортируем по изменению (улучшившиеся вверху)
    final sortedEntities = allEntitiesMap.values.toList()
      ..sort((a, b) {
        final changeA = a.totalPoints - (previousMap[a.entityId] ?? 0);
        final changeB = b.totalPoints - (previousMap[b.entityId] ?? 0);
        return changeB.compareTo(changeA);
      });

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _mode == 'shops' ? 'Динамика по магазинам' : 'Динамика по сотрудникам',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Сравнение: ${previousMonth.periodName} → ${currentMonth.periodName}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            if (sortedEntities.isEmpty)
              const Text('Нет данных')
            else
              for (final entity in sortedEntities)
                _buildEntityTrendRow(entity, previousMap[entity.entityId]),
          ],
        ),
      ),
    );
  }

  Widget _buildEntityTrendRow(EfficiencySummary entity, double? previousTotal) {
    final change = previousTotal != null ? entity.totalPoints - previousTotal : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // Имя сотрудника/магазина - гибкая ширина
          Expanded(
            flex: 3,
            child: Text(
              entity.entityName,
              style: const TextStyle(fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Текущие баллы - фиксированная ширина для выравнивания
          SizedBox(
            width: 65,
            child: Text(
              _formatPoints(entity.totalPoints),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: entity.totalPoints >= 0 ? Colors.green.shade700 : Colors.red.shade700,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Изменение - фиксированная ширина
          SizedBox(
            width: 85,
            child: change != null
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        change >= 0 ? Icons.trending_up : Icons.trending_down,
                        size: 16,
                        color: change >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          _formatPoints(change.abs()),
                          style: TextStyle(
                            fontSize: 13,
                            color: change >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'новый',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.right,
                  ),
          ),
        ],
      ),
    );
  }

  /// Форматирование баллов
  String _formatPoints(double points) {
    if (points >= 0) {
      return '+${points.toStringAsFixed(1)}';
    }
    return points.toStringAsFixed(1);
  }

  /// Короткое название месяца
  String _getShortMonthName(DateTime date) {
    const months = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
    return months[date.month - 1];
  }
}
