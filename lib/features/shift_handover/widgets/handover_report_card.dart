import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../models/shift_handover_report_model.dart';

/// Карточка отчёта сдачи-приёмки смены
class HandoverReportCard extends StatelessWidget {
  final ShiftHandoverReport report;
  final VoidCallback onTap;

  const HandoverReportCard({
    super.key,
    required this.report,
    required this.onTap,
  });

  static Color getRatingColor(int rating) {
    if (rating <= 3) return AppColors.error;
    if (rating <= 5) return AppColors.warning;
    if (rating <= 7) return AppColors.amber;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final isConfirmed = report.isConfirmed;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isConfirmed ? AppColors.success.withOpacity(0.15) : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isConfirmed ? AppColors.success.withOpacity(0.15) : AppColors.emerald.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                isConfirmed ? Icons.check : Icons.assignment_turned_in,
                color: isConfirmed ? AppColors.success : AppColors.gold,
                size: 22,
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
                      fontSize: 14.sp,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person, size: 14, color: Colors.white.withOpacity(0.4)),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          report.employeeName,
                          style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${report.createdAt.hour.toString().padLeft(2, '0')}:${report.createdAt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
                      ),
                    ],
                  ),
                  if (isConfirmed && report.rating != null) ...[
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Оценка: ', style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.7))),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: getRatingColor(report.rating!),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            '${report.rating}',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.sp,
                            ),
                          ),
                        ),
                        if (report.confirmedByAdmin != null) ...[
                          Spacer(),
                          Text(
                            report.confirmedByAdmin!,
                            style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.35)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }
}
