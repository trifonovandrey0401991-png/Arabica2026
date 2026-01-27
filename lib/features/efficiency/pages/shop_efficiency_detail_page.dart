import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/efficiency_data_model.dart';
import '../widgets/efficiency_common_widgets.dart';
import '../utils/efficiency_utils.dart';
import '../../referrals/services/referral_service.dart';
import '../../referrals/models/referral_stats_model.dart';

/// Страница детальной информации об эффективности магазина
class ShopEfficiencyDetailPage extends StatefulWidget {
  final EfficiencySummary summary;
  final String monthName;

  const ShopEfficiencyDetailPage({
    super.key,
    required this.summary,
    required this.monthName,
  });

  @override
  State<ShopEfficiencyDetailPage> createState() =>
      _ShopEfficiencyDetailPageState();
}

class _ShopEfficiencyDetailPageState extends State<ShopEfficiencyDetailPage> {
  Map<String, EmployeeReferralPoints> _referralPointsByEmployee = {};
  bool _isLoadingReferrals = true;

  @override
  void initState() {
    super.initState();
    _loadReferralPoints();
  }

  Future<void> _loadReferralPoints() async {
    setState(() => _isLoadingReferrals = true);

    // Получаем уникальных сотрудников из records
    final employeeIds = widget.summary.records
        .where((r) => r.employeeId.isNotEmpty)
        .map((r) => r.employeeId)
        .toSet();

    try {
      final Map<String, EmployeeReferralPoints> pointsMap = {};

      // Загружаем данные для каждого сотрудника параллельно
      await Future.wait(employeeIds.map((employeeId) async {
        try {
          final points = await ReferralService.getEmployeePoints(employeeId);
          if (points != null) {
            pointsMap[employeeId] = points;
          }
        } catch (e) {
          // Игнорируем ошибки для отдельных сотрудников
        }
      }));

      if (mounted) {
        setState(() {
          _referralPointsByEmployee = pointsMap;
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
      summary: widget.summary,
      monthName: widget.monthName,
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
            EfficiencyDetailRecentRecordsCard(
              summary: widget.summary,
              showEmployeeName: true, // Для магазина показываем имена сотрудников
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferralPointsSection() {
    if (_isLoadingReferrals || _referralPointsByEmployee.isEmpty) {
      return const SizedBox.shrink();
    }

    // Агрегируем баллы всех сотрудников магазина
    int totalCurrentMonthPoints = 0;
    int totalPreviousMonthPoints = 0;
    int totalCurrentMonthReferrals = 0;
    int totalPreviousMonthReferrals = 0;

    for (final points in _referralPointsByEmployee.values) {
      totalCurrentMonthPoints += points.currentMonthPoints;
      totalPreviousMonthPoints += points.previousMonthPoints;
      totalCurrentMonthReferrals += points.currentMonthReferrals;
      totalPreviousMonthReferrals += points.previousMonthReferrals;
    }

    final hasCurrentMonth = totalCurrentMonthPoints > 0 || totalCurrentMonthReferrals > 0;
    final hasPreviousMonth = totalPreviousMonthPoints > 0 || totalPreviousMonthReferrals > 0;

    if (!hasCurrentMonth && !hasPreviousMonth) return const SizedBox.shrink();

    return Column(
      children: [
        if (hasCurrentMonth)
          _buildReferralPointsCard(
            title: 'Приглашения клиентов',
            points: totalCurrentMonthPoints,
            referralsCount: totalCurrentMonthReferrals,
            isPreviousMonth: false,
          ),
        if (hasPreviousMonth)
          _buildReferralPointsCard(
            title: 'Приглашения (прошлый месяц)',
            points: totalPreviousMonthPoints,
            referralsCount: totalPreviousMonthReferrals,
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
                    '$referralsCount ${_getReferralsLabel(referralsCount)} (${_referralPointsByEmployee.length} ${_getEmployeesLabel(_referralPointsByEmployee.length)})',
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

  String _getEmployeesLabel(int count) {
    if (count % 10 == 1 && count % 100 != 11) return 'сотрудник';
    if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) {
      return 'сотрудника';
    }
    return 'сотрудников';
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
