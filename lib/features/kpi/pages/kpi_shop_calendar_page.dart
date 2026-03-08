import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/theme/app_colors.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../services/kpi_service.dart';
import '../models/kpi_models.dart';
import 'kpi_shop_day_detail_dialog.dart';
import 'kpi_shops_list_page.dart';
import '../../../core/utils/logger.dart';
import '../../../core/widgets/shop_icon.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/utils/cache_manager.dart';

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Страница KPI по магазинам с двумя вкладками: Все магазины и Магазин (календарь)
class KPIShopCalendarPage extends StatefulWidget {
  const KPIShopCalendarPage({super.key});

  @override
  State<KPIShopCalendarPage> createState() => _KPIShopCalendarPageState();
}

class _KPIShopCalendarPageState extends State<KPIShopCalendarPage>
    with SingleTickerProviderStateMixin {
  static const _cacheKey = 'kpi_shops';
  late TabController _tabController;

  // Состояние для вкладки "Магазин" (календарь)
  Shop? _selectedShop;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  final Map<DateTime, KPIShopDayData> _dayDataCache = {};
  bool _isLoading = false;
  List<Shop> _shops = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadShops();
  }

  void _onTabChanged() {
    // При переключении на вкладку "Магазин" показываем диалог выбора, если магазин не выбран
    if (_tabController.index == 1 && _selectedShop == null && _shops.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedShop == null) {
          _showShopSelection();
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadShops() async {
    // Check cache first
    final cached = CacheManager.get<List<Shop>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _shops = cached;
        _isLoading = false;
      });
    }

    try {
      if (mounted) setState(() => _isLoading = true);
      final shops = await ShopService.getShopsForCurrentUser();
      CacheManager.set(_cacheKey, shops);
      if (mounted) {
        setState(() {
          _shops = shops;
          _isLoading = false;
        });
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
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Custom AppBar for dialog
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                        ),
                      ),
                      SizedBox(width: 16),
                      Text(
                        'Выберите магазин',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.all(16.w),
                    itemCount: _shops.length,
                    itemBuilder: (context, index) {
                      final shop = _shops[index];
                      return Padding(
                        padding: EdgeInsets.only(bottom: 12.h),
                        child: Material(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12.r),
                            onTap: () => Navigator.pop(context, shop),
                            child: Container(
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                  width: 2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  ShopIcon(size: 56),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      shop.address,
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.white70,
                                    size: 28,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (shop != null && mounted) {
      if (mounted) setState(() {
        _selectedShop = shop;
        _dayDataCache.clear();
      });
      _loadMonthData();
    }
  }

  Future<void> _loadMonthData() async {
    if (_selectedShop == null) return;

    if (mounted) setState(() => _isLoading = true);

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

      // НЕ очищаем кэш - используем существующие данные где возможно
      // Кэш очищается только при явном обновлении (кнопка refresh)

      // Загружаем данные последовательно (по 2 за раз) с задержкой для избежания HTTP 429
      final batchSize = 2;
      for (int i = 0; i < datesToLoad.length; i += batchSize) {
        final batch = datesToLoad.skip(i).take(batchSize).toList();
        final results = await Future.wait<KPIShopDayData?>(
          batch.map((date) async {
            try {
              return await KPIService.getShopDayData(
                _selectedShop!.address,
                date,
              );
            } catch (e) {
              Logger.warning('Ошибка загрузки данных за ${date.year}-${date.month}-${date.day}: $e');
              return null;
            }
          }),
        );

        // Сохраняем результаты в локальный кэш
        for (int j = 0; j < batch.length; j++) {
          final dayData = results[j];
          if (dayData != null) {
            final date = batch[j];
            final normalizedDate = DateTime(date.year, date.month, date.day);
            _dayDataCache[normalizedDate] = dayData;
            if (dayData.employeesWorkedCount > 0) {
              Logger.debug('📅 Кэш: ${normalizedDate.day}.${normalizedDate.month}, сотр: ${dayData.employeesWorkedCount}, hasWorking: ${dayData.hasWorkingEmployees}');
            }
          }
        }

        // Обновляем UI после каждого пакета
        if (mounted) {
          setState(() {});
        }

        // Задержка между пакетами для избежания HTTP 429
        if (i + batchSize < datesToLoad.length) {
          await Future.delayed(Duration(milliseconds: 200));
        }
      }

      Logger.debug('📅 Всего дат в локальном кэше: ${_dayDataCache.length}');

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

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!mounted) return;

    Logger.debug('_onDaySelected вызван: ${selectedDay.year}-${selectedDay.month}-${selectedDay.day}');

    if (mounted) setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });

    // Нормализуем дату для поиска в кэше
    final normalizedDate = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);

    // Всегда показываем диалог с актуальными данными
    _showDayDetail(normalizedDate);
  }

  void _showDayDetail(DateTime date) async {
    Logger.debug('Открытие диалога для даты: ${date.year}-${date.month}-${date.day}');
    if (_selectedShop == null) return;

    final normalizedDate = DateTime(date.year, date.month, date.day);

    // Сначала проверяем локальный кэш - если данные есть, показываем сразу
    final cachedDayData = _dayDataCache[normalizedDate];
    if (cachedDayData != null) {
      Logger.debug('Показываем данные из кэша для ${date.year}-${date.month}-${date.day}');
      showDialog(
        context: context,
        builder: (context) => KPIShopDayDetailDialog(dayData: cachedDayData),
      );
      return;
    }

    // Если данных нет в кэше - загружаем
    try {
      Logger.debug('Загружаем данные с сервера для ${date.year}-${date.month}-${date.day}');
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
      // Показываем пустой диалог при ошибке
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки данных')),
        );
      }
    }
  }

  /// Получить цвет по статусу выполнения
  Color _getStatusColor(double status) {
    if (status == 1) return Colors.green; // Всё выполнено
    if (status == 0.5) return Colors.yellow; // Частично
    if (status == 0) return Colors.red; // Ничего не выполнено
    return Colors.grey.shade300; // Нет данных
  }

  Widget _buildDayCell({
    required BuildContext context,
    required DateTime date,
    required List<KPIShopDayData> events,
    required bool isSelected,
    required bool isToday,
    KPIShopDayData? dayData,
  }) {
    // Получаем статусы утренней и вечерней смены
    double morningStatus = -1;
    double eveningStatus = -1;

    if (dayData != null) {
      morningStatus = dayData.morningCompletionStatus;
      eveningStatus = dayData.eveningCompletionStatus;
    } else if (events.isNotEmpty) {
      morningStatus = events.first.morningCompletionStatus;
      eveningStatus = events.first.eveningCompletionStatus;
    }

    // Определяем цвета для утра и вечера
    final morningColor = _getStatusColor(morningStatus);
    final eveningColor = _getStatusColor(eveningStatus);

    // Есть ли данные
    final hasData = morningStatus >= 0 || eveningStatus >= 0;

    // Определяем цвет текста
    Color textColor = Colors.black;
    if (isSelected) {
      textColor = Colors.white;
    }

    // Бордер для выбранного/сегодня
    Border? border;
    if (isSelected) {
      border = Border.all(color: AppColors.emerald, width: 3);
    } else if (isToday) {
      border = Border.all(color: Colors.blue, width: 2);
    }

    // Создаем контейнер разделённый на 2 части
    return Container(
      margin: EdgeInsets.all(4.0.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        border: border,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6.r),
        child: hasData
            ? Column(
                children: [
                  // Утренняя смена (верх)
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      color: morningColor,
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 1.h),
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            color: morningStatus >= 0 ? Colors.black87 : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                            fontSize: 14.sp,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Вечерняя смена (низ)
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      color: eveningColor,
                    ),
                  ),
                ],
              )
            : Container(
                color: isSelected
                    ? AppColors.emerald
                    : (isToday ? Colors.blue.withOpacity(0.2) : Colors.transparent),
                child: Center(
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildCalendarView() {
    if (_selectedShop == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.store, size: 64, color: Colors.white54),
              SizedBox(height: 16),
              Text(
                'Выберите магазин для просмотра календаря',
                style: TextStyle(color: Colors.white70, fontSize: 16.sp),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _showShopSelection,
                icon: Icon(Icons.store),
                label: Text('Выбрать магазин'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Строка с выбранным магазином
        Padding(
          padding: EdgeInsets.all(8.0.w),
          child: InkWell(
            onTap: _showShopSelection,
            borderRadius: BorderRadius.circular(12.r),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  Icon(Icons.store, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedShop!.address,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
        // Календарь
        Expanded(
          child: _isLoading && _dayDataCache.isEmpty
              ? Center(child: CircularProgressIndicator(color: Colors.white))
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      Card(
                        margin: EdgeInsets.all(8.w),
                        child: TableCalendar<KPIShopDayData>(
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2030, 12, 31),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (day) {
                            return isSameDay(_selectedDay, day);
                          },
                          eventLoader: (day) {
                            final normalizedDay = DateTime(day.year, day.month, day.day);
                            final dayData = _dayDataCache[normalizedDay];
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
                              final eventsList = dayData != null && dayData.employeesWorkedCount > 0
                                  ? [dayData]
                                  : <KPIShopDayData>[];

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
                              return SizedBox.shrink();
                            },
                          ),
                          calendarStyle: CalendarStyle(
                            outsideDaysVisible: false,
                            cellPadding: EdgeInsets.all(8.w),
                            cellMargin: EdgeInsets.all(2.w),
                          ),
                          headerStyle: HeaderStyle(
                            formatButtonVisible: true,
                            titleCentered: true,
                          ),
                          onDaySelected: _onDaySelected,
                          onFormatChanged: (format) {
                            if (mounted) setState(() => _calendarFormat = format);
                          },
                          onPageChanged: (focusedDay) {
                            if (mounted) setState(() => _focusedDay = focusedDay);
                            _loadMonthData();
                          },
                        ),
                      ),
                      SizedBox(height: 16),
                      // Пример ячейки
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0.w),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 40,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.white54),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6.r),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        color: Colors.green,
                                        alignment: Alignment.bottomCenter,
                                        child: Padding(
                                          padding: EdgeInsets.only(bottom: 1.h),
                                          child: Text('1', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ),
                                    Expanded(child: Container(color: Colors.yellow)),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'Верх - утро, низ - вечер',
                                style: TextStyle(fontSize: 12.sp, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12),
                      // Легенда цветов
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0.w),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(4.r),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text('Всё выполнено', style: TextStyle(fontSize: 11.sp, color: Colors.white)),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: Colors.yellow,
                                    borderRadius: BorderRadius.circular(4.r),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text('Частично', style: TextStyle(fontSize: 11.sp, color: Colors.white)),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(4.r),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text('Не выполнено', style: TextStyle(fontSize: 11.sp, color: Colors.white)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
      ],
    );
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
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'KPI - Магазины',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        // Очищаем локальный кэш
                        _dayDataCache.clear();
                        // Очищаем кэш в KPIService для выбранного магазина
                        if (_selectedShop != null) {
                          KPIService.clearCacheForShop(_selectedShop!.address);
                        }
                        KPIService.clearCache();
                        // Перезагружаем данные
                        if (_tabController.index == 1 && _selectedShop != null) {
                          _loadMonthData();
                        } else {
                          if (mounted) setState(() {});
                        }
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              // TabBar
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.gold,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.5),
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: 'Все магазины'),
                    Tab(text: 'Магазин'),
                  ],
                ),
              ),
              SizedBox(height: 8),
              // Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Вкладка 1: Список всех магазинов
                    KPIShopsListPage(),
                    // Вкладка 2: Календарь
                    _buildCalendarView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
