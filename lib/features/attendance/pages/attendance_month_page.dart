import 'package:flutter/material.dart';
import '../models/shop_attendance_summary.dart';
import 'attendance_day_details_dialog.dart';

/// Страница с днями месяца (Уровень 3)
class AttendanceMonthPage extends StatelessWidget {
  final String shopAddress;
  final MonthAttendanceSummary monthSummary;

  const AttendanceMonthPage({
    super.key,
    required this.shopAddress,
    required this.monthSummary,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${monthSummary.displayName} ${monthSummary.year}'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF004D40), Color(0xFF00695C)],
          ),
        ),
        child: Column(
          children: [
            // Заголовок с общей статистикой
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    shopAddress,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard(
                        'План',
                        '${monthSummary.plannedCount}',
                        Colors.blue,
                      ),
                      _buildStatCard(
                        'Факт',
                        '${monthSummary.actualCount}',
                        _getStatusColor(monthSummary.status),
                      ),
                      _buildStatCard(
                        'Выполнено',
                        '${(monthSummary.completionRate * 100).toStringAsFixed(0)}%',
                        _getStatusColor(monthSummary.status),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Легенда
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildLegendItem('Полный день', Colors.green),
                  _buildLegendItem('Частично', Colors.orange),
                  _buildLegendItem('Пусто', Colors.red.shade300),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Список дней
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: monthSummary.days.length,
                itemBuilder: (context, index) {
                  // Показываем в обратном порядке (сначала последние дни)
                  final day = monthSummary.days[monthSummary.days.length - 1 - index];
                  return _buildDayCard(context, day);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(BuildContext context, DayAttendanceSummary day) {
    final statusColor = day.isComplete
        ? Colors.green
        : (day.hasMorning || day.hasNight)
            ? Colors.orange
            : Colors.red.shade300;

    final dayOfWeek = _getDayOfWeek(day.date.weekday);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor, width: 2),
          ),
          child: Center(
            child: Text(
              '${day.date.day}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: statusColor,
                fontSize: 16,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Text(
              '$dayOfWeek - ',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Text(
              '${day.attendanceCount} ${_getEnding(day.attendanceCount)}',
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              _buildShiftChip('Утро', day.hasMorning),
              const SizedBox(width: 6),
              _buildShiftChip('День', day.hasDay, isOptional: true),
              const SizedBox(width: 6),
              _buildShiftChip('Ночь', day.hasNight),
            ],
          ),
        ),
        trailing: day.attendanceCount > 0
            ? const Icon(Icons.chevron_right)
            : const Icon(Icons.remove, color: Colors.grey),
        onTap: day.attendanceCount > 0
            ? () {
                showDialog(
                  context: context,
                  builder: (context) => AttendanceDayDetailsDialog(
                    day: day,
                    shopAddress: shopAddress,
                  ),
                );
              }
            : null,
      ),
    );
  }

  Widget _buildShiftChip(String label, bool isPresent, {bool isOptional = false}) {
    final color = isPresent
        ? Colors.green
        : isOptional
            ? Colors.grey
            : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPresent ? Icons.check : (isOptional ? Icons.remove : Icons.close),
            size: 12,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildLegendItem(String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 11, color: Colors.white),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'good':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String _getDayOfWeek(int weekday) {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return days[weekday - 1];
  }

  String _getEnding(int count) {
    if (count == 1) return 'отметка';
    if (count >= 2 && count <= 4) return 'отметки';
    return 'отметок';
  }
}
