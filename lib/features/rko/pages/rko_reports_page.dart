import 'package:flutter/material.dart';
import 'rko_employee_reports_page.dart';
import 'rko_shop_reports_page.dart';
import '../../../core/services/report_notification_service.dart';

/// Главная страница отчетов по РКО
class RKOReportsPage extends StatefulWidget {
  const RKOReportsPage({super.key});

  @override
  State<RKOReportsPage> createState() => _RKOReportsPageState();
}

class _RKOReportsPageState extends State<RKOReportsPage> {
  @override
  void initState() {
    super.initState();
    // Отмечаем все уведомления этого типа как просмотренные
    ReportNotificationService.markAllAsViewed(reportType: ReportType.rko);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчеты по РКО'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Выберите тип отчета',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF004D40),
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RKOEmployeeReportsPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person, size: 32),
                  label: const Text(
                    'Отчет по сотруднику',
                    style: TextStyle(fontSize: 20),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 80,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RKOShopReportsPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.store, size: 32),
                  label: const Text(
                    'Отчет по магазину',
                    style: TextStyle(fontSize: 20),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
