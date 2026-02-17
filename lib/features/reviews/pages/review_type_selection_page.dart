import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import 'review_shop_selection_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница выбора типа отзыва (положительный/отрицательный)
class ReviewTypeSelectionPage extends StatelessWidget {
  const ReviewTypeSelectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    Logger.debug('ReviewTypeSelectionPage.build() вызван');
    try {
      return Scaffold(
        backgroundColor: AppColors.night,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
              stops: [0.0, 0.3, 1.0],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildAppBar(context),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20.w, 0.h, 20.w, 20.h),
                    child: Column(
                      children: [
                        SizedBox(height: 48),
                        // Иконка
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20.r),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.15),
                            ),
                          ),
                          child: Icon(
                            Icons.rate_review_outlined,
                            size: 36,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                        SizedBox(height: 24),
                        Text(
                          'Выберите тип отзыва',
                          style: TextStyle(
                            fontSize: 22.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.9),
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Ваше мнение важно для нас',
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: Colors.white.withOpacity(0.5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        Spacer(),
                        // Положительный отзыв
                        _buildReviewCard(
                          context: context,
                          title: 'Положительный отзыв',
                          subtitle: 'Нам понравилось!',
                          icon: Icons.thumb_up_rounded,
                          accentColor: AppColors.success,
                          reviewType: 'positive',
                        ),
                        SizedBox(height: 16),
                        // Отрицательный отзыв
                        _buildReviewCard(
                          context: context,
                          title: 'Отрицательный отзыв',
                          subtitle: 'Есть замечания',
                          icon: Icons.thumb_down_rounded,
                          accentColor: Color(0xFFEF5350),
                          reviewType: 'negative',
                        ),
                        Spacer(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e, stackTrace) {
      Logger.error('Ошибка в ReviewTypeSelectionPage.build()', e, stackTrace);
      return Scaffold(
        appBar: AppBar(
          title: Text('Ошибка'),
          backgroundColor: AppColors.emerald,
        ),
        body: Center(
          child: Text('Ошибка: $e'),
        ),
      );
    }
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 16.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Оставить отзыв',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildReviewCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required String reviewType,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReviewShopSelectionPage(
              reviewType: reviewType,
            ),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: accentColor.withOpacity(0.4)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accentColor.withOpacity(0.15),
              accentColor.withOpacity(0.05),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 28,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.95),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withOpacity(0.5),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
