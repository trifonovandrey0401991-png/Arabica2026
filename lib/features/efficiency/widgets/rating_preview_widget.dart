import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Виджет предпросмотра расчёта баллов для рейтинговых настроек
class RatingPreviewWidget extends StatelessWidget {
  final List<int> previewRatings;
  final double Function(int rating) calculatePoints;
  final List<Color> gradientColors;
  final String ratingColumnTitle;
  final String pointsColumnTitle;
  final String Function(int rating)? ratingFormatter;

  const RatingPreviewWidget({
    super.key,
    required this.previewRatings,
    required this.calculatePoints,
    this.gradientColors = const [Color(0xFFf46b45), Color(0xFFeea849)],
    this.ratingColumnTitle = 'Оценка',
    this.pointsColumnTitle = 'Баллы',
    this.ratingFormatter,
  });

  String _formatRating(int rating) {
    if (ratingFormatter != null) return ratingFormatter!(rating);
    return '$rating / 10';
  }

  String _formatPoints(double points) {
    if (points >= 0) return '+${points.toStringAsFixed(2)}';
    return points.toStringAsFixed(2);
  }

  Color _getPointsColor(double points) {
    if (points < 0) return AppColors.error;
    if (points > 0) return AppColors.emeraldGreen;
    return Colors.white.withOpacity(0.5);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(vertical: 14.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ratingColumnTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.sp,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      pointsColumnTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.sp,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            // Rows
            ...previewRatings.asMap().entries.map((entry) {
              final index = entry.key;
              final rating = entry.value;
              final points = calculatePoints(rating);
              final color = _getPointsColor(points);
              final isLast = index == previewRatings.length - 1;

              return Container(
                decoration: BoxDecoration(
                  color: index.isEven
                      ? AppColors.emeraldDark
                      : AppColors.night.withOpacity(0.5),
                  border: isLast
                      ? null
                      : Border(bottom: BorderSide(color: AppColors.emerald.withOpacity(0.2))),
                ),
                padding: EdgeInsets.symmetric(vertical: 14.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatRating(rating),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 20.w),
                        padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 12.w),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Text(
                          _formatPoints(points),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 15.sp,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Виджет предпросмотра для бинарных настроек (положительный/отрицательный)
class BinaryPreviewWidget extends StatelessWidget {
  final String positiveLabel;
  final String negativeLabel;
  final double positivePoints;
  final double negativePoints;
  final List<Color> gradientColors;
  final String valueColumnTitle;
  final String pointsColumnTitle;
  final IconData negativeIcon;
  final Color? negativeIconColor;

  const BinaryPreviewWidget({
    super.key,
    required this.positiveLabel,
    required this.negativeLabel,
    required this.positivePoints,
    required this.negativePoints,
    this.gradientColors = const [Color(0xFFf46b45), Color(0xFFeea849)],
    this.valueColumnTitle = 'Результат',
    this.pointsColumnTitle = 'Баллы',
    this.negativeIcon = Icons.cancel,
    this.negativeIconColor,
  });

  String _formatPoints(double points) {
    if (points >= 0) return '+${points.toStringAsFixed(1)}';
    return points.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.emeraldDark,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.emerald.withOpacity(0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(vertical: 14.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      valueColumnTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.sp,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      pointsColumnTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.sp,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            // Positive row
            Container(
              decoration: BoxDecoration(
                color: AppColors.emeraldDark,
                border: Border(bottom: BorderSide(color: AppColors.emerald.withOpacity(0.2))),
              ),
              padding: EdgeInsets.symmetric(vertical: 14.h),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: AppColors.emeraldGreen, size: 20),
                        SizedBox(width: 8),
                        Text(
                          positiveLabel,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w500,
                            color: AppColors.emeraldGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 20.w),
                      padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 12.w),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        _formatPoints(positivePoints),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.emeraldGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 15.sp,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Negative row
            Builder(
              builder: (context) {
                final negColor = negativeIconColor ?? AppColors.error;
                return Container(
                  color: AppColors.night.withOpacity(0.5),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(negativeIcon, color: negColor, size: 20),
                            SizedBox(width: 8),
                            Text(
                              negativeLabel,
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w500,
                                color: negColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: 20.w),
                          padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 12.w),
                          decoration: BoxDecoration(
                            color: negColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Text(
                            _formatPoints(negativePoints),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: negColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 15.sp,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
