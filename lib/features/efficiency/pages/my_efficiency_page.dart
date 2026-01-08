import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/efficiency_data_model.dart';
import '../services/efficiency_data_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/user_role_service.dart';

/// Страница "Моя эффективность" для сотрудника
class MyEfficiencyPage extends StatefulWidget {
  const MyEfficiencyPage({super.key});

  @override
  State<MyEfficiencyPage> createState() => _MyEfficiencyPageState();
}

class _MyEfficiencyPageState extends State<MyEfficiencyPage> {
  bool _isLoading = true;
  EfficiencySummary? _summary;
  String? _error;
  String? _employeeName;
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
      // Получаем имя текущего сотрудника
      final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
      final roleData = await UserRoleService.loadUserRole();
      final employeeName = systemEmployeeName ?? roleData?.displayName;

      if (employeeName == null || employeeName.isEmpty) {
        setState(() {
          _error = 'Не удалось определить сотрудника';
          _isLoading = false;
        });
        return;
      }

      _employeeName = employeeName;

      // Загружаем данные эффективности за выбранный месяц
      final data = await EfficiencyDataService.loadMonthData(
        _selectedYear,
        _selectedMonth,
      );

      // Находим данные текущего сотрудника
      EfficiencySummary? mySummary;
      for (final summary in data.byEmployee) {
        if (summary.entityName == employeeName) {
          mySummary = summary;
          break;
        }
      }

      setState(() {
        _summary = mySummary;
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
        title: const Text('Моя эффективность'),
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

    if (_summary == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, size: 64, color: Colors.grey[400]),
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
              'Баллы появятся после оценки ваших отчетов',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            if (_employeeName != null) ...[
              const SizedBox(height: 16),
              Text(
                _employeeName!,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTotalCard(),
            const SizedBox(height: 16),
            _buildCategoriesCard(),
            const SizedBox(height: 16),
            _buildShopsCard(),
            const SizedBox(height: 16),
            _buildRecentRecordsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard() {
    final isPositive = _summary!.totalPoints >= 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              _getMonthName(_selectedMonth, _selectedYear),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _summary!.formattedTotal,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: isPositive ? Colors.green[700] : Colors.red[700],
              ),
            ),
            const Text(
              'баллов',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem(
                  '+${_summary!.earnedPoints.toStringAsFixed(1)}',
                  'Заработано',
                  Colors.green,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[300],
                ),
                _buildStatItem(
                  '-${_summary!.lostPoints.toStringAsFixed(1)}',
                  'Потеряно',
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoriesCard() {
    // Сортируем категории по баллам (от большего к меньшему по абсолютному значению)
    final sortedCategories = _summary!.pointsByCategory.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'По категориям',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 12),
            if (sortedCategories.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Нет данных',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ...sortedCategories.map((entry) => _buildCategoryRow(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow(EfficiencyCategory category, double points) {
    final isPositive = points >= 0;
    final formattedPoints = isPositive
        ? '+${points.toStringAsFixed(2)}'
        : points.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _getCategoryColor(category).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getCategoryIcon(category),
              size: 20,
              color: _getCategoryColor(category),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              category.displayName,
              style: const TextStyle(fontSize: 15),
            ),
          ),
          Text(
            formattedPoints,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isPositive ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(EfficiencyCategory category) {
    switch (category) {
      case EfficiencyCategory.shift:
        return Icons.swap_horiz;
      case EfficiencyCategory.recount:
        return Icons.inventory_2;
      case EfficiencyCategory.shiftHandover:
        return Icons.assignment_turned_in;
      case EfficiencyCategory.attendance:
        return Icons.access_time;
      case EfficiencyCategory.test:
        return Icons.quiz;
      case EfficiencyCategory.reviews:
        return Icons.star;
      case EfficiencyCategory.productSearch:
        return Icons.search;
      case EfficiencyCategory.rko:
        return Icons.receipt_long;
      case EfficiencyCategory.orders:
        return Icons.shopping_cart;
      case EfficiencyCategory.shiftPenalty:
        return Icons.warning;
    }
  }

  Color _getCategoryColor(EfficiencyCategory category) {
    switch (category) {
      case EfficiencyCategory.shift:
        return Colors.blue;
      case EfficiencyCategory.recount:
        return Colors.purple;
      case EfficiencyCategory.shiftHandover:
        return Colors.teal;
      case EfficiencyCategory.attendance:
        return Colors.orange;
      case EfficiencyCategory.test:
        return Colors.indigo;
      case EfficiencyCategory.reviews:
        return Colors.amber;
      case EfficiencyCategory.productSearch:
        return Colors.cyan;
      case EfficiencyCategory.rko:
        return Colors.brown;
      case EfficiencyCategory.orders:
        return Colors.green;
      case EfficiencyCategory.shiftPenalty:
        return Colors.red;
    }
  }

  Widget _buildShopsCard() {
    // Группируем записи по магазинам
    final Map<String, double> pointsByShop = {};
    for (final record in _summary!.records) {
      // Для штрафов берем shopAddress из rawValue
      String shop = record.shopAddress;
      if (shop.isEmpty && record.category == EfficiencyCategory.shiftPenalty) {
        if (record.rawValue is Map && record.rawValue['shopAddress'] != null) {
          shop = record.rawValue['shopAddress'];
        }
      }
      if (shop.isNotEmpty) {
        pointsByShop[shop] = (pointsByShop[shop] ?? 0) + record.points;
      }
    }

    if (pointsByShop.isEmpty) {
      return const SizedBox.shrink();
    }

    // Сортируем по баллам
    final sortedShops = pointsByShop.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'По магазинам',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 12),
            ...sortedShops.map((entry) => _buildShopRow(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildShopRow(String shopAddress, double points) {
    final isPositive = points >= 0;
    final formattedPoints = isPositive
        ? '+${points.toStringAsFixed(2)}'
        : points.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2F1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.store,
              size: 20,
              color: Color(0xFF004D40),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              shopAddress,
              style: const TextStyle(fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formattedPoints,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isPositive ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRecordsCard() {
    // Сортируем записи по дате (новые сначала)
    final sortedRecords = List<EfficiencyRecord>.from(_summary!.records)
      ..sort((a, b) => b.date.compareTo(a.date));

    // Берем последние 20 записей
    final recentRecords = sortedRecords.take(20).toList();

    return Card(
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
                  'Последние записи',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF004D40),
                  ),
                ),
                Text(
                  'Всего: ${_summary!.recordsCount}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recentRecords.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Нет записей',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ...recentRecords.map((record) => _buildRecordRow(record)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordRow(EfficiencyRecord record) {
    final dateFormat = DateFormat('dd.MM');
    final isPositive = record.points >= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 45,
            child: Text(
              dateFormat.format(record.date),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.categoryName,
                  style: const TextStyle(fontSize: 14),
                ),
                // Для штрафов берем shopAddress из rawValue
                Builder(builder: (context) {
                  String shop = record.shopAddress;
                  if (shop.isEmpty && record.category == EfficiencyCategory.shiftPenalty) {
                    if (record.rawValue is Map && record.rawValue['shopAddress'] != null) {
                      shop = record.rawValue['shopAddress'];
                    }
                  }
                  if (shop.isNotEmpty) {
                    return Text(
                      shop,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                      overflow: TextOverflow.ellipsis,
                    );
                  }
                  return const SizedBox.shrink();
                }),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${record.formattedRawValue})',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            record.formattedPoints,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isPositive ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }
}
