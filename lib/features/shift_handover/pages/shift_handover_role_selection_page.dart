import 'package:flutter/material.dart';
import 'shift_handover_questions_page.dart';

/// Страница выбора роли для сдачи смены (Сотрудник или Заведующая)
class ShiftHandoverRoleSelectionPage extends StatelessWidget {
  final String employeeName;
  final String shopAddress;

  const ShiftHandoverRoleSelectionPage({
    super.key,
    required this.employeeName,
    required this.shopAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выберите роль'),
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
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Вы сдаете смену как:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                _buildRoleCard(
                  context,
                  title: 'Сотрудник',
                  icon: Icons.person,
                  role: 'employee',
                  description: 'Вопросы для сотрудников',
                ),
                const SizedBox(height: 20),
                _buildRoleCard(
                  context,
                  title: 'Заведующая',
                  icon: Icons.supervisor_account,
                  role: 'manager',
                  description: 'Вопросы для заведующих',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String role,
    required String description,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShiftHandoverQuestionsPage(
              employeeName: employeeName,
              shopAddress: shopAddress,
              targetRole: role,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
