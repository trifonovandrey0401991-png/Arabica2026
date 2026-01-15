import 'package:flutter/material.dart';
import '../models/product_question_model.dart';
import '../services/product_question_service.dart';

class ProductQuestionDialogPage extends StatefulWidget {
  final String questionId;

  const ProductQuestionDialogPage({
    super.key,
    required this.questionId,
  });

  @override
  State<ProductQuestionDialogPage> createState() => _ProductQuestionDialogPageState();
}

class _ProductQuestionDialogPageState extends State<ProductQuestionDialogPage> {
  ProductQuestion? _question;
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadQuestion();
    _markAsRead();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _loadQuestion();
        _startAutoRefresh();
      }
    });
  }

  Future<void> _loadQuestion() async {
    try {
      final question = await ProductQuestionService.getQuestion(widget.questionId);
      if (mounted) {
        setState(() {
          _question = question;
          _isLoading = false;
        });
        // Прокручиваем вниз после загрузки
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки диалога: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Вчера ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else {
        return '${date.day}.${date.month}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  Future<void> _markAsRead() async {
    try {
      await ProductQuestionService.markQuestionAsRead(
        questionId: widget.questionId,
        readerType: 'client',
      );
    } catch (e) {
      // Игнорируем ошибки
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_question?.shopAddress ?? 'Диалог'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadQuestion,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _question == null
              ? const Center(
                  child: Text(
                    'Диалог не найден',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: _question!.messages.length,
                  itemBuilder: (context, index) {
                    final message = _question!.messages[_question!.messages.length - 1 - index];
                    final isFromClient = message.senderType == 'client';
                    
                    return Align(
                      alignment: isFromClient 
                          ? Alignment.centerLeft 
                          : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isFromClient 
                              ? Colors.grey[300]
                              : const Color(0xFF004D40),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isFromClient) ...[
                              Text(
                                'Ответ от магазина ${message.shopAddress}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 4),
                            ],
                            Text(
                              message.text,
                              style: TextStyle(
                                color: isFromClient ? Colors.black87 : Colors.white,
                              ),
                            ),
                            if (message.imageUrl != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  message.imageUrl!.startsWith('http')
                                      ? message.imageUrl!
                                      : 'https://arabica26.ru${message.imageUrl}',
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      height: 200,
                                      color: Colors.grey[300],
                                      child: const Center(
                                        child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              _formatTimestamp(message.timestamp),
                              style: TextStyle(
                                fontSize: 10,
                                color: isFromClient 
                                    ? Colors.black54 
                                    : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}



