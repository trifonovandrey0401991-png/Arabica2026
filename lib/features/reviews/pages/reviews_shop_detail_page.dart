import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/review_model.dart';
import 'review_detail_page.dart';

/// Страница списка отзывов конкретного магазина (для админа)
class ReviewsShopDetailPage extends StatelessWidget {
  final String shopAddress;
  final List<Review> reviews;

  const ReviewsShopDetailPage({
    super.key,
    required this.shopAddress,
    required this.reviews,
  });

  @override
  Widget build(BuildContext context) {
    // Сортируем отзывы по дате (новые сверху)
    final sortedReviews = List<Review>.from(reviews)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          shopAddress,
          style: const TextStyle(fontSize: 16),
        ),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: sortedReviews.isEmpty
            ? const Center(
                child: Text(
                  'Нет отзывов',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sortedReviews.length,
                itemBuilder: (context, index) {
                  final review = sortedReviews[index];
                  final isPositive = review.reviewType == 'positive';
                  final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
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
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            review.reviewText.length > 50
                                ? '${review.reviewText.substring(0, 50)}...'
                                : review.reviewText,
                            style: const TextStyle(color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                dateFormat.format(review.createdAt),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              if (review.messages.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${review.messages.length} сообщ.',
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ReviewDetailPage(
                              review: review,
                              isAdmin: true,
                            ),
                          ),
                        );
                        if (!context.mounted) return;
                        if (result == true) {
                          // Возвращаем true, чтобы обновить список на предыдущей странице
                          Navigator.of(context).pop(true);
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
