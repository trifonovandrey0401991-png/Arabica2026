import 'package:flutter/material.dart';
import 'product_question_model.dart';
import 'product_question_service.dart';
import 'product_question_answer_page.dart';
import 'shop_model.dart';

class ProductQuestionsManagementPage extends StatefulWidget {
  const ProductQuestionsManagementPage({super.key});

  @override
  State<ProductQuestionsManagementPage> createState() => _ProductQuestionsManagementPageState();
}

class _ProductQuestionsManagementPageState extends State<ProductQuestionsManagementPage> {
  List<ProductQuestion> _questions = [];
  List<Shop> _shops = [];
  bool _isLoading = true;
  String? _selectedShopAddress;
  bool? _filterAnswered; // null = все, true = отвеченные, false = неотвеченные

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final shops = await Shop.loadShopsFromServer();
      await _loadQuestions();
      
      setState(() {
        _shops = shops;
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

  Future<void> _loadQuestions() async {
    try {
      final questions = await ProductQuestionService.getQuestions(
        shopAddress: _selectedShopAddress,
        isAnswered: _filterAnswered,
      );
      
      setState(() {
        _questions = questions;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки вопросов: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      return '${date.day}.${date.month}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ответы (поиск товара)'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadQuestions,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          // Фильтры
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              children: [
                // Фильтр по магазину
                DropdownButtonFormField<String>(
                  value: _selectedShopAddress,
                  decoration: const InputDecoration(
                    labelText: 'Магазин',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Все магазины'),
                    ),
                    ..._shops.map((shop) => DropdownMenuItem<String>(
                      value: shop.address,
                      child: Text(shop.address),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedShopAddress = value;
                    });
                    _loadQuestions();
                  },
                ),
                const SizedBox(height: 12),
                // Фильтр по статусу
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Все'),
                        selected: _filterAnswered == null,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _filterAnswered = null;
                            });
                            _loadQuestions();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Неотвеченные'),
                        selected: _filterAnswered == false,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _filterAnswered = false;
                            });
                            _loadQuestions();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Отвеченные'),
                        selected: _filterAnswered == true,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _filterAnswered = true;
                            });
                            _loadQuestions();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Список вопросов
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _questions.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет вопросов',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _questions.length,
                        itemBuilder: (context, index) {
                          final question = _questions[index];
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: question.isAnswered
                                    ? Colors.green
                                    : Colors.orange,
                                child: Icon(
                                  question.isAnswered
                                      ? Icons.check
                                      : Icons.warning,
                                  color: Colors.white,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      question.clientName,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (!question.isAnswered)
                                    const Icon(
                                      Icons.warning,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    question.clientPhone,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Магазин: ${question.shopAddress}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    question.questionText,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTimestamp(question.timestamp),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ProductQuestionAnswerPage(
                                      questionId: question.id,
                                    ),
                                  ),
                                );
                                _loadQuestions(); // Обновляем после возврата
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

