import 'package:flutter/material.dart';
import '../models/efficiency_data_model.dart';
import '../widgets/efficiency_common_widgets.dart';
import '../utils/efficiency_utils.dart';

/// Страница детальной информации об эффективности магазина
class ShopEfficiencyDetailPage extends StatelessWidget {
  final EfficiencySummary summary;
  final String monthName;

  const ShopEfficiencyDetailPage({
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
            EfficiencyDetailRecentRecordsCard(
              summary: summary,
              showEmployeeName: true, // Для магазина показываем имена сотрудников
            ),
          ],
        ),
      ),
    );
  }
}
