import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/clients/models/client_dialog_model.dart';
import '../../features/clients/services/client_dialog_service.dart';
import '../../features/clients/pages/client_dialog_page.dart';

/// Страница "Мои диалоги" для клиента
class MyDialogsPage extends StatefulWidget {
  const MyDialogsPage({super.key});

  @override
  State<MyDialogsPage> createState() => _MyDialogsPageState();
}

class _MyDialogsPageState extends State<MyDialogsPage> {
  late Future<List<ClientDialog>> _dialogsFuture = Future.value([]);

  @override
  void initState() {
    super.initState();
    _loadDialogs();
  }

  Future<void> _loadDialogs() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    
    if (phone.isEmpty) {
      setState(() {
        _dialogsFuture = Future.value([]);
      });
      return;
    }

    setState(() {
      _dialogsFuture = ClientDialogService.getClientDialogs(phone);
    });
  }

  String _formatTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Сегодня ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Вчера ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else {
        return '${date.day}.${date.month}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  String _getMessagePreview(dynamic message) {
    if (message == null) return '';
    
    try {
      switch (message.type) {
        case 'review':
          return message.data['reviewText'] ?? 'Отзыв';
        case 'product_question':
          return message.data['questionText'] ?? 'Вопрос о товаре';
        case 'order':
          final orderNumber = message.data['orderNumber'];
          if (orderNumber != null) {
            return 'Заказ #$orderNumber';
          }
          final orderId = message.data['orderId']?.toString() ?? message.id.toString();
          final shortId = orderId.length > 6 ? orderId.substring(orderId.length - 6) : orderId;
          return 'Заказ #$shortId';
        case 'employee_response':
          return message.data['text'] ?? 'Ответ от магазина';
        default:
          return 'Сообщение';
      }
    } catch (e) {
      return 'Сообщение';
    }
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
            onPressed: _loadDialogs,
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
        child: FutureBuilder<List<ClientDialog>>(
          future: _dialogsFuture,
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
                      'Оставьте отзыв, задайте вопрос или сделайте заказ',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            final dialogs = snapshot.data!;

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: dialogs.length,
              itemBuilder: (context, index) {
                final dialog = dialogs[index];
                final lastMessage = dialog.getLastMessage();

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: dialog.hasUnread()
                          ? Colors.orange
                          : Colors.green,
                      child: Icon(
                        dialog.hasUnread()
                            ? Icons.warning
                            : Icons.check,
                        color: Colors.white,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dialog.shopAddress,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (dialog.hasUnread()) ...[
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
                              dialog.unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (lastMessage != null) ...[
                          Text(
                            _formatTimestamp(lastMessage.timestamp),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getMessagePreview(lastMessage),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: dialog.hasUnread() ? Colors.blue : Colors.grey,
                              fontWeight: dialog.hasUnread() ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ] else ...[
                          Text(
                            dialog.lastMessageTime != null
                                ? _formatTimestamp(dialog.lastMessageTime!)
                                : 'Нет сообщений',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ClientDialogPage(
                            shopAddress: dialog.shopAddress,
                          ),
                        ),
                      );
                      _loadDialogs(); // Обновляем после возврата
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
















