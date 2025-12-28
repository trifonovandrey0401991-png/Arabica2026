import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../training/pages/training_page.dart';
import '../../tests/pages/test_page.dart';
import '../../shifts/pages/shift_shop_selection_page.dart';
import '../../recount/pages/recount_shop_selection_page.dart';
import '../../recipes/pages/recipes_list_page.dart';
import '../../attendance/pages/attendance_shop_selection_page.dart';
import '../../attendance/services/attendance_service.dart';
import 'employees_page.dart';
import '../services/user_role_service.dart';
import '../models/user_role_model.dart';
import '../../rko/pages/rko_type_selection_page.dart';
import '../services/employee_registration_service.dart';

/// Страница панели работника
class EmployeePanelPage extends StatefulWidget {
  const EmployeePanelPage({super.key});

  @override
  State<EmployeePanelPage> createState() => _EmployeePanelPageState();
}

class _EmployeePanelPageState extends State<EmployeePanelPage> {
  String? _userName;
  UserRoleData? _userRole;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final roleData = await UserRoleService.loadUserRole();
      setState(() {
        _userRole = roleData;
        _userName = roleData?.displayName;
      });
    } catch (e) {
      print('Ошибка загрузки данных пользователя: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Панель работника'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            context,
            title: 'Обучение',
            icon: Icons.menu_book,
            onTap: () {
              _showTrainingDialog(context);
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Я на работе',
            icon: Icons.access_time,
            onTap: () async {
              // ВАЖНО: Используем единый источник истины - меню "Сотрудники"
              // Это гарантирует, что имя будет совпадать с отображением в системе
              final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
              final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
              
              try {
                final hasAttendance = await AttendanceService.hasAttendanceToday(employeeName);
                
                if (hasAttendance && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Вы уже отметились сегодня'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }
              } catch (e) {
                print('⚠️ Ошибка проверки отметки: $e');
                // Продолжаем, даже если проверка не удалась
              }
              
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AttendanceShopSelectionPage(
                    employeeName: employeeName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Пересменка',
            icon: Icons.work_history,
            onTap: () async {
              // ВАЖНО: Используем единый источник истины - меню "Сотрудники"
              // Это гарантирует, что имя будет совпадать с отображением в системе
              final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
              final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
              
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShiftShopSelectionPage(
                    employeeName: employeeName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Пересчет товаров',
            icon: Icons.inventory,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RecountShopSelectionPage()),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Рецепты',
            icon: Icons.restaurant_menu,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RecipesListPage()),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'РКО',
            icon: Icons.receipt_long,
            onTap: () async {
              // Проверяем верификацию сотрудника
              try {
                final prefs = await SharedPreferences.getInstance();
                final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
                
                if (phone == null || phone.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Не удалось определить телефон сотрудника'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }

                final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
                final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);
                
                if (registration == null || !registration.isVerified) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Только верифицированные сотрудники могут создавать РКО'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                  return;
                }

                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RKOTypeSelectionPage()),
                );
              } catch (e) {
                print('Ошибка проверки верификации: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
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

  /// Показать диалог выбора: Обучение или Тест
  void _showTrainingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Обучение',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF004D40),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TrainingPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.menu_book),
                label: const Text('Обучение'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TestPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.quiz),
                label: const Text('Сдать тест'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


