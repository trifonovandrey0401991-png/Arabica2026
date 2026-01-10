import 'package:flutter/material.dart';
import '../../features/shops/pages/shops_management_page.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/shifts/pages/shift_questions_management_page.dart';
import '../../features/recount/pages/recount_management_tabs_page.dart';
import '../../features/tests/pages/test_questions_management_page.dart';
import '../../features/training/pages/training_articles_management_page.dart';
import '../../features/clients/pages/clients_management_page.dart';
import '../../features/shift_handover/pages/shift_handover_questions_management_page.dart';
import '../../features/suppliers/pages/suppliers_management_page.dart';
import '../../features/efficiency/pages/points_settings_page.dart';
import '../../features/tasks/pages/task_management_page.dart';
import '../../features/bonuses/pages/bonus_penalty_management_page.dart';

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
                  builder: (context) => const RecountManagementTabsPage(),
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
            title: 'Вопросы (Сдать Смену)',
            icon: Icons.assignment_turned_in,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ShiftHandoverQuestionsManagementPage(),
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
            title: 'Поставщики',
            icon: Icons.local_shipping,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SuppliersManagementPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Установка баллов',
            icon: Icons.star,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PointsSettingsPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Установить Задачи',
            icon: Icons.assignment_add,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TaskManagementPage(createdBy: 'admin'),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Премия/Штрафы',
            icon: Icons.monetization_on,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BonusPenaltyManagementPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Вопросы Для Обучения ИИ',
            icon: Icons.psychology_alt,
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
}

