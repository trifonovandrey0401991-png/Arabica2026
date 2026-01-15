import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../models/product_question_model.dart';
import '../services/product_question_service.dart';
import 'product_question_dialog_page.dart';
import 'product_question_client_dialog_page.dart';

/// Страница списка магазинов для поиска товара
class ProductQuestionShopsListPage extends StatefulWidget {
  const ProductQuestionShopsListPage({super.key});

  @override
  State<ProductQuestionShopsListPage> createState() => _ProductQuestionShopsListPageState();
}

class _ProductQuestionShopsListPageState extends State<ProductQuestionShopsListPage> {
  ProductQuestionGroupedData? _groupedData;
  bool _isLoading = true;
  String? _clientPhone;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Автообновление каждые 5 секунд
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';

    if (phone.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _clientPhone = phone;
    });

    try {
      final data = await ProductQuestionService.getClientGroupedDialogs(phone);
      if (mounted) {
        setState(() {
          _groupedData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
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
        title: const Text('Поиск товара'),
        backgroundColor: Colors.purple,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groupedData == null || (_groupedData!.byShop.isEmpty && _groupedData!.networkWideQuestions.isEmpty)
              ? const Center(
                  child: Text(
                    'Нет диалогов',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Вся сеть (если есть)
                      if (_groupedData!.networkWideQuestions.isNotEmpty)
                        _buildNetworkWideCard(),

                      // Магазины
                      ..._buildShopCards(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildNetworkWideCard() {
    final unread = _groupedData!.networkWideUnreadCount;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: unread > 0 ? Colors.purple[50] : null,
      child: ListTile(
        leading: Stack(
          children: [
            const Icon(Icons.public, size: 40, color: Colors.purple),
            if (unread > 0)
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
                    unread > 99 ? '99+' : unread.toString(),
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
          'Вся сеть',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${_groupedData!.networkWideQuestions.length} вопрос(ов)',
          style: const TextStyle(fontSize: 14),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () async {
          // Открываем общий диалог (все вопросы без привязки к магазину)
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ProductQuestionClientDialogPage(),
            ),
          );
          _loadData();
        },
      ),
    );
  }

  List<Widget> _buildShopCards() {
    final sortedShops = _groupedData!.getSortedShops();

    return sortedShops.map((shopAddress) {
      final group = _groupedData!.byShop[shopAddress]!;
      final unread = group.unreadCount;
      final lastMessage = group.getLastMessage();

      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: unread > 0 ? Colors.purple[50] : null,
        child: ListTile(
          leading: Stack(
            children: [
              const Icon(Icons.store, size: 40, color: Colors.purple),
              if (unread > 0)
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
                      unread > 99 ? '99+' : unread.toString(),
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
          title: Text(
            shopAddress,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: lastMessage != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          lastMessage.senderType == 'client'
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 14,
                          color: lastMessage.senderType == 'client'
                              ? Colors.blue
                              : Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            lastMessage.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              : Text(
                  '${group.questions.length + group.dialogs.length} сообщени(й/я)',
                  style: const TextStyle(fontSize: 14),
                ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () async {
            // Находим первый questionId для этого магазина
            String? questionId;

            if (group.questions.isNotEmpty) {
              questionId = group.questions.first.id;
            } else if (group.dialogs.isNotEmpty) {
              questionId = group.dialogs.first.originalQuestionId;
            }

            if (questionId != null) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProductQuestionDialogPage(
                    questionId: questionId!,
                  ),
                ),
              );
              // Обновляем после возврата
              _loadData();
            }
          },
        ),
      );
    }).toList();
  }
}
