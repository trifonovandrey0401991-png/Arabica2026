import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/efficiency_data_model.dart';

/// Страница детальной информации об эффективности сотрудника
class EmployeeEfficiencyDetailPage extends StatelessWidget {
  final EfficiencySummary summary;
  final String monthName;

  const EmployeeEfficiencyDetailPage({
    super.key,
    required this.summary,
    required this.monthName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(summary.entityName, overflow: TextOverflow.ellipsis),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: SingleChildScrollView(
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
    final isPositive = summary.totalPoints >= 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              monthName,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              summary.formattedTotal,
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
                  '+${summary.earnedPoints.toStringAsFixed(1)}',
                  'Заработано',
                  Colors.green,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey[300],
                ),
                _buildStatItem(
                  '-${summary.lostPoints.toStringAsFixed(1)}',
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
    final sortedCategories = summary.pointsByCategory.entries.toList()
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
    for (final record in summary.records) {
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
    final sortedRecords = List<EfficiencyRecord>.from(summary.records)
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
                  'Всего: ${summary.recordsCount}',
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
