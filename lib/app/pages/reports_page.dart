import 'package:flutter/material.dart';
import '../../features/rko/pages/rko_reports_page.dart';
import '../../features/shifts/pages/shift_reports_list_page.dart';
import '../../features/shift_handover/pages/shift_handover_reports_list_page.dart';
import '../../features/recount/pages/recount_reports_list_page.dart';
import '../../features/attendance/pages/attendance_reports_page.dart';
import '../../features/kpi/pages/kpi_type_selection_page.dart';
import '../../features/reviews/pages/reviews_list_page.dart';
import '../../features/product_questions/pages/product_questions_report_page.dart';
import '../../features/tests/pages/test_report_page.dart';
import '../../features/efficiency/pages/employees_efficiency_page.dart';
import '../../features/tasks/pages/task_reports_page.dart';
import '../../features/main_cash/pages/main_cash_page.dart';
import '../../features/employees/services/user_role_service.dart';
import '../../features/job_application/pages/job_applications_list_page.dart';
import '../../features/job_application/services/job_application_service.dart';
import '../../features/referrals/pages/referrals_report_page.dart';
import '../../features/employees/models/user_role_model.dart';
import '../../features/fortune_wheel/pages/wheel_reports_page.dart';
import '../../features/orders/pages/orders_report_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/employees/services/employee_registration_service.dart';
import '../../core/utils/logger.dart';
import '../../core/services/report_notification_service.dart';

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
  UnviewedCounts _reportCounts = UnviewedCounts();

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _loadJobApplicationsCount();
    _loadReportCounts();
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
            _buildSectionWithBadge(
              context,
              title: 'Отчет по РКО',
              icon: Icons.receipt_long,
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
            _buildSectionWithBadge(
              context,
              title: 'Отчет по пересменкам',
              icon: Icons.assessment,
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
            _buildSectionWithBadge(
              context,
              title: 'Отчет (Сдача Смены)',
              icon: Icons.assignment_turned_in,
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

          // Отчет по пересчету - только админ
          if (isAdmin)
            _buildSectionWithBadge(
              context,
              title: 'Отчет по пересчету',
              icon: Icons.inventory_2,
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
            _buildSectionWithBadge(
              context,
              title: 'Отчеты по приходам',
              icon: Icons.access_time_filled,
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

          // KPI - только админ
          if (isAdmin)
            _buildSection(
              context,
              title: 'KPI',
              icon: Icons.analytics,
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
            _buildSection(
              context,
              title: 'Отзывы покупателей',
              icon: Icons.feedback,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReviewsListPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет (Поиск товаров) - только админ
          if (isAdmin)
            _buildSection(
              context,
              title: 'Отчет (Поиск товаров)',
              icon: Icons.search,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProductQuestionsReportPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет (Тестирование) - только админ
          if (isAdmin)
            _buildSectionWithBadge(
              context,
              title: 'Отчет (Тестирование)',
              icon: Icons.quiz,
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
            _buildSection(
              context,
              title: 'Отчет (Главная Касса)',
              icon: Icons.point_of_sale,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MainCashPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Эффективность сотрудников - только админ
          if (isAdmin)
            _buildSection(
              context,
              title: 'Эффективность сотрудников',
              icon: Icons.bar_chart,
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
            _buildSection(
              context,
              title: 'Отчет по задачам',
              icon: Icons.assignment,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TaskReportsPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет (Устроиться на Работу) - только админ
          if (isAdmin)
            _buildSectionWithBadge(
              context,
              title: 'Отчет (Устроиться на Работу)',
              icon: Icons.work_outline,
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
            _buildSection(
              context,
              title: 'Отчет (Приглашения)',
              icon: Icons.person_add,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReferralsReportPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет (Колесо) - только админ
          if (isAdmin)
            _buildSection(
              context,
              title: 'Отчет (Колесо)',
              icon: Icons.casino,
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
            _buildSection(
              context,
              title: 'Отчёты (Заказы клиентов)',
              icon: Icons.shopping_bag,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OrdersReportPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет Обучения ИИ - только админ
          if (isAdmin)
            _buildSection(
              context,
              title: 'Отчет Обучения ИИ',
              icon: Icons.psychology,
              onTap: () {
                // TODO: Логика будет добавлена позже
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Функционал в разработке')),
                );
              },
            ),
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
}


