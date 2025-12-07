import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'review_model.dart';
import 'review_service.dart';

/// Страница детального просмотра отзыва/диалога
class ReviewDetailPage extends StatefulWidget {
  final Review review;
  final bool isAdmin; // true для админа, false для клиента

  const ReviewDetailPage({
    super.key,
    required this.review,
    this.isAdmin = false,
  });

  @override
  State<ReviewDetailPage> createState() => _ReviewDetailPageState();
}

class _ReviewDetailPageState extends State<ReviewDetailPage> {
  late Review _currentReview;
  final _messageController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentReview = widget.review;
    _loadReview();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadReview() async {
    final review = await ReviewService.getReviewById(_currentReview.id);
    if (review != null && mounted) {
      setState(() {
        _currentReview = review;
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String senderName;
      if (widget.isAdmin) {
        senderName = 'Администратор';
      } else {
        final prefs = await SharedPreferences.getInstance();
        senderName = prefs.getString('user_name') ?? 'Клиент';
      }

      final success = await ReviewService.addMessage(
        reviewId: _currentReview.id,
        sender: widget.isAdmin ? 'admin' : 'client',
        senderName: senderName,
        text: _messageController.text.trim(),
      );

      if (success) {
        _messageController.clear();
        await _loadReview();
        
        // Если это ответ админа, отправляем push-уведомление клиенту
        if (widget.isAdmin) {
          // TODO: Отправить push-уведомление клиенту через FCM
          // Это будет реализовано после настройки Firebase
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка при отправке сообщения'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAsRead(ReviewMessage message) async {
    if (message.isRead) return;

    final success = await ReviewService.markMessageAsRead(
      reviewId: _currentReview.id,
      messageId: message.id,
    );

    if (success) {
      await _loadReview();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Сортируем сообщения по дате
    final sortedMessages = List<ReviewMessage>.from(_currentReview.messages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'Отзыв покупателя' : 'Мой отзыв'),
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
        child: Column(
          children: [
            // Информация об отзыве
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white.withOpacity(0.1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _currentReview.reviewType == 'positive'
                            ? Icons.thumb_up
                            : Icons.thumb_down,
                        color: _currentReview.reviewType == 'positive'
                            ? Colors.green
                            : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _currentReview.reviewType == 'positive'
                            ? 'Положительный отзыв'
                            : 'Отрицательный отзыв',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Клиент: ${_currentReview.clientName}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Телефон: ${_currentReview.clientPhone}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Магазин: ${_currentReview.shopAddress}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _currentReview.reviewText,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Список сообщений
            Expanded(
              child: sortedMessages.isEmpty
                  ? const Center(
                      child: Text(
                        'Пока нет сообщений в диалоге',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: sortedMessages.length,
                      itemBuilder: (context, index) {
                        final message = sortedMessages[index];
                        final isAdminMessage = message.sender == 'admin';
                        final isUnread = !message.isRead && !isAdminMessage && !widget.isAdmin;

                        // Отмечаем как прочитанное при просмотре (для клиента)
                        if (isUnread && !widget.isAdmin) {
                          _markAsRead(message);
                        }

                        return Align(
                          alignment: isAdminMessage
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                            ),
                            child: Card(
                              color: isAdminMessage
                                  ? Colors.blue.withOpacity(0.9)
                                  : Colors.white,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          message.senderName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isAdminMessage
                                                ? Colors.white
                                                : Colors.black,
                                          ),
                                        ),
                                        if (isUnread)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: Colors.blue,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      message.text,
                                      style: TextStyle(
                                        color: isAdminMessage
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDateTime(message.createdAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isAdminMessage
                                            ? Colors.white70
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Поле ввода сообщения
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white.withOpacity(0.1),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Введите сообщение...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _isLoading ? null : _sendMessage,
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF004D40),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'только что';
        }
        return '${difference.inMinutes} мин. назад';
      }
      return '${difference.inHours} ч. назад';
    } else if (difference.inDays == 1) {
      return 'вчера';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн. назад';
    } else {
      return '${dateTime.day}.${dateTime.month}.${dateTime.year}';
    }
  }
}





