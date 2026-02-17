import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';
import 'review_detail_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница списка отзывов клиента (из "Мои диалоги")
class ClientReviewsListPage extends StatefulWidget {
  const ClientReviewsListPage({super.key});

  @override
  State<ClientReviewsListPage> createState() => _ClientReviewsListPageState();
}

class _ClientReviewsListPageState extends State<ClientReviewsListPage> {
  bool _isLoading = true;
  List<Review> _reviews = [];

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final clientPhone = prefs.getString('user_phone') ?? '';

      if (clientPhone.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final reviews = await ReviewService.getClientReviews(clientPhone);

      // Сортируем по дате (новые сверху)
      reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _reviews = reviews;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Мои отзывы'),
        backgroundColor: AppColors.primaryGreen,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadReviews,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryGreen,
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _reviews.isEmpty
                ? Center(
                    child: Text(
                      'У вас пока нет отзывов',
                      style: TextStyle(color: Colors.white, fontSize: 18.sp),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(16.w),
                    itemCount: _reviews.length,
                    itemBuilder: (context, index) {
                      final review = _reviews[index];
                      final isPositive = review.reviewType == 'positive';
                      final lastMessage = review.getLastMessage();
                      final unreadCount = review.getUnreadCountForClient();
                      final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

                      return Card(
                        margin: EdgeInsets.only(bottom: 12.h),
                        child: ListTile(
                          leading: Stack(
                            children: [
                              Container(
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
                              // Бейдж непрочитанных
                              if (unreadCount > 0)
                                Positioned(
                                  right: 0.w,
                                  top: 0.h,
                                  child: Container(
                                    padding: EdgeInsets.all(4.w),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      '$unreadCount',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Text(
                            review.shopAddress,
                            style: TextStyle(
                              fontWeight: unreadCount > 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Показываем последнее сообщение или текст отзыва
                              Text(
                                lastMessage != null
                                    ? '${lastMessage.sender == 'admin' ? 'Ответ: ' : ''}${lastMessage.text}'
                                    : review.reviewText,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: unreadCount > 0
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 4),
                              Text(
                                dateFormat.format(
                                  (lastMessage?.createdAt ?? review.createdAt).add(Duration(hours: 3)),
                                ),
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12.sp,
                                ),
                              ),
                            ],
                          ),
                          trailing: Icon(Icons.chevron_right),
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReviewDetailPage(
                                  review: review,
                                  isAdmin: false,
                                ),
                              ),
                            );
                            if (result == true) {
                              _loadReviews();
                            }
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
