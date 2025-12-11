import 'package:flutter/material.dart';
import 'rko_amount_input_page.dart';

/// Страница выбора типа РКО
class RKOTypeSelectionPage extends StatelessWidget {
  const RKOTypeSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('РКО - Расходный кассовый ордер'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Выберите тип РКО',
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
                        builder: (context) => const RKOAmountInputPage(
                          rkoType: 'ЗП после смены',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.access_time, size: 32),
                  label: const Text(
                    'ЗП после смены',
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
                        builder: (context) => const RKOAmountInputPage(
                          rkoType: 'ЗП за месяц',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.calendar_month, size: 32),
                  label: const Text(
                    'ЗП за месяц',
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





