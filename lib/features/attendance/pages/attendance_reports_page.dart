import 'package:flutter/material.dart';
import 'dart:async';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/cache_manager.dart';
import '../models/shop_attendance_summary.dart';
import '../services/attendance_report_service.dart';
import '../../../core/services/report_notification_service.dart';
import 'attendance_month_page.dart';
import 'attendance_employee_detail_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница отчётов по приходам с 4 вкладками
class AttendanceReportsPage extends StatefulWidget {
  const AttendanceReportsPage({super.key});

  @override
  State<AttendanceReportsPage> createState() => _AttendanceReportsPageState();
}

class _AttendanceReportsPageState extends State<AttendanceReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Данные для вкладок
  List<EmployeeAttendanceSummary> _employeesSummary = [];
  List<ShopAttendanceSummary> _shopsSummary = [];

  bool _isLoading = true;
  String? _error;

  // Состояние UI
  final Set<String> _expandedShops = {};
  String _searchQuery = '';
  Timer? _searchDebounce;


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllData();
    // Отмечаем уведомления как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.attendance);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  static const _cacheKey = 'page_attendance_reports';

  Future<void> _loadAllData() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _employeesSummary = cached['employees'] as List<EmployeeAttendanceSummary>;
        _shopsSummary = cached['shops'] as List<ShopAttendanceSummary>;
        _isLoading = false;
      });
    }

    // Step 2: Fetch fresh data from server
    try {
      final results = await Future.wait([
        AttendanceReportService.getEmployeesSummary(),
        AttendanceReportService.getShopsSummary(),
      ]);

      if (mounted) {
        setState(() {
          _employeesSummary = results[0] as List<EmployeeAttendanceSummary>;
          _shopsSummary = results[1] as List<ShopAttendanceSummary>;
          _isLoading = false;
          _error = null;
        });
      }

      // Step 3: Save to cache
      CacheManager.set(_cacheKey, {
        'employees': _employeesSummary,
        'shops': _shopsSummary,
      });
    } catch (e) {
      if (mounted && _employeesSummary.isEmpty) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
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
              _buildHeader(),
              _buildTabButtons(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Отчёты по приходам',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadAllData,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButtons() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(child: _buildTabButton(0, 'По сотрудникам', Icons.people)),
          SizedBox(width: 8),
          Expanded(child: _buildTabButton(1, 'По магазинам', Icons.store)),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _tabController.index == index;
    return GestureDetector(
      onTap: () {
        if (mounted) setState(() {
          _tabController.animateTo(index);
        });
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.gold.withOpacity(0.15) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppColors.gold : Colors.white,
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.gold : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12.sp,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    if (_error != null) {
      return _buildErrorView();
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildEmployeesTab(),
        _buildShopsTab(),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 48),
            SizedBox(height: 16),
            Text(
              'Ошибка загрузки',
              style: TextStyle(color: Colors.white, fontSize: 18.sp),
            ),
            SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.white70, fontSize: 14.sp),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadAllData,
              icon: Icon(Icons.refresh),
              label: Text('Повторить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ВКЛАДКА 1: ПО СОТРУДНИКАМ ====================

  Widget _buildEmployeesTab() {
    return Column(
      children: [
        // Поиск
        Container(
          margin: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: TextField(
            onChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(Duration(milliseconds: 300), () {
                if (mounted) setState(() => _searchQuery = value);
              });
            },
            style: TextStyle(color: Colors.white),
            cursorColor: AppColors.gold,
            decoration: InputDecoration(
              hintText: 'Поиск по имени...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(Icons.search, color: AppColors.gold),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            ),
          ),
        ),
        // Список сотрудников
        Expanded(
          child: _buildEmployeesList(),
        ),
      ],
    );
  }

  Widget _buildEmployeesList() {
    var filtered = _employeesSummary;
    if (_searchQuery.isNotEmpty) {
      filtered = _employeesSummary
          .where((e) => e.employeeName.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.white.withOpacity(0.5)),
            SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty ? 'Сотрудники не найдены' : 'Нет данных',
              style: TextStyle(color: Colors.white, fontSize: 16.sp),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        itemCount: filtered.length,
        itemBuilder: (context, index) => _buildEmployeeCard(filtered[index]),
      ),
    );
  }

  Widget _buildEmployeeCard(EmployeeAttendanceSummary summary) {
    final onTimeRate = summary.onTimeRate;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
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
                builder: (context) => AttendanceEmployeeDetailPage(
                  employeeName: summary.employeeName,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(14.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                // Аватар
                CircleAvatar(
                  radius: 24,
                  backgroundColor: summary.hasTodayAttendance
                      ? Colors.green.withOpacity(0.15)
                      : Colors.red.withOpacity(0.15),
                  child: Icon(
                    summary.hasTodayAttendance ? Icons.check : Icons.close,
                    color: summary.hasTodayAttendance ? Colors.green : Colors.red,
                  ),
                ),
                SizedBox(width: 16),
                // Инфо
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        summary.employeeName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.sp,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          _buildMiniChip(
                            'Сегодня: ${summary.todayCount}',
                            summary.hasTodayAttendance ? Colors.green : Colors.red,
                          ),
                          SizedBox(width: 8),
                          _buildMiniChip(
                            '${onTimeRate.toStringAsFixed(0)}% вовремя',
                            _getOnTimeColor(onTimeRate),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Стрелка
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.sp,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ==================== ВКЛАДКА 2: ПО МАГАЗИНАМ ====================

  Widget _buildShopsTab() {
    if (_shopsSummary.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store, size: 64, color: Colors.white.withOpacity(0.5)),
            SizedBox(height: 16),
            Text(
              'Нет данных о магазинах',
              style: TextStyle(color: Colors.white, fontSize: 16.sp),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: _shopsSummary.length,
        itemBuilder: (context, index) => _buildShopCard(_shopsSummary[index]),
      ),
    );
  }

  Widget _buildShopCard(ShopAttendanceSummary summary) {
    final isExpanded = _expandedShops.contains(summary.shopAddress);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Заголовок магазина
          ListTile(
            leading: CircleAvatar(
              backgroundColor: summary.isTodayComplete
                  ? Colors.green
                  : summary.todayAttendanceCount > 0
                      ? Colors.orange
                      : Colors.red.shade300,
              child: Icon(Icons.store, color: Colors.white),
            ),
            title: Text(
              summary.shopAddress,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.sp,
                color: Colors.white.withOpacity(0.9),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: summary.isTodayComplete
                          ? Colors.green.withOpacity(0.1)
                          : summary.todayAttendanceCount > 0
                              ? Colors.orange.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: summary.isTodayComplete
                            ? Colors.green
                            : summary.todayAttendanceCount > 0
                                ? Colors.orange
                                : Colors.red.shade300,
                      ),
                    ),
                    child: Text(
                      'Сегодня: ${summary.todayAttendanceCount} ${_getEnding(summary.todayAttendanceCount)}',
                      style: TextStyle(
                        color: summary.isTodayComplete
                            ? Colors.green
                            : summary.todayAttendanceCount > 0
                                ? Colors.orange
                                : Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  if (summary.totalRecords > 0)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: _getOnTimeColor(summary.onTimeRate).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: _getOnTimeColor(summary.onTimeRate),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 12,
                            color: _getOnTimeColor(summary.onTimeRate),
                          ),
                          SizedBox(width: 4),
                          Text(
                            '${summary.onTimeRate.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: _getOnTimeColor(summary.onTimeRate),
                              fontWeight: FontWeight.w600,
                              fontSize: 12.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: AppColors.gold,
            ),
            onTap: () {
              if (mounted) setState(() {
                if (isExpanded) {
                  _expandedShops.remove(summary.shopAddress);
                } else {
                  _expandedShops.add(summary.shopAddress);
                }
              });
            },
          ),
          // Месяцы
          if (isExpanded) ...[
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            _buildMonthTile('Текущий месяц', summary.currentMonth, summary.shopAddress),
            Divider(height: 1, indent: 56, color: Colors.white.withOpacity(0.1)),
            _buildMonthTile('Прошлый месяц', summary.previousMonth, summary.shopAddress),
          ],
        ],
      ),
    );
  }

  Widget _buildMonthTile(String label, MonthAttendanceSummary month, String shopAddress) {
    final statusColor = _getStatusColor(month.status);
    final percentage = (month.completionRate * 100).toStringAsFixed(0);

    return ListTile(
      contentPadding: EdgeInsets.only(left: 56.w, right: 16.w),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: statusColor, width: 2),
        ),
        child: Center(
          child: Text(
            '$percentage%',
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 10.sp,
            ),
          ),
        ),
      ),
      title: Text(
        '$label: ${month.actualCount}/${month.plannedCount}',
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.white.withOpacity(0.9),
        ),
      ),
      subtitle: Text(
        '${month.displayName} ${month.year}',
        style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
      ),
      trailing: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AttendanceMonthPage(
              shopAddress: shopAddress,
              monthSummary: month,
            ),
          ),
        );
      },
    );
  }

  // ==================== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ====================

  Color _getStatusColor(String status) {
    switch (status) {
      case 'good':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  Color _getOnTimeColor(double rate) {
    if (rate >= 90) return Colors.green;
    if (rate >= 70) return Colors.orange;
    return Colors.red;
  }

  String _getEnding(int count) {
    if (count == 1) return 'отметка';
    if (count >= 2 && count <= 4) return 'отметки';
    return 'отметок';
  }
}
