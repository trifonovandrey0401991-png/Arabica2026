import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../models/recount_report_model.dart';
import 'recount_info_chip.dart';

/// Карточка просроченного отчёта (таб "Отклонённые")
class ExpiredRecountReportCard extends StatelessWidget {
  final RecountReport report;
  final VoidCallback onTap;

  const ExpiredRecountReportCard({
    super.key,
    required this.report,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final waitingHours = now.difference(report.completedAt).inHours;
    final isFromExpiredList = report.isExpired || report.expiredAt != null;
    final statusColor = isFromExpiredList ? Colors.red : Colors.orange;

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
              // Заголовок с иконкой
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isFromExpiredList
                            ? [Colors.red.shade400, Colors.red.shade600]
                            : [Colors.orange.shade400, Colors.orange.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      isFromExpiredList ? Icons.cancel_rounded : Icons.access_time_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
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
              SizedBox(height: 10),
              // Статус просрочки
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFromExpiredList ? Icons.error_rounded : Icons.schedule_rounded,
                      size: 16,
                      color: isFromExpiredList ? Colors.red.shade700 : Colors.orange.shade700,
                    ),
                    SizedBox(width: 6),
                    Text(
                      isFromExpiredList && report.expiredAt != null
                          ? 'Просрочен: ${report.expiredAt!.day}.${report.expiredAt!.month}.${report.expiredAt!.year}'
                          : 'Ожидает: $waitingHours ч. (более 5 часов)',
                      style: TextStyle(
                        color: isFromExpiredList ? Colors.red.shade700 : Colors.orange.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
