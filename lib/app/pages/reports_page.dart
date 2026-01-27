import 'package:flutter/material.dart';
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
import '../../features/orders/pages/orders_report_page.dart';
import '../../features/orders/services/order_service.dart';
import '../../features/work_schedule/pages/shift_transfer_requests_page.dart';
import '../../features/work_schedule/services/shift_transfer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/employees/services/employee_registration_service.dart';
import '../../core/utils/logger.dart';
import '../../core/services/report_notification_service.dart';
import '../../core/services/base_http_service.dart';
import '../../features/ai_training/pages/ai_training_page.dart';
import '../../core/constants/api_constants.dart';

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
  }

  Future<void> _loadUnreadReviewsCount() async {
    try {
      final reviews = await ReviewService.getAllReviews();
      final unreadCount = reviews.where((r) => r.hasUnreadFromClient).length;

      if (mounted) {
        setState(() {
          _unreadReviewsCount = unreadCount;
        });
      }
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

      if (result != null && result['success'] == true) {
        if (mounted) {
          setState(() {
            _managementUnreadCount = result['totalUnread'] ?? 0;
          });
        }
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

        if (mounted) {
          setState(() {
            _unconfirmedWithdrawalsCount = unconfirmedCount;
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки количества неподтвержденных выемок', e);
    }
  }

  Future<void> _loadProductQuestionsUnreadCount() async {
    try {
      // Для отчётов - считаем непросмотренные админом отвеченные диалоги
      final count = await ProductQuestionService.getTotalUnviewedByAdminCount();
      if (mounted) {
        setState(() {
          _productQuestionsUnreadCount = count;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки количества непрочитанных вопросов о товарах', e);
    }
  }

  Future<void> _loadUnviewedExpiredTasksCount() async {
    try {
      final count = await TaskService.getUnviewedExpiredCount();
      if (mounted) {
        setState(() {
          _unviewedExpiredTasksCount = count;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки количества непросмотренных просроченных задач', e);
    }
  }

  Future<void> _loadReferralsUnviewedCount() async {
    try {
      final count = await ReferralService.getUnviewedCount();
      if (mounted) {
        setState(() {
          _referralsUnviewedCount = count;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки количества непросмотренных приглашений', e);
    }
  }

  Future<void> _loadOrdersUnviewedCount() async {
    try {
      final counts = await OrderService.getUnviewedCounts();
      if (mounted) {
        setState(() {
          _ordersUnviewedCount = counts['total'] ?? 0;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки количества непросмотренных заказов', e);
    }
  }

  Future<void> _loadShiftTransferRequestsCount() async {
    try {
      final requests = await ShiftTransferService.getAdminRequests();
      final unreadCount = requests.where((r) => !r.isReadByAdmin).length;
      if (mounted) {
        setState(() {
          _shiftTransferRequestsUnreadCount = unreadCount;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки количества заявок на смены', e);
    }
  }

  Future<void> _loadEnvelopeCount() async {
    try {
      final reports = await EnvelopeReportService.getReports();
      final unconfirmedCount = reports.where((r) => r.status != 'confirmed').length;
      if (mounted) {
        setState(() {
          _envelopeUnconfirmedCount = unconfirmedCount;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки количества неподтверждённых конвертов', e);
    }
  }

  Future<void> _loadReportCounts() async {
    final counts = await ReportNotificationService.getUnviewedCounts();
    if (mounted) {
      setState(() {
        _reportCounts = counts;
      });
    }
  }

  Future<void> _loadJobApplicationsCount() async {
    final count = await JobApplicationService.getUnviewedCount();
    if (mounted) {
      setState(() {
        _jobApplicationsUnviewedCount = count;
      });
    }
  }

  Future<void> _loadUserRole() async {
    try {
      final roleData = await UserRoleService.loadUserRole();
      setState(() {
        _userRole = roleData?.role;
      });

      // Проверяем верификацию для сотрудников
      if (_userRole == UserRole.employee) {
        final prefs = await SharedPreferences.getInstance();
        final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
        if (phone != null && phone.isNotEmpty) {
          final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
          final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);
          setState(() {
            _isVerified = registration?.isVerified ?? false;
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки роли', e);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Отчеты'),
          backgroundColor: const Color(0xFF004D40),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isAdmin = _userRole == UserRole.admin;
    final canViewReports = isAdmin || (_userRole == UserRole.employee && _isVerified);

    if (!canViewReports) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Отчеты'),
          backgroundColor: const Color(0xFF004D40),
        ),
        body: const Center(
          child: Text(
            'Доступ к отчетам ограничен',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчеты'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Отчет по РКО - для админов и верифицированных сотрудников
          if (isAdmin || _isVerified)
            _buildRKOSection(
              context,
              title: 'Отчет по РКО',
              badgeCount: _reportCounts.rko,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RKOReportsPage()),
                );
                _loadReportCounts();
              },
            ),
          if (isAdmin || _isVerified) const SizedBox(height: 8),

          // Отчет по пересменкам - только админ
          if (isAdmin)
            _buildShiftHandoverSection(
              context,
              title: 'Отчет по пересменкам',
              badgeCount: _reportCounts.shiftHandover,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ShiftReportsListPage()),
                );
                _loadReportCounts();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет по сдаче смены - только админ
          if (isAdmin)
            _buildShiftCompleteSection(
              context,
              title: 'Отчет (Сдача Смены)',
              badgeCount: _reportCounts.shiftReport,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ShiftHandoverReportsListPage()),
                );
                _loadReportCounts();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет по конвертам - только админ
          if (isAdmin)
            _buildEnvelopeReportSection(
              context,
              title: 'Отчет по конвертам',
              badgeCount: _envelopeUnconfirmedCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EnvelopeReportsListPage()),
                );
                _loadEnvelopeCount();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет по пересчету - только админ
          if (isAdmin)
            _buildRecountReportSection(
              context,
              title: 'Отчет по пересчету',
              badgeCount: _reportCounts.recount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RecountReportsListPage()),
                );
                _loadReportCounts();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчеты по приходам - только админ
          if (isAdmin)
            _buildAttendanceReportsSection(
              context,
              title: 'Отчеты по приходам',
              badgeCount: _reportCounts.attendance,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AttendanceReportsPage()),
                );
                _loadReportCounts();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Заявки на смены - только админ
          if (isAdmin)
            _buildShiftTransferRequestsSection(
              context,
              title: 'Заявки на смены',
              badgeCount: _shiftTransferRequestsUnreadCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ShiftTransferRequestsPage()),
                );
                _loadShiftTransferRequestsCount();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // KPI - только админ
          if (isAdmin)
            _buildKPISection(
              context,
              title: 'KPI',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const KPITypeSelectionPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отзывы покупателей - только админ
          if (isAdmin)
            _buildReviewsReportSection(
              context,
              title: 'Отзывы покупателей',
              badgeCount: _unreadReviewsCount + _managementUnreadCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReviewsListPage()),
                );
                // Перезагрузить счетчики после возврата
                _loadUnreadReviewsCount();
                _loadManagementUnreadCount();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет (Поиск товаров) - только админ
          if (isAdmin)
            _buildProductSearchSection(
              context,
              title: 'Отчет (Поиск товаров)',
              badgeCount: _productQuestionsUnreadCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProductQuestionsReportPage()),
                );
                // Перезагрузить счетчик после возврата
                _loadProductQuestionsUnreadCount();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет (Тестирование) - только админ
          if (isAdmin)
            _buildTestingSection(
              context,
              title: 'Отчет (Тестирование)',
              badgeCount: _reportCounts.test,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TestReportPage()),
                );
                _loadReportCounts();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет (Главная Касса) - только админ
          if (isAdmin)
            _buildMainCashSection(
              context,
              title: 'Отчет (Главная Касса)',
              badgeCount: _unconfirmedWithdrawalsCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MainCashPage()),
                );
                // Обновить счетчик после возврата
                _loadUnconfirmedWithdrawalsCount();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Эффективность сотрудников - только админ
          if (isAdmin)
            _buildEfficiencySection(
              context,
              title: 'Эффективность сотрудников',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EmployeesEfficiencyPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет по задачам - только админ
          if (isAdmin)
            _buildTaskSectionWithBadge(
              context,
              title: 'Отчет по задачам',
              badgeCount: _unviewedExpiredTasksCount,
              onTap: () async {
                // Помечаем просроченные задачи как просмотренные
                await TaskService.markExpiredAsViewed();
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TaskReportsPage()),
                );
                // Обновляем счётчик после возврата
                _loadUnviewedExpiredTasksCount();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет (Устроиться на Работу) - только админ
          if (isAdmin)
            _buildJobApplicationReportSection(
              context,
              title: 'Отчет (Устроиться на Работу)',
              badgeCount: _jobApplicationsUnviewedCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const JobApplicationsListPage()),
                );
                // Обновляем счётчик после возврата
                _loadJobApplicationsCount();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет (Приглашения) - только админ
          if (isAdmin)
            _buildReferralsReportSection(
              context,
              title: 'Отчет (Приглашения)',
              badgeCount: _referralsUnviewedCount,
              onTap: () async {
                // Помечаем как просмотренные при открытии
                await ReferralService.markAsViewed();
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReferralsReportPage()),
                );
                // Обновляем счётчик после возврата
                _loadReferralsUnviewedCount();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет (Колесо) - только админ
          if (isAdmin)
            _buildFortuneWheelSection(
              context,
              title: 'Отчет (Колесо)',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const WheelReportsPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчёты (Заказы клиентов) - только админ
          if (isAdmin)
            _buildOrdersReportSection(
              context,
              title: 'Отчёты (Заказы клиентов)',
              badgeCount: _ordersUnviewedCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OrdersReportPage()),
                );
                // Обновляем счётчик после возврата
                _loadOrdersUnviewedCount();
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет Обучения ИИ - только админ
          if (isAdmin)
            _buildAITrainingButton(context),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF004D40)),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSectionWithBadge(
    BuildContext context, {
    required String title,
    required IconData icon,
    required int badgeCount,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF004D40)),
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (badgeCount > 0) const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  /// Кнопка задач с кастомной иконкой чеклиста и бейджем
  Widget _buildTaskSectionWithBadge(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Кастомная иконка чеклиста с бейджем
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/tasks_checklist_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (badgeCount > 0)
                      Text(
                        'Новых: $badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Бейдж или стрелка
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.red, Color(0xFFE53935)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка "Отчет (Тестирование)" с кастомной иконкой и бейджем
  Widget _buildTestingSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Кастомная иконка тестирования с бейджем
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/testing_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    if (badgeCount > 0)
                      Text(
                        'Непросмотренных: $badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Бейдж или стрелка
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.red, Color(0xFFE53935)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка "Главная Касса" с кастомной иконкой кассового аппарата и бейджем
  Widget _buildMainCashSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Кастомная иконка кассы с бейджем
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/cash_register_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    if (badgeCount > 0)
                      Text(
                        'Неподтверждённых: $badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Бейдж или стрелка
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.red, Color(0xFFE53935)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка "Отчеты по приходам" с кастомной иконкой и бейджем
  Widget _buildAttendanceReportsSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Кастомная иконка рабочего времени с бейджем
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/arrival_report_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    if (badgeCount > 0)
                      Text(
                        'Новых: $badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Бейдж или стрелка
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.red, Color(0xFFE53935)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEfficiencySection(
    BuildContext context, {
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Кастомная иконка эффективности
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/efficiency_icon.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAITrainingButton(BuildContext context) {
    return Card(
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: const LinearGradient(
            colors: [Color(0xFF004D40), Color(0xFF00796B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/ai_training_icon.png',
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
          ),
          title: const Text(
            'Обучение ИИ',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AITrainingPage(),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Кнопка отчета сдачи смены с кастомной иконкой и бейджем
  Widget _buildShiftCompleteSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/shift_complete_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF004D40),
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка отчета по конвертам с кастомной иконкой и бейджем
  Widget _buildEnvelopeReportSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF004D40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.mail_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF004D40),
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка отчета по РКО с кастомной иконкой и бейджем
  Widget _buildRKOSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/rko_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF004D40),
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка отчета поиска товаров с кастомной иконкой и бейджем
  Widget _buildProductSearchSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/search_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF004D40),
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка отчета по пересменкам с кастомной иконкой и бейджем
  Widget _buildShiftHandoverSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/shift_handover_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF004D40),
                  ),
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка отчета по колесу удачи с кастомной иконкой
  Widget _buildFortuneWheelSection(
    BuildContext context, {
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/fortune_wheel_icon.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF004D40),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка "Отчёты (Заказы клиентов)" с кастомной иконкой корзины и бейджем
  Widget _buildOrdersReportSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Кастомная иконка корзины с бейджем
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/cart_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    if (badgeCount > 0)
                      Text(
                        'Новых: $badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Бейдж или стрелка
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.red, Color(0xFFE53935)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка "Отчет по пересчету" с кастомной иконкой и бейджем
  Widget _buildRecountReportSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Кастомная иконка пересчета с бейджем
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/recount_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    if (badgeCount > 0)
                      Text(
                        'Новых: $badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Бейдж или стрелка
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.red, Color(0xFFE53935)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка "Отчет (Устроиться на Работу)" с кастомной иконкой и бейджем
  Widget _buildJobApplicationReportSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Кастомная иконка "устроиться на работу" с бейджем
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/job_application_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    if (badgeCount > 0)
                      Text(
                        'Новых: $badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Бейдж или стрелка
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.red, Color(0xFFE53935)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка "Отчет (Приглашения)" с кастомной иконкой клиентов и бейджем
  Widget _buildReferralsReportSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Кастомная иконка клиентов с бейджем
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/clients_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    if (badgeCount > 0)
                      Text(
                        'Новых: $badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Бейдж или стрелка
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.red, Color(0xFFE53935)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка "Отзывы покупателей" с кастомной иконкой и бейджем
  Widget _buildReviewsReportSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Кастомная иконка отзывов с бейджем
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/reviews_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    if (badgeCount > 0)
                      Text(
                        'Непрочитанных: $badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Бейдж или стрелка
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.red, Color(0xFFE53935)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка "Заявки на смены" с иконкой и бейджем
  Widget _buildShiftTransferRequestsSection(
    BuildContext context, {
    required String title,
    required int badgeCount,
    required Future<void> Function() onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Иконка заявок с бейджем
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.swap_horiz,
                      size: 28,
                      color: Colors.orange[800],
                    ),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Текст
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    if (badgeCount > 0)
                      Text(
                        'Ожидают одобрения: $badgeCount',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Бейдж или стрелка
              if (badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.orange, Color(0xFFF57C00)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка "KPI" с кастомной иконкой
  Widget _buildKPISection(
    BuildContext context, {
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/kpi_icon.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF004D40),
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF004D40)),
            ],
          ),
        ),
      ),
    );
  }
}
