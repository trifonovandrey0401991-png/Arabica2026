import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/efficiency_data_model.dart';
import '../widgets/efficiency_common_widgets.dart';
import '../utils/efficiency_utils.dart';
import '../../referrals/services/referral_service.dart';
import '../../referrals/models/referral_stats_model.dart';
import '../../employees/services/employee_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

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
      // Загружаем всех сотрудников чтобы найти ID по имени
      final employees = await EmployeeService.getEmployees();

      // Ищем сотрудника по имени (entityId содержит имя сотрудника)
      final employee = employees.firstWhere(
        (e) => e.name.toLowerCase() == widget.summary.entityId.toLowerCase(),
        orElse: () => employees.firstWhere(
          (e) => e.name.toLowerCase().contains(widget.summary.entityId.toLowerCase()),
          orElse: () => throw Exception('Сотрудник не найден'),
        ),
      );

      // Получаем данные рефералов по ID сотрудника
      final points = await ReferralService.getEmployeePoints(employee.id);

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
      backgroundColor: _emeraldDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.text_snippet, color: _gold),
              title: Text('Копировать как текст', style: TextStyle(color: Colors.white)),
              subtitle: Text('Форматированный отчёт', style: TextStyle(color: Colors.white.withOpacity(0.5))),
              onTap: () {
                Navigator.pop(context);
                _exportAsText(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.table_chart, color: _gold),
              title: Text('Копировать как CSV', style: TextStyle(color: Colors.white)),
              subtitle: Text('Для Excel/Google Sheets', style: TextStyle(color: Colors.white.withOpacity(0.5))),
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
      SnackBar(
        content: Text('Отчёт скопирован в буфер обмена'),
        backgroundColor: _emerald,
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
      SnackBar(
        content: Text('CSV скопирован в буфер обмена'),
        backgroundColor: _emerald,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emeraldDark, _night],
            stops: [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom Row AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.summary.entityName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.ios_share, color: _gold, size: 22),
                      tooltip: 'Экспорт',
                      onPressed: () => _showExportMenu(context),
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EfficiencyDetailTotalCard(
                        summary: widget.summary,
                        monthName: widget.monthName,
                      ),
                      SizedBox(height: 16),
                      EfficiencyDetailCategoriesCard(summary: widget.summary),
                      SizedBox(height: 16),
                      _buildReferralPointsSection(),
                      _buildShopsCard(),
                      SizedBox(height: 16),
                      EfficiencyDetailRecentRecordsCard(
                        summary: widget.summary,
                        showEmployeeName: false, // Для сотрудника показываем адреса магазинов
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
      return SizedBox.shrink();
    }

    // Сортируем по баллам
    final sortedShops = pointsByShop.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'По магазинам',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: _gold,
            ),
          ),
          SizedBox(height: 12),
          ...sortedShops.map((entry) => _buildShopRow(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _buildShopRow(String shopAddress, double points) {
    final isPositive = points >= 0;
    final formattedPoints = isPositive
        ? '+${points.toStringAsFixed(2)}'
        : points.toStringAsFixed(2);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _emerald.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              Icons.store,
              size: 20,
              color: _gold,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              shopAddress,
              style: TextStyle(fontSize: 15.sp, color: Colors.white.withOpacity(0.9)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formattedPoints,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: isPositive ? Color(0xFF4CAF50) : Color(0xFFEF5350),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralPointsSection() {
    if (_isLoadingReferrals) {
      return SizedBox.shrink();
    }

    if (_referralPoints == null) return SizedBox.shrink();

    final hasCurrentMonth = _referralPoints!.currentMonthPoints > 0 ||
        _referralPoints!.currentMonthReferrals > 0;
    final hasPreviousMonth = _referralPoints!.previousMonthPoints > 0 ||
        _referralPoints!.previousMonthReferrals > 0;

    if (!hasCurrentMonth && !hasPreviousMonth) return SizedBox.shrink();

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
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildReferralPointsCard({
    required String title,
    required int points,
    required int referralsCount,
    required bool isPreviousMonth,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isPreviousMonth ? 0 : 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      padding: EdgeInsets.all(16.w),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _emerald.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(
              Icons.person_add_alt_outlined,
              color: _gold,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w500,
                    color: isPreviousMonth
                        ? Colors.white.withOpacity(0.5)
                        : Colors.white,
                  ),
                ),
                Text(
                  '$referralsCount ${_getReferralsLabel(referralsCount)}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '+$points',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: _gold,
            ),
          ),
          SizedBox(width: 4),
          Text(
            'балл${_getPointsEnding(points)}',
            style: TextStyle(
              fontSize: 12.sp,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
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
