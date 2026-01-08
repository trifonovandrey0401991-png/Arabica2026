import 'package:flutter/material.dart';
import '../models/efficiency_data_model.dart';
import '../services/efficiency_data_service.dart';
import 'employee_efficiency_detail_page.dart';

/// Страница списка эффективности по сотрудникам
class EfficiencyByEmployeePage extends StatefulWidget {
  const EfficiencyByEmployeePage({super.key});

  @override
  State<EfficiencyByEmployeePage> createState() => _EfficiencyByEmployeePageState();
}

class _EfficiencyByEmployeePageState extends State<EfficiencyByEmployeePage> {
  bool _isLoading = true;
  EfficiencyData? _data;
  String? _error;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await EfficiencyDataService.loadMonthData(
        _selectedYear,
        _selectedMonth,
      );
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки данных: $e';
        _isLoading = false;
      });
    }
  }

  void _showMonthPicker() async {
    final now = DateTime.now();
    final List<Map<String, dynamic>> months = [];

    // Генерируем последние 12 месяцев
    for (int i = 0; i < 12; i++) {
      final date = DateTime(now.year, now.month - i, 1);
      months.add({
        'year': date.year,
        'month': date.month,
        'name': _getMonthName(date.month, date.year),
      });
    }

    await showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Выберите месяц',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: months.length,
                itemBuilder: (context, index) {
                  final month = months[index];
                  final isSelected = month['year'] == _selectedYear &&
                      month['month'] == _selectedMonth;
                  return ListTile(
                    title: Text(
                      month['name'],
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color:
                            isSelected ? const Color(0xFF004D40) : Colors.black,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: Color(0xFF004D40))
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedYear = month['year'];
                        _selectedMonth = month['month'];
                      });
                      _loadData();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthName(int month, int year) {
    const months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    return '${months[month - 1]} $year';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('По сотрудникам'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          TextButton.icon(
            onPressed: _showMonthPicker,
            icon: const Icon(Icons.calendar_today, color: Colors.white, size: 18),
            label: Text(
              _getMonthName(_selectedMonth, _selectedYear),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF004D40)),
            SizedBox(height: 16),
            Text('Загрузка данных...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    if (_data == null || _data!.byEmployee.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Нет данных за ${_getMonthName(_selectedMonth, _selectedYear)}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Баллы появятся после оценки отчетов',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _data!.byEmployee.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildSummaryCard();
          }
          return _buildEmployeeCard(_data!.byEmployee[index - 1], index);
        },
      ),
    );
  }

  Widget _buildSummaryCard() {
    final totalEarned = _data!.byEmployee.fold(0.0, (sum, s) => sum + s.earnedPoints);
    final totalLost = _data!.byEmployee.fold(0.0, (sum, s) => sum + s.lostPoints);
    final total = totalEarned - totalLost;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFFE0F2F1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Общая статистика',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF004D40),
                  ),
                ),
                Text(
                  '${_data!.byEmployee.length} сотрудников',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat('+${totalEarned.toStringAsFixed(1)}', 'Заработано', Colors.green),
                _buildStat('-${totalLost.toStringAsFixed(1)}', 'Потеряно', Colors.red),
                _buildStat(
                  total >= 0 ? '+${total.toStringAsFixed(1)}' : total.toStringAsFixed(1),
                  'Итого',
                  total >= 0 ? const Color(0xFF004D40) : Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(EfficiencySummary summary, int position) {
    final isPositive = summary.totalPoints >= 0;

    // Определяем цвет медали для топ-3
    Color? medalColor;
    if (position == 1) medalColor = const Color(0xFFFFD700); // Золото
    if (position == 2) medalColor = const Color(0xFFC0C0C0); // Серебро
    if (position == 3) medalColor = const Color(0xFFCD7F32); // Бронза

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EmployeeEfficiencyDetailPage(
                summary: summary,
                monthName: _getMonthName(_selectedMonth, _selectedYear),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Позиция / Медаль
                  if (medalColor != null)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: medalColor.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.emoji_events,
                          color: medalColor,
                          size: 20,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$position',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      summary.entityName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isPositive ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      summary.formattedTotal,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Row(
                  children: [
                    Text(
                      '+${summary.earnedPoints.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green[600],
                      ),
                    ),
                    const Text(' / ', style: TextStyle(color: Colors.grey)),
                    Text(
                      '-${summary.lostPoints.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.red[600],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${summary.recordsCount} записей',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
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
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: _buildProgressBar(summary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(EfficiencySummary summary) {
    final total = summary.earnedPoints + summary.lostPoints;
    if (total == 0) return const SizedBox.shrink();

    final earnedPercent = summary.earnedPoints / total;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Row(
        children: [
          Expanded(
            flex: (earnedPercent * 100).round(),
            child: Container(
              height: 4,
              color: Colors.green[400],
            ),
          ),
          Expanded(
            flex: ((1 - earnedPercent) * 100).round(),
            child: Container(
              height: 4,
              color: Colors.red[400],
            ),
          ),
        ],
      ),
    );
  }
}
