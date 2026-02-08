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
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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
        backgroundColor: _emeraldDark,
        title: const Text(
          'Обработать приз?',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Сотрудник: ${record.employeeName}',
              style: const TextStyle(color: Colors.white),
            ),
            Text(
              'Приз: ${record.prize}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'После отметки приз будет считаться выданным.',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
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
        backgroundColor: _emeraldDark,
        title: const Text(
          'Выберите месяц',
          style: TextStyle(color: Colors.white),
        ),
        children: months.map((month) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, month),
            child: Text(
              _formatMonth(month),
              style: const TextStyle(color: Colors.white),
            ),
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
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Отчёт (Колесо)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showMonthPicker,
                      icon: const Icon(Icons.calendar_today, color: _gold, size: 18),
                      label: Text(
                        _formatMonth(_selectedMonth),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: _gold),
                  ),
                )
              else ...[
                // Статистика
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
                    ),
                  ),
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
                          color: _gold,
                          backgroundColor: _emeraldDark,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? _gold, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.5),
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
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Нет прокруток за этот месяц',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(WheelSpinRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: record.isProcessed
              ? Colors.green.withOpacity(0.5)
              : Colors.orange.withOpacity(0.5),
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
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${record.position} место за ${_formatMonth(record.rewardMonth)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  record.formattedDate,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Приз
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _gold.withOpacity(0.2)),
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
                        color: Colors.white,
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
                    color: record.isProcessed
                        ? Colors.green.withOpacity(0.15)
                        : Colors.orange.withOpacity(0.15),
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
                          color: record.isProcessed ? Colors.green[300] : Colors.orange[300],
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
