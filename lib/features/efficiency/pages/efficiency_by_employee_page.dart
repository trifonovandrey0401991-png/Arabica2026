import 'package:flutter/material.dart';
import '../models/efficiency_data_model.dart';
import '../services/efficiency_data_service.dart';
import '../widgets/efficiency_common_widgets.dart';
import '../utils/efficiency_utils.dart';
import 'employee_efficiency_detail_page.dart';
import '../../referrals/services/referral_service.dart';
import '../../referrals/models/referral_stats_model.dart';

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
  Map<String, EmployeeReferralPoints> _referralPointsByEmployee = {};
  bool _isLoadingReferrals = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await EfficiencyDataService.loadMonthData(
        _selectedYear,
        _selectedMonth,
        forceRefresh: forceRefresh,
      );
      setState(() {
        _data = data;
        _isLoading = false;
      });

      // Загружаем данные о приглашениях после основных данных
      _loadReferralPoints();
    } catch (e) {
      setState(() {
        _error = 'Ошибка загрузки данных: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadReferralPoints() async {
    if (_data == null || _data!.byEmployee.isEmpty) return;

    setState(() => _isLoadingReferrals = true);

    final employeeIds = _data!.byEmployee.map((s) => s.entityId).toList();

    try {
      final Map<String, EmployeeReferralPoints> pointsMap = {};

      // Загружаем данные для всех сотрудников параллельно
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('По сотрудникам'),
        backgroundColor: EfficiencyUtils.primaryColor,
        actions: [
          MonthPickerButton(
            selectedMonth: _selectedMonth,
            selectedYear: _selectedYear,
            onMonthSelected: (selection) {
              setState(() {
                _selectedYear = selection['year']!;
                _selectedMonth = selection['month']!;
              });
              _loadData();
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const EfficiencyLoadingState();
    }

    if (_error != null) {
      return EfficiencyErrorState(
        error: _error!,
        onRetry: _loadData,
      );
    }

    if (_data == null || _data!.byEmployee.isEmpty) {
      return EfficiencyEmptyState(
        monthName: EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
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
    return EfficiencySummaryCard(
      summaries: _data!.byEmployee,
      additionalInfo: '${_data!.byEmployee.length} сотрудников',
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
                monthName: EfficiencyUtils.getMonthName(_selectedMonth, _selectedYear),
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
              if (_referralPointsByEmployee.containsKey(summary.entityId) &&
                  (_referralPointsByEmployee[summary.entityId]!.currentMonthPoints > 0 ||
                   _referralPointsByEmployee[summary.entityId]!.currentMonthReferrals > 0))
                Padding(
                  padding: const EdgeInsets.only(left: 44, top: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_add_alt_outlined,
                        size: 14,
                        color: Colors.teal[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Приглашения: ${_referralPointsByEmployee[summary.entityId]!.currentMonthReferrals} клиент${_getReferralsEnding(_referralPointsByEmployee[summary.entityId]!.currentMonthReferrals)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '+${_referralPointsByEmployee[summary.entityId]!.currentMonthPoints}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal[600],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: EfficiencyProgressBar(summary: summary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getReferralsEnding(int count) {
    if (count % 10 == 1 && count % 100 != 11) return '';
    if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) {
      return 'а';
    }
    return 'ов';
  }
}
