import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_colors.dart';

// Отчёты
import '../../features/rko/pages/rko_reports_page.dart';
import '../../features/shifts/pages/shift_reports_list_page.dart';
import '../../features/shift_handover/pages/shift_handover_reports_list_page.dart';
import '../../features/envelope/pages/envelope_reports_list_page.dart';
import '../../features/coffee_machine/pages/coffee_machine_reports_list_page.dart';
import '../../features/recount/pages/recount_reports_list_page.dart';
import '../../features/attendance/pages/attendance_reports_page.dart';
import '../../features/work_schedule/pages/shift_transfer_requests_page.dart';
import '../../features/kpi/pages/kpi_type_selection_page.dart';
import '../../features/reviews/pages/reviews_list_page.dart';
import '../../features/product_questions/pages/product_questions_report_page.dart';
import '../../features/tests/pages/test_report_page.dart';
import '../../features/main_cash/pages/main_cash_page.dart';
import '../../features/efficiency/pages/employees_efficiency_page.dart';
import '../../features/tasks/pages/task_reports_page.dart';
import '../../features/tasks/pages/my_tasks_page.dart';
import '../../features/job_application/pages/job_applications_list_page.dart';
import '../../features/referrals/pages/referrals_report_page.dart';
import '../../features/fortune_wheel/pages/wheel_reports_page.dart';
import '../../features/loyalty/pages/client_wheel_prizes_report_page.dart';
import '../../features/orders/pages/orders_report_page.dart';
import '../../features/ai_training/pages/ai_training_page.dart';

// Управление данными
import '../../features/work_schedule/pages/work_schedule_page.dart';
import '../../features/clients/pages/clients_management_page.dart';
import '../../features/bonuses/pages/bonus_penalty_management_page.dart';
import '../../features/tasks/pages/task_management_page.dart';

// Режимы просмотра
import '../../features/employees/pages/employee_panel_page.dart';
import 'client_functions_page.dart';

// Сервисы для счётчиков
import '../../core/services/report_notification_service.dart';
import '../../core/services/base_http_service.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/logger.dart';
import '../../features/envelope/services/envelope_report_service.dart';
import '../../features/coffee_machine/services/coffee_machine_report_service.dart';
import '../../features/work_schedule/services/shift_transfer_service.dart';
import '../../features/reviews/services/review_service.dart';
import '../../features/product_questions/services/product_question_service.dart';
import '../../features/tasks/services/task_service.dart';
import '../../features/tasks/services/recurring_task_service.dart';
import '../../features/shifts/services/shift_report_service.dart';
import '../../features/recount/services/recount_service.dart';
import '../../features/employees/services/user_role_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/job_application/services/job_application_service.dart';
import '../../features/referrals/services/referral_service.dart';
import '../../features/orders/services/order_service.dart';

/// Страница-сетка для управляющего: 8 отчётов + 7 работа с сотрудниками + 3 эффективность + 7 работа с клиентами = 25
class ManagerGridPage extends StatefulWidget {
  final bool isHomePage;
  final String? userName;
  final VoidCallback? onLogout;

  const ManagerGridPage({
    super.key,
    this.isHomePage = false,
    this.userName,
    this.onLogout,
  });

  @override
  State<ManagerGridPage> createState() => _ManagerGridPageState();
}

class _ManagerGridPageState extends State<ManagerGridPage> {

