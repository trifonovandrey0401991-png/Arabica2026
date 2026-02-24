import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/efficiency_data_model.dart';
import '../services/efficiency_data_service.dart';
import '../../../core/utils/cache_manager.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  static const _cacheKey = 'efficiency_analytics';

  Future<void> _loadData() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<List<EfficiencyData>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _monthsData = cached;
        _isLoading = false;
      });
    }

    // Step 2: Fetch fresh data from server
    try {
      final now = DateTime.now();

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

      final data = await Future.wait(
        months.map((m) => EfficiencyDataService.loadMonthData(m['year']!, m['month']!)),
      );

      if (!mounted) return;
      setState(() {
        _monthsData = data;
        _isLoading = false;
        _error = null;
      });

      // Step 3: Save to cache
      CacheManager.set(_cacheKey, data);
    } catch (e) {
      if (!mounted) return;
      if (_monthsData.isEmpty) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
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
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom Row AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        'Аналитика',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.filter_list, color: Colors.white.withOpacity(0.9)),
                      color: AppColors.emeraldDark,
                      onSelected: (value) => setState(() => _mode = value),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'shops',
                          child: Row(
                            children: [
                              Icon(
                                Icons.store,
                                color: _mode == 'shops' ? AppColors.gold : Colors.white.withOpacity(0.5),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'По магазинам',
                                style: TextStyle(
                                  color: Colors.white,
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
                                color: _mode == 'employees' ? AppColors.gold : Colors.white.withOpacity(0.5),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'По сотрудникам',
                                style: TextStyle(
                                  color: Colors.white,
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
              'Загрузка данных за 3 месяца...',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
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
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Ошибка: $_error',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emerald,
                foregroundColor: AppColors.gold,
              ),
              child: Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_monthsData.isEmpty) {
      return Center(
        child: Text(
          'Нет данных',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
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
            _buildModeIndicator(),
            SizedBox(height: 16),
            _buildSummaryChart(),
            SizedBox(height: 24),
            _buildMonthsTable(),
            SizedBox(height: 24),
            _buildEntitiesTrends(),
          ],
        ),
      ),
    );
  }

  /// Индикатор текущего режима
  Widget _buildModeIndicator() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: AppColors.emerald.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _mode == 'shops' ? Icons.store : Icons.person,
            color: AppColors.gold,
            size: 20,
          ),
          SizedBox(width: 8),
          Text(
            _mode == 'shops' ? 'По магазинам' : 'По сотрудникам',
            style: TextStyle(
              color: Colors.white,
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

    return Container(
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.5)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Динамика эффективности',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.gold,
              ),
            ),
            SizedBox(height: 16),
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
                        color: Colors.white.withOpacity(0.1),
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
                              color: Colors.white.withOpacity(0.5),
                              fontSize: 11.sp,
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
                              padding: EdgeInsets.only(top: 8.h),
                              child: Text(
                                _getShortMonthName(_monthsData[index].periodStart),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                          return Text('');
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
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
                      color: AppColors.gold,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 6,
                            color: AppColors.emeraldDark,
                            strokeWidth: 3,
                            strokeColor: AppColors.gold,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.gold.withOpacity(0.1),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (touchedSpot) => AppColors.emerald,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final index = spot.x.toInt();
                          final monthName = index < _monthsData.length
                              ? _monthsData[index].periodName
                              : '';
                          return LineTooltipItem(
                            '$monthName\n${spot.y.toStringAsFixed(1)} баллов',
                            TextStyle(
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.5)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Сравнение по месяцам',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.gold,
              ),
            ),
            SizedBox(height: 16),
            // Заголовок таблицы
            Container(
              padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 12.w),
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text('Месяц', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.9)))),
                  Expanded(flex: 2, child: Text('Итого', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.9)), textAlign: TextAlign.right)),
                  Expanded(flex: 2, child: Text('Изменение', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.9)), textAlign: TextAlign.right)),
                ],
              ),
            ),
            SizedBox(height: 8),
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
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              data.periodName,
              style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.9)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatPoints(total),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: total >= 0 ? Colors.green.shade300 : Colors.red.shade300,
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
                        color: change >= 0 ? Colors.green.shade300 : Colors.red.shade300,
                      ),
                      SizedBox(width: 2),
                      Text(
                        _formatPoints(change.abs()),
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: change >= 0 ? Colors.green.shade300 : Colors.red.shade300,
                        ),
                      ),
                    ],
                  )
                : Text('—', textAlign: TextAlign.right, style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
        ],
      ),
    );
  }

  /// Тренды по сущностям (магазинам/сотрудникам)
  Widget _buildEntitiesTrends() {
    if (_monthsData.length < 2) {
      return SizedBox.shrink();
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

    return Container(
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.5)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _mode == 'shops' ? 'Динамика по магазинам' : 'Динамика по сотрудникам',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.gold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Сравнение: ${previousMonth.periodName} → ${currentMonth.periodName}',
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            SizedBox(height: 16),
            if (sortedEntities.isEmpty)
              Text('Нет данных', style: TextStyle(color: Colors.white.withOpacity(0.7)))
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
      padding: EdgeInsets.symmetric(vertical: 10.h),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          // Имя сотрудника/магазина - гибкая ширина
          Expanded(
            flex: 3,
            child: Text(
              entity.entityName,
              style: TextStyle(fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.9)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8),
          // Текущие баллы - фиксированная ширина для выравнивания
          SizedBox(
            width: 65,
            child: Text(
              _formatPoints(entity.totalPoints),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: entity.totalPoints >= 0 ? Colors.green.shade300 : Colors.red.shade300,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8),
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
                        color: change >= 0 ? Colors.green.shade300 : Colors.red.shade300,
                      ),
                      SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          _formatPoints(change.abs()),
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: change >= 0 ? Colors.green.shade300 : Colors.red.shade300,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'новый',
                    style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.4)),
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
    final months = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
    return months[date.month - 1];
  }
}
