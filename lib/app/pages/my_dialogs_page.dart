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
import '../../features/product_questions/pages/product_question_client_dialog_page.dart';
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
  int _groupsUnreadCount = 0;
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

    // Загружаем сетевые сообщения
    final networkData = await NetworkMessageService.getNetworkMessages(phone);
    if (mounted) {
      setState(() {
        _networkData = networkData;
      });
    }

    // Загружаем сообщения руководству
    final managementData = await ManagementMessageService.getManagementMessages(phone);
    if (mounted) {
      setState(() {
        _managementData = managementData;
      });
    }

    // Загружаем отзывы клиента
    try {
      final reviews = await ReviewService.getClientReviews(phone);
      int unreadCount = 0;
      for (final review in reviews) {
        unreadCount += review.getUnreadCountForClient();
      }
      if (mounted) {
        setState(() {
          _clientReviews = reviews;
          _reviewsUnreadCount = unreadCount;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки отзывов', e);
    }

    // Загружаем персональные диалоги "Поиск Товара"
    final personalDialogs = await ProductQuestionService.getClientPersonalDialogs(phone);
    if (mounted) {
      setState(() {
        _personalDialogs = personalDialogs;
      });
    }

    // Загружаем общий чат "Поиск Товара"
    final productQuestionData = await ProductQuestionService.getClientDialog(phone);
    if (mounted) {
      setState(() {
        _productQuestionData = productQuestionData;
      });
    }

    // Загружаем групповые чаты клиента
    try {
      final groups = await ClientGroupChatService.getClientGroupChats(phone);
      int unreadCount = 0;
      for (final group in groups) {
        unreadCount += group.unreadCount;
      }
      if (mounted) {
        setState(() {
          _clientGroups = groups;
          _groupsUnreadCount = unreadCount;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки групповых чатов', e);
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF004D40),
      appBar: AppBar(
        title: const Text(
          'Мои диалоги',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF004D40),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDialogs,
            tooltip: 'Обновить',
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF004D40),
              const Color(0xFF00695C),
              const Color(0xFF00796B),
            ],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : _buildContent(),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00897B), Color(0xFF4DB6AC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ManagementDialogPage(),
              ),
            );
            _loadDialogs();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.business, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'Связаться с Руководством',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: sortedItems.length,
      itemBuilder: (context, index) {
        final item = sortedItems[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'У вас пока нет диалогов',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Оставьте отзыв, задайте вопрос или сделайте заказ',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
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

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(hasUnread ? 0.4 : 0.2),
            blurRadius: hasUnread ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Иконка с градиентом или фото
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: imageUrl == null
                        ? LinearGradient(
                            colors: gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: gradientColors.first.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (imageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            imageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: gradientColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: Icon(icon, color: Colors.white, size: 28),
                              ),
                            ),
                          ),
                        )
                      else
                        Center(
                          child: Icon(icon, color: Colors.white, size: 28),
                        ),
                      if (hasUnread)
                        Positioned(
                          right: -6,
                          top: -6,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 22,
                              minHeight: 22,
                            ),
                            child: Text(
                              unreadCount > 9 ? '9+' : unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Контент
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: hasUnread ? accentColor : const Color(0xFF1A1A1A),
                        ),
                      ),
                      if (timestamp != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          timestamp,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: hasUnread ? accentColor.withOpacity(0.8) : Colors.grey[600],
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Стрелка
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
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
      timestamp: lastReview != null ? lastReview.shopAddress : null,
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
