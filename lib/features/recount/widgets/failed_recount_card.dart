import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../models/pending_recount_model.dart';
import '../../efficiency/models/points_settings_model.dart';

/// Карточка просроченного (непройденного) пересчёта (таб "Не прошли")
class FailedRecountCard extends StatelessWidget {
  final PendingRecount failed;
  final RecountPointsSettings? recountSettings;

  const FailedRecountCard({
    super.key,
    required this.failed,
    required this.recountSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isMorning = failed.shiftType == 'morning';
    final deadline = isMorning
        ? (recountSettings?.morningEndTime ?? '13:00')
        : (recountSettings?.eveningEndTime ?? '23:00');

    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Row(
          children: [
            // Иконка с предупреждением
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.red.shade400, Colors.red.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  Positioned(
                    right: 0.w,
                    bottom: 0.h,
                    child: Container(
                      padding: EdgeInsets.all(2.w),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldDark,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.error, color: Colors.red, size: 14),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 14),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failed.shopAddress,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.sp,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                        decoration: BoxDecoration(
                          color: isMorning ? Colors.orange.withOpacity(0.15) : Colors.indigo.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Text(
                          failed.shiftName,
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.bold,
                            color: isMorning ? Colors.orange : Colors.indigo.shade300,
                          ),
                        ),
                      ),
                      Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Text(
                          'ПРОСРОЧЕНО',
                          style: TextStyle(
                            fontSize: 10.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.red[400]),
                      SizedBox(width: 4),
                      Text(
                        'Дедлайн: $deadline',
                        style: TextStyle(fontSize: 12.sp, color: Colors.red[400]),
                      ),
                      if (recountSettings != null) ...[
                        Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            '${recountSettings!.missedPenalty.toStringAsFixed(1)} б.',
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
