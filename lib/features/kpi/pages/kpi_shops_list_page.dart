import 'package:flutter/material.dart';
import '../../shops/models/shop_model.dart';
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

        if (shops.isEmpty) {
          Logger.debug('Список магазинов пуст!');
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

                        return Column(
                          children: [
                            // Главная строка магазина
                            Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setState(() {
                                    if (isExpanded) {
                                      _expandedShops.remove(shop.address);
                                    } else {
                                      _expandedShops.add(shop.address);
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      // Иконка магазина
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF004D40),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.store,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Название магазина
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              shop.address,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (shop.name.isNotEmpty && shop.name != shop.address)
                                              Text(
                                                shop.name,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                      // Стрелка раскрытия
                                      Icon(
                                        isExpanded ? Icons.expand_less : Icons.expand_more,
                                        color: const Color(0xFF004D40),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Раскрытые строки месяцев
                            if (isExpanded) ...[
                              _buildMonthRow('Текущий месяц', _getCurrentMonth()),
                              _buildMonthRow('Прошлый месяц', _getPreviousMonth()),
                              _buildMonthRow('Позапрошлый месяц', _getTwoMonthsAgo()),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
      ],
    );
  }

  Widget _buildMonthRow(String label, String monthName) {
    return Card(
      margin: const EdgeInsets.only(left: 32, right: 8, top: 4, bottom: 4),
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF004D40).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.calendar_month,
            color: Color(0xFF004D40),
            size: 20,
          ),
        ),
        title: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          monthName,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
        onTap: () {
          // TODO: Переход к детальной статистике месяца
        },
      ),
    );
  }

  String _getCurrentMonth() {
    final now = DateTime.now();
    return _getMonthName(now.month) + ' ' + now.year.toString();
  }

  String _getPreviousMonth() {
    final now = DateTime.now();
    final prevMonth = now.month == 1 ? 12 : now.month - 1;
    final prevYear = now.month == 1 ? now.year - 1 : now.year;
    return _getMonthName(prevMonth) + ' ' + prevYear.toString();
  }

  String _getTwoMonthsAgo() {
    final now = DateTime.now();
    int month = now.month - 2;
    int year = now.year;
    if (month <= 0) {
      month += 12;
      year -= 1;
    }
    return _getMonthName(month) + ' ' + year.toString();
  }

  String _getMonthName(int month) {
    const months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    return months[month - 1];
  }
}
