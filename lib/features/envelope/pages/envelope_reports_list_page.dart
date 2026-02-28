import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';
import '../models/envelope_report_model.dart';
import '../models/pending_envelope_report_model.dart';
import '../services/envelope_report_service.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/models/user_role_model.dart';
import 'envelope_report_view_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/report_list_widgets.dart';

/// Страница со списком отчетов по конвертам
class EnvelopeReportsListPage extends StatefulWidget {
  const EnvelopeReportsListPage({super.key});

  @override
  State<EnvelopeReportsListPage> createState() => _EnvelopeReportsListPageState();
}

class _EnvelopeReportsListPageState extends State<EnvelopeReportsListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTab = 0;
  String? _selectedShop;
  String? _selectedEmployee;
  DateTime? _selectedDate;
  List<EnvelopeReport> _allReports = [];
  List<PendingEnvelopeReport> _pendingReports = [];
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() => _selectedTab = _tabController.index);
    });
    _detectRole();
    _loadData();
  }

  Future<void> _detectRole() async {
    final roleData = await UserRoleService.loadUserRole();
    if (roleData != null && mounted) {
      if (mounted) setState(() {
        _isAdmin = roleData.role == UserRole.admin ||
                   roleData.role == UserRole.developer;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<Map<String, dynamic>>('reports_envelope');
    if (cached != null && mounted) {
      setState(() {
        _allReports = cached['allReports'] as List<EnvelopeReport>;
        _pendingReports = cached['pendingReports'] as List<PendingEnvelopeReport>;
        _isLoading = false;
      });
    }

    // Step 2: Fetch fresh data in parallel (no spinner if cache shown)
    List<EnvelopeReport> reports = [];
    List<PendingEnvelopeReport> pendingReports = [];

    try {
      await Future.wait([
        () async {
          try { reports = await EnvelopeReportService.getReportsForCurrentUser(); }
          catch (e) { Logger.error('Ошибка загрузки отчетов конвертов', e); }
        }(),
        () async {
          try { pendingReports = await EnvelopeReportService.getPendingReportsForCurrentUser(); }
          catch (e) { Logger.error('Ошибка загрузки pending конвертов', e); }
        }(),
      ]);

      reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      pendingReports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _allReports = reports;
        _pendingReports = pendingReports;
        _isLoading = false;
      });
      // Step 3: Save to cache
      CacheManager.set('reports_envelope', {
        'allReports': reports,
        'pendingReports': pendingReports,
      });
    } catch (e) {
      Logger.error('Ошибка загрузки отчетов', e);
      if (cached == null && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<EnvelopeReport> get _filteredReports {
    var reports = _allReports;

    if (_selectedShop != null) {
      reports = reports.where((r) => r.shopAddress == _selectedShop).toList();
    }

    if (_selectedEmployee != null) {
      reports = reports.where((r) => r.employeeName == _selectedEmployee).toList();
    }

    if (_selectedDate != null) {
      reports = reports.where((r) {
        return r.createdAt.year == _selectedDate!.year &&
               r.createdAt.month == _selectedDate!.month &&
               r.createdAt.day == _selectedDate!.day;
      }).toList();
    }

    return reports;
  }

  // Вкладка 1: В Очереди (pending отчеты из автоматизации)
  List<PendingEnvelopeReport> get _queueReports {
    var reports = _pendingReports.where((r) => r.status == 'pending').toList();

    // Применяем фильтры
    if (_selectedShop != null) {
      reports = reports.where((r) => r.shopAddress == _selectedShop).toList();
    }
    if (_selectedDate != null) {
      reports = reports.where((r) {
        return r.createdAt.year == _selectedDate!.year &&
               r.createdAt.month == _selectedDate!.month &&
               r.createdAt.day == _selectedDate!.day;
      }).toList();
    }

    return reports;
  }

  // Вкладка 2: Не Сданы (failed отчеты из автоматизации)
  List<PendingEnvelopeReport> get _notSubmittedReports {
    var reports = _pendingReports.where((r) => r.status == 'failed').toList();

    // Применяем фильтры
    if (_selectedShop != null) {
      reports = reports.where((r) => r.shopAddress == _selectedShop).toList();
    }
    if (_selectedDate != null) {
      reports = reports.where((r) {
        return r.createdAt.year == _selectedDate!.year &&
               r.createdAt.month == _selectedDate!.month &&
               r.createdAt.day == _selectedDate!.day;
      }).toList();
    }

    return reports;
  }

  // Вкладка 3: Ожидают (все pending)
  List<EnvelopeReport> get _awaitingReports {
    return _filteredReports.where((r) => r.status == 'pending').toList();
  }

  // Вкладка 4: Подтверждены
  List<EnvelopeReport> get _confirmedReports {
    return _filteredReports.where((r) => r.status == 'confirmed').toList();
  }

  // Вкладка 5: Отклонены (просроченные)
  List<EnvelopeReport> get _rejectedReports {
    return _filteredReports.where((r) => r.isExpired).toList();
  }

  List<String> get _uniqueShops {
    return _allReports.map((r) => r.shopAddress).where((a) => a.trim().isNotEmpty).toSet().toList()..sort();
  }

  List<String> get _uniqueEmployees {
    return _allReports.map((r) => r.employeeName).toSet().toList()..sort();
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
                        'Отчеты (Конверты)',
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

              // Tab buttons (2 rows)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                ),
                child: Column(
                  children: [
                    // Первый ряд
                    Row(
                      children: [
                        for (int i = 0; i < 3; i++)
                          ReportTabButton(
                            isSelected: _selectedTab == i,
                            onTap: () {
                              _tabController.animateTo(i);
                              if (mounted) setState(() {});
                            },
                            label: ['Не пройдены', 'Не в срок', 'Ожидают'][i],
                            count: [_queueReports.length, _notSubmittedReports.length, _awaitingReports.length][i],
                            accentColor: AppColors.gold,
                          ),
                      ],
                    ),
                    SizedBox(height: 8),
                    // Второй ряд
                    Row(
                      children: [
                        for (int i = 3; i < 5; i++)
                          ReportTabButton(
                            isSelected: _selectedTab == i,
                            onTap: () {
                              _tabController.animateTo(i);
                              if (mounted) setState(() {});
                            },
                            label: ['', '', '', 'Подтверждены', 'Отклонены'][i],
                            count: [0, 0, 0, _confirmedReports.length, _rejectedReports.length][i],
                            accentColor: AppColors.gold,
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Фильтры
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
                child: ReportFiltersWidget(
                  shops: _uniqueShops,
                  employees: _uniqueEmployees,
                  selectedShop: _selectedShop,
                  selectedEmployee: _selectedEmployee,
                  selectedDate: _selectedDate,
                  onShopChanged: (v) => setState(() => _selectedShop = v),
                  onEmployeeChanged: (v) => setState(() => _selectedEmployee = v),
                  onDateChanged: (v) {
                    if (mounted) setState(() => _selectedDate = v);
                  },
                  onReset: () => setState(() {
                    _selectedShop = null;
                    _selectedEmployee = null;
                    _selectedDate = null;
                  }),
                ),
              ),

              // TabBarView с отчетами
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildPendingReportsList(_queueReports, 'Не пройденных отчетов нет'),
                          _buildPendingReportsList(_notSubmittedReports, 'Просроченных отчетов нет'),
                          _buildReportsList(_awaitingReports, 'Ожидающих отчетов нет'),
                          _buildReportsList(_confirmedReports, 'Подтвержденных отчетов нет'),
                          _buildReportsList(_rejectedReports, 'Отклоненных отчетов нет'),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportsList(List<EnvelopeReport> reports, String emptyMessage) {
    if (reports.isEmpty) {
      return ReportEmptyState(
        icon: Icons.mail_outline,
        title: emptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: reports.length,
        itemBuilder: (context, index) {
          final report = reports[index];
          return _buildReportCard(report);
        },
      ),
    );
  }

  Widget _buildReportCard(EnvelopeReport report) {
    final isExpired = report.isExpired;
    final isConfirmed = report.status == 'confirmed';

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EnvelopeReportViewPage(report: report, isAdmin: _isAdmin),
              ),
            ).then((_) => _loadData());
          },
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isConfirmed
                        ? Colors.green.withOpacity(0.2)
                        : isExpired
                            ? Colors.red.withOpacity(0.2)
                            : AppColors.emerald,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    isConfirmed ? Icons.check : Icons.mail,
                    color: isConfirmed
                        ? Colors.green
                        : isExpired
                            ? Colors.red
                            : Colors.white,
                    size: 22,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.shopAddress,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Сотрудник: ${report.employeeName}',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                      Text(
                        '${report.createdAt.day}.${report.createdAt.month}.${report.createdAt.year} '
                        '${report.createdAt.hour}:${report.createdAt.minute.toString().padLeft(2, '0')} '
                        '• ${report.shiftTypeText}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            'Итого: ${report.totalEnvelopeAmount.toStringAsFixed(0)} руб',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.gold,
                              fontSize: 13.sp,
                            ),
                          ),
                          SizedBox(width: 8),
                          if (isConfirmed)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Подтвержден',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.sp,
                                  ),
                                ),
                              ],
                            )
                          else if (isExpired)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning, color: Colors.red, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Просрочен',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.sp,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (report.hasEditedZReport)
                        Padding(
                          padding: EdgeInsets.only(top: 4.h),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_note, color: Colors.orange, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Исправлен вручную',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingReportCard(PendingEnvelopeReport report) {
    final isFailed = report.status == 'failed';

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isFailed ? Colors.red.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isFailed ? Colors.red.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                isFailed ? Icons.cancel : Icons.access_time,
                color: isFailed ? Colors.red : Colors.orange,
                size: 22,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.shopAddress,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Смена: ${report.shiftTypeText}',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                  Text(
                    'Дата: ${report.date} • Дедлайн: ${report.deadline}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        isFailed ? Icons.warning : Icons.schedule,
                        color: isFailed ? Colors.red : Colors.orange,
                        size: 14,
                      ),
                      SizedBox(width: 4),
                      Text(
                        report.statusText,
                        style: TextStyle(
                          color: isFailed ? Colors.red : Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingReportsList(List<PendingEnvelopeReport> reports, String emptyMessage) {
    if (reports.isEmpty) {
      return ReportEmptyState(
        icon: Icons.mail_outline,
        title: emptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: reports.length,
        itemBuilder: (context, index) {
          final report = reports[index];
          return _buildPendingReportCard(report);
        },
      ),
    );
  }
}
