import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/referral_service.dart';
import '../models/referral_stats_model.dart';

/// Страница детальной статистики приглашений сотрудника
class EmployeeReferralsDetailPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final int referralCode;

  const EmployeeReferralsDetailPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.referralCode,
  });

  @override
  State<EmployeeReferralsDetailPage> createState() => _EmployeeReferralsDetailPageState();
}

class _EmployeeReferralsDetailPageState extends State<EmployeeReferralsDetailPage> {
  bool _isLoading = true;
  int _today = 0;
  int _currentMonth = 0;
  int _previousMonth = 0;
  int _total = 0;
  List<ReferredClient> _clients = [];
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
      final result = await ReferralService.getEmployeeStats(widget.employeeId);
      if (result != null) {
        setState(() {
          _today = result['today'] ?? 0;
          _currentMonth = result['currentMonth'] ?? 0;
          _previousMonth = result['previousMonth'] ?? 0;
          _total = result['total'] ?? 0;
          _clients = result['clients'] ?? [];
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
        title: Text('${widget.employeeName} (#${widget.referralCode})'),
        backgroundColor: const Color(0xFF004D40),
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
                      // Статистика
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Статистика приглашений',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildStatRow('Сегодня', _today),
                              _buildStatRow('За текущий месяц', _currentMonth),
                              _buildStatRow('За прошлый месяц', _previousMonth),
                              const Divider(),
                              _buildStatRow('Всего', _total, isTotal: true),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Заголовок списка клиентов
                      Text(
                        'Приглашённые клиенты (${_clients.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Список клиентов
                      if (_clients.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'Нет приглашённых клиентов',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ..._clients.map((client) => _buildClientCard(client)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatRow(String label, int value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isTotal ? const Color(0xFF004D40) : Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: isTotal ? 18 : 16,
                fontWeight: FontWeight.bold,
                color: isTotal ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientCard(ReferredClient client) {
    final dateFormat = DateFormat('dd.MM.yyyy');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFF004D40),
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(
          client.name.isNotEmpty ? client.name : 'Клиент',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(client.maskedPhone),
        trailing: Text(
          dateFormat.format(client.referredAt),
          style: TextStyle(color: Colors.grey[600]),
        ),
      ),
    );
  }
}
