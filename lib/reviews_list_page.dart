import 'package:flutter/material.dart';
import 'review_model.dart';
import 'review_service.dart';
import 'review_detail_page.dart';

/// Страница списка всех отзывов (для админа)
class ReviewsListPage extends StatefulWidget {
  const ReviewsListPage({super.key});

  @override
  State<ReviewsListPage> createState() => _ReviewsListPageState();
}

class _ReviewsListPageState extends State<ReviewsListPage> {
  late Future<List<Review>> _reviewsFuture;
  String _searchQuery = '';
  String? _selectedType; // 'positive', 'negative', или null (все)

  @override
  void initState() {
    super.initState();
    _reviewsFuture = ReviewService.getAllReviews();
  }

  void _refreshReviews() {
    setState(() {
      _reviewsFuture = ReviewService.getAllReviews();
    });
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
            onPressed: _refreshReviews,
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
        child: Column(
          children: [
            // Поиск и фильтры
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white.withOpacity(0.1),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Поиск по имени или телефону...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedType,
                          decoration: InputDecoration(
                            labelText: 'Тип отзыва',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Все типы'),
                            ),
                            const DropdownMenuItem<String>(
                              value: 'positive',
                              child: Text('Положительные'),
                            ),
                            const DropdownMenuItem<String>(
                              value: 'negative',
                              child: Text('Отрицательные'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedType = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Список отзывов
            Expanded(
              child: FutureBuilder<List<Review>>(
                future: _reviewsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text(
                        'Отзывы не найдены',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    );
                  }

                  var reviews = snapshot.data!;

                  // Фильтрация
                  if (_searchQuery.isNotEmpty) {
                    reviews = reviews.where((r) {
                      return r.clientName.toLowerCase().contains(_searchQuery) ||
                          r.clientPhone.contains(_searchQuery) ||
                          r.shopAddress.toLowerCase().contains(_searchQuery);
                    }).toList();
                  }

                  if (_selectedType != null) {
                    reviews = reviews.where((r) => r.reviewType == _selectedType).toList();
                  }

                  if (reviews.isEmpty) {
                    return const Center(
                      child: Text(
                        'Отзывы не найдены',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: reviews.length,
                    itemBuilder: (context, index) {
                      final review = reviews[index];
                      final lastMessage = review.getLastMessage();
                      final hasUnread = review.messages.any((m) => m.sender == 'admin' && !m.isRead);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: review.reviewType == 'positive'
                                ? Colors.green
                                : Colors.red,
                            child: Icon(
                              review.reviewType == 'positive'
                                  ? Icons.thumb_up
                                  : Icons.thumb_down,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            review.clientName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(review.shopAddress),
                              if (lastMessage != null)
                                Text(
                                  lastMessage.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: hasUnread ? Colors.blue : Colors.grey,
                                    fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasUnread)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Text(
                                    '!',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              const Icon(Icons.arrow_forward_ios, size: 16),
                            ],
                          ),
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
                            if (result == true) {
                              _refreshReviews();
                            }
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}









