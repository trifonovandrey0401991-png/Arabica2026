import 'package:flutter/material.dart';
import '../../../core/widgets/shop_icon.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import 'review_text_input_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница выбора магазина для отзыва
class ReviewShopSelectionPage extends StatelessWidget {
  final String reviewType;

  const ReviewShopSelectionPage({
    super.key,
    required this.reviewType,
  });

  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final isPositive = reviewType == 'positive';
    final accentColor = isPositive ? Colors.green : Colors.red;

    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Выберите магазин',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: FutureBuilder<List<Shop>>(
                  future: ShopService.getShopsForCurrentUser(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: CircularProgressIndicator(color: _gold),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.error_outline, size: 40, color: Colors.red.shade300),
                            ),
                            SizedBox(height: 20),
                            Text(
                              'Что-то пошло не так',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Попробуйте позже',
                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14.sp),
                            ),
                            SizedBox(height: 24),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(Icons.arrow_back, color: Colors.white.withOpacity(0.7)),
                              label: Text('Назад', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final shops = snapshot.data ?? [];
                    if (shops.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.store_mall_directory_outlined, size: 40, color: Colors.white.withOpacity(0.3)),
                            ),
                            SizedBox(height: 20),
                            Text(
                              'Магазины не найдены',
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16.sp),
                            ),
                          ],
                        ),
                      );
                    }

                    return Column(
                      children: [
                        // Заголовок с типом отзыва
                        Container(
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
                        ),
                        // Список магазинов
                        Expanded(
                          child: ListView.builder(
                            padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 16.h),
                            itemCount: shops.length,
                            itemBuilder: (context, index) {
                              final shop = shops[index];
                              return _buildShopCard(context, shop);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShopCard(BuildContext context, Shop shop) {
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () {
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
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                // Иконка магазина
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: ShopIcon(size: 52),
                  ),
                ),
                SizedBox(width: 14),
                // Адрес магазина
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.address,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.storefront, size: 14, color: Colors.white.withOpacity(0.3)),
                          SizedBox(width: 4),
                          Text(
                            'Магазин',
                            style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.3)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Стрелка
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: _gold.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
