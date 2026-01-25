import 'package:flutter/material.dart';
import '../../shops/models/shop_model.dart';
import '../services/kpi_service.dart';
import '../models/kpi_shop_month_stats.dart';
import '../../../core/utils/logger.dart';

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
    setState(() => _isLoading = true);

    try {
      Logger.debug('Загрузка списка магазинов для KPI...');
      final shops = await Shop.loadShopsFromServer();
      Logger.debug('Загружено магазинов: ${shops.length}');

      if (mounted) {
        setState(() {
          _shops = shops;
          _isLoading = false;
        });

        // Ленивая загрузка: предзагружаем первые 3 магазина ПОСЛЕДОВАТЕЛЬНО
        // чтобы не перегружать сервер запросами
        final preloadCount = shops.length > 3 ? 3 : shops.length;
        for (var i = 0; i < preloadCount; i++) {
          await _loadMonthlyStats(shops[i].address);
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки списка магазинов', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMonthlyStats(String shopAddress) async {
    if (_loadingShops.contains(shopAddress) || _monthlyStatsCache.containsKey(shopAddress)) {
      return;
    }

    _loadingShops.add(shopAddress);

    try {
      final stats = await KPIService.getShopMonthlyStats(shopAddress);
      if (mounted) {
        setState(() {
          _monthlyStatsCache[shopAddress] = stats;
          _loadingShops.remove(shopAddress);
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки месячной статистики магазина: $shopAddress', e);
      if (mounted) {
        setState(() {
          // Сохраняем пустой список чтобы показать "Нет данных" вместо бесконечных retry
          _monthlyStatsCache[shopAddress] = [];
          _loadingShops.remove(shopAddress);
        });
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
            const SizedBox(width: 6),
          ],
          _buildIndicatorWithFraction(
            Icons.access_time,
            stats.attendanceFraction,
            stats.attendancePercentage,
          ),
          const SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.handshake,
            stats.shiftsFraction,
            stats.shiftsPercentage,
          ),
          const SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.calculate,
            stats.recountsFraction,
            stats.recountsPercentage,
          ),
          const SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.description,
            stats.rkosFraction,
            stats.rkosPercentage,
          ),
          const SizedBox(width: 4),
          _buildIndicatorWithFraction(
            Icons.mail,
            stats.envelopesFraction,
            stats.envelopesPercentage,
          ),
          const SizedBox(width: 4),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: hasProblems ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasProblems ? Colors.red.shade200 : Colors.green.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Опоздания
          if (stats.lateArrivals > 0) ...[
            Icon(Icons.schedule, size: 10, color: Colors.orange.shade700),
            const SizedBox(width: 2),
            Text(
              '${stats.lateArrivals}',
              style: TextStyle(fontSize: 8, color: Colors.orange.shade700, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
          ],
          // Пропуски
          if (stats.missedDays > 0) ...[
            Icon(Icons.event_busy, size: 10, color: Colors.red.shade700),
            const SizedBox(width: 2),
            Text(
              '${stats.missedDays}',
              style: TextStyle(fontSize: 8, color: Colors.red.shade700, fontWeight: FontWeight.bold),
            ),
          ],
          // Если нет проблем - показываем галочку
          if (!hasProblems)
            Icon(Icons.check_circle, size: 12, color: Colors.green.shade700),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(height: 2),
          Text(
            fraction,
            style: TextStyle(
              fontSize: 9,
              color: fractionColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    return months[month - 1];
  }

  Widget _buildMonthRow(String shopAddress, KPIShopMonthStats stats, String label) {
    final monthLabel = '${_getMonthName(stats.month)} ${stats.year}';

    return Card(
      margin: const EdgeInsets.only(left: 40, right: 8, top: 2, bottom: 2),
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                Text(
                  monthLabel,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 2),
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
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Поиск магазина...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
          ),
        ),
        _isLoading
            ? const Expanded(
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              )
            : _filteredShops.isEmpty
                ? Expanded(
                    child: Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'Нет магазинов'
                            : 'Магазины не найдены',
                        style: const TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                    ),
                  )
                : Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _filteredShops.length,
                      itemBuilder: (context, index) {
                        final shop = _filteredShops[index];
                        final isExpanded = _expandedShops.contains(shop.address);
                        final monthlyStats = _monthlyStatsCache[shop.address];

                        // Ленивая загрузка: загружаем статистику когда элемент становится видимым
                        // НЕ добавляем в _loadingShops здесь - это делается внутри _loadMonthlyStats
                        if (monthlyStats == null && !_loadingShops.contains(shop.address)) {
                          _loadMonthlyStats(shop.address);
                        }

                        return Column(
                          children: [
                            // Главная строка магазина
                            Card(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    if (isExpanded) {
                                      _expandedShops.remove(shop.address);
                                    } else {
                                      _expandedShops.add(shop.address);
                                      if (!_monthlyStatsCache.containsKey(shop.address)) {
                                        _loadMonthlyStats(shop.address);
                                      }
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  child: Row(
                                    children: [
                                      // Иконка магазина
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: const Color(0xFF004D40),
                                        child: const Icon(
                                          Icons.store,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Адрес и показатели
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Адрес в одну строку
                                            Text(
                                              shop.address,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            // Показатели под адресом
                                            monthlyStats != null && monthlyStats.isNotEmpty
                                                ? _buildMonthIndicators(monthlyStats[0])
                                                : monthlyStats != null && monthlyStats.isEmpty
                                                    ? Text(
                                                        'Нет данных',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey[500],
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                      )
                                                    : const SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child: CircularProgressIndicator(strokeWidth: 2),
                                                      ),
                                          ],
                                        ),
                                      ),
                                      // Стрелка раскрытия
                                      Icon(
                                        isExpanded ? Icons.expand_less : Icons.expand_more,
                                        color: Colors.grey[600],
                                        size: 20,
                                      ),
                                    ],
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
