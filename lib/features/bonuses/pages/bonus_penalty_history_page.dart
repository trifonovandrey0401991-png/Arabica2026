import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/bonus_penalty_model.dart';

class BonusPenaltyHistoryPage extends StatelessWidget {
  final String title;
  final List<BonusPenalty> records;
  final double total;

  const BonusPenaltyHistoryPage({
    super.key,
    required this.title,
    required this.records,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: total >= 0 ? Colors.green : Colors.red,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Итого
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: (total >= 0 ? Colors.green : Colors.red).withOpacity(0.1),
            child: Column(
              children: [
                const Text(
                  'Итого',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${total >= 0 ? '+' : ''}${total.toStringAsFixed(0)} руб',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: total >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),

          // Список записей
          Expanded(
            child: records.isEmpty
                ? const Center(
                    child: Text(
                      'Нет записей',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: records.length,
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) {
                      final record = records[index];
                      final isBonus = record.isBonus;
                      final color = isBonus ? Colors.green : Colors.red;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isBonus
                                        ? Icons.add_circle
                                        : Icons.remove_circle,
                                    color: color,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isBonus ? 'Премия' : 'Штраф',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${isBonus ? '+' : '-'}${record.amount.toStringAsFixed(0)} руб',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                    ),
                                  ),
                                ],
                              ),
                              if (record.comment.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.comment,
                                        size: 16,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          record.comment,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    record.adminName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: Colors.grey[500],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    dateFormat.format(record.createdAt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
