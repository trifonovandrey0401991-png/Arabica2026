import 'package:flutter/material.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';
import 'reviews_shop_detail_page.dart';
import '../../../core/services/base_http_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../clients/pages/management_dialogs_list_page.dart';

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
                    itemCount: _shopStats.length + 1,
                    itemBuilder: (context, index) {
                      // Первый элемент - "Связь с руководством"
                      if (index == 0) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: Stack(
                              children: [
                                const CircleAvatar(
                                  backgroundColor: Color(0xFFFF6F00),
                                  child: Icon(
                                    Icons.business,
                                    color: Colors.white,
                                  ),
                                ),
                                if (_managementUnreadCount > 0)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        _managementUnreadCount > 9 ? '9+' : '$_managementUnreadCount',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            title: const Text(
                              'Связь с руководством',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: const Text(
                              'Сообщения от клиентов',
                              style: TextStyle(color: Colors.grey),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ManagementDialogsListPage(),
                                ),
                              );
                              // Перезагрузить счетчик после возврата
                              _loadManagementUnreadCount();
                            },
                          ),
                        );
                      }

                      // Остальные элементы - магазины
                      final shopIndex = index - 1;
                      final shopAddress = _shopStats.keys.elementAt(shopIndex);
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
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Всего отзывов: ${stats.total}',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  // Положительные
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
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
                                          size: 14,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${stats.positive}',
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Отрицательные
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
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
                                          size: 14,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${stats.negative}',
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Непрочитанные
                                  if (stats.unread > 0) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'непрочитано: ${stats.unread}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
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
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReviewsShopDetailPage(
                                  shopAddress: shopAddress,
                                  reviews: stats.reviews,
                                ),
                              ),
                            );
                            // Перезагрузить список после возврата
                            _loadReviews();
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
