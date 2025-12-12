import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'shop_model.dart';
import 'kpi_service.dart';
import 'kpi_models.dart';
import 'kpi_shop_day_detail_dialog.dart';
import 'utils/logger.dart';

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Страница календаря KPI по магазину
class KPIShopCalendarPage extends StatefulWidget {
  const KPIShopCalendarPage({super.key});

  @override
  State<KPIShopCalendarPage> createState() => _KPIShopCalendarPageState();
}

class _KPIShopCalendarPageState extends State<KPIShopCalendarPage> {
  Shop? _selectedShop;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, KPIShopDayData> _dayDataCache = {};
  bool _isLoading = false;
  List<Shop> _shops = [];

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    try {
      setState(() => _isLoading = true);
      final shops = await Shop.loadShopsFromGoogleSheets();
      if (mounted) {
        setState(() {
          _shops = shops;
          _isLoading = false;
        });
        if (shops.isNotEmpty && _selectedShop == null) {
          _showShopSelection();
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showShopSelection() async {
    if (_shops.isEmpty) return;

    final shop = await showDialog<Shop>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите магазин'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _shops.length,
            itemBuilder: (context, index) {
              final shop = _shops[index];
              return ListTile(
                leading: Icon(shop.icon),
                title: Text(shop.name),
                subtitle: Text(shop.address),
                onTap: () => Navigator.pop(context, shop),
              );
            },
          ),
        ),
      ),
    );

    if (shop != null && mounted) {
      setState(() {
        _selectedShop = shop;
        _dayDataCache.clear();
      });
      _loadMonthData();
    }
  }

  Future<void> _loadMonthData() async {
    if (_selectedShop == null) return;

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      DateTime previousMonth;
      if (now.month == 1) {
        previousMonth = DateTime(now.year - 1, 12, 1);
      } else {
        previousMonth = DateTime(now.year, now.month - 1, 1);
      }

      // Собираем все даты для загрузки
      final datesToLoad = <DateTime>[];
      
      // Добавляем даты текущего месяца
      for (int day = 1; day <= 31; day++) {
        final date = DateTime(currentMonth.year, currentMonth.month, day);
        if (date.month != currentMonth.month) break;
        // Загружаем только если данных еще нет
        if (!_dayDataCache.containsKey(date)) {
          datesToLoad.add(date);
        }
      }

      // Добавляем даты предыдущего месяца
      for (int day = 1; day <= 31; day++) {
        final date = DateTime(previousMonth.year, previousMonth.month, day);
        if (date.month != previousMonth.month) break;
        // Загружаем только если данных еще нет
        if (!_dayDataCache.containsKey(date)) {
          datesToLoad.add(date);
        }
      }

      // Загружаем данные параллельно (пакетами по 5 для снижения нагрузки)
      const batchSize = 5;
      for (int i = 0; i < datesToLoad.length; i += batchSize) {
        final batch = datesToLoad.skip(i).take(batchSize).toList();
        final results = await Future.wait(
          batch.map((date) => KPIService.getShopDayData(
            _selectedShop!.address,
            date,
          ).catchError((e) {
            Logger.warning('Ошибка загрузки данных за ${date.year}-${date.month}-${date.day}');
            return null;
          })),
        );

        // Сохраняем результаты в кэш
        for (int j = 0; j < batch.length; j++) {
          if (results[j] != null) {
            _dayDataCache[batch[j]] = results[j]!;
          }
        }

        // Обновляем UI после каждого пакета
        if (mounted) {
          setState(() {});
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      Logger.error('Ошибка загрузки данных месяца', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<DateTime> _getWorkedDays() {
    return _dayDataCache.entries
        .where((entry) => entry.value.employeesWorkedCount > 0)
        .map((entry) => entry.key)
        .toList();
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!mounted) return;

    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });

    // Загружаем данные за день, если их нет в кэше
    if (!_dayDataCache.containsKey(selectedDay)) {
      _loadDayData(selectedDay);
    } else {
      _showDayDetail(selectedDay);
    }
  }

  Future<void> _loadDayData(DateTime date) async {
    if (_selectedShop == null) return;

    // Показываем индикатор загрузки только если данных совсем нет
    if (_dayDataCache.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final dayData = await KPIService.getShopDayData(
        _selectedShop!.address,
        date,
      );

      if (mounted) {
        setState(() {
          _dayDataCache[date] = dayData;
          _isLoading = false;
        });
        _showDayDetail(date);
      }
    } catch (e) {
      Logger.error('Ошибка загрузки данных за день', e);
      if (mounted) {
        setState(() => _isLoading = false);
        // Показываем диалог даже при ошибке (может быть пустым)
        _showDayDetail(date);
      }
    }
  }

  void _showDayDetail(DateTime date) {
    final dayData = _dayDataCache[date];
    if (dayData == null) return;

    showDialog(
      context: context,
      builder: (context) => KPIShopDayDetailDialog(dayData: dayData),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedShop?.name ?? 'Выберите магазин'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _dayDataCache.clear();
              _loadMonthData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.store),
            onPressed: _showShopSelection,
          ),
        ],
      ),
      body: _isLoading && _dayDataCache.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _selectedShop == null
              ? Center(
                  child: ElevatedButton(
                    onPressed: _showShopSelection,
                    child: const Text('Выбрать магазин'),
                  ),
                )
              : Column(
                  children: [
                    TableCalendar<KPIShopDayData>(
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2030, 12, 31),
                      focusedDay: _focusedDay,
                      selectedDayPredicate: (day) {
                        return isSameDay(_selectedDay, day);
                      },
                        eventLoader: (day) {
                          // Нормализуем дату для поиска в кэше
                          final normalizedDay = DateTime(day.year, day.month, day.day);
                          final dayData = _dayDataCache[normalizedDay];
                          if (dayData != null && dayData.employeesWorkedCount > 0) {
                            return [dayData];
                          }
                          return [];
                        },
                      calendarFormat: _calendarFormat,
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      calendarStyle: CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: const BoxDecoration(
                          color: Color(0xFF004D40),
                          shape: BoxShape.circle,
                        ),
                        markerDecoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        outsideDaysVisible: false,
                      ),
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: true,
                        titleCentered: true,
                      ),
                      onDaySelected: _onDaySelected,
                      onFormatChanged: (format) {
                        setState(() => _calendarFormat = format);
                      },
                      onPageChanged: (focusedDay) {
                        setState(() => _focusedDay = focusedDay);
                        _loadMonthData();
                      },
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Рабочий день'),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

