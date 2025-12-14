import 'package:flutter/material.dart';
import 'shop_service.dart';
import 'employee_service.dart';
import 'shift_question_service.dart';
import 'recount_question_service.dart';
import 'test_question_service.dart';
import 'training_article_service.dart';
import 'menu_service.dart';
import 'shops_management_page.dart';
import 'employees_page.dart';

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
              // TODO: Создать страницу управления вопросами пересменки
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Страница управления вопросами пересменки в разработке'),
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
              // TODO: Создать страницу управления вопросами пересчета
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Страница управления вопросами пересчета в разработке'),
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
              // TODO: Создать страницу управления вопросами тестирования
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Страница управления вопросами тестирования в разработке'),
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
              // TODO: Создать страницу управления статьями обучения
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Страница управления статьями обучения в разработке'),
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

