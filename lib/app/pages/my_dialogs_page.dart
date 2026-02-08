import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/clients/models/network_message_model.dart';
import '../../features/clients/models/management_message_model.dart';
import '../../features/clients/services/network_message_service.dart';
import '../../features/clients/services/management_message_service.dart';
import '../../features/clients/pages/network_dialog_page.dart';
import '../../features/clients/pages/management_dialog_page.dart';
import '../../features/product_questions/models/product_question_model.dart';
import '../../features/product_questions/services/product_question_service.dart';
import '../../features/product_questions/pages/product_question_personal_dialog_page.dart';
import '../../features/product_questions/pages/product_question_shops_list_page.dart';
import '../../features/reviews/models/review_model.dart';
import '../../features/reviews/services/review_service.dart';
import '../../features/reviews/pages/client_reviews_list_page.dart';
import '../../core/utils/logger.dart';
import '../../features/employee_chat/models/employee_chat_model.dart';
import '../../features/employee_chat/pages/employee_chat_page.dart';
import '../../features/employee_chat/services/client_group_chat_service.dart';

/// Страница "Мои диалоги" для клиента
class MyDialogsPage extends StatefulWidget {
  const MyDialogsPage({super.key});

  @override
  State<MyDialogsPage> createState() => _MyDialogsPageState();
}

/// Тип диалога для сортировки
enum _DialogType {
  network,
  management,
  reviews,
  productSearch,
  personalDialog,
  groupChat,
}

/// Элемент диалога для унифицированной сортировки
class _DialogItem {
  final _DialogType type;
  final int unreadCount;
  final DateTime? lastMessageTime;
  final dynamic data; // Оригинальные данные

  _DialogItem({
    required this.type,
    required this.unreadCount,
    this.lastMessageTime,
    this.data,
  });

  bool get hasUnread => unreadCount > 0;
}

class _MyDialogsPageState extends State<MyDialogsPage> {
  NetworkDialogData? _networkData;
  ManagementDialogData? _managementData;
  ProductQuestionClientDialogData? _productQuestionData;
  List<PersonalProductDialog> _personalDialogs = [];
  List<Review> _clientReviews = [];
  int _reviewsUnreadCount = 0;
  bool _isLoading = true;

