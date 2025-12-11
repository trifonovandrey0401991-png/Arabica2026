import 'package:flutter/material.dart';
import 'kpi_shop_calendar_page.dart';
import 'kpi_employees_list_page.dart';

/// Страница выбора типа KPI: Сотрудники / Магазины
class KPITypeSelectionPage extends StatelessWidget {
  const KPITypeSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KPI'),
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
                        builder: (context) => const KPIEmployeesListPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person, size: 32),
                  label: const Text(
                    'Сотрудники',
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
                        builder: (context) => const KPIShopCalendarPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.store, size: 32),
                  label: const Text(
                    'Магазины',
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

