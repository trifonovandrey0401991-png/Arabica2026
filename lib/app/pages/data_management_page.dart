import 'package:flutter/material.dart';
import '../../features/shops/services/shop_service.dart';
import '../../features/employees/services/employee_service.dart';
import '../../features/shifts/services/shift_question_service.dart';
import '../../features/recount/services/recount_question_service.dart';
import '../../features/tests/services/test_question_service.dart';
import '../../features/training/services/training_article_service.dart';
import '../../features/menu/services/menu_service.dart';
import '../../features/shops/pages/shops_management_page.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/shifts/pages/shift_questions_management_page.dart';
import '../../features/recount/pages/recount_questions_management_page.dart';
import '../../features/tests/pages/test_questions_management_page.dart';
import '../../features/training/pages/training_articles_management_page.dart';
import '../../features/clients/pages/clients_management_page.dart';
import '../../features/product_questions/pages/product_questions_management_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/tests/pages/test_notifications_page.dart';
import 'role_test_page.dart';

/// Страница управления данными (только для администраторов)
class DataManagementPage extends StatelessWidget {
  const DataManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление данными'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            context,
            title: 'Магазины',
            icon: Icons.store,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ShopsManagementPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Сотрудники',
            icon: Icons.people,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EmployeesPage()),
              );
              // Обновляем страницу после возврата (на случай, если были изменения)
              if (context.mounted) {
                // Можно добавить обновление данных, если нужно
              }
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Вопросы пересменки',
            icon: Icons.question_answer,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ShiftQuestionsManagementPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Вопросы пересчета',
            icon: Icons.help_outline,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RecountQuestionsManagementPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Вопросы тестирования',
            icon: Icons.quiz,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TestQuestionsManagementPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Статьи обучения',
            icon: Icons.article,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TrainingArticlesManagementPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Клиенты',
            icon: Icons.people,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ClientsManagementPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Ответы (поиск товара)',
            icon: Icons.search,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProductQuestionsManagementPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Меню заказов',
            icon: Icons.restaurant_menu,
            onTap: () {
              // TODO: Создать страницу управления меню
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Страница управления меню в разработке'),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Тест',
            icon: Icons.science,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const TestNotificationsPage()),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Тест ролей',
            icon: Icons.science,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RoleTestPage()),
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

