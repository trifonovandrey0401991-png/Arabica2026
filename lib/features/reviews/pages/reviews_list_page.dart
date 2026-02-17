import 'package:flutter/material.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';
import 'reviews_shop_detail_page.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/multitenancy_filter_service.dart';
import '../../clients/pages/management_dialogs_list_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница списка отзывов, сгруппированных по магазинам (для админа)
class ReviewsListPage extends StatefulWidget {
  const ReviewsListPage({super.key});

  @override
  State<ReviewsListPage> createState() => _ReviewsListPageState();
}

class _ReviewsListPageState extends State<ReviewsListPage> {
  bool _isLoading = true;
  Map<String, ShopReviewStats> _shopStats = {};
  int _managementUnreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadReviews();
    _loadManagementUnreadCount();
  }

  Future<void> _loadReviews() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final allReviews = await ReviewService.getAllReviews();

      final reviews = await MultitenancyFilterService.filterByShopAddress(
        allReviews,
        (review) => review.shopAddress,
      );

      final stats = <String, ShopReviewStats>{};

      for (final review in reviews) {
        final shopAddress = review.shopAddress;

        if (!stats.containsKey(shopAddress)) {
          stats[shopAddress] = ShopReviewStats(shopAddress: shopAddress);
        }

        stats[shopAddress]!.addReview(review);
      }

      setState(() {
        _shopStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadManagementUnreadCount() async {
    try {
      final result = await BaseHttpService.getRaw(
        endpoint: '/api/management-dialogs',
        timeout: ApiConstants.longTimeout,
      );

      if (result != null && result['success'] == true) {
        if (mounted) {
          setState(() {
            _managementUnreadCount = result['totalUnread'] ?? 0;
          });
        }
      }
    } catch (e) {
      // Игнорируем ошибки загрузки счетчика
    }
  }

  @override
  Widget build(BuildContext context) {
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
              // Custom AppBar
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
                        'Отзывы покупателей',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadReviews,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _shopStats.isEmpty
                        ? Center(
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
                                  child: Icon(Icons.reviews, size: 40, color: Colors.white.withOpacity(0.3)),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Нет отзывов',
                                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16.sp),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadReviews,
                            color: AppColors.gold,
                            backgroundColor: AppColors.emeraldDark,
                            child: ListView.builder(
                              padding: EdgeInsets.all(16.w),
                              itemCount: _shopStats.length + 1,
                              itemBuilder: (context, index) {
                                // Первый элемент - "Связь с руководством"
                                if (index == 0) {
                                  return _buildManagementCard();
                                }

                                // Остальные элементы - магазины
                                final shopIndex = index - 1;
                                final shopAddress = _shopStats.keys.elementAt(shopIndex);
                                final stats = _shopStats[shopAddress]!;

                                return _buildShopCard(shopAddress, stats);
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManagementCard() {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ManagementDialogsListPage(),
              ),
            );
            _loadManagementUnreadCount();
          },
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Icon(Icons.business, color: Colors.orange, size: 24),
                    ),
                    if (_managementUnreadCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: EdgeInsets.all(4.w),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            _managementUnreadCount > 9 ? '9+' : '$_managementUnreadCount',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Связь с руководством',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Сообщения от клиентов',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13.sp),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShopCard(String shopAddress, ShopReviewStats stats) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ReviewsShopDetailPage(
                  shopAddress: shopAddress,
                  reviews: stats.reviews,
                ),
              ),
            );
            _loadReviews();
          },
          child: Padding(
            padding: EdgeInsets.all(14.w),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.emerald,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(Icons.store, color: Colors.white, size: 24),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shopAddress,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Всего отзывов: ${stats.total}',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13.sp),
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          // Положительные
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 14),
                                SizedBox(width: 2),
                                Text(
                                  '${stats.positive}',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.sp,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 6),
                          // Отрицательные
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.cancel, color: Colors.red, size: 14),
                                SizedBox(width: 2),
                                Text(
                                  '${stats.negative}',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.sp,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Непрочитанные
                          if (stats.unread > 0) ...[
                            SizedBox(width: 6),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                'новых: ${stats.unread}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Класс для хранения статистики отзывов магазина
class ShopReviewStats {
  final String shopAddress;
  final List<Review> reviews = [];
  int positive = 0;
  int negative = 0;
  int unread = 0;

  ShopReviewStats({required this.shopAddress});

  int get total => positive + negative;

  void addReview(Review review) {
    reviews.add(review);
    if (review.reviewType == 'positive') {
      positive++;
    } else {
      negative++;
    }
    if (review.hasUnreadFromClient) {
      unread++;
    }
  }
}
