import 'package:flutter/material.dart';
import '../services/referral_service.dart';
import '../models/referral_stats_model.dart';
import 'employee_referrals_detail_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница отчёта по приглашениям
class ReferralsReportPage extends StatefulWidget {
  const ReferralsReportPage({super.key});

  @override
  State<ReferralsReportPage> createState() => _ReferralsReportPageState();
}

class _ReferralsReportPageState extends State<ReferralsReportPage> {
  bool _isLoading = true;
  int _totalClients = 0;
  int _unassignedCount = 0;
  List<EmployeeReferralStats> _employeeStats = [];
  Map<String, int> _unviewedByEmployee = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        ReferralService.getAllStatsForCurrentUser(),
        ReferralService.getUnviewedByEmployee(),
      ]);

      final statsResult = results[0] as Map<String, dynamic>?;
      final unviewedResult = results[1] as Map<String, int>;

      if (!mounted) return;
      if (statsResult != null) {
        setState(() {
          _totalClients = statsResult['totalClients'] ?? 0;
          _unassignedCount = statsResult['unassignedCount'] ?? 0;
          _employeeStats = statsResult['employeeStats'] ?? [];
          _unviewedByEmployee = unviewedResult;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() {
          _error = 'Не удалось загрузить данные';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Отчет по приглашениям',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadData,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                                SizedBox(height: 16),
                                Text(_error!, style: TextStyle(color: Colors.white.withOpacity(0.7))),
                                SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadData,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.emerald,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text('Повторить'),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            color: AppColors.gold,
                            backgroundColor: AppColors.emeraldDark,
                            child: ListView(
                              padding: EdgeInsets.all(16.w),
                              children: [
                                // Общее количество клиентов — hero card
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [AppColors.emerald, AppColors.emeraldDark],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14.r),
                                    border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                                  ),
                                  padding: EdgeInsets.all(20.w),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Всего клиентов',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.5),
                                          fontSize: 16.sp,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        '$_totalClients',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 48.sp,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 16),

                                // Заголовок списка
                                Row(
                                  children: [
                                    Text(
                                      'Сотрудники',
                                      style: TextStyle(
                                        fontSize: 18.sp,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white.withOpacity(0.9),
                                      ),
                                    ),
                                    Spacer(),
                                    Text(
                                      'сегодня/месяц/прош./всего',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Colors.white.withOpacity(0.4),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),

                                // Список сотрудников
                                if (_employeeStats.isEmpty)
                                  Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(32.w),
                                      child: Text(
                                        'Нет данных о приглашениях',
                                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                                      ),
                                    ),
                                  )
                                else
                                  ..._employeeStats.map((stats) => _buildEmployeeCard(stats)),

                                SizedBox(height: 16),

                                // Неучтённые клиенты
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(14.r),
                                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(16.w),
                                    child: Row(
                                      children: [
                                        Icon(Icons.person_off, color: Colors.white.withOpacity(0.3)),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'Не учтённые клиенты',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white.withOpacity(0.5),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12.r),
                                          ),
                                          child: Text(
                                            '$_unassignedCount',
                                            style: TextStyle(
                                              fontSize: 16.sp,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white.withOpacity(0.7),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
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

  Widget _buildEmployeeCard(EmployeeReferralStats stats) {
    final unviewedCount = _unviewedByEmployee[stats.employeeId] ?? 0;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EmployeeReferralsDetailPage(
                  employeeId: stats.employeeId,
                  employeeName: stats.employeeName,
                  referralCode: stats.referralCode,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(14.r),
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.emerald,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '#${stats.referralCode}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stats.employeeName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        stats.statsString,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unviewedCount > 0) ...[
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Text(
                      '$unviewedCount',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                ],
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
