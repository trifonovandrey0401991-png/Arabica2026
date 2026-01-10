import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/clients/models/client_dialog_model.dart';
import '../../features/clients/models/network_message_model.dart';
import '../../features/clients/models/management_message_model.dart';
import '../../features/clients/services/client_dialog_service.dart';
import '../../features/clients/services/network_message_service.dart';
import '../../features/clients/services/management_message_service.dart';
import '../../features/clients/pages/client_dialog_page.dart';
import '../../features/clients/pages/network_dialog_page.dart';
import '../../features/clients/pages/management_dialog_page.dart';
import '../../features/product_questions/models/product_question_model.dart';
import '../../features/product_questions/services/product_question_service.dart';
import '../../features/product_questions/pages/product_question_client_dialog_page.dart';
import '../../features/product_questions/pages/product_question_personal_dialog_page.dart';
import '../../features/reviews/models/review_model.dart';
import '../../features/reviews/services/review_service.dart';
import '../../features/reviews/pages/client_reviews_list_page.dart';
import '../../core/utils/logger.dart';

/// Страница "Мои диалоги" для клиента
class MyDialogsPage extends StatefulWidget {
  const MyDialogsPage({super.key});

  @override
  State<MyDialogsPage> createState() => _MyDialogsPageState();
}

class _MyDialogsPageState extends State<MyDialogsPage> {
  late Future<List<ClientDialog>> _dialogsFuture = Future.value([]);
  NetworkDialogData? _networkData;
  ManagementDialogData? _managementData;
  ProductQuestionClientDialogData? _productQuestionData;
  List<PersonalProductDialog> _personalDialogs = [];
  List<Review> _clientReviews = [];
  int _reviewsUnreadCount = 0;

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

    // Загружаем сетевые сообщения
    final networkData = await NetworkMessageService.getNetworkMessages(phone);
    setState(() {
      _networkData = networkData;
    });

    // Загружаем сообщения руководству
    final managementData = await ManagementMessageService.getManagementMessages(phone);
    setState(() {
      _managementData = managementData;
    });

    // Загружаем отзывы клиента
    try {
      final reviews = await ReviewService.getClientReviews(phone);
      int unreadCount = 0;
      for (final review in reviews) {
        unreadCount += review.getUnreadCountForClient();
      }
      setState(() {
        _clientReviews = reviews;
        _reviewsUnreadCount = unreadCount;
      });
    } catch (e) {
      Logger.error('Ошибка загрузки отзывов', e);
    }

    // Загружаем персональные диалоги "Поиск Товара"
    final personalDialogs = await ProductQuestionService.getClientPersonalDialogs(phone);
    setState(() {
      _personalDialogs = personalDialogs;
    });

