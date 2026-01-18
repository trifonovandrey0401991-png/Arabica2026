import 'package:flutter/material.dart';
import 'z_report_training_page.dart';
import 'cigarette_training_page.dart';

/// Главная страница обучения ИИ
class AITrainingPage extends StatelessWidget {
  const AITrainingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Обучение ИИ'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF004D40), Color(0xFF00796B)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 20),
            const Center(
              child: Icon(
                Icons.psychology,
                size: 80,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Выберите тип обучения',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Помогите ИИ лучше распознавать документы',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
            ),
            const SizedBox(height: 32),
            _buildTrainingCard(
              context,
              title: 'Z-отчёт',
              description: 'Обучение распознаванию кассовых Z-отчётов',
              icon: Icons.receipt_long,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ZReportTrainingPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildTrainingCard(
              context,
              title: 'Подсчёт сигарет',
              description: 'Обучение ИИ распознаванию и подсчёту пачек сигарет',
              icon: Icons.smoking_rooms,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CigaretteTrainingPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrainingCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF004D40).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 40,
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
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF004D40),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabled)
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF004D40),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
