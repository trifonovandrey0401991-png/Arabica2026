import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_colors.dart';
import '../models/shop_revenue_model.dart';
import '../services/revenue_analytics_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  // Данные для таблицы по неделям (один магазин)
  bool _showWeeklyTable = false;
  List<MonthlyRevenueTable> _weeklyRevenues = [];

  // Данные для таблицы по неделям (все магазины)
  Map<String, List<MonthlyRevenueTable>> _allShopsWeeklyRevenues = {};
  final Set<String> _collapsedShops = {}; // Свёрнутые магазины

  @override
  void initState() {
    super.initState();
    _loadShopAddresses();
  }

  static const _addressesCacheKey = 'revenue_addresses';

  Future<void> _loadShopAddresses() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<List<String>>(_addressesCacheKey);
    if (cached != null && mounted) {
      setState(() {
        _shopAddresses = cached;
        _isLoading = false;
      });
      // Show mode dialog even with cached data
      if (_mode == AnalyticsMode.none) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showModeSelectionDialog();
        });
      }
    }

    if (_shopAddresses.isEmpty && mounted) setState(() => _isLoading = true);

    try {
      // Step 2: Fetch fresh data
      final allAddresses = await RevenueAnalyticsService.getShopAddresses();
      final allowedAddresses = await MultitenancyFilterService.getAllowedShopAddresses();
      final addresses = allowedAddresses == null
          ? allAddresses
          : allAddresses.where((a) => allowedAddresses.contains(a)).toList();
      if (!mounted) return;
      setState(() {
        _shopAddresses = addresses;
        _isLoading = false;
      });

      // Step 3: Save to cache
      CacheManager.set(_addressesCacheKey, addresses);

      // Show mode dialog after fresh load (only if not shown from cache)
      if (_mode == AnalyticsMode.none && cached == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showModeSelectionDialog();
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки списка магазинов', e);
      if (!mounted) return;
      if (_shopAddresses.isEmpty) setState(() => _isLoading = false);
    }
  }

  void _showModeSelectionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        title: Row(
          children: [
            Icon(Icons.bar_chart, color: AppColors.gold),
            SizedBox(width: 12),
            Expanded(
              child: Text('Аналитика выручки', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Выберите режим просмотра:',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
            SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.store, color: AppColors.gold),
              ),
              title: Text('Один магазин', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              subtitle: Text('Детальная аналитика и сравнение периодов', style: TextStyle(color: Colors.white.withOpacity(0.5))),
              onTap: () {
                Navigator.pop(context);
                _selectMode(AnalyticsMode.singleShop);
              },
            ),
            Divider(color: Colors.white.withOpacity(0.1)),
            ListTile(
              leading: Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.storefront, color: AppColors.gold),
              ),
              title: Text('Все магазины', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              subtitle: Text('Обзор выручки и сравнение магазинов', style: TextStyle(color: Colors.white.withOpacity(0.5))),
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
            style: TextButton.styleFrom(foregroundColor: AppColors.gold),
            child: Text('Отмена'),
          ),
        ],
      ),
    );
  }

  void _selectMode(AnalyticsMode mode) {
    if (mounted) setState(() {
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
        backgroundColor: AppColors.emeraldDark,
        title: Text('Выберите магазин', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: _shopAddresses.isEmpty
              ? Center(child: Text('Магазины не найдены', style: TextStyle(color: Colors.white.withOpacity(0.5))))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _shopAddresses.length,
                  itemBuilder: (context, index) {
                    final address = _shopAddresses[index];
                    return ListTile(
                      leading: Icon(Icons.store_outlined, color: AppColors.gold),
                      title: Text(
                        address,
                        style: TextStyle(fontSize: 14.sp, color: Colors.white),
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
              if (mounted) setState(() => _mode = AnalyticsMode.none);
              _showModeSelectionDialog();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.gold),
            child: Text('Назад'),
          ),
        ],
      ),
    );
  }

  void _selectShop(String shopAddress) {
    if (mounted) setState(() => _selectedShop = shopAddress);
    _loadSingleShopData(shopAddress);
  }

  String _singleShopCacheKey(String addr) => 'revenue_single_${addr.hashCode}';

  Future<void> _loadSingleShopData(String shopAddress) async {
    // Step 1: Show cached data instantly
    final cacheKey = _singleShopCacheKey(shopAddress);
    final cached = CacheManager.get<Map<String, dynamic>>(cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _yesterdayRevenue = cached['yesterday'] as double;
        _weekAgoRevenue = cached['weekAgo'] as double;
        _monthAgoRevenue = cached['monthAgo'] as double;
        _currentMonthRevenue = cached['currentMonth'] as double;
        _prevMonthRevenue = cached['prevMonth'] as double;
        _currentWeekRevenue = cached['currentWeek'] as double;
        _prevWeekRevenue = cached['prevWeek'] as double;
        _dailyRevenues = cached['daily'] as List<DailyRevenue>;
        _isLoading = false;
      });
    }

    if (cached == null && mounted) setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final weekAgo = yesterday.subtract(Duration(days: 7));
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
      final prevWeekStart = currentWeekStart.subtract(Duration(days: 7));
      final prevWeekEnd = now.subtract(Duration(days: 7));

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

      // Step 3: Save to cache
      CacheManager.set(cacheKey, {
        'yesterday': yesterdayRev,
        'weekAgo': weekAgoRev,
        'monthAgo': monthAgoRev,
        'currentMonth': currentMonthRev,
        'prevMonth': prevMonthRev,
        'currentWeek': currentWeekRev,
        'prevWeek': prevWeekRev,
        'daily': dailyRevenues,
      });
    } catch (e) {
      Logger.error('Ошибка загрузки данных магазина', e);
      if (!mounted) return;
      if (cached == null) setState(() => _isLoading = false);
    }
  }

  static const _allShopsCacheKey = 'revenue_all_shops';

  Future<void> _loadAllShopsData() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<List<ShopRevenue>>(_allShopsCacheKey);
    if (cached != null && mounted) {
      setState(() {
        _allShopsRevenues = cached;
        _isLoading = false;
      });
    }

    if (_allShopsRevenues.isEmpty && mounted) setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, 1);
      final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final results = await Future.wait([
        RevenueAnalyticsService.getShopRevenues(
          startDate: startDate,
          endDate: endDate,
        ),
        RevenueAnalyticsService.getAllShopsDailyRevenues(
          startDate: startDate,
          endDate: endDate,
        ),
        MultitenancyFilterService.getAllowedShopAddresses(),
      ]);

      final allRevenues = results[0] as List<ShopRevenue>;
      // results[1] contains daily revenues (Map<String, List<DailyRevenue>>), not used here
      final allowedAddresses = results[2] as List<String>?;

      // Фильтрация по мультитенантности
      final revenues = allowedAddresses == null
          ? allRevenues
          : allRevenues.where((r) => allowedAddresses.contains(r.shopAddress)).toList();
      if (!mounted) return;
      setState(() {
        _allShopsRevenues = revenues;
        _isLoading = false;
      });

      // Step 3: Save to cache
      CacheManager.set(_allShopsCacheKey, revenues);
    } catch (e) {
      Logger.error('Ошибка загрузки данных всех магазинов', e);
      if (!mounted) return;
      if (_allShopsRevenues.isEmpty) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Column(
        children: [
          _buildHeader(),
          if (_isLoading)
            Expanded(
              child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
            )
          else if (_mode == AnalyticsMode.none)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bar_chart, size: 64, color: Colors.white.withOpacity(0.3)),
                    SizedBox(height: 16),
                    Text(
                      'Выберите режим аналитики',
                      style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.5)),
                    ),
                    SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _showModeSelectionDialog,
                      icon: Icon(Icons.settings),
                      label: Text('Выбрать режим'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.night,
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
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.emeraldDark, AppColors.emerald],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
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
                icon: Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () {
                  // Если показывается таблица - закрыть её
                  if (_showWeeklyTable) {
                    if (mounted) setState(() => _showWeeklyTable = false);
                    return;
                  }
                  if (_showRevenueTable) {
                    if (mounted) setState(() => _showRevenueTable = false);
                    return;
                  }
                  // Иначе вернуться к выбору режима
                  if (mounted) setState(() {
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
                      Icon(Icons.bar_chart, color: Colors.white, size: 24),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_mode != AnalyticsMode.none)
              IconButton(
                icon: Icon(Icons.refresh, color: Colors.white),
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
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      onRefresh: () => _loadSingleShopData(_selectedShop!),
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDayComparisonRow(),
            SizedBox(height: 16),
            _buildGrowthIndicators(),
            SizedBox(height: 16),
            _buildDailyRevenueChart(),
          ],
        ),
      ),
    );
  }

  Future<void> _loadWeeklyRevenues() async {
    Logger.debug('_loadWeeklyRevenues() for shop: $_selectedShop');
    final cacheKey = 'revenue_weekly_${_selectedShop.hashCode}';

    // Step 1: Show cached data instantly
    final cached = CacheManager.get<List<MonthlyRevenueTable>>(cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _weeklyRevenues = cached;
        _showWeeklyTable = true;
        _isLoading = false;
      });
    }

    if (cached == null && mounted) setState(() => _isLoading = true);

    try {
      final data = await RevenueAnalyticsService.getWeeklyRevenuesAllMonths(
        shopAddress: _selectedShop!,
      );
      if (!mounted) return;
      setState(() {
        _weeklyRevenues = data;
        _showWeeklyTable = true;
        _isLoading = false;
      });

      // Step 3: Save to cache
      CacheManager.set(cacheKey, data);
    } catch (e, stackTrace) {
      Logger.error('Ошибка загрузки недельных данных', e);
      Logger.debug('Stack trace: $stackTrace');
      if (!mounted) return;
      if (cached == null) setState(() => _isLoading = false);
    }
  }

  Widget _buildDayComparisonRow() {
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
          Text(
            'Сравнение по дням',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildDayCard(
                  title: 'Вчера',
                  value: _yesterdayRevenue,
                  color: AppColors.emerald,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _buildDayCard(
                  title: 'Неделю назад',
                  value: _weekAgoRevenue,
                  color: AppColors.emerald,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _buildDayCard(
                  title: 'Месяц назад',
                  value: _monthAgoRevenue,
                  color: Color(0xFF009688),
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
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10.sp,
              color: Colors.white.withOpacity(0.5),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatRevenue(value),
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.9),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthIndicators() {
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
          Text(
            'Показатели роста',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          SizedBox(height: 16),
          _buildGrowthCard(
            title: 'Текущий месяц vs прошлый',
            subtitle: 'За одинаковое количество дней',
            currentValue: _currentMonthRevenue,
            prevValue: _prevMonthRevenue,
            icon: Icons.calendar_month,
          ),
          Divider(height: 24, color: Colors.white.withOpacity(0.1)),
          _buildGrowthCard(
            title: 'Текущая неделя vs прошлая',
            subtitle: 'С понедельника по сегодня',
            currentValue: _currentWeekRevenue,
            prevValue: _prevWeekRevenue,
            icon: Icons.date_range,
          ),
          Divider(height: 24, color: Colors.white.withOpacity(0.1)),
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
        indicatorColor = AppColors.success;
        trendIcon = Icons.trending_up;
      } else if (changePercent < -5) {
        indicatorColor = Color(0xFFEF5350);
        trendIcon = Icons.trending_down;
      } else {
        indicatorColor = Color(0xFFFFA726);
        trendIcon = Icons.trending_flat;
      }
    }

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(10.w),
          decoration: BoxDecoration(
            color: indicatorColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, color: indicatorColor, size: 24),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.sp,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
              SizedBox(height: 4),
              Text(
                '${_formatRevenue(prevValue)} → ${_formatRevenue(currentValue)}',
                style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.7)),
              ),
            ],
          ),
        ),
        Flexible(
          flex: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(trendIcon, color: indicatorColor, size: 20),
                  SizedBox(width: 4),
                  Text(
                    changePercent != null
                        ? '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(1)}%'
                        : 'Н/Д',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.sp,
                      color: indicatorColor,
                    ),
                  ),
                ],
              ),
              if (changeAmount != null)
                Text(
                  '${changeAmount >= 0 ? '+' : ''}${_formatRevenue(changeAmount)}',
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: Colors.white.withOpacity(0.5),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDailyRevenueChart() {
    if (_dailyRevenues.isEmpty) {
      return Container(
        padding: EdgeInsets.all(32.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Text(
              'Нет данных для графика',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
            SizedBox(height: 16),
            _buildDetailedButton(),
          ],
        ),
      );
    }

    // Находим максимальное значение для масштаба
    double maxY = _dailyRevenues.fold(0.0, (max, r) => r.totalRevenue > max ? r.totalRevenue : max);
    if (maxY == 0) maxY = 1000;

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
          Text(
            'Выручка по дням (текущий месяц)',
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: AppColors.gold,
            ),
          ),
          SizedBox(height: 16),
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
                        TextStyle(color: Colors.white, fontSize: 12.sp),
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
                          return SizedBox.shrink();
                        }
                        return Text(
                          '${_dailyRevenues[index].day}',
                          style: TextStyle(fontSize: 9.sp, color: Colors.white.withOpacity(0.5)),
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
                          style: TextStyle(fontSize: 9.sp, color: Colors.white.withOpacity(0.5)),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(
                  _dailyRevenues.length,
                  (index) => BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: _dailyRevenues[index].totalRevenue,
                        color: AppColors.gold,
                        width: _dailyRevenues.length > 20 ? 8 : 12,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(3.r)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 16),
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
        icon: Icon(Icons.table_chart),
        label: Text('Подробно'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.gold,
          side: BorderSide(color: AppColors.gold.withOpacity(0.5)),
          padding: EdgeInsets.symmetric(vertical: 12.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.r),
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
      color: AppColors.night,
      child: Column(
        children: [
          // Заголовок
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            color: AppColors.emeraldDark,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: Colors.white.withOpacity(0.9)),
                  onPressed: () => setState(() => _showWeeklyTable = false),
                ),
                Expanded(
                  child: Text(
                    'Выручка по неделям (${_weeklyRevenues.length} мес.)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Таблица
          Expanded(
            child: _weeklyRevenues.isEmpty
                ? Center(child: Text('Нет данных', style: TextStyle(color: Colors.white.withOpacity(0.5))))
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.all(8.w),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildWeeklyTableHeader(),
                            for (int i = 0; i < _weeklyRevenues.length; i++) ...[
                              ..._weeklyRevenues[i].weeks.map((week) => _buildWeekRow(week)),
                              _buildMonthTotalRow(_weeklyRevenues[i]),
                              if (i < _weeklyRevenues.length - 1)
                                SizedBox(height: 8),
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
    TextStyle headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 11.sp,
      color: AppColors.gold,
    );
    final cellWidth = 55.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
      decoration: BoxDecoration(
        color: AppColors.emerald.withOpacity(0.2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
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
    final cellStyle = TextStyle(fontSize: 10.sp, color: Colors.white.withOpacity(0.7));
    final cellWidth = 55.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text(
              week.formattedDate,
              style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ),
          for (int i = 0; i < 7; i++)
            SizedBox(
              width: cellWidth,
              child: Text(
                _formatWeeklyValue(week.dailyRevenues[i]),
                style: cellStyle.copyWith(
                  color: week.dailyRevenues[i] > 0 ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.3),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: 70,
            child: Text(
              _formatWeeklyValue(week.total),
              style: TextStyle(
                fontSize: 10.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
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
    final monthNameWidth = 470.0;
    final totalWidth = 70.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 4.w),
      decoration: BoxDecoration(
        color: AppColors.emerald.withOpacity(0.15),
        border: Border(
          bottom: BorderSide(color: AppColors.gold.withOpacity(0.3), width: 2),
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
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.sp,
                    color: AppColors.gold,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '(СРЕДНЯЯ: ${_formatRevenueCompact(month.averageRevenue)})',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: totalWidth,
            child: Text(
              _formatRevenueCompact(month.totalRevenue),
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.bold,
                color: Color(0xFFEF5350),
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
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      onRefresh: _loadAllShopsData,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAllShopsSummary(),
            SizedBox(height: 16),
            _buildTopGrowersSection(),
            SizedBox(height: 16),
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
            color: AppColors.gold,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            icon: Icons.store,
            title: 'Магазинов',
            value: _allShopsRevenues.length.toString(),
            subtitle: '$totalShifts смен',
            color: AppColors.emerald,
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
              Icon(icon, color: color, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withOpacity(0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.9),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.sp,
                color: Colors.white.withOpacity(0.5),
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
            color: AppColors.success,
            shop: topGrowers.first,
          ),
        if (topGrowers.isNotEmpty && decliners.isNotEmpty)
          SizedBox(height: 12),
        if (decliners.isNotEmpty)
          _buildTopCard(
            title: 'Падение',
            icon: Icons.trending_down,
            color: Color(0xFFEF5350),
            shop: decliners.first,
          ),
        if (topGrowers.isEmpty && decliners.isEmpty)
          Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Center(
              child: Text(
                'Недостаточно данных для сравнения',
                style: TextStyle(color: Colors.white.withOpacity(0.5)),
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
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withOpacity(0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  shop.shopAddress,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.sp,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  _formatRevenue(shop.totalRevenue),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            flex: 0,
            child: Text(
              shop.formattedChange,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18.sp,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
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
        icon: Icon(Icons.table_chart),
        label: Text('Показать таблицу выручки'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.night,
          padding: EdgeInsets.symmetric(vertical: 14.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
      ),
    );
  }

  static const _allShopsWeeklyCacheKey = 'revenue_all_shops_weekly';

  Future<void> _loadAllShopsWeeklyData() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, List<MonthlyRevenueTable>>>(_allShopsWeeklyCacheKey);
    if (cached != null && mounted) {
      setState(() {
        _allShopsWeeklyRevenues = cached;
        _showRevenueTable = true;
        _isLoading = false;
      });
    }

    if (cached == null && mounted) setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        RevenueAnalyticsService.getWeeklyRevenuesAllShops(),
        MultitenancyFilterService.getAllowedShopAddresses(),
      ]);

      final allData = results[0] as Map<String, List<MonthlyRevenueTable>>;
      final allowedAddresses = results[1] as List<String>?;

      // Фильтрация по мультитенантности
      final data = allowedAddresses == null
          ? allData
          : Map.fromEntries(
              allData.entries.where((e) => allowedAddresses.contains(e.key)),
            );

      if (!mounted) return;
      setState(() {
        _allShopsWeeklyRevenues = data;
        _showRevenueTable = true;
        _isLoading = false;
      });

      // Step 3: Save to cache
      CacheManager.set(_allShopsWeeklyCacheKey, data);
    } catch (e) {
      Logger.error('Ошибка загрузки данных по неделям для всех магазинов', e);
      if (!mounted) return;
      if (cached == null) setState(() => _isLoading = false);
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
          padding: EdgeInsets.all(12.w),
          color: AppColors.emeraldDark,
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white.withOpacity(0.9)),
                onPressed: () => setState(() => _showRevenueTable = false),
              ),
              Expanded(
                child: Text(
                  'Выручка по неделям ($monthName ${now.year})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.sp,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: sortedShops.isEmpty
              ? Center(child: Text('Нет данных за текущий месяц', style: TextStyle(color: Colors.white.withOpacity(0.5))))
              : ListView.builder(
                  padding: EdgeInsets.all(8.w),
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
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Заголовок магазина (сворачиваемый)
          InkWell(
            onTap: () {
              if (mounted) setState(() {
                if (isCollapsed) {
                  _collapsedShops.remove(shopAddress);
                } else {
                  _collapsedShops.add(shopAddress);
                }
              });
            },
            borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
            child: Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.2),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(14.r),
                  bottom: isCollapsed ? Radius.circular(14.r) : Radius.zero,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCollapsed ? Icons.expand_more : Icons.expand_less,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      shopAddress,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.sp,
                        color: Colors.white.withOpacity(0.9),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (month != null)
                    Text(
                      _formatRevenueCompact(month.totalRevenue),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.sp,
                        color: Color(0xFFEF5350),
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
              padding: EdgeInsets.symmetric(horizontal: 4.w),
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
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Text('Нет данных', style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
        ],
      ),
    );
  }

  Widget _buildAllShopsTableHeader() {
    TextStyle headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 10.sp,
      color: AppColors.gold,
    );
    final cellWidth = 55.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.gold.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text('ДАТА', style: headerStyle, textAlign: TextAlign.center),
          ),
          for (final day in ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'])
            SizedBox(
              width: cellWidth,
              child: Text(day, style: headerStyle, textAlign: TextAlign.center),
            ),
          SizedBox(
            width: 70,
            child: Text('ИТОГО', style: headerStyle, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _buildAllShopsWeekRow(WeeklyRevenue week) {
    final cellStyle = TextStyle(fontSize: 10.sp, color: Colors.white.withOpacity(0.7));
    final cellWidth = 55.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            child: Text(
              week.formattedDate,
              style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
          ),
          for (int i = 0; i < 7; i++)
            SizedBox(
              width: cellWidth,
              child: Text(
                _formatWeeklyValue(week.dailyRevenues[i]),
                style: cellStyle.copyWith(
                  color: week.dailyRevenues[i] > 0 ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.3),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: 70,
            child: Text(
              _formatWeeklyValue(week.total),
              style: TextStyle(
                fontSize: 10.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
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
    final monthNameWidth = 470.0;
    final totalWidth = 70.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 4.w),
      decoration: BoxDecoration(
        color: AppColors.emerald.withOpacity(0.15),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12.r)),
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
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.sp,
                    color: AppColors.gold,
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  '(СРЕДНЯЯ: ${_formatWeeklyValue(month.averageRevenue)})',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: totalWidth,
            child: Text(
              _formatRevenueCompact(month.totalRevenue),
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.bold,
                color: Color(0xFFEF5350),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    final months = [
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