    // Загружаем общий чат "Поиск Товара" только если нет персональных диалогов
    if (personalDialogs.isEmpty) {
      final productQuestionData = await ProductQuestionService.getClientDialog(phone);
      setState(() {
        _productQuestionData = productQuestionData;
      });
    } else {
      setState(() {
        _productQuestionData = null;
      });
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ManagementDialogPage(),
            ),
          );
          _loadDialogs();
        },
        backgroundColor: const Color(0xFF004D40),
        icon: const Icon(Icons.business),
        label: const Text('Связаться с Руководством'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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

            // Показываем сетевые сообщения даже если нет обычных диалогов
            final hasNetworkMessages = _networkData?.hasMessages ?? false;
            final hasManagementMessages = _managementData?.hasMessages ?? false;
            final hasReviews = _clientReviews.isNotEmpty;
            final hasProductQuestions = _productQuestionData?.hasQuestions ?? false;
            final hasPersonalDialogs = _personalDialogs.isNotEmpty;
            final hasShopDialogs = snapshot.hasData && snapshot.data!.isNotEmpty;

            if (!hasNetworkMessages && !hasManagementMessages && !hasReviews && !hasProductQuestions && !hasPersonalDialogs && !hasShopDialogs) {
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

            final dialogs = snapshot.data ?? [];
            // Считаем элементы: сеть + руководство + отзывы + поиск товара (общий или персональные) + диалоги
            final productDialogsCount = hasPersonalDialogs ? _personalDialogs.length : (hasProductQuestions ? 1 : 0);
            final totalItems = (hasNetworkMessages ? 1 : 0) + (hasManagementMessages ? 1 : 0) + (hasReviews ? 1 : 0) + productDialogsCount + dialogs.length;

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: totalItems,
              itemBuilder: (context, index) {
                // Первый элемент - "Сообщение от Всей Сети" (если есть сообщения)
                if (hasNetworkMessages && index == 0) {
                  final networkUnread = _networkData!.unreadCount;
                  final lastNetworkMessage = _networkData!.messages.isNotEmpty
                      ? _networkData!.messages.last
                      : null;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: networkUnread > 0 ? Colors.orange[50] : null,
                    child: ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            backgroundColor: networkUnread > 0
                                ? Colors.orange
                                : const Color(0xFF004D40),
                            child: const Icon(
                              Icons.language,
                              color: Colors.white,
                            ),
                          ),
                          if (networkUnread > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    networkUnread > 9 ? '9+' : networkUnread.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        'Сообщение от Всей Сети',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: networkUnread > 0 ? Colors.orange[800] : null,
                        ),
                      ),
                      subtitle: lastNetworkMessage != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatTimestamp(lastNetworkMessage.timestamp),
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  lastNetworkMessage.text.length > 50
                                      ? '${lastNetworkMessage.text.substring(0, 50)}...'
                                      : lastNetworkMessage.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: networkUnread > 0 ? Colors.blue : Colors.grey,
                                    fontWeight: networkUnread > 0 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            )
                          : const Text('Нажмите, чтобы открыть'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NetworkDialogPage(),
                          ),
                        );
                        _loadDialogs();
                      },
                    ),
                  );
                }

                // Второй элемент - "Связь с Руководством" (если есть сообщения)
                final managementIndex = hasNetworkMessages ? 1 : 0;
                if (hasManagementMessages && index == managementIndex) {
                  final managementUnread = _managementData!.unreadCount;
                  final lastManagementMessage = _managementData!.messages.isNotEmpty
                      ? _managementData!.messages.last
                      : null;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: managementUnread > 0 ? Colors.blue[50] : null,
                    child: ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            backgroundColor: managementUnread > 0
                                ? Colors.blue
                                : const Color(0xFF004D40),
                            child: const Icon(
                              Icons.business,
                              color: Colors.white,
                            ),
                          ),
                          if (managementUnread > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    managementUnread > 9 ? '9+' : managementUnread.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        'Связь с Руководством',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: managementUnread > 0 ? Colors.blue[800] : null,
                        ),
                      ),
                      subtitle: lastManagementMessage != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatTimestamp(lastManagementMessage.timestamp),
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  lastManagementMessage.text.length > 50
                                      ? '${lastManagementMessage.text.substring(0, 50)}...'
                                      : lastManagementMessage.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: managementUnread > 0 ? Colors.blue : Colors.grey,
                                    fontWeight: managementUnread > 0 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            )
                          : const Text('Нажмите, чтобы открыть'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ManagementDialogPage(),
                          ),
                        );
                        _loadDialogs();
                      },
                    ),
                  );
                }

                // Третий элемент - "Отзывы" (если есть)
                final reviewsIndex = (hasNetworkMessages ? 1 : 0) + (hasManagementMessages ? 1 : 0);
                if (hasReviews && index == reviewsIndex) {
                  final lastReview = _clientReviews.isNotEmpty ? _clientReviews.first : null;
                  final lastMessage = lastReview?.getLastMessage();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: _reviewsUnreadCount > 0 ? Colors.amber[50] : null,
                    child: ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            backgroundColor: _reviewsUnreadCount > 0
                                ? Colors.amber
                                : const Color(0xFF004D40),
                            child: const Icon(
                              Icons.rate_review,
                              color: Colors.white,
                            ),
                          ),
                          if (_reviewsUnreadCount > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    _reviewsUnreadCount > 9 ? '9+' : _reviewsUnreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        'Отзывы',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _reviewsUnreadCount > 0 ? Colors.amber[800] : null,
                        ),
                      ),
                      subtitle: lastReview != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lastReview.shopAddress,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  lastMessage != null
                                      ? '${lastMessage.sender == 'admin' ? 'Ответ: ' : ''}${lastMessage.text}'
                                      : lastReview.reviewText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _reviewsUnreadCount > 0 ? Colors.amber[800] : Colors.grey,
                                    fontWeight: _reviewsUnreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            )
                          : Text('Всего отзывов: ${_clientReviews.length}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ClientReviewsListPage(),
                          ),
                        );
                        _loadDialogs();
                      },
                    ),
                  );
                }

                // Четвёртый элемент (или несколько) - персональные диалоги "Поиск Товара" или общий чат
                final productQuestionStartIndex = (hasNetworkMessages ? 1 : 0) + (hasManagementMessages ? 1 : 0) + (hasReviews ? 1 : 0);

                // Если есть персональные диалоги - показываем их
                if (hasPersonalDialogs) {
                  final personalDialogIndex = index - productQuestionStartIndex;
                  if (personalDialogIndex >= 0 && personalDialogIndex < _personalDialogs.length) {
                    final personalDialog = _personalDialogs[personalDialogIndex];
                    final hasUnread = personalDialog.hasUnreadFromEmployee;
                    final lastMessage = personalDialog.getLastMessage();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: hasUnread ? Colors.purple[50] : null,
                      child: ListTile(
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              backgroundColor: hasUnread
                                  ? Colors.purple
                                  : const Color(0xFF004D40),
                              child: const Icon(
                                Icons.search,
                                color: Colors.white,
                              ),
                            ),
                            if (hasUnread)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: Text(
                                      '!',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(
                          'Поиск товара - ${personalDialog.shopAddress}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: hasUnread ? Colors.purple[800] : null,
                          ),
                        ),
                        subtitle: lastMessage != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatTimestamp(lastMessage.timestamp),
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    lastMessage.text.length > 50
                                        ? '${lastMessage.text.substring(0, 50)}...'
                                        : lastMessage.text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: hasUnread ? Colors.purple : Colors.grey,
                                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              )
                            : const Text('Нажмите, чтобы открыть'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProductQuestionPersonalDialogPage(
                                dialogId: personalDialog.id,
                                shopAddress: personalDialog.shopAddress,
                              ),
                            ),
                          );
                          _loadDialogs();
                        },
                      ),
                    );
                  }
                }

                // Если нет персональных диалогов, показываем общий чат "Поиск Товара"
                if (!hasPersonalDialogs && hasProductQuestions && index == productQuestionStartIndex) {
                  final productUnread = _productQuestionData!.unreadCount;
                  final lastProductMessage = _productQuestionData!.lastMessage;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: productUnread > 0 ? Colors.purple[50] : null,
                    child: ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            backgroundColor: productUnread > 0
                                ? Colors.purple
                                : const Color(0xFF004D40),
                            child: const Icon(
                              Icons.search,
                              color: Colors.white,
                            ),
                          ),
                          if (productUnread > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    productUnread > 9 ? '9+' : productUnread.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        'Поиск Товара',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: productUnread > 0 ? Colors.purple[800] : null,
                        ),
                      ),
                      subtitle: lastProductMessage != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (lastProductMessage.senderType == 'employee' && lastProductMessage.shopAddress != null)
                                  Text(
                                    '${lastProductMessage.shopAddress} - ${lastProductMessage.senderName ?? "Сотрудник"}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                Text(
                                  _formatTimestamp(lastProductMessage.timestamp),
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  lastProductMessage.text.length > 50
                                      ? '${lastProductMessage.text.substring(0, 50)}...'
                                      : lastProductMessage.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: productUnread > 0 ? Colors.purple : Colors.grey,
                                    fontWeight: productUnread > 0 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            )
                          : const Text('Нажмите, чтобы открыть'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ProductQuestionClientDialogPage(),
                          ),
                        );
                        _loadDialogs();
                      },
                    ),
                  );
                }

                // Остальные диалоги (с магазинами)
                final dialogOffset = (hasNetworkMessages ? 1 : 0) + (hasManagementMessages ? 1 : 0) + (hasReviews ? 1 : 0) + productDialogsCount;
                final dialogIndex = index - dialogOffset;
                final dialog = dialogs[dialogIndex];
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
















