import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/shop_attendance_summary.dart';
import '../models/pending_attendance_model.dart';
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
  List<PendingAttendanceReport> _pendingReports = [];
  List<PendingAttendanceReport> _failedReports = [];

  bool _isLoading = true;
  String? _error;

  // Состояние UI
  final Set<String> _expandedShops = {};
  String _searchQuery = '';

  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
    // Отмечаем уведомления как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.attendance);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        AttendanceReportService.getEmployeesSummary(),
        AttendanceReportService.getShopsSummary(),
        AttendanceReportService.getPendingReports(),
        AttendanceReportService.getFailedReports(),
      ]);

      if (mounted) {
        setState(() {
          _employeesSummary = results[0] as List<EmployeeAttendanceSummary>;
          _shopsSummary = results[1] as List<ShopAttendanceSummary>;
          _pendingReports = results[2] as List<PendingAttendanceReport>;
          _failedReports = results[3] as List<PendingAttendanceReport>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
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
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
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
      child: Column(
        children: [
          // Первый ряд кнопок
          Row(
            children: [
              Expanded(child: _buildTabButton(0, 'По сотрудникам', Icons.people)),
              SizedBox(width: 8),
              Expanded(child: _buildTabButton(1, 'По магазинам', Icons.store)),
            ],
          ),
          SizedBox(height: 8),
          // Второй ряд кнопок
          Row(
            children: [
              Expanded(
                child: _buildTabButton(
                  2,
                  'Ожидание (${_pendingReports.length})',
                  Icons.hourglass_empty,
                  badgeColor: _pendingReports.isNotEmpty ? Colors.orange : null,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _buildTabButton(
                  3,
                  'Не отмечены (${_failedReports.length})',
                  Icons.warning_amber,
                  badgeColor: _failedReports.isNotEmpty ? Colors.red : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon, {Color? badgeColor}) {
    final isSelected = _tabController.index == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _tabController.animateTo(index);
        });
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        decoration: BoxDecoration(
          color: isSelected ? _gold.withOpacity(0.15) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isSelected ? _gold : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (badgeColor != null)
              Container(
                width: 8,
                height: 8,
                margin: EdgeInsets.only(right: 6.w),
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
            Icon(
              icon,
              size: 18,
              color: isSelected ? _gold : Colors.white,
            ),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? _gold : Colors.white,
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
        child: CircularProgressIndicator(color: _gold),
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
        _buildPendingTab(),
        _buildFailedTab(),
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
                backgroundColor: _gold,
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
            onChanged: (value) => setState(() => _searchQuery = value),
            style: TextStyle(color: Colors.white),
            cursorColor: _gold,
            decoration: InputDecoration(
              hintText: 'Поиск по имени...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(Icons.search, color: _gold),
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
      color: _gold,
      backgroundColor: _emeraldDark,
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
      color: _gold,
      backgroundColor: _emeraldDark,
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
              color: _gold,
            ),
            onTap: () {
              setState(() {
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

  // ==================== ВКЛАДКА 3: ОЖИДАНИЕ (pending) ====================

  Widget _buildPendingTab() {
    if (_pendingReports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.white.withOpacity(0.5)),
            SizedBox(height: 16),
            Text(
              'Нет ожидающих отчётов',
              style: TextStyle(color: Colors.white, fontSize: 16.sp),
            ),
            SizedBox(height: 8),
            Text(
              'Сейчас не время для отметки',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14.sp),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: _gold,
      backgroundColor: _emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: _pendingReports.length,
        itemBuilder: (context, index) => _buildPendingCard(_pendingReports[index]),
      ),
    );
  }

  Widget _buildPendingCard(PendingAttendanceReport report) {
    final deadline = DateFormat('HH:mm').format(report.deadline);
    final timeLeft = report.timeUntilDeadline;
    final minutesLeft = timeLeft.inMinutes;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Row(
          children: [
            // Иконка
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.hourglass_empty, color: Colors.orange),
            ),
            SizedBox(width: 16),
            // Инфо
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.shopName.isNotEmpty ? report.shopName : report.shopAddress,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    report.shopAddress,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 13.sp,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text(
                          report.shiftTypeDisplay,
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.timer, size: 14, color: Colors.white.withOpacity(0.4)),
                      SizedBox(width: 4),
                      Text(
                        'до $deadline',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Осталось времени
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: minutesLeft <= 30
                    ? Colors.red.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(
                  color: minutesLeft <= 30 ? Colors.red : Colors.orange,
                ),
              ),
              child: Text(
                minutesLeft > 60 ? '${(minutesLeft / 60).floor()} ч' : '$minutesLeft мин',
                style: TextStyle(
                  color: minutesLeft <= 30 ? Colors.red : Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.sp,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ВКЛАДКА 4: НЕ ОТМЕЧЕНЫ (failed) ====================

  Widget _buildFailedTab() {
    if (_failedReports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.white.withOpacity(0.5)),
            SizedBox(height: 16),
            Text(
              'Все магазины отметились',
              style: TextStyle(color: Colors.white, fontSize: 16.sp),
            ),
            SizedBox(height: 8),
            Text(
              'Нет пропущенных отчётов',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14.sp),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllData,
      color: _gold,
      backgroundColor: _emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: _failedReports.length,
        itemBuilder: (context, index) => _buildFailedCard(_failedReports[index]),
      ),
    );
  }

  Widget _buildFailedCard(PendingAttendanceReport report) {
    final failedAt = report.failedAt != null
        ? DateFormat('HH:mm').format(report.failedAt!)
        : '—';

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Row(
          children: [
            // Иконка
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cancel, color: Colors.red),
            ),
            SizedBox(width: 16),
            // Инфо
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.shopName.isNotEmpty ? report.shopName : report.shopAddress,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    report.shopAddress,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 13.sp,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text(
                          report.shiftTypeDisplay,
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.schedule, size: 14, color: Colors.white.withOpacity(0.4)),
                      SizedBox(width: 4),
                      Text(
                        'дедлайн: $failedAt',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Статус
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: Colors.red),
              ),
              child: Text(
                'Пропущен',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.sp,
                ),
              ),
            ),
          ],
        ),
      ),
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
