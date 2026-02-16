import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/review_model.dart';
import '../services/review_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
    _markDialogAsRead();
  }

  /// Отметить весь диалог как прочитанный
  Future<void> _markDialogAsRead() async {
    try {
      await ReviewService.markDialogRead(
        reviewId: _currentReview.id,
        readerType: widget.isAdmin ? 'admin' : 'client',
      );
    } catch (e) {
      // Игнорируем ошибки отметки прочитанным
    }
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
        
        // Если это ответ админа - push-уведомление отправляется через сервер
        // (см. loyalty-proxy/index.js - POST /api/reviews/:id/reply)
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
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
        child: Column(
          children: [
            // Информация об отзыве
            Container(
              padding: EdgeInsets.all(16.w),
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
                      SizedBox(width: 8),
                      Text(
                        _currentReview.reviewType == 'positive'
                            ? 'Положительный отзыв'
                            : 'Отрицательный отзыв',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Клиент: ${_currentReview.clientName}',
                    style: TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Телефон: ${_currentReview.clientPhone}',
                    style: TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Магазин: ${_currentReview.shopAddress}',
                    style: TextStyle(color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  Card(
                    color: Colors.white,
                    child: Padding(
                      padding: EdgeInsets.all(12.w),
                      child: Text(
                        _currentReview.reviewText,
                        style: TextStyle(fontSize: 16.sp),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Список сообщений
            Expanded(
              child: sortedMessages.isEmpty
                  ? Center(
                      child: Text(
                        'Пока нет сообщений в диалоге',
                        style: TextStyle(color: Colors.white, fontSize: 16.sp),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.all(16.w),
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
                            margin: EdgeInsets.only(bottom: 12.h),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.75,
                            ),
                            child: Card(
                              color: isAdminMessage
                                  ? Colors.blue.withOpacity(0.9)
                                  : Colors.white,
                              child: Padding(
                                padding: EdgeInsets.all(12.w),
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
                                            decoration: BoxDecoration(
                                              color: Colors.blue,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      message.text,
                                      style: TextStyle(
                                        color: isAdminMessage
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      _formatDateTime(message.createdAt),
                                      style: TextStyle(
                                        fontSize: 12.sp,
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
              padding: EdgeInsets.all(16.w),
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
                          borderRadius: BorderRadius.circular(24.r),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 12.h,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  SizedBox(width: 8),
                  IconButton(
                    icon: _isLoading
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.send),
                    onPressed: _isLoading ? null : _sendMessage,
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Color(0xFF004D40),
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
    // Добавляем 3 часа для конвертации UTC в МСК (UTC+3)
    final moscowDateTime = dateTime.add(Duration(hours: 3));
    final now = DateTime.now().toUtc().add(Duration(hours: 3));
    final difference = now.difference(moscowDateTime);

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
      return '${moscowDateTime.day}.${moscowDateTime.month}.${moscowDateTime.year}';
    }
  }
}
















