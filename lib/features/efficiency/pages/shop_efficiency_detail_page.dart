import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  void _showExportMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_snippet),
              title: const Text('Копировать как текст'),
              subtitle: const Text('Форматированный отчёт'),
              onTap: () {
                Navigator.pop(context);
                _exportAsText(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Копировать как CSV'),
              subtitle: const Text('Для Excel/Google Sheets'),
              onTap: () {
                Navigator.pop(context);
                _exportAsCsv(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _exportAsText(BuildContext context) {
    final text = EfficiencyUtils.formatForExport(
      summary: summary,
      monthName: monthName,
      isShop: true,
    );
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Отчёт скопирован в буфер обмена'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _exportAsCsv(BuildContext context) {
    final csv = EfficiencyUtils.formatForExportCsv(
      summary: summary,
      monthName: monthName,
      isShop: true,
    );
    Clipboard.setData(ClipboardData(text: csv));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV скопирован в буфер обмена'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(summary.entityName, overflow: TextOverflow.ellipsis),
        backgroundColor: EfficiencyUtils.primaryColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Экспорт',
            onPressed: () => _showExportMenu(context),
          ),
        ],
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
