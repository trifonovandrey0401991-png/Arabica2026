import 'package:flutter/material.dart';
import 'shift_handover_questions_page.dart';
import '../../envelope/pages/envelope_form_page.dart';

/// Страница выбора типа сдачи смены
class ShiftHandoverRoleSelectionPage extends StatelessWidget {
  final String employeeName;
  final String shopAddress;
  final bool isCurrentUserManager;

  const ShiftHandoverRoleSelectionPage({
    super.key,
    required this.employeeName,
    required this.shopAddress,
    this.isCurrentUserManager = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сдача смены'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                const Text(
                  'Выберите тип:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  shopAddress,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),

                // Формирование конверта - главная опция
                _buildOptionCard(
                  context,
                  title: 'Формирование конверта',
                  icon: Icons.mail,
                  description: 'Выручка, расходы, итог',
                  color: Colors.green,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EnvelopeFormPage(
                          employeeName: employeeName,
                          shopAddress: shopAddress,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Вопросы',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
                  ],
                ),
                const SizedBox(height: 16),

                // Сотрудник
                _buildOptionCard(
                  context,
                  title: 'Сотрудник',
                  icon: Icons.person,
                  description: 'Вопросы для сотрудников',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ShiftHandoverQuestionsPage(
                          employeeName: employeeName,
                          shopAddress: shopAddress,
                          targetRole: 'employee',
                        ),
                      ),
                    );
                  },
                ),
                // Заведующая - показываем только для сотрудников с флагом isManager
                if (isCurrentUserManager) ...[
                  const SizedBox(height: 16),
                  _buildOptionCard(
                    context,
                    title: 'Заведующая',
                    icon: Icons.supervisor_account,
                    description: 'Вопросы для заведующих',
                    color: Colors.purple,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ShiftHandoverQuestionsPage(
                            employeeName: employeeName,
                            shopAddress: shopAddress,
                            targetRole: 'manager',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 32,
                color: color,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: color,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}
