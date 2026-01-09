import 'package:flutter/material.dart';
import '../services/referral_service.dart';
import '../models/referral_stats_model.dart';
import 'employee_referrals_detail_page.dart';

/// Страница отчёта по приглашениям
class ReferralsReportPage extends StatefulWidget {
  const ReferralsReportPage({super.key});

  @override
  State<ReferralsReportPage> createState() => _ReferralsReportPageState();
}

class _ReferralsReportPageState extends State<ReferralsReportPage> {
  bool _isLoading = true;
  int _totalClients = 0;
  int _unassignedCount = 0;
  List<EmployeeReferralStats> _employeeStats = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ReferralService.getAllStats();
      if (result != null) {
        setState(() {
          _totalClients = result['totalClients'] ?? 0;
          _unassignedCount = result['unassignedCount'] ?? 0;
          _employeeStats = result['employeeStats'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Не удалось загрузить данные';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Ошибка: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчет по приглашениям'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadStats,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Общее количество клиентов
                      Card(
                        color: const Color(0xFF004D40),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Text(
                                'Всего клиентов',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$_totalClients',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Заголовок списка
                      Row(
                        children: [
                          const Text(
                            'Сотрудники',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'сегодня/месяц/прош./всего',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Список сотрудников
                      if (_employeeStats.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'Нет данных о приглашениях',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ..._employeeStats.map((stats) => _buildEmployeeCard(stats)),

                      const SizedBox(height: 16),

                      // Неучтённые клиенты
                      Card(
                        color: Colors.grey[100],
                        child: ListTile(
                          leading: const Icon(Icons.person_off, color: Colors.grey),
                          title: const Text(
                            'Не учтённые клиенты',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$_unassignedCount',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmployeeCard(EmployeeReferralStats stats) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF004D40),
          child: Text(
            '#${stats.referralCode}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          stats.employeeName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          stats.statsString,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF004D40),
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EmployeeReferralsDetailPage(
                employeeId: stats.employeeId,
                employeeName: stats.employeeName,
                referralCode: stats.referralCode,
              ),
            ),
          );
        },
      ),
    );
  }
}