  // Групповые чаты для клиента
  List<EmployeeChat> _clientGroups = [];
  String? _userPhone;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadDialogs();
  }

  Future<void> _loadDialogs() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final userName = prefs.getString('user_name') ?? phone;

    if (phone.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    // Сохраняем для использования в навигации
    _userPhone = phone;
    _userName = userName;

    // Запускаем все запросы параллельно (вместо последовательных)
    final networkFuture = NetworkMessageService.getNetworkMessages(phone);
    final managementFuture = ManagementMessageService.getManagementMessages(phone);
    final reviewsFuture = ReviewService.getClientReviews(phone).catchError((e) {
      Logger.error('Ошибка загрузки отзывов', e);
      return <Review>[];
    });
    final personalDialogsFuture = ProductQuestionService.getClientPersonalDialogs(phone);
    final productQuestionFuture = ProductQuestionService.getClientDialog(phone);
    final groupsFuture = ClientGroupChatService.getClientGroupChats(phone).catchError((e) {
      Logger.error('Ошибка загрузки групповых чатов', e);
      return <EmployeeChat>[];
    });

    // Ждём завершения всех запросов параллельно
    final results = await Future.wait<dynamic>([
      networkFuture,
      managementFuture,
      reviewsFuture,
      personalDialogsFuture,
      productQuestionFuture,
      groupsFuture,
    ]);

    if (!mounted) return;

    // Распаковываем результаты
    final networkData = results[0] as NetworkDialogData?;
    final managementData = results[1] as ManagementDialogData?;
    final reviews = results[2] as List<Review>;
    final personalDialogs = results[3] as List<PersonalProductDialog>;
    final productQuestionData = results[4] as ProductQuestionClientDialogData?;
    final groups = results[5] as List<EmployeeChat>;

    // Подсчитываем непрочитанные отзывы
    int reviewsUnreadCount = 0;
    for (final review in reviews) {
      reviewsUnreadCount += review.getUnreadCountForClient();
    }

    // Обновляем состояние один раз со всеми данными
    setState(() {
      _networkData = networkData;
      _managementData = managementData;
      _clientReviews = reviews;
      _reviewsUnreadCount = reviewsUnreadCount;
      _personalDialogs = personalDialogs;
      _productQuestionData = productQuestionData;
      _clientGroups = groups;
      _isLoading = false;
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

  // Единая палитра приложения
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          const Expanded(
            child: Text(
              'Мои диалоги',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          IconButton(
            onPressed: _loadDialogs,
            icon: Icon(
              Icons.refresh_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ManagementDialogPage(),
          ),
        );
        _loadDialogs();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              _emerald,
              _emerald.withOpacity(0.8),
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_rounded, color: Colors.white.withOpacity(0.9), size: 20),
            const SizedBox(width: 10),
            Text(
              'Связаться с Руководством',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Собрать все диалоги в единый список для сортировки
  List<_DialogItem> _buildDialogItems() {
    final items = <_DialogItem>[];

    // Сообщение от Всей Сети
    if (_networkData?.hasMessages ?? false) {
      final lastMessage = _networkData!.messages.isNotEmpty
          ? _networkData!.messages.last
          : null;
      DateTime? timestamp;
      if (lastMessage != null) {
        try {
          timestamp = DateTime.parse(lastMessage.timestamp);
        } catch (_) {}
      }
      items.add(_DialogItem(
        type: _DialogType.network,
        unreadCount: _networkData!.unreadCount,
        lastMessageTime: timestamp,
      ));
    }

    // Связь с Руководством
    if (_managementData?.hasMessages ?? false) {
      final lastMessage = _managementData!.messages.isNotEmpty
          ? _managementData!.messages.last
          : null;
      DateTime? timestamp;
      if (lastMessage != null) {
        try {
          timestamp = DateTime.parse(lastMessage.timestamp);
        } catch (_) {}
      }
      items.add(_DialogItem(
        type: _DialogType.management,
        unreadCount: _managementData!.unreadCount,
        lastMessageTime: timestamp,
      ));
    }

    // Отзывы
    if (_clientReviews.isNotEmpty) {
      final lastReview = _clientReviews.first;
      items.add(_DialogItem(
        type: _DialogType.reviews,
        unreadCount: _reviewsUnreadCount,
        lastMessageTime: lastReview.createdAt,
      ));
    }

    // Поиск Товара (общий)
    if (_productQuestionData?.hasQuestions ?? false) {
      items.add(_DialogItem(
        type: _DialogType.productSearch,
        unreadCount: _productQuestionData!.unreadCount,
        lastMessageTime: null, // Нет общего timestamp
      ));
    }

    // Персональные диалоги
    for (final dialog in _personalDialogs) {
      final lastMessage = dialog.getLastMessage();
      DateTime? timestamp;
      if (lastMessage != null) {
        try {
          timestamp = DateTime.parse(lastMessage.timestamp);
        } catch (_) {}
      }
      items.add(_DialogItem(
        type: _DialogType.personalDialog,
        unreadCount: dialog.hasUnreadFromEmployee ? 1 : 0,
        lastMessageTime: timestamp,
        data: dialog,
      ));
    }

    // Групповые чаты
    for (final group in _clientGroups) {
      items.add(_DialogItem(
        type: _DialogType.groupChat,
        unreadCount: group.unreadCount,
        lastMessageTime: group.lastMessage?.timestamp,
        data: group,
      ));
    }

    return items;
  }

  /// Отсортировать диалоги: с непрочитанными вверх, затем по времени
  List<_DialogItem> _sortDialogItems(List<_DialogItem> items) {
    items.sort((a, b) {
      // Сначала по наличию непрочитанных (с непрочитанными вверх)
      if (a.hasUnread && !b.hasUnread) return -1;
      if (!a.hasUnread && b.hasUnread) return 1;

      // Затем по времени последнего сообщения (новые вверх)
      final aTime = a.lastMessageTime ?? DateTime(1970);
      final bTime = b.lastMessageTime ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return items;
  }

  /// Построить виджет для элемента диалога
  Widget _buildDialogItemWidget(_DialogItem item) {
    switch (item.type) {
      case _DialogType.network:
        return _buildNetworkCard();
      case _DialogType.management:
        return _buildManagementCard();
      case _DialogType.reviews:
        return _buildReviewsCard();
      case _DialogType.productSearch:
        return _buildProductSearchCard();
      case _DialogType.personalDialog:
        return _buildPersonalDialogCard(item.data as PersonalProductDialog);
      case _DialogType.groupChat:
        return _buildGroupChatCard(item.data as EmployeeChat);
    }
  }

  Widget _buildContent() {
    // Собираем все диалоги
    final items = _buildDialogItems();

    if (items.isEmpty) {
      return _buildEmptyState();
    }

    // Сортируем: непрочитанные вверх, затем по времени
    final sortedItems = _sortDialogItems(items);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      itemCount: sortedItems.length,
      itemBuilder: (context, index) {
        final item = sortedItems[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _buildDialogItemWidget(item),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 32,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'У вас пока нет диалогов',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Оставьте отзыв, задайте вопрос или сделайте заказ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDialogCard({
    required String title,
    required String? subtitle,
    required String? timestamp,
    required IconData icon,
    required Color accentColor,
    required List<Color> gradientColors,
    required int unreadCount,
    required VoidCallback onTap,
    String? imageUrl,
  }) {
    final hasUnread = unreadCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasUnread
                ? accentColor.withOpacity(0.5)
                : Colors.white.withOpacity(0.12),
          ),
          color: hasUnread
              ? accentColor.withOpacity(0.08)
              : Colors.white.withOpacity(0.04),
        ),
        child: Row(
          children: [
            // Иконка
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            imageUrl,
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(icon, color: accentColor, size: 18),
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(icon, color: accentColor, size: 18),
                        ),
                ),
                if (hasUnread)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        unreadCount > 9 ? '9+' : unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            // Контент
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.95),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (timestamp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        timestamp,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.4),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Стрелка
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Colors.white.withOpacity(0.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkCard() {
    final unread = _networkData!.unreadCount;
    final lastMessage = _networkData!.messages.isNotEmpty
        ? _networkData!.messages.last
        : null;

    return _buildDialogCard(
      title: 'Сообщение от Всей Сети',
      subtitle: lastMessage != null
          ? lastMessage.text.length > 60
              ? '${lastMessage.text.substring(0, 60)}...'
              : lastMessage.text
          : 'Нажмите, чтобы открыть',
      timestamp: lastMessage != null ? _formatTimestamp(lastMessage.timestamp) : null,
      icon: Icons.language,
      accentColor: Colors.orange[700]!,
      gradientColors: [Colors.orange[400]!, Colors.deepOrange[400]!],
      unreadCount: unread,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const NetworkDialogPage()),
        );
        _loadDialogs();
      },
    );
  }

  Widget _buildManagementCard() {
    final unread = _managementData!.unreadCount;
    final lastMessage = _managementData!.messages.isNotEmpty
        ? _managementData!.messages.last
        : null;

    return _buildDialogCard(
      title: 'Связь с Руководством',
      subtitle: lastMessage != null
          ? lastMessage.text.length > 60
              ? '${lastMessage.text.substring(0, 60)}...'
              : lastMessage.text
          : 'Нажмите, чтобы открыть',
      timestamp: lastMessage != null ? _formatTimestamp(lastMessage.timestamp) : null,
      icon: Icons.business,
      accentColor: Colors.blue[700]!,
      gradientColors: [Colors.blue[400]!, Colors.indigo[400]!],
      unreadCount: unread,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ManagementDialogPage()),
        );
        _loadDialogs();
      },
    );
  }

  Widget _buildReviewsCard() {
    final lastReview = _clientReviews.isNotEmpty ? _clientReviews.first : null;
    final lastMessage = lastReview?.getLastMessage();

    return _buildDialogCard(
      title: 'Отзывы',
      subtitle: lastReview != null
          ? lastMessage != null
              ? '${lastMessage.sender == 'admin' ? 'Ответ: ' : ''}${lastMessage.text}'
              : lastReview.reviewText
          : 'Всего отзывов: ${_clientReviews.length}',
      timestamp: lastReview?.shopAddress,
      icon: Icons.rate_review,
      accentColor: Colors.amber[700]!,
      gradientColors: [Colors.amber[400]!, Colors.orange[400]!],
      unreadCount: _reviewsUnreadCount,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ClientReviewsListPage()),
        );
        _loadDialogs();
      },
    );
  }

  Widget _buildProductSearchCard() {
    final unread = _productQuestionData!.unreadCount;

    return _buildDialogCard(
      title: 'Поиск Товара',
      subtitle: 'Нажмите, чтобы открыть список магазинов',
      timestamp: null,
      icon: Icons.search,
      accentColor: Colors.purple[700]!,
      gradientColors: [Colors.purple[400]!, Colors.deepPurple[400]!],
      unreadCount: unread,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ProductQuestionShopsListPage()),
        );
        _loadDialogs();
      },
    );
  }

  Widget _buildPersonalDialogCard(PersonalProductDialog dialog) {
    final hasUnread = dialog.hasUnreadFromEmployee;
    final lastMessage = dialog.getLastMessage();

    return _buildDialogCard(
      title: 'Поиск товара',
      subtitle: lastMessage != null
          ? lastMessage.text.length > 60
              ? '${lastMessage.text.substring(0, 60)}...'
              : lastMessage.text
          : 'Нажмите, чтобы открыть',
      timestamp: dialog.shopAddress,
      icon: Icons.storefront,
      accentColor: Colors.teal[700]!,
      gradientColors: [Colors.teal[400]!, Colors.cyan[400]!],
      unreadCount: hasUnread ? 1 : 0,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductQuestionPersonalDialogPage(
              dialogId: dialog.id,
              shopAddress: dialog.shopAddress,
            ),
          ),
        );
        _loadDialogs();
      },
    );
  }

  Widget _buildGroupChatCard(EmployeeChat group) {
    final lastMsg = group.lastMessage;
    String subtitle = 'Нет сообщений';
    String? timestamp;

    if (lastMsg != null) {
      subtitle = '${lastMsg.senderName}: ${lastMsg.text}';
      if (subtitle.length > 50) subtitle = '${subtitle.substring(0, 47)}...';
      timestamp = lastMsg.formattedTime;
    }

    return _buildDialogCard(
      title: group.name,
      subtitle: subtitle,
      timestamp: timestamp,
      icon: Icons.groups_rounded,
      accentColor: Colors.purple[700]!,
      gradientColors: [Colors.purple[400]!, Colors.deepPurple[400]!],
      unreadCount: group.unreadCount,
      imageUrl: group.imageUrl,
      onTap: () async {
        if (_userPhone == null) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EmployeeChatPage(
              chat: group,
              userPhone: _userPhone!,
              userName: _userName ?? _userPhone!,
              isAdmin: false, // Клиент никогда не админ
            ),
          ),
        );
        _loadDialogs();
      },
    );
  }
}
