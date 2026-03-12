import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../models/pending_shift_handover_model.dart';
import '../../efficiency/models/points_settings_model.dart';

/// Список ожидающих (не пройденных) сдач смен
class PendingShiftsList extends StatelessWidget {
  final List<PendingShiftHandover> pendingHandovers;
  final ShiftHandoverPointsSettings settings;

  const PendingShiftsList({
    super.key,
    required this.pendingHandovers,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingHandovers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.white.withOpacity(0.3)),
            SizedBox(height: 16),
            Text(
              'Все сдачи смен в срок пройдены!',
              style: TextStyle(color: Colors.white, fontSize: 18.sp),
            ),
            SizedBox(height: 8),
            Text(
              'Дедлайны: утро до ${settings.morningEndTime}, вечер до ${settings.eveningEndTime}',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13.sp),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16.w),
      itemCount: pendingHandovers.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white.withOpacity(0.5), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Дедлайны: утро до ${settings.morningEndTime}, вечер до ${settings.eveningEndTime}',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12.sp),
                  ),
                ),
              ],
            ),
          );
        }

        final pending = pendingHandovers[index - 1];

        return Container(
          margin: EdgeInsets.only(bottom: 10.h),
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: pending.shiftType == 'morning'
                    ? AppColors.warning.withOpacity(0.8)
                    : AppColors.indigo.withOpacity(0.8),
                child: Icon(
                  pending.shiftType == 'morning' ? Icons.wb_sunny : Icons.nights_stay,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pending.shopAddress,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: pending.shiftType == 'morning'
                                ? AppColors.warning.withOpacity(0.2)
                                : AppColors.indigo.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Text(
                            pending.shiftName,
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.bold,
                              color: pending.shiftType == 'morning'
                                  ? AppColors.warningLight
                                  : AppColors.indigo,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'до ${pending.shiftType == 'morning' ? settings.morningEndTime : settings.eveningEndTime}',
                          style: TextStyle(fontSize: 11.sp, color: Colors.white.withOpacity(0.5)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.schedule,
                color: pending.shiftType == 'morning' ? AppColors.warning.withOpacity(0.7) : AppColors.indigo.withOpacity(0.7),
                size: 28,
              ),
            ],
          ),
        );
      },
    );
  }
}
