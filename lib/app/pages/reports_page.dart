import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../features/rko/pages/rko_reports_page.dart';
import '../../features/shifts/pages/shift_reports_list_page.dart';
import '../../features/shift_handover/pages/shift_handover_reports_list_page.dart';
import '../../features/envelope/pages/envelope_reports_list_page.dart';
import '../../features/envelope/services/envelope_report_service.dart';
import '../../features/recount/pages/recount_reports_list_page.dart';
import '../../features/attendance/pages/attendance_reports_page.dart';
import '../../features/kpi/pages/kpi_type_selection_page.dart';
import '../../features/reviews/pages/reviews_list_page.dart';
import '../../features/reviews/services/review_service.dart';
import '../../features/product_questions/pages/product_questions_report_page.dart';
import '../../features/product_questions/services/product_question_service.dart';
import '../../features/tests/pages/test_report_page.dart';
import '../../features/efficiency/pages/employees_efficiency_page.dart';
import '../../features/tasks/pages/task_reports_page.dart';
import '../../features/tasks/services/task_service.dart';
import '../../features/main_cash/pages/main_cash_page.dart';
import '../../features/employees/services/user_role_service.dart';
import '../../features/job_application/pages/job_applications_list_page.dart';
import '../../features/job_application/services/job_application_service.dart';
import '../../features/referrals/pages/referrals_report_page.dart';
import '../../features/referrals/services/referral_service.dart';
import '../../features/employees/models/user_role_model.dart';
import '../../features/fortune_wheel/pages/wheel_reports_page.dart';
import '../../features/loyalty/pages/client_wheel_prizes_report_page.dart';
import '../../features/orders/pages/orders_report_page.dart';
import '../../features/orders/services/order_service.dart';
import '../../features/coffee_machine/pages/coffee_machine_reports_list_page.dart';
import '../../features/coffee_machine/services/coffee_machine_report_service.dart';
import '../../features/work_schedule/pages/shift_transfer_requests_page.dart';
import '../../features/work_schedule/services/shift_transfer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/employees/services/employee_registration_service.dart';
import '../../core/utils/logger.dart';
import '../../core/services/report_notification_service.dart';
import '../../core/services/base_http_service.dart';
import '../../features/ai_training/pages/ai_training_page.dart';
import '../../core/constants/api_constants.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница отчетов (только для администраторов и верифицированных сотрудников)
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  UserRole? _userRole;
  bool _isVerified = false;
  bool _isLoading = true;
  int _jobApplicationsUnviewedCount = 0;
  int _unreadReviewsCount = 0;
  int _managementUnreadCount = 0;
  int _unconfirmedWithdrawalsCount = 0;
  int _productQuestionsUnreadCount = 0;
  int _unviewedExpiredTasksCount = 0;
  int _referralsUnviewedCount = 0;
  int _ordersUnviewedCount = 0;
  int _shiftTransferRequestsUnreadCount = 0;
  int _envelopeUnconfirmedCount = 0;
  int _coffeeMachineUnconfirmedCount = 0;
  UnviewedCounts _reportCounts = UnviewedCounts();

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _loadJobApplicationsCount();
    _loadReportCounts();
    _loadUnreadReviewsCount();
    _loadManagementUnreadCount();
    _loadUnconfirmedWithdrawalsCount();
    _loadProductQuestionsUnreadCount();
    _loadUnviewedExpiredTasksCount();
    _loadReferralsUnviewedCount();
    _loadOrdersUnviewedCount();
    _loadShiftTransferRequestsCount();
    _loadEnvelopeCount();
    _loadCoffeeMachineCount();
  }

  Future<void> _loadUnreadReviewsCount() async {
    try {
      final reviews = await ReviewService.getAllReviews();
      final unreadCount = reviews.where((r) => r.hasUnreadFromClient).length;
      if (mounted) setState(() => _unreadReviewsCount = unreadCount);
    } catch (e) {
      Logger.error('Ошибка загрузки количества непрочитанных отзывов', e);
    }
  }

  Future<void> _loadManagementUnreadCount() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/management-dialogs',
        timeout: ApiConstants.longTimeout,
      );
      if (result != null && result['success'] == true && mounted) {
        setState(() => _managementUnreadCount = result['totalUnread'] ?? 0);
      }
    } catch (e) {
      Logger.error('Ошибка загрузки количества непрочитанных сообщений руководству', e);
    }
  }

  Future<void> _loadUnconfirmedWithdrawalsCount() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/withdrawals',
        timeout: ApiConstants.longTimeout,
      );
      if (result != null && result['success'] == true) {
        final withdrawals = result['withdrawals'] as List<dynamic>? ?? [];
        final unconfirmedCount = withdrawals.where((w) => w['confirmed'] != true).length;
        if (mounted) setState(() => _unconfirmedWithdrawalsCount = unconfirmedCount);
      }
    } catch (e) {
      Logger.error('Ошибка загрузки количества неподтвержденных выемок', e);
    }
  }

  Future<void> _loadProductQuestionsUnreadCount() async {
    try {
      final count = await ProductQuestionService.getTotalUnviewedByAdminCount();
      if (mounted) setState(() => _productQuestionsUnreadCount = count);
    } catch (e) {
      Logger.error('Ошибка загрузки количества непрочитанных вопросов о товарах', e);
    }
  }

  Future<void> _loadUnviewedExpiredTasksCount() async {
    try {
      final count = await TaskService.getUnviewedExpiredCount();
      if (mounted) setState(() => _unviewedExpiredTasksCount = count);
    } catch (e) {
      Logger.error('Ошибка загрузки количества непросмотренных просроченных задач', e);
    }
  }

  Future<void> _loadReferralsUnviewedCount() async {
    try {
      final count = await ReferralService.getUnviewedCount();
      if (mounted) setState(() => _referralsUnviewedCount = count);
    } catch (e) {
      Logger.error('Ошибка загрузки количества непросмотренных приглашений', e);
    }
  }

  Future<void> _loadOrdersUnviewedCount() async {
    try {
      final counts = await OrderService.getUnviewedCounts();
      if (mounted) setState(() => _ordersUnviewedCount = counts['total'] ?? 0);
    } catch (e) {
      Logger.error('Ошибка загрузки количества непросмотренных заказов', e);
    }
  }

  Future<void> _loadShiftTransferRequestsCount() async {
    try {
      final requests = await ShiftTransferService.getAdminRequests();
      final unreadCount = requests.where((r) => !r.isReadByAdmin).length;
      if (mounted) setState(() => _shiftTransferRequestsUnreadCount = unreadCount);
    } catch (e) {
      Logger.error('Ошибка загрузки количества заявок на смены', e);
    }
  }

  Future<void> _loadEnvelopeCount() async {
    try {
      final reports = await EnvelopeReportService.getReportsForCurrentUser();
      final unconfirmedCount = reports.where((r) => r.status != 'confirmed').length;
      if (mounted) setState(() => _envelopeUnconfirmedCount = unconfirmedCount);
    } catch (e) {
      Logger.error('Ошибка загрузки количества неподтверждённых конвертов', e);
    }
  }

  Future<void> _loadCoffeeMachineCount() async {
    try {
      final count = await CoffeeMachineReportService.getUnconfirmedCountForCurrentUser();
      if (mounted) setState(() => _coffeeMachineUnconfirmedCount = count);
    } catch (e) {
      Logger.error('Ошибка загрузки количества неподтверждённых отчётов кофемашин', e);
    }
  }

  Future<void> _loadReportCounts() async {
    final counts = await ReportNotificationService.getUnviewedCounts();
    if (mounted) setState(() => _reportCounts = counts);
  }

  Future<void> _loadJobApplicationsCount() async {
    final count = await JobApplicationService.getUnviewedCount();
    if (mounted) setState(() => _jobApplicationsUnviewedCount = count);
  }

  Future<void> _loadUserRole() async {
    try {
      var roleData = await UserRoleService.loadUserRole();

      // Если кэш устарел или пуст — загружаем с сервера
      if (roleData == null) {
        final prefs = await SharedPreferences.getInstance();
        final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
        if (phone != null && phone.isNotEmpty) {
          roleData = await UserRoleService.getUserRole(phone);
          await UserRoleService.saveUserRole(roleData);
        }
      }

      setState(() => _userRole = roleData?.role);

      if (_userRole == UserRole.employee) {
        final prefs = await SharedPreferences.getInstance();
        final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
        if (phone != null && phone.isNotEmpty) {
          final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
          final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);
          setState(() => _isVerified = registration?.isVerified ?? false);
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки роли', e);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.night,
        body: Container(
          decoration: _buildGradient(),
          child: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    final isAdmin = _userRole == UserRole.admin || _userRole == UserRole.developer;
    final canViewReports = isAdmin || (_userRole == UserRole.employee && _isVerified);

    if (!canViewReports) {
      return Scaffold(
        backgroundColor: AppColors.night,
        body: Container(
          decoration: _buildGradient(),
          child: SafeArea(
            child: Column(
              children: [
                _buildAppBar(),
                Expanded(
                  child: Center(
                    child: Text(
                      'Доступ к отчетам ограничен',
                      style: TextStyle(fontSize: 18.sp, color: Colors.white54),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: _buildGradient(),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
                  children: _buildReportItems(isAdmin),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildGradient() {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
        stops: [0.0, 0.3, 1.0],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 24.w, 16.h),
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
          SizedBox(width: 48),
        ],
      ),
    );
  }

  List<Widget> _buildReportItems(bool isAdmin) {
    final items = <Widget>[];

    // Отчет по РКО
    if (isAdmin || _isVerified) {
      items.add(_buildRow(
        icon: Icons.receipt_long_outlined,
        title: 'Отчёт по РКО',
        badge: _reportCounts.rko,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => RKOReportsPage()));
          _loadReportCounts();
        },
      ));
    }

    // Отчет по пересменкам
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.swap_horiz_rounded,
        title: 'Отчёт по пересменкам',
        badge: _reportCounts.shiftHandover,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftReportsListPage()));
          _loadReportCounts();
        },
      ));
    }

    // Отчет (Сдача Смены)
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.check_circle_outline_rounded,
        title: 'Отчёт (Сдача смены)',
        badge: _reportCounts.shiftReport,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftHandoverReportsListPage()));
          _loadReportCounts();
        },
      ));
    }

    // Отчет по конвертам
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.mail_outline_rounded,
        title: 'Отчёт по конвертам',
        badge: _envelopeUnconfirmedCount,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => EnvelopeReportsListPage()));
          _loadEnvelopeCount();
        },
      ));
    }

    // Счётчик кофемашин
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.coffee_outlined,
        title: 'Счётчик кофемашин',
        badge: _coffeeMachineUnconfirmedCount,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => CoffeeMachineReportsListPage()));
          _loadCoffeeMachineCount();
        },
      ));
    }

    // Отчет по пересчету
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.calculate_outlined,
        title: 'Отчёт по пересчёту',
        badge: _reportCounts.recount,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => RecountReportsListPage()));
          _loadReportCounts();
        },
      ));
    }

    // Отчеты по приходам
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.access_time_rounded,
        title: 'Отчёты по приходам',
        badge: _reportCounts.attendance,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => AttendanceReportsPage()));
          _loadReportCounts();
        },
      ));
    }

    // Заявки на смены
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.swap_horizontal_circle_outlined,
        title: 'Заявки на смены',
        badge: _shiftTransferRequestsUnreadCount,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftTransferRequestsPage()));
          _loadShiftTransferRequestsCount();
        },
      ));
    }

    // KPI
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.insights_outlined,
        title: 'KPI',
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => KPITypeSelectionPage()));
        },
      ));
    }

    // Отзывы покупателей
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.star_outline_rounded,
        title: 'Отзывы покупателей',
        badge: _unreadReviewsCount + _managementUnreadCount,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewsListPage()));
          _loadUnreadReviewsCount();
          _loadManagementUnreadCount();
        },
      ));
    }

    // Отчет (Поиск товаров)
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.search_rounded,
        title: 'Отчёт (Поиск товаров)',
        badge: _productQuestionsUnreadCount,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductQuestionsReportPage()));
          _loadProductQuestionsUnreadCount();
        },
      ));
    }

    // Отчет (Тестирование)
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.quiz_outlined,
        title: 'Отчёт (Тестирование)',
        badge: _reportCounts.test,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => TestReportPage()));
          _loadReportCounts();
        },
      ));
    }

    // Отчет (Главная Касса)
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.point_of_sale_outlined,
        title: 'Отчёт (Главная касса)',
        badge: _unconfirmedWithdrawalsCount,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => MainCashPage()));
          _loadUnconfirmedWithdrawalsCount();
        },
      ));
    }

    // Эффективность сотрудников
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.trending_up_rounded,
        title: 'Эффективность сотрудников',
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeesEfficiencyPage()));
        },
      ));
    }

    // Отчет по задачам
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.task_alt_outlined,
        title: 'Отчёт по задачам',
        badge: _unviewedExpiredTasksCount,
        onTap: () async {
          await TaskService.markExpiredAsViewed();
          await Navigator.push(context, MaterialPageRoute(builder: (_) => TaskReportsPage()));
          _loadUnviewedExpiredTasksCount();
        },
      ));
    }

    // Отчет (Устроиться на Работу)
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.work_outline_rounded,
        title: 'Отчёт (Устроиться на работу)',
        badge: _jobApplicationsUnviewedCount,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => JobApplicationsListPage()));
          _loadJobApplicationsCount();
        },
      ));
    }

    // Отчет (Приглашения)
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.person_add_alt_outlined,
        title: 'Отчёт (Приглашения)',
        badge: _referralsUnviewedCount,
        onTap: () async {
          await ReferralService.markAsViewed();
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ReferralsReportPage()));
          _loadReferralsUnviewedCount();
        },
      ));
    }

    // Отчет (Колесо) - для сотрудников
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.casino_outlined,
        title: 'Колесо (Сотрудники)',
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => WheelReportsPage()));
        },
      ));
    }

    // Отчет (Колесо) - для клиентов
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.emoji_events_outlined,
        title: 'Колесо (Клиенты)',
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ClientWheelPrizesReportPage()));
        },
      ));
    }

    // Отчёты (Заказы клиентов)
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.shopping_bag_outlined,
        title: 'Отчёт (Заказы клиентов)',
        badge: _ordersUnviewedCount,
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersReportPage()));
          _loadOrdersUnviewedCount();
        },
      ));
    }

    // Обучение ИИ
    if (isAdmin) {
      items.add(_buildRow(
        icon: Icons.psychology_outlined,
        title: 'Обучение ИИ',
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => AITrainingPage()));
        },
      ));
    }

    return items;
  }

  /// Минималистичная строка отчёта
  Widget _buildRow({
    required IconData icon,
    required String title,
    int? badge,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.r),
          splashColor: Colors.white.withOpacity(0.1),
          highlightColor: Colors.white.withOpacity(0.05),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                // Иконка
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10.r),
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white.withOpacity(0.85),
                    size: 22,
                  ),
                ),
                SizedBox(width: 14),

                // Название
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                // Бейдж или стрелка
                if (badge != null && badge > 0) ...[
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        color: AppColors.emerald,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.4),
                    size: 24,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
