import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../services/kpi_service.dart';
import '../models/kpi_shop_month_stats.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница списка всех магазинов для KPI
class KPIShopsListPage extends StatefulWidget {
  const KPIShopsListPage({super.key});

  @override
  State<KPIShopsListPage> createState() => _KPIShopsListPageState();
}

class _KPIShopsListPageState extends State<KPIShopsListPage> {
  List<Shop> _shops = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // Отслеживание раскрытых магазинов
  final Set<String> _expandedShops = {};

  // Кэш месячной статистики
  final Map<String, List<KPIShopMonthStats>> _monthlyStatsCache = {};

  // Отслеживание загружаемых магазинов (для предотвращения дублирования)
  final Set<String> _loadingShops = {};

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      Logger.debug('Загрузка списка магазинов для KPI...');
      final shops = await ShopService.getShopsForCurrentUser();
      Logger.debug('Загружено магазинов: ${shops.length}');

      if (mounted) {
        setState(() {
          _shops = shops;
          _isLoading = false;
        });

        // BATCH: загружаем статистику ВСЕХ магазинов одним пакетом (8 запросов вместо 78)
        final addresses = shops.map((s) => s.address).toList();
        final batchStats = await KPIService.getAllShopsMonthlyStatsBatch(addresses);

        if (mounted) {
          setState(() {
            _monthlyStatsCache.addAll(batchStats);
            // Для магазинов без данных — пустой список
            for (final shop in shops) {
              _monthlyStatsCache.putIfAbsent(shop.address, () => []);
            }
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки списка магазинов', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Shop> get _filteredShops {
    if (_searchQuery.isEmpty) {
      return _shops;
    }
    return _shops
        .where((shop) =>
            shop.address.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  Widget _buildMonthIndicators(KPIShopMonthStats stats) {
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
  Widget _buildScheduleBadge(KPIShopMonthStats stats) {
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
            Icon(Icons.schedule, size: 10, color: Colors.orange),
            SizedBox(width: 2),
            Text(
              '${stats.lateArrivals}',
              style: TextStyle(fontSize: 8.sp, color: Colors.orange, fontWeight: FontWeight.bold),
            ),
            SizedBox(width: 4),
          ],
          // Пропуски
          if (stats.missedDays > 0) ...[
            Icon(Icons.event_busy, size: 10, color: Colors.red),
            SizedBox(width: 2),
            Text(
              '${stats.missedDays}',
              style: TextStyle(fontSize: 8.sp, color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
          // Если нет проблем - показываем галочку
          if (!hasProblems)
            Icon(Icons.check_circle, size: 12, color: Colors.green),
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

  String _getMonthName(int month) {
    final months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    return months[month - 1];
  }

  Widget _buildMonthRow(String shopAddress, KPIShopMonthStats stats, String label) {
    final monthLabel = '${_getMonthName(stats.month)} ${stats.year}';

    return Container(
      margin: EdgeInsets.only(left: 40.w, right: 8.w, top: 2.h, bottom: 2.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.9)),
                      ),
                      SizedBox(width: 8),
                      Text(
                        monthLabel,
                        style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5)),
                      ),
                    ],
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(12.0.w),
          child: TextField(
            style: TextStyle(color: Colors.white),
            cursorColor: AppColors.gold,
            decoration: InputDecoration(
              hintText: 'Поиск магазина...',
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
        _isLoading
            ? Expanded(
                child: Center(child: CircularProgressIndicator(color: AppColors.gold)),
              )
            : _filteredShops.isEmpty
                ? Expanded(
                    child: Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'Нет магазинов'
                            : 'Магазины не найдены',
                        style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.5)),
                      ),
                    ),
                  )
                : Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 8.w),
                      itemCount: _filteredShops.length,
                      itemBuilder: (context, index) {
                        final shop = _filteredShops[index];
                        final isExpanded = _expandedShops.contains(shop.address);
                        final monthlyStats = _monthlyStatsCache[shop.address];

                        return Column(
                          children: [
                            // Главная строка магазина
                            Container(
                              margin: EdgeInsets.symmetric(vertical: 2.h),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    if (mounted) setState(() {
                                      if (isExpanded) {
                                        _expandedShops.remove(shop.address);
                                      } else {
                                        _expandedShops.add(shop.address);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(14.r),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                                    child: Row(
                                      children: [
                                        // Иконка магазина
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: AppColors.emerald,
                                          child: Icon(
                                            Icons.store,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        // Адрес и показатели
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Адрес в одну строку
                                              Text(
                                                shop.address,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13.sp,
                                                  color: Colors.white.withOpacity(0.9),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              SizedBox(height: 4),
                                              // Показатели под адресом
                                              monthlyStats != null && monthlyStats.isNotEmpty
                                                  ? _buildMonthIndicators(monthlyStats[0])
                                                  : monthlyStats != null && monthlyStats.isEmpty
                                                      ? Text(
                                                          'Нет данных',
                                                          style: TextStyle(
                                                            fontSize: 11.sp,
                                                            color: Colors.white.withOpacity(0.4),
                                                            fontStyle: FontStyle.italic,
                                                          ),
                                                        )
                                                      : SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                                                          ),
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
                            ),

                            // Раскрытые месячные строки
                            if (isExpanded && monthlyStats != null && monthlyStats.length >= 3) ...[
                              _buildMonthRow(shop.address, monthlyStats[1], 'Прошлый месяц'),
                              _buildMonthRow(shop.address, monthlyStats[2], 'Позапрошлый месяц'),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
      ],
    );
  }
}
