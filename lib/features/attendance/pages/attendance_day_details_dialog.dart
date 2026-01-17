import 'package:flutter/material.dart';
import '../models/attendance_model.dart';
import '../models/shop_attendance_summary.dart';

/// Диалог деталей дня (Уровень 4)
class AttendanceDayDetailsDialog extends StatelessWidget {
  final DayAttendanceSummary day;
  final String shopAddress;

  const AttendanceDayDetailsDialog({
    super.key,
    required this.day,
    required this.shopAddress,
  });

  @override
  Widget build(BuildContext context) {
    // Сортируем записи по времени
    final sortedRecords = List<AttendanceRecord>.from(day.records)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF004D40),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${day.date.day}.${day.date.month.toString().padLeft(2, '0')}.${day.date.year}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          '${day.attendanceCount} ${_getEnding(day.attendanceCount)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Статус смен
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildShiftStatus('Утро', day.hasMorning, Icons.wb_sunny),
                  _buildShiftStatus('День', day.hasDay, Icons.wb_cloudy, isOptional: true),
                  _buildShiftStatus('Ночь', day.hasNight, Icons.nights_stay),
                ],
              ),
            ),

            // Список отметок
            Flexible(
              child: sortedRecords.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Нет отметок'),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: sortedRecords.length,
                      itemBuilder: (context, index) {
                        return _buildRecordCard(sortedRecords[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShiftStatus(String label, bool isPresent, IconData icon, {bool isOptional = false}) {
    final color = isPresent
        ? Colors.green
        : isOptional
            ? Colors.grey
            : Colors.red;

    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
        Icon(
          isPresent ? Icons.check_circle : (isOptional ? Icons.remove : Icons.cancel),
          color: color,
          size: 16,
        ),
      ],
    );
  }

  Widget _buildRecordCard(AttendanceRecord record) {
    final time = '${record.timestamp.hour.toString().padLeft(2, '0')}:'
        '${record.timestamp.minute.toString().padLeft(2, '0')}';

    final shiftLabel = _getShiftLabel(record);
    final shiftColor = _getShiftColor(record);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: shiftColor.withOpacity(0.2),
          child: Text(
            time.split(':')[0],
            style: TextStyle(
              color: shiftColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        title: Text(
          record.employeeName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Row(
          children: [
            Text(time),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: shiftColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                shiftLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: shiftColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (record.isOnTime == false && record.lateMinutes != null) ...[
              const SizedBox(width: 4),
              Text(
                '+${record.lateMinutes} мин',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        trailing: record.isOnTime == true
            ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
            : record.isOnTime == false
                ? const Icon(Icons.warning, color: Colors.orange, size: 20)
                : const Icon(Icons.info, color: Colors.grey, size: 20),
      ),
    );
  }

  String _getShiftLabel(AttendanceRecord record) {
    if (record.shiftType != null) {
      switch (record.shiftType) {
        case 'morning':
          return 'Утренняя';
        case 'day':
          return 'Дневная';
        case 'night':
          return 'Ночная';
      }
    }
    // Определяем по времени
    final hour = record.timestamp.hour;
    if (hour >= 6 && hour < 10) return 'Утренняя';
    if (hour >= 18 && hour < 22) return 'Ночная';
    if (hour >= 10 && hour < 18) return 'Дневная';
    return 'Вне смены';
  }

  Color _getShiftColor(AttendanceRecord record) {
    if (record.shiftType != null) {
      switch (record.shiftType) {
        case 'morning':
          return Colors.orange;
        case 'day':
          return Colors.blue;
        case 'night':
          return Colors.indigo;
      }
    }
    // Определяем по времени
    final hour = record.timestamp.hour;
    if (hour >= 6 && hour < 10) return Colors.orange;
    if (hour >= 18 && hour < 22) return Colors.indigo;
    if (hour >= 10 && hour < 18) return Colors.blue;
    return Colors.grey;
  }

  String _getEnding(int count) {
    if (count == 1) return 'отметка';
    if (count >= 2 && count <= 4) return 'отметки';
    return 'отметок';
  }
}
