import 'package:flutter/material.dart';
import '../models/fortune_wheel_model.dart';
import '../services/fortune_wheel_service.dart';

/// Страница отчёта по Колесу Удачи (для админа)
class WheelReportsPage extends StatefulWidget {
  const WheelReportsPage({super.key});

  @override
  State<WheelReportsPage> createState() => _WheelReportsPageState();
}

class _WheelReportsPageState extends State<WheelReportsPage> {
  List<WheelSpinRecord> _records = [];
  bool _isLoading = true;
  String _selectedMonth = '';

  @override
  void initState() {
    super.initState();
    _initMonth();
    _loadRecords();
  }

  void _initMonth() {
    final now = DateTime.now();
    _selectedMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);

    final records = await FortuneWheelService.getHistory(month: _selectedMonth);

    if (mounted) {
      setState(() {
        _records = records;
        _isLoading = false;
      });
    }
  }

  Future<void> _markAsProcessed(WheelSpinRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обработать приз?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Сотрудник: ${record.employeeName}'),
            Text('Приз: ${record.prize}'),
            const SizedBox(height: 8),
            const Text(
              'После отметки приз будет считаться выданным.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Обработать'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await FortuneWheelService.markProcessed(
        recordId: record.id,
        adminName: 'Администратор',
        month: _selectedMonth,
      );

      if (success) {
        _loadRecords();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Приз отмечен как обработанный'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

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
      _loadRecords();
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
    final unprocessedCount = _records.where((r) => !r.isProcessed).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Отчёт (Колесо)'),
        backgroundColor: const Color(0xFF004D40),
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Статистика
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFF004D40).withOpacity(0.1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        'Всего',
                        _records.length.toString(),
                        Icons.casino,
                      ),
                      _buildStatItem(
                        'Обработано',
                        (_records.length - unprocessedCount).toString(),
                        Icons.check_circle,
                        color: Colors.green,
                      ),
                      _buildStatItem(
                        'Ожидает',
                        unprocessedCount.toString(),
                        Icons.pending,
                        color: Colors.orange,
                      ),
                    ],
                  ),
                ),

                // Список
                Expanded(
                  child: _records.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadRecords,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _records.length,
                            itemBuilder: (context, index) {
                              return _buildRecordCard(_records[index]);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? const Color(0xFF004D40), size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.casino_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Нет прокруток за этот месяц',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(WheelSpinRecord record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: record.isProcessed ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Row(
              children: [
                Text(
                  record.positionIcon,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.employeeName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${record.position} место за ${_formatMonth(record.rewardMonth)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  record.formattedDate,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Приз
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      record.prize,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Статус и действия
            Row(
              children: [
                // Статус
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: record.isProcessed ? Colors.green[50] : Colors.orange[50],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        record.isProcessed ? Icons.check_circle : Icons.pending,
                        size: 16,
                        color: record.isProcessed ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        record.isProcessed
                            ? 'Обработано${record.processedBy != null ? ' • ${record.processedBy}' : ''}'
                            : 'Ожидает обработки',
                        style: TextStyle(
                          fontSize: 12,
                          color: record.isProcessed ? Colors.green[700] : Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Кнопка обработки
                if (!record.isProcessed)
                  TextButton.icon(
                    onPressed: () => _markAsProcessed(record),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Обработать'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
