import 'package:flutter/material.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';
import 'reviews_shop_detail_page.dart';

/// Страница списка отзывов, сгруппированных по магазинам (для админа)
class ReviewsListPage extends StatefulWidget {
  const ReviewsListPage({super.key});

  @override
  State<ReviewsListPage> createState() => _ReviewsListPageState();
}

class _ReviewsListPageState extends State<ReviewsListPage> {
  bool _isLoading = true;
  Map<String, ShopReviewStats> _shopStats = {};

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
      final reviews = await ReviewService.getAllReviews();

      // Группируем по магазинам
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Отзывы покупателей'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReviews,
            tooltip: 'Обновить',
          ),
        ],
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
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _shopStats.isEmpty
                ? const Center(
                    child: Text(
                      'Нет отзывов',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _shopStats.length,
                    itemBuilder: (context, index) {
                      final shopAddress = _shopStats.keys.elementAt(index);
                      final stats = _shopStats[shopAddress]!;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF004D40),
                            child: Icon(
                              Icons.store,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            shopAddress,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Всего отзывов: ${stats.total}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Положительные
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${stats.positive}',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Отрицательные
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.cancel,
                                      color: Colors.red,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${stats.negative}',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReviewsShopDetailPage(
                                  shopAddress: shopAddress,
                                  reviews: stats.reviews,
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

/// Класс для хранения статистики отзывов магазина
class ShopReviewStats {
  final String shopAddress;
  final List<Review> reviews = [];
  int positive = 0;
  int negative = 0;

  ShopReviewStats({required this.shopAddress});

  int get total => positive + negative;

  void addReview(Review review) {
    reviews.add(review);
    if (review.reviewType == 'positive') {
      positive++;
    } else {
      negative++;
    }
  }
}
