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
  Map<String, int> _unviewedByEmployee = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Загружаем статистику и непросмотренные параллельно
      final results = await Future.wait([
        ReferralService.getAllStats(),
        ReferralService.getUnviewedByEmployee(),
      ]);

      final statsResult = results[0] as Map<String, dynamic>?;
      final unviewedResult = results[1] as Map<String, int>;

      if (statsResult != null) {
        setState(() {
          _totalClients = statsResult['totalClients'] ?? 0;
          _unassignedCount = statsResult['unassignedCount'] ?? 0;
          _employeeStats = statsResult['employeeStats'] ?? [];
          _unviewedByEmployee = unviewedResult;
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
            onPressed: _loadData,
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
                        onPressed: _loadData,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
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
    final unviewedCount = _unviewedByEmployee[stats.employeeId] ?? 0;

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unviewedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$unviewedCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (unviewedCount > 0) const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
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
