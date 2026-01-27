import 'package:flutter/material.dart';
import '../models/efficiency_data_model.dart';
import '../widgets/efficiency_common_widgets.dart';
import '../utils/efficiency_utils.dart';

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
        backgroundColor: EfficiencyUtils.primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EfficiencyDetailTotalCard(
              summary: summary,
              monthName: monthName,
            ),
            const SizedBox(height: 16),
            EfficiencyDetailCategoriesCard(summary: summary),
            const SizedBox(height: 16),
            _buildShopsCard(),
            const SizedBox(height: 16),
            EfficiencyDetailRecentRecordsCard(
              summary: summary,
              showEmployeeName: false, // Для сотрудника показываем адреса магазинов
            ),
          ],
        ),
      ),
    );
  }

  /// Карточка с баллами по магазинам (специфична для страницы сотрудника)
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
                color: EfficiencyUtils.primaryColor,
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
              color: EfficiencyUtils.secondaryColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.store,
              size: 20,
              color: EfficiencyUtils.primaryColor,
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
}
