import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/attendance_model.dart';
import '../models/shop_attendance_summary.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
        constraints: BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(4.r),
                  topRight: Radius.circular(4.r),
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
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18.sp,
                          ),
                        ),
                        Text(
                          '${day.attendanceCount} ${_getEnding(day.attendanceCount)}',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Статус смен
            Container(
              padding: EdgeInsets.all(12.w),
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
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.w),
                        child: Text('Нет отметок'),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.all(8.w),
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
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
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
      margin: EdgeInsets.only(bottom: 8.h),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: shiftColor.withOpacity(0.2),
          child: Text(
            time.split(':')[0],
            style: TextStyle(
              color: shiftColor,
              fontWeight: FontWeight.bold,
              fontSize: 14.sp,
            ),
          ),
        ),
        title: Text(
          record.employeeName,
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Row(
          children: [
            Icon(Icons.access_time, size: 14, color: Colors.grey),
            SizedBox(width: 4),
            Text(
              time,
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.sp),
            ),
            SizedBox(width: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: shiftColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4.r),
              ),
              child: Text(
                shiftLabel,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: shiftColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (record.isOnTime == false && record.lateMinutes != null) ...[
              SizedBox(width: 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4.r),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red),
                    SizedBox(width: 2),
                    Text(
                      '+${record.lateMinutes} мин',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        trailing: record.isOnTime == true
            ? Icon(Icons.check_circle, color: Colors.green, size: 20)
            : record.isOnTime == false
                ? Icon(Icons.warning, color: Colors.orange, size: 20)
                : Icon(Icons.info, color: Colors.grey, size: 20),
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
