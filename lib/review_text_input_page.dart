import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shop_model.dart';
import 'review_service.dart';

/// Страница ввода текста отзыва
class ReviewTextInputPage extends StatefulWidget {
  final String reviewType;
  final Shop shop;

  const ReviewTextInputPage({
    super.key,
    required this.reviewType,
    required this.shop,
  });

  @override
  State<ReviewTextInputPage> createState() => _ReviewTextInputPageState();
}

class _ReviewTextInputPageState extends State<ReviewTextInputPage> {
  final _textController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пожалуйста, введите текст отзыва'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Получаем данные клиента из SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final clientPhone = prefs.getString('user_phone') ?? '';
      final clientName = prefs.getString('user_name') ?? '';

      if (clientPhone.isEmpty || clientName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка: данные пользователя не найдены'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Создаем отзыв
      final review = await ReviewService.createReview(
        clientPhone: clientPhone,
        clientName: clientName,
        shopAddress: widget.shop.address,
        reviewType: widget.reviewType,
        reviewText: _textController.text.trim(),
      );

      if (mounted) {
        if (review != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Отзыв успешно отправлен!'),
              backgroundColor: Colors.green,
            ),
          );
          // Возвращаемся на главный экран
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка при отправке отзыва'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Напишите отзыв'),
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
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Информация о магазине
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        widget.shop.icon,
                        size: 40,
                        color: const Color(0xFF004D40),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.shop.address,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Тип отзыва
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        widget.reviewType == 'positive'
                            ? Icons.thumb_up
                            : Icons.thumb_down,
                        color: widget.reviewType == 'positive'
                            ? Colors.green
                            : Colors.red,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.reviewType == 'positive'
                            ? 'Положительный отзыв'
                            : 'Отрицательный отзыв',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Поле ввода текста
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _textController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Введите ваш отзыв...',
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Кнопки
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.of(context).pop();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Вернуться',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitReview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Отправить',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}





