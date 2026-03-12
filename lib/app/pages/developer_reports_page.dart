import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/logger.dart';
import '../../core/services/report_notification_service.dart';

// Reports
import '../../features/rko/pages/rko_reports_page.dart';
import '../../features/shifts/pages/shift_reports_list_page.dart';
import '../../features/shift_handover/pages/shift_handover_reports_list_page.dart';
import '../../features/envelope/pages/envelope_reports_list_page.dart';
import '../../features/envelope/services/envelope_report_service.dart';
import '../../features/coffee_machine/pages/coffee_machine_reports_list_page.dart';
import '../../features/coffee_machine/services/coffee_machine_report_service.dart';
import '../../features/recount/pages/recount_reports_list_page.dart';
import '../../features/attendance/pages/attendance_reports_page.dart';
import '../../features/tests/pages/test_report_page.dart';

// Staff
import '../../features/kpi/pages/kpi_type_selection_page.dart';
import '../../features/tasks/pages/task_reports_page.dart';
import '../../features/tasks/services/task_service.dart';
import '../../features/work_schedule/pages/shift_transfer_requests_page.dart';
import '../../features/work_schedule/services/shift_transfer_service.dart';
import '../../features/fortune_wheel/pages/wheel_reports_page.dart';
import '../../features/work_schedule/pages/work_schedule_page.dart';
import '../../features/bonuses/pages/bonus_penalty_management_page.dart';
import '../../features/tasks/pages/task_management_page.dart';
import '../../features/efficiency/pages/employees_efficiency_page.dart';
import '../../features/messenger/pages/messenger_shell_page.dart';

// My efficiency
import '../../features/efficiency/pages/my_efficiency_page.dart';
import '../../features/main_cash/pages/main_cash_page.dart';
import '../../features/tasks/pages/my_tasks_page.dart';
import '../../features/ai_training/pages/ai_training_page.dart';

// Clients
import '../../features/reviews/pages/reviews_list_page.dart';
import '../../features/reviews/services/review_service.dart';
import '../../features/product_questions/pages/product_questions_report_page.dart';
import '../../features/product_questions/services/product_question_service.dart';
import '../../features/job_application/pages/job_applications_list_page.dart';
import '../../features/job_application/services/job_application_service.dart';
import '../../features/referrals/pages/referrals_report_page.dart';
import '../../features/referrals/services/referral_service.dart';
import '../../features/loyalty/pages/client_wheel_prizes_report_page.dart';
import '../../features/orders/pages/orders_report_page.dart';
import '../../features/orders/services/order_service.dart';
import '../../features/clients/pages/clients_management_page.dart';
import '../../features/loyalty/pages/free_drinks_report_page.dart';

/// Developer reports page — tile grid (4 per row), same visual as DataManagementPage
class DeveloperReportsPage extends StatefulWidget {
  const DeveloperReportsPage({super.key});

  @override
  State<DeveloperReportsPage> createState() => _DeveloperReportsPageState();
}

class _DeveloperReportsPageState extends State<DeveloperReportsPage> {
  // Badge counters — reports section
  UnviewedCounts _reportCounts = UnviewedCounts();
  int _envelopeUnconfirmedCount = 0;
  int _coffeeMachineUnconfirmedCount = 0;

  // Badge counters — staff section
  int _shiftTransferRequestsUnreadCount = 0;
  int _unviewedExpiredTasksCount = 0;