  // Счётчики
  UnviewedCounts _reportCounts = UnviewedCounts();
  int _envelopeCount = 0;
  int _coffeeMachineCount = 0;
  int _shiftTransferCount = 0;
  int _reviewsCount = 0;
  int _managementCount = 0;
  int _productQuestionsCount = 0;
  int _withdrawalsCount = 0;
  int _tasksExpiredCount = 0;
  int _jobApplicationsCount = 0;
  int _referralsCount = 0;
  int _ordersCount = 0;
  int _myTasksCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAllCounts();
  }

  Future<void> _loadAllCounts() async {
    // Запускаем все загрузки параллельно
    await Future.wait([
      _loadReportCounts(),
      _loadEnvelopeCount(),
      _loadCoffeeMachineCount(),
      _loadShiftTransferCount(),
      _loadReviewsCount(),
      _loadManagementCount(),
      _loadProductQuestionsCount(),
      _loadWithdrawalsCount(),
      _loadTasksExpiredCount(),
      _loadJobApplicationsCount(),
      _loadReferralsCount(),
      _loadOrdersCount(),
      _loadMyTasksCount(),
    ]);
  }

  Future<void> _loadReportCounts() async {
    try {
      final counts = await ReportNotificationService.getUnviewedCounts();
      if (mounted) setState(() => _reportCounts = counts);
    } catch (e) { Logger.error('Ошибка загрузки счётчиков отчётов', e); }
  }

  Future<void> _loadEnvelopeCount() async {
    try {
      final reports = await EnvelopeReportService.getReports();
      final count = reports.where((r) => r.status != 'confirmed').length;
      if (mounted) setState(() => _envelopeCount = count);
    } catch (e) { Logger.error('Ошибка загрузки счётчика конвертов', e); }
  }

  Future<void> _loadCoffeeMachineCount() async {
    try {
      final count = await CoffeeMachineReportService.getUnconfirmedCount();
      if (mounted) setState(() => _coffeeMachineCount = count);
    } catch (e) { Logger.error('Ошибка загрузки счётчика кофемашин', e); }
  }

  Future<void> _loadShiftTransferCount() async {
    try {
      final requests = await ShiftTransferService.getAdminRequests();
      final count = requests.where((r) => !r.isReadByAdmin).length;
      if (mounted) setState(() => _shiftTransferCount = count);
    } catch (e) { Logger.error('Ошибка загрузки счётчика заявок', e); }
  }

  Future<void> _loadReviewsCount() async {
    try {
      final reviews = await ReviewService.getAllReviews();
      final count = reviews.where((r) => r.hasUnreadFromClient).length;
      if (mounted) setState(() => _reviewsCount = count);
    } catch (e) { Logger.error('Ошибка загрузки счётчика отзывов', e); }
  }

  Future<void> _loadManagementCount() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/management-dialogs',
        timeout: ApiConstants.longTimeout,
      );
      if (result != null && result['success'] == true && mounted) {
        setState(() => _managementCount = result['totalUnread'] ?? 0);
      }
    } catch (e) { Logger.error('Ошибка загрузки счётчика сообщений руководству', e); }
  }

  Future<void> _loadProductQuestionsCount() async {
    try {
      final count = await ProductQuestionService.getTotalUnviewedByAdminCount();
      if (mounted) setState(() => _productQuestionsCount = count);
    } catch (e) { Logger.error('Ошибка загрузки счётчика поиска товаров', e); }
  }

  Future<void> _loadWithdrawalsCount() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/withdrawals',
        timeout: ApiConstants.longTimeout,
      );
      if (result != null && result['success'] == true) {
        final withdrawals = result['withdrawals'] as List<dynamic>? ?? [];
        final count = withdrawals.where((w) => w['confirmed'] != true).length;
        if (mounted) setState(() => _withdrawalsCount = count);
      }
    } catch (e) { Logger.error('Ошибка загрузки счётчика выемок', e); }
  }

  Future<void> _loadTasksExpiredCount() async {
    try {
      final count = await TaskService.getUnviewedExpiredCount();
      if (mounted) setState(() => _tasksExpiredCount = count);
    } catch (e) { Logger.error('Ошибка загрузки счётчика задач', e); }
  }

  Future<void> _loadJobApplicationsCount() async {
    try {
      final count = await JobApplicationService.getUnviewedCount();
      if (mounted) setState(() => _jobApplicationsCount = count);
    } catch (e) { Logger.error('Ошибка загрузки счётчика вакансий', e); }
  }

  Future<void> _loadReferralsCount() async {
    try {
      final count = await ReferralService.getUnviewedCount();
      if (mounted) setState(() => _referralsCount = count);
    } catch (e) { Logger.error('Ошибка загрузки счётчика приглашений', e); }
  }

  Future<void> _loadOrdersCount() async {
    try {
      final counts = await OrderService.getUnviewedCounts();
      if (mounted) setState(() => _ordersCount = counts['total'] ?? 0);
    } catch (e) { Logger.error('Ошибка загрузки счётчика заказов', e); }
  }

  Future<void> _loadMyTasksCount() async {
    try {
      int count = 0;
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
      final employeeId = phone?.replaceAll(RegExp(r'[\s\+]'), '');

      await Future.wait([
        // Обычные задачи (pending/submitted)
        () async {
          if (employeeId == null) return;
          try {
            final now = DateTime.now();
            final assignments = await TaskService.getMyAssignmentsCached(
              assigneeId: employeeId,
              year: now.year,
              month: now.month,
            );
            count += assignments.where((a) => a.status.name == 'pending' || a.status.name == 'submitted').length;
          } catch (_) {}
        }(),
        // Циклические задачи (pending)
        () async {
          if (phone == null) return;
          try {
            final cleanPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
            final now = DateTime.now();
            final yearMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
            final instances = await RecurringTaskService.getInstancesForAssignee(
              assigneePhone: cleanPhone,
              yearMonth: yearMonth,
            );
            count += instances.where((i) => i.status == 'pending').length;
          } catch (_) {}
        }(),
        // Отчёты пересменки (review) — admin only
        () async {
          try {
            final role = await UserRoleService.loadUserRole();
            if (role != null && role.isAdminOrAbove) {
              final reports = await ShiftReportService.getReportsForCurrentUser();
              count += reports.where((r) => r.status == 'review').length;
            }
          } catch (_) {}
        }(),
        // Отчёты пересчёта (review) — admin only
        () async {
          try {
            final role = await UserRoleService.loadUserRole();
            if (role != null && role.isAdminOrAbove) {
              final reports = await RecountService.getReportsForCurrentUser();
              count += reports.where((r) => r.status == 'review').length;
            }
          } catch (_) {}
        }(),
        // Конверты (pending) — admin only
        () async {
          try {
            final role = await UserRoleService.loadUserRole();
            if (role != null && role.isAdminOrAbove) {
              final reports = await EnvelopeReportService.getReportsForCurrentUser();
              count += reports.where((r) => r.status == 'pending').length;
            }
          } catch (_) {}
        }(),
        // Счётчики кофемашин (pending) — admin only
        () async {
          try {
            final role = await UserRoleService.loadUserRole();
            if (role != null && role.isAdminOrAbove) {
              final reports = await CoffeeMachineReportService.getReportsForCurrentUser();
              count += reports.where((r) => r.status == 'pending').length;
            }
          } catch (_) {}
        }(),
      ]);

      if (mounted) setState(() => _myTasksCount = count);
    } catch (e) { Logger.error('Ошибка загрузки счётчика моих задач', e); }
  }

  @override
  Widget build(BuildContext context) {
    final sections = _getSections(context);
    final pad = 12.w;
    const int cols = 4;
    final spacing = 5.w;

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
                padding: EdgeInsets.fromLTRB(pad, 6.h, pad, 0),
                child: SizedBox(
                  height: 40,
                  child: widget.isHomePage
                    ? Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.userName != null ? 'Привет, ${_getFirstName(widget.userName)}!' : 'Управляющая(ий)',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.95),
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: widget.onLogout,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: Icon(Icons.logout_rounded, color: Colors.white.withOpacity(0.8), size: 20),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white.withOpacity(0.8), size: 20),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                'Управляющая(ий)',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.95),
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 40),
                        ],
                      ),
                ),
              ),
              SizedBox(height: 8.h),
              // Scrollable sections
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final tileW = (constraints.maxWidth - pad * 2 - spacing * (cols - 1)) / cols;
                    final tileH = tileW * 0.85;
                    final iconSize = (tileH * 0.28).clamp(16.0, 22.0);
                    final fontSize = (tileH * 0.12).clamp(7.0, 9.5);

                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, 4.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int si = 0; si < sections.length; si++) ...[
                            if (sections[si]['title'] != null)
                              Padding(
                                padding: EdgeInsets.only(bottom: 6.h, top: si == 0 ? 0 : 6.h),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 3,
                                      height: 14.h,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [AppColors.gold, AppColors.darkGold],
                                        ),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    SizedBox(width: 8.w),
                                    Text(
                                      sections[si]['title'] as String,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    SizedBox(width: 10.w),
                                    Expanded(
                                      child: Container(
                                        height: 0.5,
                                        color: Colors.white.withOpacity(0.08),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            GridView.count(
                              crossAxisCount: cols,
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              mainAxisSpacing: spacing,
                              crossAxisSpacing: spacing,
                              childAspectRatio: tileW / tileH,
                              children: (sections[si]['items'] as List<Map<String, dynamic>>).map((item) => _buildTile(
                                context,
                                icon: item['icon'] as IconData,
                                label: item['label'] as String,
                                onTap: item['onTap'] as VoidCallback,
                                color: item['color'] as Color?,
                                badge: item['badge'] as int?,
                                iconSize: iconSize,
                                fontSize: fontSize,
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Кнопки "Сотрудники" и "Клиенты" — прижаты к низу
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 4.h, pad, 6.h),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildRoleButton(
                        context,
                        icon: Icons.badge_outlined,
                        label: 'Сотрудники',
                        color: AppColors.success,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => EmployeePanelPage()),
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: _buildRoleButton(
                        context,
                        icon: Icons.person_outline_rounded,
                        label: 'Клиенты',
                        color: AppColors.blue,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ClientFunctionsPage()),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    int? badge,
    required double iconSize,
    required double fontSize,
  }) {
    final borderColor = color != null ? color.withOpacity(0.35) : Colors.white.withOpacity(0.12);

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: borderColor, width: 1),
            gradient: color != null
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withOpacity(0.2), color.withOpacity(0.08)],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.03)],
                ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14.r),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14.r),
              splashColor: Colors.white.withOpacity(0.1),
              highlightColor: Colors.white.withOpacity(0.05),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight;
                  final adaptiveIconSize = (h * 0.34).clamp(18.0, 28.0);
                  final adaptiveFontSize = (h * 0.14).clamp(7.5, 11.0);
                  final gap = (h * 0.06).clamp(2.0, 5.0);

                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 3.w, vertical: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Icon(
                                icon,
                                size: adaptiveIconSize,
                                color: color ?? Colors.white.withOpacity(0.85),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: gap),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: adaptiveFontSize,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.8),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (badge != null && badge > 0)
          Positioned(
            top: 3,
            right: 3,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                badge > 99 ? '99+' : badge.toString(),
                style: TextStyle(
                  color: AppColors.emerald,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRoleButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.18), color.withOpacity(0.08)],
        ),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14.r),
          splashColor: color.withOpacity(0.15),
          highlightColor: color.withOpacity(0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10.w),
            child: Row(
              children: [
                Icon(icon, color: color, size: 26),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: color.withOpacity(0.6), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getFirstName(String? fullName) {
    if (fullName == null || fullName.isEmpty) return 'Гость';
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) return parts[1];
    return parts[0];
  }

  List<Map<String, dynamic>> _getSections(BuildContext context) {
    return [
      // ═══════════════════════════════════════
      // 1. ОТЧЁТЫ (8 шт.)
      // ═══════════════════════════════════════
      {
        'title': 'Отчёты',
        'items': <Map<String, dynamic>>[
          {
            'icon': Icons.receipt_long_outlined,
            'label': 'РКО',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => RKOReportsPage()));
              _loadReportCounts();
            },
            'color': null,
            'badge': _reportCounts.rko,
          },
          {
            'icon': Icons.swap_horiz_rounded,
            'label': 'Пересменки',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftReportsListPage()));
              _loadReportCounts();
            },
            'color': null,
            'badge': _reportCounts.shiftReport,
          },
          {
            'icon': Icons.check_circle_outline_rounded,
            'label': 'Сдача смены',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftHandoverReportsListPage()));
              _loadReportCounts();
            },
            'color': null,
            'badge': _reportCounts.shiftHandover,
          },
          {
            'icon': Icons.mail_outline_rounded,
            'label': 'Конверты',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => EnvelopeReportsListPage()));
              _loadEnvelopeCount();
            },
            'color': null,
            'badge': _envelopeCount,
          },
          {
            'icon': Icons.coffee_outlined,
            'label': 'Кофемашины',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => CoffeeMachineReportsListPage()));
              _loadCoffeeMachineCount();
            },
            'color': null,
            'badge': _coffeeMachineCount,
          },
          {
            'icon': Icons.calculate_outlined,
            'label': 'Пересчёт',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => RecountReportsListPage()));
              _loadReportCounts();
            },
            'color': null,
            'badge': _reportCounts.recount,
          },
          {
            'icon': Icons.access_time_rounded,
            'label': 'Приходы',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceReportsPage()));
              _loadReportCounts();
            },
            'color': null,
            'badge': _reportCounts.attendance,
          },
          {
            'icon': Icons.quiz_outlined,
            'label': 'Тесты',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => TestReportPage()));
              _loadReportCounts();
            },
            'color': null,
            'badge': _reportCounts.test,
          },
        ],
      },
      // ═══════════════════════════════════════
      // 2. РАБОТА С СОТРУДНИКАМИ (7 шт.)
      // ═══════════════════════════════════════
      {
        'title': 'Работа с сотрудниками',
        'items': <Map<String, dynamic>>[
          {
            'icon': Icons.insights_outlined,
            'label': 'KPI',
            'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => KPITypeSelectionPage())),
            'color': null,
            'badge': null,
          },
          {
            'icon': Icons.task_alt_outlined,
            'label': 'Задачи',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => TaskReportsPage()));
              _loadTasksExpiredCount();
            },
            'color': null,
            'badge': _tasksExpiredCount,
          },
          {
            'icon': Icons.swap_horizontal_circle_outlined,
            'label': 'Заявки',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftTransferRequestsPage()));
              _loadShiftTransferCount();
            },
            'color': null,
            'badge': _shiftTransferCount,
          },
          {
            'icon': Icons.casino_outlined,
            'label': 'Колесо (Сотр)',
            'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => WheelReportsPage())),
            'color': null,
            'badge': null,
          },
          {
            'icon': Icons.psychology_outlined,
            'label': 'Обучение ИИ',
            'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => AITrainingPage())),
            'color': null,
            'badge': null,
          },
          {
            'icon': Icons.calendar_month_outlined,
            'label': 'График',
            'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => WorkSchedulePage())),
            'color': null,
            'badge': null,
          },
          {
            'icon': Icons.account_balance_wallet_outlined,
            'label': 'Штрафы',
            'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => BonusPenaltyManagementPage())),
            'color': null,
            'badge': null,
          },
          {
            'icon': Icons.assignment_outlined,
            'label': 'Задачи (упр)',
            'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => TaskManagementPage(createdBy: 'admin'))),
            'color': null,
            'badge': null,
          },
        ],
      },
      // ═══════════════════════════════════════
      // 3. МОЯ ЭФФЕКТИВНОСТЬ (4 шт.)
      // ═══════════════════════════════════════
      {
        'title': 'Моя эффективность',
        'items': <Map<String, dynamic>>[
          {
            'icon': Icons.trending_up_rounded,
            'label': 'Эффективность',
            'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeesEfficiencyPage())),
            'color': null,
            'badge': null,
          },
          {
            'icon': Icons.point_of_sale_outlined,
            'label': 'Касса',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => MainCashPage()));
              _loadWithdrawalsCount();
            },
            'color': null,
            'badge': _withdrawalsCount,
          },
          {
            'icon': Icons.task_alt_rounded,
            'label': 'Мои задачи',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTasksPage()));
              _loadMyTasksCount();
            },
            'color': null,
            'badge': _myTasksCount,
          },
        ],
      },
      // ═══════════════════════════════════════
      // 4. РАБОТА С КЛИЕНТАМИ (7 шт.)
      // ═══════════════════════════════════════
      {
        'title': 'Работа с клиентами',
        'items': <Map<String, dynamic>>[
          {
            'icon': Icons.star_outline_rounded,
            'label': 'Отзывы',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewsListPage()));
              _loadReviewsCount();
              _loadManagementCount();
            },
            'color': null,
            'badge': _reviewsCount + _managementCount,
          },
          {
            'icon': Icons.search_rounded,
            'label': 'Поиск товаров',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductQuestionsReportPage()));
              _loadProductQuestionsCount();
            },
            'color': null,
            'badge': _productQuestionsCount,
          },
          {
            'icon': Icons.work_outline_rounded,
            'label': 'Вакансии',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => JobApplicationsListPage()));
              _loadJobApplicationsCount();
            },
            'color': null,
            'badge': _jobApplicationsCount,
          },
          {
            'icon': Icons.person_add_alt_outlined,
            'label': 'Приглашения',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ReferralsReportPage()));
              _loadReferralsCount();
            },
            'color': null,
            'badge': _referralsCount,
          },
          {
            'icon': Icons.emoji_events_outlined,
            'label': 'Колесо (Кл)',
            'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientWheelPrizesReportPage())),
            'color': null,
            'badge': null,
          },
          {
            'icon': Icons.shopping_bag_outlined,
            'label': 'Заказы',
            'onTap': () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersReportPage()));
              _loadOrdersCount();
            },
            'color': null,
            'badge': _ordersCount,
          },
          {
            'icon': Icons.groups_outlined,
            'label': 'Клиенты',
            'onTap': () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientsManagementPage())),
            'color': null,
            'badge': null,
          },
        ],
      },
    ];
  }
}
