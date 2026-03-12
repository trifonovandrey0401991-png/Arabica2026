import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Stock cell in OOS table — shows quantity with color coding
class OosStockCell extends StatelessWidget {
  final int? stock;

  const OosStockCell({super.key, this.stock});

  @override
  Widget build(BuildContext context) {
    if (stock == null) {
      return SizedBox(
        width: 70.w,
        child: Center(
          child: Text(
            '-',
            style: TextStyle(color: Colors.white24, fontSize: 12.sp),
          ),
        ),
      );
    }

    final isZeroOrNeg = stock! <= 0;

    return Container(
      width: 70.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isZeroOrNeg
            ? Colors.red.withOpacity(0.25)
            : AppColors.emerald.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4.r),
      ),
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Text(
        '$stock',
        style: TextStyle(
          color: isZeroOrNeg ? Colors.red.shade300 : Colors.white70,
          fontSize: 13.sp,
          fontWeight: isZeroOrNeg ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
