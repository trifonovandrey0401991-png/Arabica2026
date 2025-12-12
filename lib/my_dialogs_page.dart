import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'review_model.dart';
import 'review_service.dart';
import 'review_detail_page.dart';

/// Страница "Мои диалоги" для клиента
class MyDialogsPage extends StatefulWidget {
  const MyDialogsPage({super.key});

  @override
  State<MyDialogsPage> createState() => _MyDialogsPageState();
}

class _MyDialogsPageState extends State<MyDialogsPage> {
  late Future<List<Review>> _reviewsFuture;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    
    if (phone.isEmpty) {
      setState(() {
        _reviewsFuture = Future.value([]);
      });
      return;
    }

    setState(() {
      _reviewsFuture = ReviewService.getClientReviews(phone);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои диалоги'),
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
        child: FutureBuilder<List<Review>>(
          future: _reviewsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,
                      size: 64,
                      color: Colors.white54,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'У вас пока нет диалогов',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Оставьте отзыв, чтобы начать диалог',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              );
            }

            final reviews = snapshot.data!;

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reviews.length,
              itemBuilder: (context, index) {
                final review = reviews[index];
                final lastMessage = review.getLastMessage();
                final unreadCount = review.getUnreadCountForClient();
                final hasUnread = review.hasUnreadForClient();

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
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            review.shopAddress,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (hasUnread)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          review.reviewType == 'positive'
                              ? 'Положительный отзыв'
                              : 'Отрицательный отзыв',
                          style: TextStyle(
                            color: review.reviewType == 'positive'
                                ? Colors.green
                                : Colors.red,
                            fontSize: 12,
                          ),
                        ),
                        if (lastMessage != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            lastMessage.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread ? Colors.blue : Colors.grey,
                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
            );
          },
        ),
      ),
    );
  }
}











