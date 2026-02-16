import 'package:flutter/material.dart';
import '../models/shop_attendance_summary.dart';
import 'attendance_day_details_dialog.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
        backgroundColor: Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
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
              padding: EdgeInsets.all(16.w),
              margin: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    shopAddress,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.sp,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 12),
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
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildLegendItem('Полный день', Colors.green),
                  _buildLegendItem('Частично', Colors.orange),
                  _buildLegendItem('Пусто', Colors.red.shade300),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Список дней
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
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
      margin: EdgeInsets.only(bottom: 8.h),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: statusColor, width: 2),
          ),
          child: Center(
            child: Text(
              '${day.date.day}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: statusColor,
                fontSize: 16.sp,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Text(
              '$dayOfWeek - ',
              style: TextStyle(fontWeight: FontWeight.w500),
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
          padding: EdgeInsets.only(top: 4.h),
          child: Row(
            children: [
              _buildShiftChip('Утро', day.hasMorning),
              SizedBox(width: 6),
              _buildShiftChip('День', day.hasDay, isOptional: true),
              SizedBox(width: 6),
              _buildShiftChip('Ночь', day.hasNight),
            ],
          ),
        ),
        trailing: day.attendanceCount > 0
            ? Icon(Icons.chevron_right)
            : Icon(Icons.remove, color: Colors.grey),
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
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4.r),
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
          SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
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
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12.sp, color: Colors.grey),
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
        SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 11.sp, color: Colors.white),
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
    final days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return days[weekday - 1];
  }

  String _getEnding(int count) {
    if (count == 1) return 'отметка';
    if (count >= 2 && count <= 4) return 'отметки';
    return 'отметок';
  }
}
