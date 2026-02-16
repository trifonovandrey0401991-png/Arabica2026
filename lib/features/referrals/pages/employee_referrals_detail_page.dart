import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/referral_service.dart';
import '../models/referral_stats_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
        backgroundColor: Color(0xFF004D40),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red),
                      SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: Colors.red)),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadStats,
                        child: Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  child: ListView(
                    padding: EdgeInsets.all(16.w),
                    children: [
                      // Статистика
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Статистика приглашений',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 16),
                              _buildStatRow('Сегодня', _today),
                              _buildStatRow('За текущий месяц', _currentMonth),
                              _buildStatRow('За прошлый месяц', _previousMonth),
                              Divider(),
                              _buildStatRow('Всего', _total, isTotal: true),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 16),

                      // Заголовок списка клиентов
                      Text(
                        'Приглашённые клиенты (${_clients.length})',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),

                      // Список клиентов
                      if (_clients.isEmpty)
                        Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.w),
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
      padding: EdgeInsets.symmetric(vertical: 8.h),
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
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: isTotal ? Color(0xFF004D40) : Colors.grey[200],
              borderRadius: BorderRadius.circular(8.r),
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
      margin: EdgeInsets.only(bottom: 8.h),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(0xFF004D40),
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(
          client.name.isNotEmpty ? client.name : 'Клиент',
          style: TextStyle(fontWeight: FontWeight.w500),
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
