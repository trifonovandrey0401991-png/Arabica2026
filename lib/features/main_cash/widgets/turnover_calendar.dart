import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../models/shop_cash_balance_model.dart';
import '../services/turnover_service.dart';

/// Виджет календаря оборота магазина
class TurnoverCalendarWidget extends StatefulWidget {
  final String shopAddress;

  const TurnoverCalendarWidget({
    super.key,
    required this.shopAddress,
  });

  @override
  State<TurnoverCalendarWidget> createState() => _TurnoverCalendarWidgetState();
}

class _TurnoverCalendarWidgetState extends State<TurnoverCalendarWidget> {
  late DateTime _selectedMonth;
  DateTime? _selectedDate;
  List<DayTurnover> _monthTurnover = [];
  TurnoverComparison? _comparison;
  bool _isLoading = true;
  bool _isLoadingComparison = false;

  static const List<String> _monthNames = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
  ];

  static const List<String> _weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _loadMonthTurnover();
  }

  Future<void> _loadMonthTurnover() async {
    setState(() => _isLoading = true);

    try {
      final turnover = await TurnoverService.getMonthTurnover(
        widget.shopAddress,
        _selectedMonth.year,
        _selectedMonth.month,
      );

      setState(() {
        _monthTurnover = turnover;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки оборота', e);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadComparison(DateTime date) async {
    setState(() {
      _selectedDate = date;
      _isLoadingComparison = true;
    });

    try {
      final comparison = await TurnoverService.getDayComparison(
        widget.shopAddress,
        date,
      );

      setState(() {
        _comparison = comparison;
        _isLoadingComparison = false;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки сравнения', e);
      setState(() => _isLoadingComparison = false);
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      _selectedDate = null;
      _comparison = null;
    });
    _loadMonthTurnover();
  }

  void _nextMonth() {
    final now = DateTime.now();
    final nextMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);

    // Не переходим в будущее
    if (nextMonth.isAfter(DateTime(now.year, now.month + 1))) return;

    setState(() {
      _selectedMonth = nextMonth;
      _selectedDate = null;
      _comparison = null;
    });
    _loadMonthTurnover();
  }

  DayTurnover? _getTurnoverForDay(int day) {
    try {
      return _monthTurnover.firstWhere(
        (t) => t.date.day == day &&
               t.date.month == _selectedMonth.month &&
               t.date.year == _selectedMonth.year,
      );
    } catch (e) {
      return null;
    }
  }

  String _formatAmount(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      final k = amount / 1000;
      return '${k.toStringAsFixed(k % 1 == 0 ? 0 : 1)}k';
    }
    return amount.toStringAsFixed(0);
  }

  String _formatFullAmount(double amount) {
    final formatter = amount.toStringAsFixed(0);
    final chars = formatter.split('');
    final result = <String>[];
    for (int i = 0; i < chars.length; i++) {
      if (i > 0 && (chars.length - i) % 3 == 0 && chars[i] != '-') {
        result.add(' ');
      }
      result.add(chars[i]);
    }
    return result.join('');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Заголовок с месяцем
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _previousMonth,
              ),
              Text(
                '${_monthNames[_selectedMonth.month - 1]} ${_selectedMonth.year}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _nextMonth,
              ),
            ],
          ),
        ),

        // Календарь
        Expanded(
          flex: 2,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildCalendar(),
        ),

        // Детали выбранного дня
        if (_selectedDate != null)
          Expanded(
            flex: 1,
            child: _buildDayDetails(),
          ),
      ],
    );
  }

  Widget _buildCalendar() {
    final firstDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final firstWeekday = firstDayOfMonth.weekday; // 1 = Monday

    return Column(
      children: [
        // Дни недели
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: _weekDays.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: day == 'Сб' || day == 'Вс' ? Colors.red[300] : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),

        // Дни месяца
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.8,
            ),
            itemCount: 42, // 6 недель x 7 дней
            itemBuilder: (context, index) {
              final day = index - firstWeekday + 2;

              if (day < 1 || day > lastDayOfMonth.day) {
                return const SizedBox();
              }

              final turnover = _getTurnoverForDay(day);
              final isSelected = _selectedDate?.day == day &&
                  _selectedDate?.month == _selectedMonth.month &&
                  _selectedDate?.year == _selectedMonth.year;
              final isToday = DateTime.now().day == day &&
                  DateTime.now().month == _selectedMonth.month &&
                  DateTime.now().year == _selectedMonth.year;
              final isFuture = DateTime(_selectedMonth.year, _selectedMonth.month, day)
                  .isAfter(DateTime.now());

              return InkWell(
                onTap: isFuture
                    ? null
                    : () => _loadComparison(
                          DateTime(_selectedMonth.year, _selectedMonth.month, day),
                        ),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF004D40)
                        : isToday
                            ? const Color(0xFF004D40).withOpacity(0.1)
                            : null,
                    borderRadius: BorderRadius.circular(8),
                    border: isToday && !isSelected
                        ? Border.all(color: const Color(0xFF004D40), width: 2)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        day.toString().padLeft(2, '0'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : isFuture
                                  ? Colors.grey[400]
                                  : null,
                        ),
                      ),
                      if (turnover != null && turnover.totalRevenue > 0)
                        Text(
                          _formatAmount(turnover.totalRevenue),
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected ? Colors.white70 : Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      else if (!isFuture)
                        Text(
                          '--',
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected ? Colors.white54 : Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDayDetails() {
    if (_isLoadingComparison) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_comparison == null) {
      return const Center(
        child: Text('Выберите день для просмотра'),
      );
    }

    final current = _comparison!.current;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Выбрано: ${current.formattedDate}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),

            // Оборот за день
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAmountChip('ООО', current.oooRevenue, Colors.blue),
                _buildAmountChip('ИП', current.ipRevenue, Colors.orange),
                _buildAmountChip('Итого', current.totalRevenue, const Color(0xFF004D40)),
              ],
            ),
            const SizedBox(height: 16),

            // Сравнение
            const Text(
              'Сравнение:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),

            if (_comparison!.weekAgo != null)
              _buildComparisonRow(
                'Нед. назад (${_comparison!.weekAgo!.formattedDate})',
                _comparison!.weekAgo!.totalRevenue,
                _comparison!.weekAgoChangePercent,
              ),

            if (_comparison!.monthAgo != null)
              _buildComparisonRow(
                'Мес. назад (${_comparison!.monthAgo!.formattedDate})',
                _comparison!.monthAgo!.totalRevenue,
                _comparison!.monthAgoChangePercent,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountChip(String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatFullAmount(amount)} \u20bd',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonRow(String label, double amount, double? changePercent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Row(
            children: [
              Text(
                '${_formatFullAmount(amount)} \u20bd',
                style: const TextStyle(fontSize: 13),
              ),
              if (changePercent != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: changePercent >= 0
                        ? Colors.green.withOpacity(0.1)
                        : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${changePercent >= 0 ? '+' : ''}${changePercent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: changePercent >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
