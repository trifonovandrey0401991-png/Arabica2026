import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../shops/models/shop_model.dart';
import '../services/kpi_service.dart';
import '../models/kpi_models.dart';
import 'kpi_shop_day_detail_dialog.dart';
import '../../../core/utils/logger.dart';

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
                leading: shop.leadingIcon,
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
        datesToLoad.add(date);
      }

      // Добавляем даты предыдущего месяца
      for (int day = 1; day <= 31; day++) {
        final date = DateTime(previousMonth.year, previousMonth.month, day);
        if (date.month != previousMonth.month) break;
        datesToLoad.add(date);
      }
      
      // Очищаем кэш KPIService для всех дат, которые будем загружать
      for (final date in datesToLoad) {
        KPIService.clearCacheForDate(_selectedShop!.address, date);
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
            final date = batch[j];
            final isTargetDate = date.year == 2025 && date.month == 12 && date.day == 12;
            final normalizedDate = DateTime(date.year, date.month, date.day);
            _dayDataCache[normalizedDate] = results[j]!;
            if (isTargetDate) {
              Logger.debug('🔍 === Сохранение в кэш для 12.12.2025 ===');
              Logger.debug('   Ключ в кэше: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
              Logger.debug('   employeesWorkedCount: ${results[j]!.employeesWorkedCount}');
              Logger.debug('   hasMorningAttendance: ${results[j]!.hasMorningAttendance}');
              Logger.debug('   hasEveningAttendance: ${results[j]!.hasEveningAttendance}');
              Logger.debug('   === КОНЕЦ сохранения в кэш для 12.12.2025 ===');
            }
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

    // Очищаем кэш для этой даты перед загрузкой
    KPIService.clearCacheForDate(_selectedShop!.address, date);
    // Удаляем из локального кэша
    final normalizedDate = DateTime(date.year, date.month, date.day);
    _dayDataCache.remove(normalizedDate);

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
        final isTargetDate = normalizedDate.year == 2025 && normalizedDate.month == 12 && normalizedDate.day == 12;
        if (isTargetDate) {
          Logger.debug('🔍 === Сохранение в кэш при загрузке дня для 12.12.2025 ===');
          Logger.debug('   Ключ в кэше: ${normalizedDate.year}-${normalizedDate.month}-${normalizedDate.day}');
          Logger.debug('   employeesWorkedCount: ${dayData.employeesWorkedCount}');
          Logger.debug('   hasMorningAttendance: ${dayData.hasMorningAttendance}');
          Logger.debug('   hasEveningAttendance: ${dayData.hasEveningAttendance}');
          Logger.debug('   === КОНЕЦ сохранения в кэш для 12.12.2025 ===');
        }
        setState(() {
          _dayDataCache[normalizedDate] = dayData;
          _isLoading = false;
        });
        _showDayDetail(normalizedDate);
      }
    } catch (e) {
      Logger.error('Ошибка загрузки данных за день', e);
      if (mounted) {
        setState(() => _isLoading = false);
        // Показываем диалог даже при ошибке (может быть пустым)
        _showDayDetail(normalizedDate);
      }
    }
  }

  void _showDayDetail(DateTime date) async {
    // Всегда перезагружаем данные при открытии диалога, чтобы получить актуальные данные с РКО
    Logger.debug('🔍 Открытие диалога для даты: ${date.year}-${date.month}-${date.day}');
    if (_selectedShop == null) return;
    
    // Очищаем кэш для этой даты перед загрузкой
    KPIService.clearCacheForDate(_selectedShop!.address, date);
    final normalizedDate = DateTime(date.year, date.month, date.day);
    _dayDataCache.remove(normalizedDate);
    
    try {
      // Загружаем свежие данные
      final dayData = await KPIService.getShopDayData(
        _selectedShop!.address,
        date,
      );
      
      if (mounted) {
        setState(() {
          _dayDataCache[normalizedDate] = dayData;
        });
        
        showDialog(
          context: context,
          builder: (context) => KPIShopDayDetailDialog(dayData: dayData),
        );
      }
    } catch (e) {
      Logger.error('Ошибка загрузки данных для диалога', e);
      // Показываем диалог с данными из кэша, если они есть
      final cachedDayData = _dayDataCache[normalizedDate];
      if (cachedDayData != null && mounted) {
        showDialog(
          context: context,
          builder: (context) => KPIShopDayDetailDialog(dayData: cachedDayData),
        );
      }
    }
  }

  Widget _buildDayCell({
    required BuildContext context,
    required DateTime date,
    required List<KPIShopDayData> events,
    required bool isSelected,
    required bool isToday,
    KPIShopDayData? dayData,
  }) {
    // Определяем статус выполнения всех действий
    bool allCompleted = false;
    bool hasWorking = false;
    
    final isTargetDate = date.year == 2025 && date.month == 12 && date.day == 12;
    
    if (dayData != null) {
      allCompleted = dayData.allActionsCompleted;
      hasWorking = dayData.hasWorkingEmployees;
      if (isTargetDate) {
        Logger.debug('🔍 === ОТРИСОВКА 12.12.2025 ===');
        Logger.debug('   dayData не null');
        Logger.debug('   Сотрудников: ${dayData.employeesWorkedCount}');
        Logger.debug('   Все действия выполнены: $allCompleted');
        Logger.debug('   Есть работающие сотрудники: $hasWorking');
        Logger.debug('   Всего записей сотрудников: ${dayData.employeesData.length}');
        for (var emp in dayData.employeesData) {
          Logger.debug('      - ${emp.employeeName}: приход=${emp.attendanceTime != null}, пересменка=${emp.hasShift}, пересчет=${emp.hasRecount}, РКО=${emp.hasRKO}');
        }
        Logger.debug('   === КОНЕЦ ОТРИСОВКИ 12.12.2025 ===');
      }
      Logger.debug('🎨 _buildDayCell для ${date.year}-${date.month}-${date.day}: все выполнено=$allCompleted, есть работающие=$hasWorking, сотрудников=${dayData.employeesWorkedCount}');
    } else if (events.isNotEmpty) {
      allCompleted = events.first.allActionsCompleted;
      hasWorking = events.first.hasWorkingEmployees;
      if (isTargetDate) {
        Logger.debug('🔍 === ОТРИСОВКА 12.12.2025 (через events) ===');
        Logger.debug('   events не пуст');
        Logger.debug('   Все действия выполнены: $allCompleted');
        Logger.debug('   Есть работающие сотрудники: $hasWorking');
        Logger.debug('   === КОНЕЦ ОТРИСОВКИ 12.12.2025 ===');
      }
      Logger.debug('🎨 _buildDayCell для ${date.year}-${date.month}-${date.day}: используем events, все выполнено=$allCompleted, есть работающие=$hasWorking');
    } else {
      if (isTargetDate) {
        Logger.debug('🔍 === ОТРИСОВКА 12.12.2025: НЕТ ДАННЫХ ===');
      }
      Logger.debug('🎨 _buildDayCell для ${date.year}-${date.month}-${date.day}: нет данных');
    }

    // Определяем цвет круга
    Color circleColor = Colors.transparent;
    if (hasWorking) {
      if (allCompleted) {
        circleColor = Colors.green; // Все выполнено - зеленый
      } else {
        circleColor = Colors.yellow; // Что-то не выполнено - желтый
      }
    }

    // Определяем цвета фона и текста
    Color backgroundColor = Colors.white;
    Color textColor = Colors.black;
    
    if (isSelected) {
      backgroundColor = const Color(0xFF004D40);
      textColor = Colors.white;
    } else if (isToday) {
      backgroundColor = Colors.blue.withOpacity(0.3);
    }

    // Логирование для отладки
    if (hasWorking) {
      Logger.debug('🎨 Отрисовка ячейки ${date.year}-${date.month}-${date.day}: все выполнено=$allCompleted, цвет=${circleColor == Colors.green ? "зеленый" : circleColor == Colors.yellow ? "желтый" : "прозрачный"}');
    }
    
    // Создаем контейнер с кругом
    return Container(
      margin: const EdgeInsets.all(6.0),
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: circleColor != Colors.transparent ? circleColor : Colors.grey.shade300,
          width: circleColor != Colors.transparent ? 2 : 1,
        ),
      ),
      child: circleColor != Colors.transparent
          ? Container(
              decoration: BoxDecoration(
                color: circleColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                '${date.day}',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
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
              // Очищаем локальный кэш
              _dayDataCache.clear();
              // Очищаем кэш в KPIService для выбранного магазина
              if (_selectedShop != null) {
                KPIService.clearCacheForShop(_selectedShop!.address);
              }
              // Перезагружаем данные
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
                        final isTargetDate = normalizedDay.year == 2025 && normalizedDay.month == 12 && normalizedDay.day == 12;
                        final dayData = _dayDataCache[normalizedDay];
                        if (isTargetDate) {
                          Logger.debug('🔍 === eventLoader для 12.12.2025 ===');
                          Logger.debug('   normalizedDay: ${normalizedDay.year}-${normalizedDay.month}-${normalizedDay.day}');
                          Logger.debug('   dayData в кэше: ${dayData != null}');
                          if (dayData != null) {
                            Logger.debug('   employeesWorkedCount: ${dayData.employeesWorkedCount}');
                            Logger.debug('   hasMorningAttendance: ${dayData.hasMorningAttendance}');
                            Logger.debug('   hasEveningAttendance: ${dayData.hasEveningAttendance}');
                          }
                          Logger.debug('   === КОНЕЦ eventLoader для 12.12.2025 ===');
                        }
                        if (dayData != null && dayData.employeesWorkedCount > 0) {
                          return [dayData];
                        }
                        return [];
                      },
                      calendarFormat: _calendarFormat,
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      calendarBuilders: CalendarBuilders<KPIShopDayData>(
                        defaultBuilder: (context, date, focusedDay) {
                          final normalizedDay = DateTime(date.year, date.month, date.day);
                          final dayData = _dayDataCache[normalizedDay];
                          // Получаем события из кэша (как в eventLoader)
                          final eventsList = dayData != null && dayData.employeesWorkedCount > 0
                              ? [dayData]
                              : <KPIShopDayData>[];
                          
                          // Логирование для отладки
                          if (dayData != null && dayData.employeesWorkedCount > 0) {
                            Logger.debug('📅 Календарь: ${date.year}-${date.month}-${date.day}, утро=${dayData.hasMorningAttendance}, вечер=${dayData.hasEveningAttendance}, сотрудников=${dayData.employeesWorkedCount}');
                          }
                          
                          return _buildDayCell(
                            context: context,
                            date: date,
                            events: eventsList,
                            isSelected: false,
                            isToday: false,
                            dayData: dayData,
                          );
                        },
                        todayBuilder: (context, date, focusedDay) {
                          final normalizedDay = DateTime(date.year, date.month, date.day);
                          final dayData = _dayDataCache[normalizedDay];
                          final isSelected = isSameDay(_selectedDay, date);
                          // Получаем события из кэша (как в eventLoader)
                          final eventsList = dayData != null && dayData.employeesWorkedCount > 0
                              ? [dayData]
                              : <KPIShopDayData>[];
                          return _buildDayCell(
                            context: context,
                            date: date,
                            events: eventsList,
                            isSelected: isSelected,
                            isToday: true,
                            dayData: dayData,
                          );
                        },
                        selectedBuilder: (context, date, focusedDay) {
                          final normalizedDay = DateTime(date.year, date.month, date.day);
                          final dayData = _dayDataCache[normalizedDay];
                          // Получаем события из кэша (как в eventLoader)
                          final eventsList = dayData != null && dayData.employeesWorkedCount > 0
                              ? [dayData]
                              : <KPIShopDayData>[];
                          return _buildDayCell(
                            context: context,
                            date: date,
                            events: eventsList,
                            isSelected: true,
                            isToday: false,
                            dayData: dayData,
                          );
                        },
                        markerBuilder: (context, date, events) {
                          // Маркеры не нужны, используем цветные круги
                          return const SizedBox.shrink();
                        },
                      ),
                      calendarStyle: CalendarStyle(
                        outsideDaysVisible: false,
                        cellPadding: const EdgeInsets.all(8),
                        cellMargin: const EdgeInsets.all(2),
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
                      child: Wrap(
                        spacing: 24,
                        runSpacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Все выполнено', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.yellow,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Что-то не выполнено', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

