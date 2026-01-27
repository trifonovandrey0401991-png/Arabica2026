import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/efficiency_data_model.dart';
import '../widgets/efficiency_common_widgets.dart';
import '../utils/efficiency_utils.dart';
import '../../referrals/services/referral_service.dart';
import '../../referrals/models/referral_stats_model.dart';

/// Страница детальной информации об эффективности сотрудника
class EmployeeEfficiencyDetailPage extends StatefulWidget {
  final EfficiencySummary summary;
  final String monthName;

  const EmployeeEfficiencyDetailPage({
    super.key,
    required this.summary,
    required this.monthName,
  });

  @override
  State<EmployeeEfficiencyDetailPage> createState() =>
      _EmployeeEfficiencyDetailPageState();
}

class _EmployeeEfficiencyDetailPageState
    extends State<EmployeeEfficiencyDetailPage> {
  EmployeeReferralPoints? _referralPoints;
  bool _isLoadingReferrals = true;

  @override
  void initState() {
    super.initState();
    _loadReferralPoints();
  }

  Future<void> _loadReferralPoints() async {
    setState(() => _isLoadingReferrals = true);
    try {
      final points =
          await ReferralService.getEmployeePoints(widget.summary.entityId);
      if (mounted) {
        setState(() {
          _referralPoints = points;
          _isLoadingReferrals = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingReferrals = false);
      }
    }
  }

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
      summary: widget.summary,
      monthName: widget.monthName,
      isShop: false,
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
      summary: widget.summary,
      monthName: widget.monthName,
      isShop: false,
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
        title: Text(widget.summary.entityName, overflow: TextOverflow.ellipsis),
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
              summary: widget.summary,
              monthName: widget.monthName,
            ),
            const SizedBox(height: 16),
            EfficiencyDetailCategoriesCard(summary: widget.summary),
            const SizedBox(height: 16),
            _buildReferralPointsSection(),
            _buildShopsCard(),
            const SizedBox(height: 16),
            EfficiencyDetailRecentRecordsCard(
              summary: widget.summary,
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
    for (final record in widget.summary.records) {
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

  Widget _buildReferralPointsSection() {
    if (_isLoadingReferrals) {
      return const SizedBox.shrink();
    }

    if (_referralPoints == null) return const SizedBox.shrink();

    final hasCurrentMonth = _referralPoints!.currentMonthPoints > 0 ||
        _referralPoints!.currentMonthReferrals > 0;
    final hasPreviousMonth = _referralPoints!.previousMonthPoints > 0 ||
        _referralPoints!.previousMonthReferrals > 0;

    if (!hasCurrentMonth && !hasPreviousMonth) return const SizedBox.shrink();

    return Column(
      children: [
        if (hasCurrentMonth)
          _buildReferralPointsCard(
            title: 'Приглашения клиентов',
            points: _referralPoints!.currentMonthPoints,
            referralsCount: _referralPoints!.currentMonthReferrals,
            isPreviousMonth: false,
          ),
        if (hasPreviousMonth)
          _buildReferralPointsCard(
            title: 'Приглашения (прошлый месяц)',
            points: _referralPoints!.previousMonthPoints,
            referralsCount: _referralPoints!.previousMonthReferrals,
            isPreviousMonth: true,
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildReferralPointsCard({
    required String title,
    required int points,
    required int referralsCount,
    required bool isPreviousMonth,
  }) {
    return Card(
      margin: EdgeInsets.only(bottom: isPreviousMonth ? 0 : 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.person_add_alt_outlined,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: isPreviousMonth ? Colors.grey[600] : Colors.black,
                    ),
                  ),
                  Text(
                    '$referralsCount ${_getReferralsLabel(referralsCount)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '+$points',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'балл${_getPointsEnding(points)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getReferralsLabel(int count) {
    if (count % 10 == 1 && count % 100 != 11) return 'клиент';
    if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) {
      return 'клиента';
    }
    return 'клиентов';
  }

  String _getPointsEnding(int points) {
    final abs = points.abs();
    if (abs % 10 == 1 && abs % 100 != 11) return '';
    if (abs % 10 >= 2 && abs % 10 <= 4 && (abs % 100 < 10 || abs % 100 >= 20)) {
      return 'а';
    }
    return 'ов';
  }
}
