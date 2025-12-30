import 'package:flutter/material.dart';
import '../../features/rko/pages/rko_reports_page.dart';
import '../../features/shifts/pages/shift_reports_list_page.dart';
import '../../features/shift_handover/pages/shift_handover_reports_list_page.dart';
import '../../features/recount/pages/recount_reports_list_page.dart';
import '../../features/attendance/pages/attendance_reports_page.dart';
import '../../features/kpi/pages/kpi_type_selection_page.dart';
import '../../features/reviews/pages/reviews_list_page.dart';
import '../../features/employees/services/user_role_service.dart';
import '../../features/employees/models/user_role_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/employees/services/employee_registration_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserRole();
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
      print('Ошибка загрузки роли: $e');
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
            _buildSection(
              context,
              title: 'Отчет по РКО',
              icon: Icons.receipt_long,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RKOReportsPage()),
                );
              },
            ),
          if (isAdmin || _isVerified) const SizedBox(height: 8),

          // Отчет по пересменкам - только админ
          if (isAdmin)
            _buildSection(
              context,
              title: 'Отчет по пересменкам',
              icon: Icons.assessment,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ShiftReportsListPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет по сдаче смены - только админ
          if (isAdmin)
            _buildSection(
              context,
              title: 'Отчет (Сдача Смены)',
              icon: Icons.assignment_turned_in,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ShiftHandoverReportsListPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчет по пересчету - только админ
          if (isAdmin)
            _buildSection(
              context,
              title: 'Отчет по пересчету',
              icon: Icons.inventory_2,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RecountReportsListPage()),
                );
              },
            ),
          if (isAdmin) const SizedBox(height: 8),

          // Отчеты по приходам - только админ
          if (isAdmin)
            _buildSection(
              context,
              title: 'Отчеты по приходам',
              icon: Icons.access_time_filled,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AttendanceReportsPage()),
                );
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
}