  // Badge counters — clients section
  int _unreadReviewsCount = 0;
  int _productQuestionsUnreadCount = 0;
  int _jobApplicationsUnviewedCount = 0;
  int _referralsUnviewedCount = 0;
  int _ordersUnviewedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAllBadges();
  }

  /// Load all badge counters in parallel
  void _loadAllBadges() {
    _loadReportCounts();
    _loadEnvelopeCount();
    _loadCoffeeMachineCount();
    _loadShiftTransferRequestsCount();
    _loadUnviewedExpiredTasksCount();
    _loadUnreadReviewsCount();
    _loadProductQuestionsUnreadCount();
    _loadJobApplicationsCount();
    _loadReferralsUnviewedCount();
    _loadOrdersUnviewedCount();
  }

  Future<void> _loadReportCounts() async {
    try {
      final counts = await ReportNotificationService.getUnviewedCounts();
      if (mounted) setState(() => _reportCounts = counts);
    } catch (e) {
      Logger.error('Error loading report counts', e);
    }
  }

  Future<void> _loadEnvelopeCount() async {
    try {
      final reports = await EnvelopeReportService.getReportsForCurrentUser();
      final count = reports.where((r) => r.status != 'confirmed').length;
      if (mounted) setState(() => _envelopeUnconfirmedCount = count);
    } catch (e) {
      Logger.error('Error loading envelope count', e);
    }
  }

  Future<void> _loadCoffeeMachineCount() async {
    try {
      final count = await CoffeeMachineReportService.getUnconfirmedCountForCurrentUser();
      if (mounted) setState(() => _coffeeMachineUnconfirmedCount = count);
    } catch (e) {
      Logger.error('Error loading coffee machine count', e);
    }
  }

  Future<void> _loadShiftTransferRequestsCount() async {
    try {
      final requests = await ShiftTransferService.getAdminRequests();
      final count = requests.where((r) => !r.isReadByAdmin).length;
      if (mounted) setState(() => _shiftTransferRequestsUnreadCount = count);
    } catch (e) {
      Logger.error('Error loading shift transfer requests count', e);
    }
  }

  Future<void> _loadUnviewedExpiredTasksCount() async {
    try {
      final count = await TaskService.getUnviewedExpiredCount();
      if (mounted) setState(() => _unviewedExpiredTasksCount = count);
    } catch (e) {
      Logger.error('Error loading unviewed expired tasks count', e);
    }
  }

  Future<void> _loadUnreadReviewsCount() async {
    try {
      final reviews = await ReviewService.getAllReviews();
      final count = reviews.where((r) => r.hasUnreadFromClient).length;
      if (mounted) setState(() => _unreadReviewsCount = count);
    } catch (e) {
      Logger.error('Error loading unread reviews count', e);
    }
  }

  Future<void> _loadProductQuestionsUnreadCount() async {
    try {
      final count = await ProductQuestionService.getTotalUnviewedByAdminCount();
      if (mounted) setState(() => _productQuestionsUnreadCount = count);
    } catch (e) {
      Logger.error('Error loading product questions count', e);
    }
  }

  Future<void> _loadJobApplicationsCount() async {
    try {
      final count = await JobApplicationService.getUnviewedCount();
      if (mounted) setState(() => _jobApplicationsUnviewedCount = count);
    } catch (e) {
      Logger.error('Error loading job applications count', e);
    }
  }

  Future<void> _loadReferralsUnviewedCount() async {
    try {
      final count = await ReferralService.getUnviewedCount();
      if (mounted) setState(() => _referralsUnviewedCount = count);
    } catch (e) {
      Logger.error('Error loading referrals count', e);
    }
  }

  Future<void> _loadOrdersUnviewedCount() async {
    try {
      final counts = await OrderService.getUnviewedCounts();
      if (mounted) setState(() => _ordersUnviewedCount = counts['total'] ?? 0);
    } catch (e) {
      Logger.error('Error loading orders count', e);
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
              _buildAppBar(context),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [
                    _buildSection(context, 'Отчёты', _reportsItems(context)),
                    _buildSection(context, 'Работа с сотрудниками', _staffItems(context)),
                    _buildSection(context, 'Моя эффективность', _myEfficiencyItems(context)),
                    _buildSection(context, 'Работа с клиентами', _clientItems(context)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 24.w, 8.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Отчёты',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<_DevReportItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 8.h, bottom: 6.h, left: 4.w),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14.h,
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const cols = 4;
            const spacing = 8.0;
            final tileW = (constraints.maxWidth - spacing * (cols - 1)) / cols;
            final tileH = tileW * 0.95;
            return GridView.count(
              crossAxisCount: cols,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: tileW / tileH,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: items.map((item) => _buildTile(context, item)).toList(),
            );
          },
        ),
        SizedBox(height: 8.h),
      ],
    );
  }

  Widget _buildTile(BuildContext context, _DevReportItem item) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14.r),
      child: InkWell(
        onTap: () => item.onTap(context),
        borderRadius: BorderRadius.circular(14.r),
        splashColor: Colors.white.withOpacity(0.12),
        highlightColor: Colors.white.withOpacity(0.06),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14.r),
            color: Colors.white.withOpacity(0.07),
            border: Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Stack(
            children: [
              // Main tile content
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40.w,
                      height: 40.w,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10.r),
                        color: Colors.white.withOpacity(0.1),
                      ),
                      child: Icon(
                        item.icon,
                        color: Colors.white.withOpacity(0.85),
                        size: 22,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w400,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              // Badge (top-right corner)
              if (item.badge > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      item.badge > 99 ? '99+' : '${item.badge}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<_DevReportItem> _reportsItems(BuildContext context) => [
    _DevReportItem(Icons.receipt_long_outlined, 'РКО',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => RKOReportsPage()));
          _loadReportCounts();
        },
        badge: _reportCounts.rko),
    _DevReportItem(Icons.swap_horiz_rounded, 'Пересменки',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => ShiftHandoverReportsListPage()));
          _loadReportCounts();
        },
        badge: _reportCounts.shiftHandover),
    _DevReportItem(Icons.check_circle_outline_rounded, 'Сдача смены',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => ShiftReportsListPage()));
          _loadReportCounts();
        },
        badge: _reportCounts.shiftReport),
    _DevReportItem(Icons.mail_outline_rounded, 'Конверты',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => EnvelopeReportsListPage()));
          _loadEnvelopeCount();
        },
        badge: _envelopeUnconfirmedCount),
    _DevReportItem(Icons.coffee_outlined, 'Кофемашины',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => CoffeeMachineReportsListPage()));
          _loadCoffeeMachineCount();
        },
        badge: _coffeeMachineUnconfirmedCount),
    _DevReportItem(Icons.calculate_outlined, 'Пересчёт',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => RecountReportsListPage()));
          _loadReportCounts();
        },
        badge: _reportCounts.recount),
    _DevReportItem(Icons.access_time_rounded, 'Приходы',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => AttendanceReportsPage()))),
    _DevReportItem(Icons.quiz_outlined, 'Тесты',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => TestReportPage()))),
  ];

  List<_DevReportItem> _staffItems(BuildContext context) => [
    _DevReportItem(Icons.insights_outlined, 'KPI',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => KPITypeSelectionPage()))),
    _DevReportItem(Icons.task_alt_outlined, 'Задачи',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => TaskReportsPage()));
          _loadUnviewedExpiredTasksCount();
        },
        badge: _unviewedExpiredTasksCount),
    _DevReportItem(Icons.swap_horizontal_circle_outlined, 'Заявки',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => ShiftTransferRequestsPage()));
          _loadShiftTransferRequestsCount();
        },
        badge: _shiftTransferRequestsUnreadCount),
    _DevReportItem(Icons.casino_outlined, 'Колесо (Сотр)',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => WheelReportsPage()))),
    _DevReportItem(Icons.calendar_month_outlined, 'График',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => WorkSchedulePage()))),
    _DevReportItem(Icons.account_balance_wallet_outlined, 'Штрафы',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => BonusPenaltyManagementPage()))),
    _DevReportItem(Icons.assignment_outlined, 'Задачи (упр)',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => TaskManagementPage(createdBy: 'admin')))),
    _DevReportItem(Icons.trending_up_rounded, 'Эффективность',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => EmployeesEfficiencyPage()))),
    _DevReportItem(Icons.chat_outlined, 'Чат',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const MessengerShellPage()))),
  ];

  List<_DevReportItem> _myEfficiencyItems(BuildContext context) => [
    _DevReportItem(Icons.person_outline_rounded, 'Моя эффект.',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => MyEfficiencyPage()))),
    _DevReportItem(Icons.point_of_sale_outlined, 'Касса',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => MainCashPage()))),
    _DevReportItem(Icons.task_alt_rounded, 'Мои задачи',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const MyTasksPage()))),
    _DevReportItem(Icons.psychology_outlined, 'Обучение ИИ',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => AITrainingPage()))),
  ];

  List<_DevReportItem> _clientItems(BuildContext context) => [
    _DevReportItem(Icons.star_outline_rounded, 'Отзывы',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => ReviewsListPage()));
          _loadUnreadReviewsCount();
        },
        badge: _unreadReviewsCount),
    _DevReportItem(Icons.search_rounded, 'Поиск товаров',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => ProductQuestionsReportPage()));
          _loadProductQuestionsUnreadCount();
        },
        badge: _productQuestionsUnreadCount),
    _DevReportItem(Icons.work_outline_rounded, 'Вакансии',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => JobApplicationsListPage()));
          _loadJobApplicationsCount();
        },
        badge: _jobApplicationsUnviewedCount),
    _DevReportItem(Icons.person_add_alt_outlined, 'Приглашения',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => ReferralsReportPage()));
          _loadReferralsUnviewedCount();
        },
        badge: _referralsUnviewedCount),
    _DevReportItem(Icons.emoji_events_outlined, 'Колесо (Кл)',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => ClientWheelPrizesReportPage()))),
    _DevReportItem(Icons.shopping_bag_outlined, 'Заказы',
        (ctx) async {
          await Navigator.push(ctx, MaterialPageRoute(builder: (_) => OrdersReportPage()));
          _loadOrdersUnviewedCount();
        },
        badge: _ordersUnviewedCount),
    _DevReportItem(Icons.groups_outlined, 'Клиенты',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => ClientsManagementPage()))),
    _DevReportItem(Icons.local_cafe_outlined, 'Бонусы кл.',
        (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const FreeDrinksReportPage()))),
  ];
}

class _DevReportItem {
  final IconData icon;
  final String label;
  final void Function(BuildContext) onTap;
  final int badge;

  const _DevReportItem(this.icon, this.label, this.onTap, {this.badge = 0});
}
