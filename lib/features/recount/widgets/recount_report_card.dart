import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/recount_report_model.dart';
import 'recount_info_chip.dart';

/// Карточка отчёта пересчёта (используется в табах "Проверка" и "Проверено")
class RecountReportCard extends StatelessWidget {
  final RecountReport report;
  final VoidCallback onTap;

  const RecountReportCard({
    super.key,
    required this.report,
    required this.onTap,
  });

  static Color getRatingColor(int rating) {
    if (rating <= 3) return Colors.red;
    if (rating <= 5) return Colors.orange;
    if (rating <= 7) return Colors.amber.shade700;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = report.isRated ? Colors.green : Colors.amber;
    final statusIcon = report.isRated ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded;
    final statusText = report.isRated ? 'Оценён' : 'Ожидает оценки';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 10.h, right: 8.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: statusColor.withOpacity(0.3),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(14.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок с иконкой и статусом
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: report.isRated
                            ? [Colors.green.shade400, Colors.teal.shade600]
                            : [Colors.amber.shade400, Colors.orange.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(statusIcon, color: Colors.white, size: 24),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.shopAddress,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.sp,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          report.employeeName,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withOpacity(0.3),
                    size: 18,
                  ),
                ],
              ),
              SizedBox(height: 12),
              // Информация о дате и времени
              Row(
                children: [
                  RecountInfoChip(
                    icon: Icons.calendar_today_rounded,
                    text: '${report.completedAt.day}.${report.completedAt.month}.${report.completedAt.year}',
                    color: Colors.blue,
                  ),
                  SizedBox(width: 8),
                  RecountInfoChip(
                    icon: Icons.access_time_rounded,
                    text: '${report.completedAt.hour.toString().padLeft(2, '0')}:${report.completedAt.minute.toString().padLeft(2, '0')}',
                    color: Colors.indigo,
                  ),
                  SizedBox(width: 8),
                  RecountInfoChip(
                    icon: Icons.timer_outlined,
                    text: report.formattedDuration,
                    color: Colors.teal,
                  ),
                ],
              ),
              // Оценка (если есть)
              if (report.isRated) ...[
                SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            getRatingColor(report.adminRating!).withOpacity(0.8),
                            getRatingColor(report.adminRating!),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10.r),
                        boxShadow: [
                          BoxShadow(
                            color: getRatingColor(report.adminRating!).withOpacity(0.3),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 4),
                          Text(
                            '${report.adminRating}/10',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (report.adminName != null) ...[
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Проверил: ${report.adminName}',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ] else ...[
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hourglass_empty_rounded, size: 14, color: Colors.amber.shade700),
                      SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: Colors.amber.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
