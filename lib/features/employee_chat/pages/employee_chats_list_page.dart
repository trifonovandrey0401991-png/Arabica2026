import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee_chat_model.dart';
import '../services/employee_chat_service.dart';
import '../../employees/pages/employees_page.dart';
import 'employee_chat_page.dart';
import 'new_chat_page.dart';
import 'shop_chat_members_page.dart';

/// Страница списка чатов сотрудников
class EmployeeChatsListPage extends StatefulWidget {
  const EmployeeChatsListPage({super.key});

  @override
  State<EmployeeChatsListPage> createState() => _EmployeeChatsListPageState();
}

class _EmployeeChatsListPageState extends State<EmployeeChatsListPage>
    with SingleTickerProviderStateMixin {
  List<EmployeeChat> _chats = [];
  bool _isLoading = true;
  String? _userPhone;
  String? _userName;
  bool _isAdmin = false;
  Timer? _refreshTimer;
  late AnimationController _fabAnimationController;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadUserData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _fabAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? prefs.getString('userPhone') ?? '';
    final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
    final fallbackName = prefs.getString('user_display_name') ?? prefs.getString('user_name') ?? '';
    final userRole = prefs.getString('user_role') ?? '';
    final isAdmin = userRole == 'admin';

    setState(() {
      _userPhone = phone;
      _userName = systemEmployeeName ?? fallbackName;
      _isAdmin = isAdmin;
    });
    await _loadChats();
    _startAutoRefresh();
    _fabAnimationController.forward();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _loadChats(silent: true);
    });
  }

  Future<void> _loadChats({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }

    if (_userPhone == null || _userPhone!.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final chats = await EmployeeChatService.getChats(_userPhone!, isAdmin: _isAdmin);
      if (mounted) {
        setState(() {
          _chats = chats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка загрузки: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    }
  }

  void _openChat(EmployeeChat chat) async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => EmployeeChatPage(
          chat: chat,
          userPhone: _userPhone!,
          userName: _userName!,
          isAdmin: _isAdmin,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
      ),
    );
    _loadChats();
  }

  void _openShopChatMembers(EmployeeChat chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShopChatMembersPage(
          shopAddress: chat.shopAddress ?? chat.displayName,
          userPhone: _userPhone ?? '',
        ),
      ),
    );
    _loadChats();
  }

  void _openNewChat() async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => NewChatPage(
          userPhone: _userPhone!,
          userName: _userName!,
          isAdmin: _isAdmin,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.1),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
      ),
    );

    if (result != null && result is EmployeeChat) {
      _openChat(result);
    } else {
      _loadChats();
    }
  }

  int get _totalUnread => _chats.fold(0, (sum, chat) => sum + chat.unreadCount);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Color(0xFF004D40))),
            )
          else if (_chats.isEmpty)
            SliverFillRemaining(child: _buildEmptyState())
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildChatCard(_chats[index], index),
                  childCount: _chats.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabAnimationController,
        child: FloatingActionButton.extended(
          onPressed: _openNewChat,
          backgroundColor: const Color(0xFF004D40),
          foregroundColor: Colors.white,
          elevation: 4,
          icon: const Icon(Icons.edit_note),
          label: const Text('Новый чат'),
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF004D40),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF00695C), Color(0xFF004D40)],
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_rounded, size: 24),
            const SizedBox(width: 10),
            const Text(
              'Чаты',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (_totalUnread > 0) ...[
              const SizedBox(width: 10),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.8, end: 1.0),
                duration: const Duration(milliseconds: 300),
                builder: (context, scale, child) => Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '$_totalUnread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        centerTitle: true,
        titlePadding: const EdgeInsets.only(bottom: 16),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadChats,
          tooltip: 'Обновить',
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF004D40).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.forum_outlined,
              size: 60,
              color: Color(0xFF004D40),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Нет активных чатов',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF004D40),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Начните общение с коллегами\nнажав кнопку ниже',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _openNewChat,
            icon: const Icon(Icons.add),
            label: const Text('Создать чат'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatCard(EmployeeChat chat, int index) {
    final showMembersButton = _isAdmin && chat.type == EmployeeChatType.shop;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 50)),
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: chat.unreadCount > 0
                  ? const Color(0xFF004D40).withOpacity(0.15)
                  : Colors.black.withOpacity(0.05),
              blurRadius: chat.unreadCount > 0 ? 12 : 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: chat.unreadCount > 0
              ? Border.all(color: const Color(0xFF004D40).withOpacity(0.3), width: 1.5)
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openChat(chat),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _buildChatAvatar(chat),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                chat.displayName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: chat.unreadCount > 0
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: Colors.grey[850],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              chat.lastMessageTime,
                              style: TextStyle(
                                fontSize: 12,
                                color: chat.unreadCount > 0
                                    ? const Color(0xFF004D40)
                                    : Colors.grey[500],
                                fontWeight: chat.unreadCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                chat.lastMessagePreview,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: chat.unreadCount > 0
                                      ? Colors.grey[800]
                                      : Colors.grey[600],
                                  fontWeight: chat.unreadCount > 0
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (chat.unreadCount > 0) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00695C), Color(0xFF004D40)],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${chat.unreadCount}',
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
                      ],
                    ),
                  ),
                  if (showMembersButton) ...[
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF004D40).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.group, color: Color(0xFF004D40)),
                        onPressed: () => _openShopChatMembers(chat),
                        tooltip: 'Участники',
                        iconSize: 22,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatAvatar(EmployeeChat chat) {
    final hasImage = chat.type == EmployeeChatType.group && chat.imageUrl != null;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: hasImage
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _getGradientColors(chat.type),
              ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _getGradientColors(chat.type).first.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(chat.imageUrl!),
                fit: BoxFit.cover,
                onError: (_, __) {},
              )
            : null,
      ),
      child: hasImage
          ? null
          : Center(
              child: Text(
                chat.typeIcon,
                style: const TextStyle(fontSize: 26),
              ),
            ),
    );
  }

  List<Color> _getGradientColors(EmployeeChatType type) {
    switch (type) {
      case EmployeeChatType.general:
        return [Colors.blue[300]!, Colors.blue[500]!];
      case EmployeeChatType.shop:
        return [Colors.orange[300]!, Colors.orange[500]!];
      case EmployeeChatType.private:
        return [Colors.green[300]!, Colors.green[500]!];
      case EmployeeChatType.group:
        return [Colors.purple[300]!, Colors.purple[500]!];
    }
  }
}
