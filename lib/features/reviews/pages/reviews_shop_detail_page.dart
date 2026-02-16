import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';
import 'review_detail_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница списка отзывов конкретного магазина (для админа)
class ReviewsShopDetailPage extends StatefulWidget {
  final String shopAddress;
  final List<Review> initialReviews;

  const ReviewsShopDetailPage({
    super.key,
    required this.shopAddress,
    required List<Review> reviews,
  }) : initialReviews = reviews;

  @override
  State<ReviewsShopDetailPage> createState() => _ReviewsShopDetailPageState();
}

class _ReviewsShopDetailPageState extends State<ReviewsShopDetailPage> {
  late List<Review> _reviews;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _reviews = widget.initialReviews;
  }

  Future<void> _loadReviews() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final allReviews = await ReviewService.getAllReviews();
      final filteredReviews = allReviews
          .where((r) => r.shopAddress == widget.shopAddress)
          .toList();

      if (mounted) {
        setState(() {
          _reviews = filteredReviews;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Сортируем отзывы по дате (новые сверху)
    final sortedReviews = List<Review>.from(_reviews)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.shopAddress,
          style: TextStyle(fontSize: 16.sp),
        ),
        backgroundColor: Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : sortedReviews.isEmpty
                ? Center(
                    child: Text(
                      'Нет отзывов',
                      style: TextStyle(color: Colors.white, fontSize: 18.sp),
                    ),
                  )
                : ListView.builder(
                padding: EdgeInsets.all(16.w),
                itemCount: sortedReviews.length,
                itemBuilder: (context, index) {
                  final review = sortedReviews[index];
                  final isPositive = review.reviewType == 'positive';
                  final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

                  return Card(
                    margin: EdgeInsets.only(bottom: 12.h),
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isPositive
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPositive ? Icons.check_circle : Icons.cancel,
                          color: isPositive ? Colors.green : Colors.red,
                          size: 24,
                        ),
                      ),
                      title: Text(
                        review.clientName.isNotEmpty
                            ? review.clientName
                            : 'Клиент',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            review.reviewText.length > 50
                                ? '${review.reviewText.substring(0, 50)}...'
                                : review.reviewText,
                            style: TextStyle(color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                dateFormat.format(review.createdAt.add(Duration(hours: 3))),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12.sp,
                                ),
                              ),
                              if (review.messages.isNotEmpty) ...[
                                SizedBox(width: 8),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6.w,
                                    vertical: 2.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  child: Text(
                                    '${review.messages.length} сообщ.',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontSize: 11.sp,
                                    ),
                                  ),
                                ),
                              ],
                              // Показать badge с непрочитанными от клиента
                              if (review.hasUnreadFromClient) ...[
                                SizedBox(width: 8),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6.w,
                                    vertical: 2.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  child: Text(
                                    'непрочитано',
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
                      trailing: Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ReviewDetailPage(
                              review: review,
                              isAdmin: true,
                            ),
                          ),
                        );
                        // Перезагружаем список отзывов после возврата
                        await _loadReviews();
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
