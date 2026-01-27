import 'package:flutter/material.dart';
import 'efficiency_by_shop_page.dart';
import 'efficiency_by_employee_page.dart';
import 'efficiency_analytics_page.dart';

/// Страница выбора типа отчета эффективности
class EmployeesEfficiencyPage extends StatelessWidget {
  const EmployeesEfficiencyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Эффективность сотрудников'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Text(
              'Выберите тип отчета:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Color(0xFF004D40),
              ),
            ),
            const SizedBox(height: 24),
            _buildOptionCard(
              context,
              icon: Icons.store,
              title: 'По магазинам',
              subtitle: 'Эффективность каждого магазина',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EfficiencyByShopPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildOptionCard(
              context,
              icon: Icons.person,
              title: 'По сотрудникам',
              subtitle: 'Эффективность каждого сотрудника',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EfficiencyByEmployeePage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildOptionCard(
              context,
              icon: Icons.analytics_outlined,
              title: 'Аналитика',
              subtitle: 'Динамика за 3 месяца',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EfficiencyAnalyticsPage(),
                  ),
                );
              },
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Color(0xFF004D40),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Баллы рассчитываются автоматически на основе оценок отчетов за текущий месяц',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: const Color(0xFF004D40),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF004D40),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF004D40),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
