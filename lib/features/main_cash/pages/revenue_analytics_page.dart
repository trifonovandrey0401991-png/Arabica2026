import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/shop_revenue_model.dart';
import '../services/revenue_analytics_service.dart';
import '../../../core/utils/logger.dart';

/// Режим аналитики
enum AnalyticsMode {
  none,       // Ничего не выбрано - показать диалог
  singleShop, // Один магазин
  allShops,   // Все магазины
}

class RevenueAnalyticsPage extends StatefulWidget {
  const RevenueAnalyticsPage({super.key});

  @override
  State<RevenueAnalyticsPage> createState() => _RevenueAnalyticsPageState();
}

class _RevenueAnalyticsPageState extends State<RevenueAnalyticsPage> {
  AnalyticsMode _mode = AnalyticsMode.none;
  String? _selectedShop;
  List<String> _shopAddresses = [];
  bool _isLoading = true;
  bool _showRevenueTable = false;

  // Данные для одного магазина
  double _yesterdayRevenue = 0;
  double _weekAgoRevenue = 0;
  double _monthAgoRevenue = 0;
  double _currentMonthRevenue = 0;
  double _prevMonthRevenue = 0;
  double _currentWeekRevenue = 0;
  double _prevWeekRevenue = 0;
  List<DailyRevenue> _dailyRevenues = [];

  // Данные для всех магазинов
  List<ShopRevenue> _allShopsRevenues = [];
  Map<String, List<DailyRevenue>> _allShopsDailyRevenues = {};

  // Данные для таблицы по неделям (один магазин)
  bool _showWeeklyTable = false;
  List<MonthlyRevenueTable> _weeklyRevenues = [];

  // Данные для таблицы по неделям (все магазины)
  Map<String, List<MonthlyRevenueTable>> _allShopsWeeklyRevenues = {};
  Set<String> _collapsedShops = {}; // Свёрнутые магазины

  @override
  void initState() {
    super.initState();
    _loadShopAddresses();
  }

