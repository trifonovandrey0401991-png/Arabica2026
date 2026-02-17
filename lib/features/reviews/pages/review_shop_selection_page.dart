import 'package:flutter/material.dart';
import '../../shops/services/shop_service.dart';
import 'review_text_input_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../shared/widgets/shop_selection_scaffold.dart';

/// Страница выбора магазина для отзыва
class ReviewShopSelectionPage extends StatelessWidget {
  final String reviewType;

  const ReviewShopSelectionPage({
    super.key,
    required this.reviewType,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = reviewType == 'positive';
    final accentColor = isPositive ? Colors.green : Colors.red;

    return ShopSelectionScaffold(
      title: 'Выберите магазин',
      loadShops: () => ShopService.getShopsForCurrentUser(),
      onShopTap: (context, shop) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReviewTextInputPage(
              reviewType: reviewType,
              shop: shop,
            ),
          ),
        );
      },
      headerWidget: _buildReviewTypeBanner(isPositive, accentColor),
    );
  }

  Widget _buildReviewTypeBanner(bool isPositive, Color accentColor) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 14.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: accentColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              isPositive ? Icons.thumb_up_rounded : Icons.thumb_down_rounded,
              color: accentColor,
              size: 24,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPositive ? 'Положительный отзыв' : 'Отрицательный отзыв',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Выберите магазин из списка',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 13.sp,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
