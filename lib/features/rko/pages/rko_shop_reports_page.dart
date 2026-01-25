import 'package:flutter/material.dart';
import '../../shops/models/shop_model.dart';
import '../services/rko_reports_service.dart';
import 'rko_pdf_viewer_page.dart';
import '../../../core/utils/logger.dart';

/// Страница отчетов по магазинам
class RKOShopReportsPage extends StatefulWidget {
  const RKOShopReportsPage({super.key});

  @override
  State<RKOShopReportsPage> createState() => _RKOShopReportsPageState();
}

/// Группа РКО за один день
class RKODayGroup {
  final DateTime date;
  final String dayKey; // "YYYY-MM-DD"
  final List<dynamic> items;
  final double totalAmount;

  RKODayGroup({
    required this.date,
    required this.dayKey,
    required this.items,
    required this.totalAmount,
  });

  static const _monthsGenitive = ['', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
                                  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];

  String get displayTitle => '${date.day} ${_monthsGenitive[date.month]}';
  int get count => items.length;
}

/// Группа РКО за месяц
class RKOMonthGroup {
  final int year;
  final int month;
  final String monthKey; // "YYYY-MM"
  final List<RKODayGroup> days;
  final double totalAmount;
  final int totalCount;

  RKOMonthGroup({
    required this.year,
    required this.month,
    required this.monthKey,
    required this.days,
    required this.totalAmount,
    required this.totalCount,
  });

  static const _monthNames = ['', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
                              'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];

  String get displayTitle => _monthNames[month];
}

/// Группа РКО за год
class RKOYearGroup {
  final int year;
  final List<RKOMonthGroup> months;
  final double totalAmount;
  final int totalCount;

  RKOYearGroup({
    required this.year,
    required this.months,
    required this.totalAmount,
    required this.totalCount,
  });
}

class _RKOShopReportsPageState extends State<RKOShopReportsPage> {
  static const _primaryColor = Color(0xFF004D40);

  List<Shop> _shops = [];
  Shop? _selectedShop;
  List<dynamic> _currentMonthRKOs = [];
  List<dynamic> _months = [];
  bool _isLoading = true;

  // 3-уровневая иерархия
  List<RKODayGroup> _currentMonthDays = [];      // Дни текущего месяца (показываются напрямую)
  List<RKOMonthGroup> _previousMonths = [];      // Прошлые месяцы текущего года
  List<RKOYearGroup> _previousYears = [];        // Прошлые годы

