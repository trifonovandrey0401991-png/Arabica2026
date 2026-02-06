import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/loyalty_gamification_model.dart';
import '../services/loyalty_gamification_service.dart';

/// Страница отчёта по призам клиентов от Колеса Удачи (для админа)
class ClientWheelPrizesReportPage extends StatefulWidget {
  const ClientWheelPrizesReportPage({super.key});

  @override
  State<ClientWheelPrizesReportPage> createState() => _ClientWheelPrizesReportPageState();
}

class _ClientWheelPrizesReportPageState extends State<ClientWheelPrizesReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ClientPrize> _allPrizes = [];
  bool _isLoading = true;
  String _selectedMonth = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initMonth();
    _loadPrizes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initMonth() {
    final now = DateTime.now();
    _selectedMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _loadPrizes() async {
    setState(() => _isLoading = true);

    final prizes = await LoyaltyGamificationService.fetchClientPrizesReport(
      month: _selectedMonth,
      limit: 200,
    );

    if (mounted) {
      setState(() {
        _allPrizes = prizes;
        _isLoading = false;
      });
    }
  }

  List<ClientPrize> get _pendingPrizes =>
      _allPrizes.where((p) => p.isPending).toList();

  List<ClientPrize> get _issuedPrizes =>
      _allPrizes.where((p) => !p.isPending).toList();

  void _showMonthPicker() async {
    final now = DateTime.now();
    final months = <String>[];

    // Последние 6 месяцев
    for (int i = 0; i < 6; i++) {
      final date = DateTime(now.year, now.month - i, 1);
      months.add('${date.year}-${date.month.toString().padLeft(2, '0')}');
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Выберите месяц'),
        children: months.map((month) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, month),
            child: Text(_formatMonth(month)),
          );
        }).toList(),
      ),
    );

    if (selected != null && selected != _selectedMonth) {
      setState(() => _selectedMonth = selected);
      _loadPrizes();
    }
  }

  String _formatMonth(String month) {
    final months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
    ];
    final parts = month.split('-');
    final year = parts[0];
    final monthNum = int.parse(parts[1]);
    return '${months[monthNum - 1]} $year';
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _pendingPrizes.length;
    final issuedCount = _issuedPrizes.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Колесо (Клиенты)'),
        backgroundColor: const Color(0xFF1A4D4D),
        actions: [
          TextButton.icon(
            onPressed: _showMonthPicker,
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            label: Text(
              _formatMonth(_selectedMonth),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Все (${_allPrizes.length})'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Ожидает'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(text: 'Выдано ($issuedCount)'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPrizesList(_allPrizes),
                _buildPrizesList(_pendingPrizes),
                _buildPrizesList(_issuedPrizes),
              ],
            ),
    );
  }

  Widget _buildPrizesList(List<ClientPrize> prizes) {
    if (prizes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Нет призов за этот период',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPrizes,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: prizes.length,
        itemBuilder: (context, index) {
          final prize = prizes[index];
          return _buildPrizeCard(prize);
        },
      ),
    );
  }

  Widget _buildPrizeCard(ClientPrize prize) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        prize.prizeColor,
                        prize.prizeColor.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    prize.prizeIcon,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prize.prize,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        prize.clientName,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(prize),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            // Детали
            _buildDetailRow(
              Icons.phone_outlined,
              'Телефон',
              _formatPhone(prize.clientPhone),
            ),
            const SizedBox(height: 6),
            _buildDetailRow(
              Icons.calendar_today_outlined,
              'Дата выигрыша',
              dateFormat.format(prize.spinDate),
            ),
            if (!prize.isPending && prize.issuedAt != null) ...[
              const SizedBox(height: 6),
              _buildDetailRow(
                Icons.check_circle_outline,
                'Выдано',
                '${dateFormat.format(prize.issuedAt!)} (${prize.issuedByName ?? "Сотрудник"})',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ClientPrize prize) {
    final isPending = prize.isPending;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPending
            ? Colors.orange.withOpacity(0.1)
            : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPending ? Colors.orange : Colors.green,
        ),
      ),
      child: Text(
        isPending ? 'Ожидает' : 'Выдано',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isPending ? Colors.orange.shade700 : Colors.green.shade700,
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _formatPhone(String phone) {
    if (phone.length == 11 && phone.startsWith('7')) {
      return '+${phone[0]} ${phone.substring(1, 4)} ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}';
    }
    return phone;
  }
}