  Future<void> _loadShopAddresses() async {
    setState(() => _isLoading = true);
    try {
      final addresses = await RevenueAnalyticsService.getShopAddresses();
      if (!mounted) return;
      setState(() {
        _shopAddresses = addresses;
        _isLoading = false;
      });

      // Показать диалог выбора режима после загрузки
      if (_mode == AnalyticsMode.none) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showModeSelectionDialog();
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки списка магазинов', e);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _showModeSelectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bar_chart, color: Color(0xFF004D40)),
            SizedBox(width: 12),
            Text('Аналитика выручки'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Выберите режим просмотра:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF004D40).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.store, color: Color(0xFF004D40)),
              ),
              title: const Text('Один магазин', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Детальная аналитика и сравнение периодов'),
              onTap: () {
                Navigator.pop(context);
                _selectMode(AnalyticsMode.singleShop);
              },
            ),
            const Divider(),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00796B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.storefront, color: Color(0xFF00796B)),
              ),
              title: const Text('Все магазины', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Обзор выручки и сравнение магазинов'),
              onTap: () {
                Navigator.pop(context);
                _selectMode(AnalyticsMode.allShops);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  void _selectMode(AnalyticsMode mode) {
    setState(() {
      _mode = mode;
      _showRevenueTable = false;
      _showWeeklyTable = false;
    });

    if (mode == AnalyticsMode.singleShop) {
      _showShopSelectionDialog();
    } else if (mode == AnalyticsMode.allShops) {
      _loadAllShopsData();
    }
  }

  void _showShopSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите магазин'),
        content: SizedBox(
          width: double.maxFinite,
          child: _shopAddresses.isEmpty
              ? const Center(child: Text('Магазины не найдены'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _shopAddresses.length,
                  itemBuilder: (context, index) {
                    final address = _shopAddresses[index];
                    return ListTile(
                      leading: const Icon(Icons.store_outlined),
                      title: Text(
                        address,
                        style: const TextStyle(fontSize: 14),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _selectShop(address);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _mode = AnalyticsMode.none);
              _showModeSelectionDialog();
            },
            child: const Text('Назад'),
          ),
        ],
      ),
    );
  }

  void _selectShop(String shopAddress) {
    setState(() => _selectedShop = shopAddress);
    _loadSingleShopData(shopAddress);
  }

  Future<void> _loadSingleShopData(String shopAddress) async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final weekAgo = yesterday.subtract(const Duration(days: 7));
      final monthAgo = DateTime(yesterday.year, yesterday.month - 1, yesterday.day);

      // Загружаем выручку за конкретные дни
      final yesterdayRev = await RevenueAnalyticsService.getDayRevenue(
        shopAddress: shopAddress,
        date: yesterday,
      );
      final weekAgoRev = await RevenueAnalyticsService.getDayRevenue(
        shopAddress: shopAddress,
        date: weekAgo,
      );
      final monthAgoRev = await RevenueAnalyticsService.getDayRevenue(
        shopAddress: shopAddress,
        date: monthAgo,
      );

      // Загружаем данные за периоды (с учетом одинакового количества дней)
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final currentMonthEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final daysInCurrentPeriod = now.day;

      final prevMonthStart = DateTime(now.year, now.month - 1, 1);
      final prevMonthEnd = DateTime(now.year, now.month - 1, daysInCurrentPeriod, 23, 59, 59);

      final currentMonthRev = await RevenueAnalyticsService.getPeriodRevenue(
        shopAddress: shopAddress,
        startDate: currentMonthStart,
        endDate: currentMonthEnd,
      );
      final prevMonthRev = await RevenueAnalyticsService.getPeriodRevenue(
        shopAddress: shopAddress,
        startDate: prevMonthStart,
        endDate: prevMonthEnd,
      );

      // Неделя к неделе
      final currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
      final currentWeekEnd = now;
      final prevWeekStart = currentWeekStart.subtract(const Duration(days: 7));
      final prevWeekEnd = now.subtract(const Duration(days: 7));

      final currentWeekRev = await RevenueAnalyticsService.getPeriodRevenue(
        shopAddress: shopAddress,
        startDate: DateTime(currentWeekStart.year, currentWeekStart.month, currentWeekStart.day),
        endDate: DateTime(currentWeekEnd.year, currentWeekEnd.month, currentWeekEnd.day, 23, 59, 59),
      );
      final prevWeekRev = await RevenueAnalyticsService.getPeriodRevenue(
        shopAddress: shopAddress,
        startDate: DateTime(prevWeekStart.year, prevWeekStart.month, prevWeekStart.day),
        endDate: DateTime(prevWeekEnd.year, prevWeekEnd.month, prevWeekEnd.day, 23, 59, 59),
      );

      // Загружаем выручку по дням для графика
      final dailyRevenues = await RevenueAnalyticsService.getDailyRevenues(
        shopAddress: shopAddress,
        startDate: currentMonthStart,
        endDate: currentMonthEnd,
      );

      if (!mounted) return;
      setState(() {
        _yesterdayRevenue = yesterdayRev;
        _weekAgoRevenue = weekAgoRev;
        _monthAgoRevenue = monthAgoRev;
        _currentMonthRevenue = currentMonthRev;
        _prevMonthRevenue = prevMonthRev;
        _currentWeekRevenue = currentWeekRev;
        _prevWeekRevenue = prevWeekRev;
        _dailyRevenues = dailyRevenues;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки данных магазина', e);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAllShopsData() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, 1);
      final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final revenues = await RevenueAnalyticsService.getShopRevenues(
        startDate: startDate,
        endDate: endDate,
      );

      final dailyRevenues = await RevenueAnalyticsService.getAllShopsDailyRevenues(
        startDate: startDate,
        endDate: endDate,
      );

      if (!mounted) return;
      setState(() {
        _allShopsRevenues = revenues;
        _allShopsDailyRevenues = dailyRevenues;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки данных всех магазинов', e);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          _buildHeader(),
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_mode == AnalyticsMode.none)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bar_chart, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Выберите режим аналитики',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _showModeSelectionDialog,
                      icon: const Icon(Icons.settings),
                      label: const Text('Выбрать режим'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_mode == AnalyticsMode.singleShop)
            Expanded(child: _buildSingleShopView())
          else if (_mode == AnalyticsMode.allShops)
            Expanded(child: _buildAllShopsView()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    String title = 'Аналитика выручки';
    String? subtitle;

    if (_mode == AnalyticsMode.singleShop && _selectedShop != null) {
      title = _selectedShop!;
      subtitle = 'Детальная аналитика';
    } else if (_mode == AnalyticsMode.allShops) {
      subtitle = 'Все магазины';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF004D40),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (_mode != AnalyticsMode.none)
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  // Если показывается таблица - закрыть её
                  if (_showWeeklyTable) {
                    setState(() => _showWeeklyTable = false);
                    return;
                  }
                  if (_showRevenueTable) {
                    setState(() => _showRevenueTable = false);
                    return;
                  }
                  // Иначе вернуться к выбору режима
                  setState(() {
                    _mode = AnalyticsMode.none;
                    _selectedShop = null;
                    _showRevenueTable = false;
                    _showWeeklyTable = false;
                  });
                  _showModeSelectionDialog();
                },
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bar_chart, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_mode != AnalyticsMode.none)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () {
                  if (_mode == AnalyticsMode.singleShop && _selectedShop != null) {
                    _loadSingleShopData(_selectedShop!);
                  } else if (_mode == AnalyticsMode.allShops) {
                    _loadAllShopsData();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  // ==================== SINGLE SHOP VIEW ====================

  Widget _buildSingleShopView() {
    if (_showWeeklyTable) {
      return _buildWeeklyRevenueTableView();
    }

    return RefreshIndicator(
      onRefresh: () => _loadSingleShopData(_selectedShop!),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDayComparisonRow(),
            const SizedBox(height: 16),
            _buildGrowthIndicators(),
            const SizedBox(height: 16),
            _buildDailyRevenueChart(),
          ],
        ),
      ),
    );
  }

  Future<void> _loadWeeklyRevenues() async {
    Logger.debug('🔵 _loadWeeklyRevenues() вызван для магазина: $_selectedShop');
    setState(() => _isLoading = true);
    try {
      final data = await RevenueAnalyticsService.getWeeklyRevenuesAllMonths(
        shopAddress: _selectedShop!,
      );
      Logger.debug('✅ Загружено месяцев: ${data.length}');
      for (final month in data) {
        Logger.debug('   ${month.monthNameWithYear}: ${month.weeks.length} недель, итого: ${month.totalRevenue}');
      }
      if (!mounted) return;
      setState(() {
        _weeklyRevenues = data;
        _showWeeklyTable = true;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      Logger.error('❌ Ошибка загрузки недельных данных', e);
      Logger.debug('Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Widget _buildDayComparisonRow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Сравнение по дням',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF004D40),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildDayCard(
                  title: 'Вчера',
                  value: _yesterdayRevenue,
                  color: const Color(0xFF004D40),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDayCard(
                  title: 'Неделю назад',
                  value: _weekAgoRevenue,
                  color: const Color(0xFF00796B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDayCard(
                  title: 'Месяц назад',
                  value: _monthAgoRevenue,
                  color: const Color(0xFF009688),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard({
    required String title,
    required double value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _formatRevenue(value),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthIndicators() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Показатели роста',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF004D40),
            ),
          ),
          const SizedBox(height: 16),
          _buildGrowthCard(
            title: 'Текущий месяц vs прошлый',
            subtitle: 'За одинаковое количество дней',
            currentValue: _currentMonthRevenue,
            prevValue: _prevMonthRevenue,
            icon: Icons.calendar_month,
          ),
          const Divider(height: 24),
          _buildGrowthCard(
            title: 'Текущая неделя vs прошлая',
            subtitle: 'С понедельника по сегодня',
            currentValue: _currentWeekRevenue,
            prevValue: _prevWeekRevenue,
            icon: Icons.date_range,
          ),
          const Divider(height: 24),
          _buildGrowthCard(
            title: 'Вчера vs неделю назад',
            subtitle: 'Тот же день недели',
            currentValue: _yesterdayRevenue,
            prevValue: _weekAgoRevenue,
            icon: Icons.today,
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthCard({
    required String title,
    required String subtitle,
    required double currentValue,
    required double prevValue,
    required IconData icon,
  }) {
    double? changePercent;
    double? changeAmount;
    if (prevValue > 0) {
      changeAmount = currentValue - prevValue;
      changePercent = (changeAmount / prevValue) * 100;
    }

    Color indicatorColor = Colors.grey;
    IconData trendIcon = Icons.remove;
    if (changePercent != null) {
      if (changePercent > 5) {
        indicatorColor = const Color(0xFF4CAF50);
        trendIcon = Icons.trending_up;
      } else if (changePercent < -5) {
        indicatorColor = const Color(0xFFEF5350);
        trendIcon = Icons.trending_down;
      } else {
        indicatorColor = const Color(0xFFFFA726);
        trendIcon = Icons.trending_flat;
      }
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: indicatorColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: indicatorColor, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatRevenue(prevValue)} → ${_formatRevenue(currentValue)}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(trendIcon, color: indicatorColor, size: 20),
                const SizedBox(width: 4),
                Text(
                  changePercent != null
                      ? '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(1)}%'
                      : 'Н/Д',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: indicatorColor,
                  ),
                ),
              ],
            ),
            if (changeAmount != null)
              Text(
                '${changeAmount >= 0 ? '+' : ''}${_formatRevenue(changeAmount)}',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDailyRevenueChart() {
    if (_dailyRevenues.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            const Text(
              'Нет данных для графика',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            _buildDetailedButton(),
          ],
        ),
      );
    }

    // Находим максимальное значение для масштаба
    double maxY = _dailyRevenues.fold(0.0, (max, r) => r.totalRevenue > max ? r.totalRevenue : max);
    if (maxY == 0) maxY = 1000;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Выручка по дням (текущий месяц)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF004D40),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (groupIndex >= _dailyRevenues.length) return null;
                      final revenue = _dailyRevenues[groupIndex];
                      return BarTooltipItem(
                        '${revenue.day} число\n${_formatRevenue(revenue.totalRevenue)}',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= _dailyRevenues.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          '${_dailyRevenues[index].day}',
                          style: const TextStyle(fontSize: 9),
                        );
                      },
                      reservedSize: 20,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          _formatRevenueShort(value),
                          style: const TextStyle(fontSize: 9),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(
                  _dailyRevenues.length,
                  (index) => BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: _dailyRevenues[index].totalRevenue,
                        color: const Color(0xFF004D40),
                        width: _dailyRevenues.length > 20 ? 8 : 12,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailedButton(),
        ],
      ),
    );
  }

  Widget _buildDetailedButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _loadWeeklyRevenues,
        icon: const Icon(Icons.table_chart),
        label: const Text('Подробно'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF004D40),
          side: const BorderSide(color: Color(0xFF004D40)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // ==================== WEEKLY TABLE VIEW ====================

  Widget _buildWeeklyRevenueTableView() {
    Logger.debug('🔵 _buildWeeklyRevenueTableView: ${_weeklyRevenues.length} месяцев');
    for (final m in _weeklyRevenues) {
      Logger.debug('   Месяц: ${m.monthNameWithYear}, недель: ${m.weeks.length}');
    }

    return Container(
      color: Colors.grey[100],
      child: Column(
        children: [
          // Заголовок
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _showWeeklyTable = false),
                ),
                Expanded(
                  child: Text(
                    'Выручка по неделям (${_weeklyRevenues.length} мес.)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Таблица
          Expanded(
            child: _weeklyRevenues.isEmpty
                ? const Center(child: Text('Нет данных'))
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(8),
                      child: Container(
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildWeeklyTableHeader(),
                            for (int i = 0; i < _weeklyRevenues.length; i++) ...[
                              ..._weeklyRevenues[i].weeks.map((week) => _buildWeekRow(week)),
                              _buildMonthTotalRow(_weeklyRevenues[i]),
                              if (i < _weeklyRevenues.length - 1)
                                const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyTableHeader() {
    const headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 11,
      color: Color(0xFF004D40),
    );
    const cellWidth = 55.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF004D40).withOpacity(0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text('ДАТА', style: headerStyle, textAlign: TextAlign.center),
          ),
          SizedBox(width: cellWidth, child: Text('ПН', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: cellWidth, child: Text('ВТ', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: cellWidth, child: Text('СР', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: cellWidth, child: Text('ЧТ', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: cellWidth, child: Text('ПТ', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: cellWidth, child: Text('СБ', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: cellWidth, child: Text('ВС', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(
            width: 70,
            child: Text('ИТОГО', style: headerStyle, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekRow(WeeklyRevenue week) {
    Logger.debug('   📅 Week row: ${week.formattedDate}, days: ${week.dailyRevenues}, total: ${week.total}');
    const cellStyle = TextStyle(fontSize: 10);
    const cellWidth = 55.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text(
              week.formattedDate,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          for (int i = 0; i < 7; i++)
            SizedBox(
              width: cellWidth,
              child: Text(
                _formatWeeklyValue(week.dailyRevenues[i]),
                style: cellStyle.copyWith(
                  color: week.dailyRevenues[i] > 0 ? Colors.black87 : Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: 70,
            child: Text(
              _formatWeeklyValue(week.total),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthTotalRow(MonthlyRevenueTable month) {
    // Ширина: ДАТА (85) + 7 дней (7*55=385) = 470
    const monthNameWidth = 470.0;
    const totalWidth = 70.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF004D40).withOpacity(0.05),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF004D40).withOpacity(0.3), width: 2),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: monthNameWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  month.monthNameWithYear,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF004D40),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '(СРЕДНЯЯ: ${_formatRevenueCompact(month.averageRevenue)})',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: totalWidth,
            child: Text(
              _formatRevenueCompact(month.totalRevenue),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD32F2F),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String _formatWeeklyValue(double value) {
    if (value == 0) return '0';
    // Форматируем с разделителем тысяч: 17665 -> "17 665"
    final intValue = value.round();
    if (intValue >= 1000) {
      final thousands = intValue ~/ 1000;
      final remainder = intValue % 1000;
      return '$thousands ${remainder.toString().padLeft(3, '0')}';
    }
    return intValue.toString();
  }

  String _formatRevenueCompact(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)} млн';
    } else if (amount >= 1000) {
      final thousands = (amount / 1000).floor();
      final remainder = (amount % 1000).floor();
      if (remainder > 0) {
        return '$thousands ${remainder.toString().padLeft(3, '0')}';
      }
      return '$thousands 000';
    }
    return amount.toStringAsFixed(0);
  }

  // ==================== ALL SHOPS VIEW ====================

  Widget _buildAllShopsView() {
    if (_showRevenueTable) {
      return _buildRevenueTableView();
    }

    return RefreshIndicator(
      onRefresh: _loadAllShopsData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAllShopsSummary(),
            const SizedBox(height: 16),
            _buildTopGrowersSection(),
            const SizedBox(height: 16),
            _buildShowRevenueTableButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildAllShopsSummary() {
    final totalRevenue = _allShopsRevenues.fold(0.0, (sum, r) => sum + r.totalRevenue);
    final totalShifts = _allShopsRevenues.fold(0, (sum, r) => sum + r.shiftsCount);

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.attach_money,
            title: 'Общая выручка',
            value: _formatRevenue(totalRevenue),
            subtitle: 'за текущий месяц',
            color: const Color(0xFF004D40),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.store,
            title: 'Магазинов',
            value: _allShopsRevenues.length.toString(),
            subtitle: '$totalShifts смен',
            color: const Color(0xFF00796B),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String title,
    required String value,
    String? subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopGrowersSection() {
    final topGrowers = RevenueAnalyticsService.getTopGrowers(_allShopsRevenues, limit: 1);
    final decliners = RevenueAnalyticsService.getDecliners(_allShopsRevenues, limit: 1);

    return Column(
      children: [
        if (topGrowers.isNotEmpty)
          _buildTopCard(
            title: 'Лидер роста',
            icon: Icons.trending_up,
            color: const Color(0xFF4CAF50),
            shop: topGrowers.first,
          ),
        if (topGrowers.isNotEmpty && decliners.isNotEmpty)
          const SizedBox(height: 12),
        if (decliners.isNotEmpty)
          _buildTopCard(
            title: 'Падение',
            icon: Icons.trending_down,
            color: const Color(0xFFEF5350),
            shop: decliners.first,
          ),
        if (topGrowers.isEmpty && decliners.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Недостаточно данных для сравнения',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopCard({
    required String title,
    required IconData icon,
    required Color color,
    required ShopRevenue shop,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  shop.shopAddress,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatRevenue(shop.totalRevenue),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          Text(
            shop.formattedChange,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShowRevenueTableButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _loadAllShopsWeeklyData,
        icon: const Icon(Icons.table_chart),
        label: const Text('Показать таблицу выручки'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF004D40),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Future<void> _loadAllShopsWeeklyData() async {
    setState(() => _isLoading = true);
    try {
      final data = await RevenueAnalyticsService.getWeeklyRevenuesAllShops();
      if (!mounted) return;
      setState(() {
        _allShopsWeeklyRevenues = data;
        _showRevenueTable = true;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки данных по неделям для всех магазинов', e);
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Widget _buildRevenueTableView() {
    final now = DateTime.now();
    final monthName = _getMonthName(now.month);

    // Сортируем магазины по алфавиту
    final sortedShops = _allShopsWeeklyRevenues.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showRevenueTable = false),
              ),
              Expanded(
                child: Text(
                  'Выручка по неделям ($monthName ${now.year})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: sortedShops.isEmpty
              ? const Center(child: Text('Нет данных за текущий месяц'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: sortedShops.length,
                  itemBuilder: (context, index) {
                    final entry = sortedShops[index];
                    return _buildShopWeeklySection(entry.key, entry.value);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShopWeeklySection(String shopAddress, List<MonthlyRevenueTable> months) {
    final isCollapsed = _collapsedShops.contains(shopAddress);
    final month = months.isNotEmpty ? months.first : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Заголовок магазина (сворачиваемый)
          InkWell(
            onTap: () {
              setState(() {
                if (isCollapsed) {
                  _collapsedShops.remove(shopAddress);
                } else {
                  _collapsedShops.add(shopAddress);
                }
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF004D40).withOpacity(0.1),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(12),
                  bottom: isCollapsed ? const Radius.circular(12) : Radius.zero,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCollapsed ? Icons.expand_more : Icons.expand_less,
                    color: const Color(0xFF004D40),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      shopAddress,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF004D40),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (month != null)
                    Text(
                      _formatRevenueCompact(month.totalRevenue),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Таблица (если не свёрнута)
          if (!isCollapsed && month != null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAllShopsTableHeader(),
                  for (final week in month.weeks)
                    _buildAllShopsWeekRow(week),
                  _buildAllShopsMonthTotalRow(month),
                ],
              ),
            ),
          if (!isCollapsed && month == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Нет данных', style: TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  Widget _buildAllShopsTableHeader() {
    const headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 10,
      color: Color(0xFF004D40),
    );
    const cellWidth = 55.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: const Color(0xFF004D40).withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 85,
            child: Text('ДАТА', style: headerStyle, textAlign: TextAlign.center),
          ),
          for (final day in ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'])
            SizedBox(
              width: cellWidth,
              child: Text(day, style: headerStyle, textAlign: TextAlign.center),
            ),
          const SizedBox(
            width: 70,
            child: Text('ИТОГО', style: headerStyle, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _buildAllShopsWeekRow(WeeklyRevenue week) {
    const cellStyle = TextStyle(fontSize: 10);
    const cellWidth = 55.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text(
              week.formattedDate,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          for (int i = 0; i < 7; i++)
            SizedBox(
              width: cellWidth,
              child: Text(
                _formatWeeklyValue(week.dailyRevenues[i]),
                style: cellStyle.copyWith(
                  color: week.dailyRevenues[i] > 0 ? Colors.black87 : Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: 70,
            child: Text(
              _formatWeeklyValue(week.total),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllShopsMonthTotalRow(MonthlyRevenueTable month) {
    // Ширина: ДАТА (85) + 7 дней (7*55=385) = 470
    const monthNameWidth = 470.0;
    const totalWidth = 70.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF004D40).withOpacity(0.05),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: monthNameWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  month.monthNameWithYear,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF004D40),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '(СРЕДНЯЯ: ${_formatWeeklyValue(month.averageRevenue)})',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: totalWidth,
            child: Text(
              _formatRevenueCompact(month.totalRevenue),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD32F2F),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    return months[month];
  }

  // ==================== HELPERS ====================

  String _formatRevenue(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)} млн руб';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)} тыс руб';
    } else {
      return '${amount.toStringAsFixed(0)} руб';
    }
  }

  String _formatRevenueShort(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}k';
    } else {
      return amount.toStringAsFixed(0);
    }
  }
}
