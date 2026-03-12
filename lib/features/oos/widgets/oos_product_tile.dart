import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../ai_training/models/master_product_model.dart';

/// Product row with checkbox for OOS settings
class OosProductTile extends StatelessWidget {
  final MasterProduct product;
  final bool isFlagged;
  final VoidCallback onToggle;

  const OosProductTile({
    super.key,
    required this.product,
    required this.isFlagged,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: isFlagged
            ? AppColors.emerald.withOpacity(0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
        leading: Checkbox(
          value: isFlagged,
          onChanged: (_) => onToggle(),
          activeColor: AppColors.gold,
          checkColor: AppColors.night,
          side: BorderSide(
            color: isFlagged ? AppColors.gold : Colors.white30,
          ),
        ),
        title: Text(
          product.name,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14.sp,
          ),
        ),
        subtitle: product.group.isNotEmpty
            ? Text(
                product.group,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12.sp,
                ),
              )
            : null,
        onTap: onToggle,
      ),
    );
  }
}