  // Состояние раскрытия
  final Set<String> _expandedDays = {};    // "YYYY-MM-DD"
  final Set<String> _expandedMonths = {};  // "YYYY-MM"
  final Set<int> _expandedYears = {};      // year

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final shops = await Shop.loadShopsFromGoogleSheets();
      setState(() {
        _shops = shops;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadShopRKOs(String shopAddress) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await RKOReportsService.getShopRKOs(shopAddress);
      if (data != null) {
        setState(() {
          _currentMonthRKOs = data['currentMonth'] ?? [];
          _months = data['months'] ?? [];
          _buildHierarchy();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки РКО магазина', e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Построить 3-уровневую иерархию: год → месяц → день
  void _buildHierarchy() {
    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;

    final allRKOs = <dynamic>[];

    // Собираем все РКО
    allRKOs.addAll(_currentMonthRKOs);
    for (final monthData in _months) {
      final items = monthData['items'] as List<dynamic>? ?? [];
      allRKOs.addAll(items);
    }

    // Группируем по году → месяц → день
    // Map: year -> month -> day -> List<RKO>
    final hierarchy = <int, Map<int, Map<int, List<dynamic>>>>{};

    for (final rko in allRKOs) {
      final dateStr = rko['date']?.toString() ?? '';
      if (dateStr.isEmpty) continue;

      DateTime date;
      try {
        date = DateTime.parse(dateStr);
      } catch (e) {
        continue;
      }

      final year = date.year;
      final month = date.month;
      final day = date.day;

      hierarchy.putIfAbsent(year, () => {});
      hierarchy[year]!.putIfAbsent(month, () => {});
      hierarchy[year]![month]!.putIfAbsent(day, () => []);
      hierarchy[year]![month]![day]!.add(rko);
    }

    // Очищаем предыдущие данные
    _currentMonthDays = [];
    _previousMonths = [];
    _previousYears = [];

    // Обрабатываем иерархию
    final sortedYears = hierarchy.keys.toList()..sort((a, b) => b.compareTo(a));

    for (final year in sortedYears) {
      final monthsData = hierarchy[year]!;
      final sortedMonths = monthsData.keys.toList()..sort((a, b) => b.compareTo(a));

      if (year == currentYear) {
        // Текущий год - разделяем на текущий месяц и прошлые
        for (final month in sortedMonths) {
          final daysData = monthsData[month]!;
          final dayGroups = _buildDayGroups(year, month, daysData);

          if (month == currentMonth) {
            // Текущий месяц - дни показываются напрямую
            _currentMonthDays = dayGroups;
          } else {
            // Прошлые месяцы текущего года
            double totalAmount = 0;
            int totalCount = 0;
            for (final day in dayGroups) {
              totalAmount += day.totalAmount;
              totalCount += day.count;
            }
            _previousMonths.add(RKOMonthGroup(
              year: year,
              month: month,
              monthKey: '$year-${month.toString().padLeft(2, '0')}',
              days: dayGroups,
              totalAmount: totalAmount,
              totalCount: totalCount,
            ));
          }
        }
      } else {
        // Прошлые годы - группируем все месяцы под год
        final monthGroups = <RKOMonthGroup>[];
        double yearTotal = 0;
        int yearCount = 0;

        for (final month in sortedMonths) {
          final daysData = monthsData[month]!;
          final dayGroups = _buildDayGroups(year, month, daysData);

          double monthTotal = 0;
          int monthCount = 0;
          for (final day in dayGroups) {
            monthTotal += day.totalAmount;
            monthCount += day.count;
          }

          monthGroups.add(RKOMonthGroup(
            year: year,
            month: month,
            monthKey: '$year-${month.toString().padLeft(2, '0')}',
            days: dayGroups,
            totalAmount: monthTotal,
            totalCount: monthCount,
          ));

          yearTotal += monthTotal;
          yearCount += monthCount;
        }

        _previousYears.add(RKOYearGroup(
          year: year,
          months: monthGroups,
          totalAmount: yearTotal,
          totalCount: yearCount,
        ));
      }
    }
  }

  /// Создать группы дней из Map<day, List<RKO>>
  List<RKODayGroup> _buildDayGroups(int year, int month, Map<int, List<dynamic>> daysData) {
    final sortedDays = daysData.keys.toList()..sort((a, b) => b.compareTo(a));
    return sortedDays.map((day) {
      final items = daysData[day]!;
      double total = 0;
      for (final rko in items) {
        final amount = double.tryParse(rko['amount']?.toString() ?? '0') ?? 0;
        total += amount;
      }
      return RKODayGroup(
        date: DateTime(year, month, day),
        dayKey: '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
        items: items,
        totalAmount: total,
      );
    }).toList();
  }

  /// Построить плитку группы за день (иерархический список)
  Widget _buildDayGroupTile(RKODayGroup group) {
    final isExpanded = _expandedDays.contains(group.dayKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
          // Заголовок дня
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedDays.remove(group.dayKey);
                  } else {
                    _expandedDays.add(group.dayKey);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Иконка даты
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${group.date.day}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Информация о дне
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.displayTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D2D2D),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${group.totalAmount.toStringAsFixed(0)} руб.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Счётчик РКО
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _primaryColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${group.count}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Стрелка
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: _primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Раскрывающийся список сотрудников
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: group.items.map((rko) => _buildEmployeeRKOCard(rko)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Карточка РКО сотрудника (внутри раскрытой группы)
  Widget _buildEmployeeRKOCard(dynamic rko) {
    final fileName = rko['fileName'] ?? '';
    final employeeName = rko['employeeName'] ?? '';
    final amount = rko['amount']?.toString() ?? '';
    final rkoType = rko['rkoType'] ?? '';

    final isPdf = !fileName.toLowerCase().endsWith('.docx');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RKOPDFViewerPage(fileName: fileName),
              ),
            );
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Иконка документа
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isPdf ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded,
                    color: isPdf ? Colors.red : Colors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Имя сотрудника
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employeeName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2D2D2D),
                        ),
                      ),
                      if (rkoType.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: rkoType.contains('месяц')
                                ? Colors.blue.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            rkoType,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: rkoType.contains('месяц') ? Colors.blue : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Сумма
                if (amount.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$amount р.',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Плитка группы за месяц (уровень 2)
  Widget _buildMonthGroupTile(RKOMonthGroup month) {
    final isExpanded = _expandedMonths.contains(month.monthKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
          // Заголовок месяца
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedMonths.remove(month.monthKey);
                  } else {
                    _expandedMonths.add(month.monthKey);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Иконка месяца
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calendar_month,
                        color: Colors.blue,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Информация о месяце
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            month.displayTitle,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D2D2D),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${month.totalAmount.toStringAsFixed(0)} руб.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Счётчик РКО
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${month.totalCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.blue,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Раскрывающийся список дней
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: month.days.map((day) => _buildNestedDayTile(day)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Плитка группы за год (уровень 1)
  Widget _buildYearGroupTile(RKOYearGroup year) {
    final isExpanded = _expandedYears.contains(year.year);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
          // Заголовок года
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedYears.remove(year.year);
                  } else {
                    _expandedYears.add(year.year);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Иконка года
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '${year.year}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Информация о годе
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${year.year} год',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D2D2D),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${year.totalAmount.toStringAsFixed(0)} руб.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Счётчик РКО
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.purple,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${year.totalCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.purple,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Раскрывающийся список месяцев
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: year.months.map((month) => _buildNestedMonthTile(month)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Вложенная плитка месяца (внутри года)
  Widget _buildNestedMonthTile(RKOMonthGroup month) {
    final isExpanded = _expandedMonths.contains(month.monthKey);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedMonths.remove(month.monthKey);
                  } else {
                    _expandedMonths.add(month.monthKey);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.calendar_month,
                        color: Colors.blue,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        month.displayTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2D2D2D),
                        ),
                      ),
                    ),
                    Text(
                      '${month.totalAmount.toStringAsFixed(0)} р.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${month.totalCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.blue,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Раскрывающийся список дней
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: month.days.map((day) => _buildNestedDayTile(day)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Вложенная плитка дня (внутри месяца)
  Widget _buildNestedDayTile(RKODayGroup day) {
    final isExpanded = _expandedDays.contains(day.dayKey);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedDays.remove(day.dayKey);
                  } else {
                    _expandedDays.add(day.dayKey);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '${day.date.day}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _primaryColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        day.displayTitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '${day.totalAmount.toStringAsFixed(0)} р.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: _primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${day.count}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: _primaryColor,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Раскрывающийся список сотрудников
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Column(
                children: day.items.map((rko) => _buildEmployeeRKOCard(rko)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Общее количество документов
  int get _totalDocsCount {
    int count = 0;
    for (final day in _currentMonthDays) {
      count += day.count;
    }
    for (final month in _previousMonths) {
      count += month.totalCount;
    }
    for (final year in _previousYears) {
      count += year.totalCount;
    }
    return count;
  }

  // Общая сумма всех РКО
  double get _totalAmount {
    double total = 0;
    for (final day in _currentMonthDays) {
      total += day.totalAmount;
    }
    for (final month in _previousMonths) {
      total += month.totalAmount;
    }
    for (final year in _previousYears) {
      total += year.totalAmount;
    }
    return total;
  }

  // Проверка есть ли данные
  bool get _hasData => _currentMonthDays.isNotEmpty || _previousMonths.isNotEmpty || _previousYears.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // Выбор магазина - не трогаем
    if (_selectedShop == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Отчет по магазину'),
          backgroundColor: _primaryColor,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _shops.length,
                itemBuilder: (context, index) {
                  final shop = _shops[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: shop.leadingIcon,
                      title: Text(
                        shop.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(shop.address),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        setState(() {
                          _selectedShop = shop;
                        });
                        _loadShopRKOs(shop.address);
                      },
                    ),
                  );
                },
              ),
      );
    }

    // Детальный просмотр - улучшенный UI
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('История РКО'),
        backgroundColor: _primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _selectedShop = null;
              _currentMonthRKOs = [];
              _months = [];
            });
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadShopRKOs(_selectedShop!.address),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Шапка с информацией о магазине
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    children: [
                      // Иконка и название магазина
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.store_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedShop!.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Документов: $_totalDocsCount',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Сумма за текущий месяц
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.calendar_month_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Сумма всего',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.8),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_totalAmount.toStringAsFixed(0)} руб.',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 3-уровневый иерархический список
                Expanded(
                  child: !_hasData
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.receipt_long_outlined,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'РКО не найдены',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            // 1. Дни текущего месяца (показываются напрямую)
                            ..._currentMonthDays.map((day) => _buildDayGroupTile(day)),

                            // 2. Прошлые месяцы текущего года
                            ..._previousMonths.map((month) => _buildMonthGroupTile(month)),

                            // 3. Прошлые годы
                            ..._previousYears.map((year) => _buildYearGroupTile(year)),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}

/// Страница детального просмотра РКО магазина
class RKOShopDetailPage extends StatefulWidget {
  final String shopAddress;

  const RKOShopDetailPage({
    super.key,
    required this.shopAddress,
  });

  @override
  State<RKOShopDetailPage> createState() => _RKOShopDetailPageState();
}

class _RKOShopDetailPageState extends State<RKOShopDetailPage> {
  static const _primaryColor = Color(0xFF004D40);

  List<dynamic> _currentMonthRKOs = [];
  List<dynamic> _months = [];
  bool _isLoading = true;

  // 3-уровневая иерархия
  List<RKODayGroup> _currentMonthDays = [];
  List<RKOMonthGroup> _previousMonths = [];
  List<RKOYearGroup> _previousYears = [];

  // Состояние раскрытия
  final Set<String> _expandedDays = {};
  final Set<String> _expandedMonths = {};
  final Set<int> _expandedYears = {};

  @override
  void initState() {
    super.initState();
    _loadRKOs();
  }

  Future<void> _loadRKOs() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await RKOReportsService.getShopRKOs(widget.shopAddress);
      if (data != null) {
        setState(() {
          _currentMonthRKOs = data['currentMonth'] ?? [];
          _months = data['months'] ?? [];
          _buildHierarchy();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки РКО магазина', e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _buildHierarchy() {
    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonth = now.month;

    final allRKOs = <dynamic>[];

    allRKOs.addAll(_currentMonthRKOs);
    for (final monthData in _months) {
      final items = monthData['items'] as List<dynamic>? ?? [];
      allRKOs.addAll(items);
    }

    final hierarchy = <int, Map<int, Map<int, List<dynamic>>>>{};

    for (final rko in allRKOs) {
      final dateStr = rko['date']?.toString() ?? '';
      if (dateStr.isEmpty) continue;

      DateTime date;
      try {
        date = DateTime.parse(dateStr);
      } catch (e) {
        continue;
      }

      final year = date.year;
      final month = date.month;
      final day = date.day;

      hierarchy.putIfAbsent(year, () => {});
      hierarchy[year]!.putIfAbsent(month, () => {});
      hierarchy[year]![month]!.putIfAbsent(day, () => []);
      hierarchy[year]![month]![day]!.add(rko);
    }

    _currentMonthDays = [];
    _previousMonths = [];
    _previousYears = [];

    final sortedYears = hierarchy.keys.toList()..sort((a, b) => b.compareTo(a));

    for (final year in sortedYears) {
      final monthsData = hierarchy[year]!;
      final sortedMonths = monthsData.keys.toList()..sort((a, b) => b.compareTo(a));

      if (year == currentYear) {
        for (final month in sortedMonths) {
          final daysData = monthsData[month]!;
          final dayGroups = _buildDayGroups(year, month, daysData);

          if (month == currentMonth) {
            _currentMonthDays = dayGroups;
          } else {
            double totalAmount = 0;
            int totalCount = 0;
            for (final day in dayGroups) {
              totalAmount += day.totalAmount;
              totalCount += day.count;
            }
            _previousMonths.add(RKOMonthGroup(
              year: year,
              month: month,
              monthKey: '$year-${month.toString().padLeft(2, '0')}',
              days: dayGroups,
              totalAmount: totalAmount,
              totalCount: totalCount,
            ));
          }
        }
      } else {
        final monthGroups = <RKOMonthGroup>[];
        double yearTotal = 0;
        int yearCount = 0;

        for (final month in sortedMonths) {
          final daysData = monthsData[month]!;
          final dayGroups = _buildDayGroups(year, month, daysData);

          double monthTotal = 0;
          int monthCount = 0;
          for (final day in dayGroups) {
            monthTotal += day.totalAmount;
            monthCount += day.count;
          }

          monthGroups.add(RKOMonthGroup(
            year: year,
            month: month,
            monthKey: '$year-${month.toString().padLeft(2, '0')}',
            days: dayGroups,
            totalAmount: monthTotal,
            totalCount: monthCount,
          ));

          yearTotal += monthTotal;
          yearCount += monthCount;
        }

        _previousYears.add(RKOYearGroup(
          year: year,
          months: monthGroups,
          totalAmount: yearTotal,
          totalCount: yearCount,
        ));
      }
    }
  }

  List<RKODayGroup> _buildDayGroups(int year, int month, Map<int, List<dynamic>> daysData) {
    final sortedDays = daysData.keys.toList()..sort((a, b) => b.compareTo(a));
    return sortedDays.map((day) {
      final items = daysData[day]!;
      double total = 0;
      for (final rko in items) {
        final amount = double.tryParse(rko['amount']?.toString() ?? '0') ?? 0;
        total += amount;
      }
      return RKODayGroup(
        date: DateTime(year, month, day),
        dayKey: '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
        items: items,
        totalAmount: total,
      );
    }).toList();
  }

  int get _totalDocsCount {
    int count = 0;
    for (final day in _currentMonthDays) count += day.count;
    for (final month in _previousMonths) count += month.totalCount;
    for (final year in _previousYears) count += year.totalCount;
    return count;
  }

  double get _totalAmount {
    double total = 0;
    for (final day in _currentMonthDays) total += day.totalAmount;
    for (final month in _previousMonths) total += month.totalAmount;
    for (final year in _previousYears) total += year.totalAmount;
    return total;
  }

  bool get _hasData => _currentMonthDays.isNotEmpty || _previousMonths.isNotEmpty || _previousYears.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('История РКО'),
        backgroundColor: _primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRKOs,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Шапка
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.store_rounded, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.shopAddress,
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Документов: $_totalDocsCount',
                                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.payments_rounded, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Общая сумма выплат', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text('${_totalAmount.toStringAsFixed(0)} руб.', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Список
                Expanded(
                  child: !_hasData
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('РКО не найдены', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            ..._currentMonthDays.map((day) => _buildDayTile(day)),
                            ..._previousMonths.map((month) => _buildMonthTile(month)),
                            ..._previousYears.map((year) => _buildYearTile(year)),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildDayTile(RKODayGroup group) {
    final isExpanded = _expandedDays.contains(group.dayKey);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => isExpanded ? _expandedDays.remove(group.dayKey) : _expandedDays.add(group.dayKey)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: Center(child: Text('${group.date.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryColor))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(group.displayTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
                          const SizedBox(height: 4),
                          Text('${group.totalAmount.toStringAsFixed(0)} руб.', style: TextStyle(fontSize: 14, color: Colors.green[700], fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(16)),
                      child: Text('${group.count}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: _primaryColor),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(children: group.items.map((rko) => _buildRKOCard(rko)).toList()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthTile(RKOMonthGroup month) {
    final isExpanded = _expandedMonths.contains(month.monthKey);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => isExpanded ? _expandedMonths.remove(month.monthKey) : _expandedMonths.add(month.monthKey)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.calendar_month, color: Colors.blue, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(month.displayTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
                          const SizedBox(height: 4),
                          Text('${month.totalAmount.toStringAsFixed(0)} руб.', style: TextStyle(fontSize: 14, color: Colors.green[700], fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(16)),
                      child: Text('${month.totalCount}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.blue),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(children: month.days.map((day) => _buildNestedDayTile(day)).toList()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildYearTile(RKOYearGroup year) {
    final isExpanded = _expandedYears.contains(year.year);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => isExpanded ? _expandedYears.remove(year.year) : _expandedYears.add(year.year)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: Center(child: Text('${year.year}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.purple))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${year.year} год', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D2D2D))),
                          const SizedBox(height: 4),
                          Text('${year.totalAmount.toStringAsFixed(0)} руб.', style: TextStyle(fontSize: 14, color: Colors.green[700], fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(16)),
                      child: Text('${year.totalCount}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.purple),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(children: year.months.map((month) => _buildNestedMonthTile(month)).toList()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNestedDayTile(RKODayGroup day) {
    final isExpanded = _expandedDays.contains(day.dayKey);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => isExpanded ? _expandedDays.remove(day.dayKey) : _expandedDays.add(day.dayKey)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: _primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: Center(child: Text('${day.date.day}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _primaryColor))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(day.displayTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                    Text('${day.totalAmount.toStringAsFixed(0)} р.', style: TextStyle(fontSize: 12, color: Colors.green[700])),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(color: _primaryColor, borderRadius: BorderRadius.circular(8)),
                      child: Text('${day.count}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                    const SizedBox(width: 4),
                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: _primaryColor, size: 18),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), child: Column(children: day.items.map((rko) => _buildRKOCard(rko)).toList())),
          ],
        ],
      ),
    );
  }

  Widget _buildNestedMonthTile(RKOMonthGroup month) {
    final isExpanded = _expandedMonths.contains(month.monthKey);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade100)),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => isExpanded ? _expandedMonths.remove(month.monthKey) : _expandedMonths.add(month.monthKey)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.calendar_month, color: Colors.blue, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(month.displayTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF2D2D2D)))),
                    Text('${month.totalAmount.toStringAsFixed(0)} р.', style: TextStyle(fontSize: 13, color: Colors.green[700], fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(10)),
                      child: Text('${month.totalCount}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const SizedBox(width: 4),
                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.blue, size: 20),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: Column(children: month.days.map((day) => _buildNestedDayTile(day)).toList())),
          ],
        ],
      ),
    );
  }

  Widget _buildRKOCard(dynamic rko) {
    final fileName = rko['fileName'] ?? '';
    final employeeName = rko['employeeName'] ?? '';
    final amount = rko['amount']?.toString() ?? '';
    final rkoType = rko['rkoType'] ?? '';
    final isPdf = !fileName.toLowerCase().endsWith('.docx');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => RKOPDFViewerPage(fileName: fileName))),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: isPdf ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(isPdf ? Icons.picture_as_pdf_rounded : Icons.description_rounded, color: isPdf ? Colors.red : Colors.blue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employeeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF2D2D2D))),
                      if (rkoType.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: rkoType.contains('месяц') ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text(rkoType, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: rkoType.contains('месяц') ? Colors.blue : Colors.orange)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (amount.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('$amount р.', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green)),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
