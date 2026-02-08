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
  // Dark emerald palette
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);

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
    final isAdmin = userRole == 'admin' || userRole == 'developer';

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
      backgroundColor: _night,
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
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _chats.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                            itemCount: _chats.length,
                            itemBuilder: (context, index) => _buildChatCard(_chats[index], index),
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabAnimationController,
        child: GestureDetector(
          onTap: _openNewChat,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _emerald,
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_note, color: Colors.white.withOpacity(0.9), size: 22),
                const SizedBox(width: 10),
                Text(
                  'Новый чат',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Чаты',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1,
                  ),
                ),
                if (_totalUnread > 0) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_totalUnread',
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
          ),
          IconButton(
            onPressed: _loadChats,
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
              Icons.forum_outlined,
              size: 32,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Нет активных чатов',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Начните общение с коллегами\nнажав кнопку ниже',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatCard(EmployeeChat chat, int index) {
    final showMembersButton = _isAdmin && chat.type == EmployeeChatType.shop;
    final hasUnread = chat.unreadCount > 0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 50)),
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: GestureDetector(
        onTap: () => _openChat(chat),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: hasUnread
                ? Colors.white.withOpacity(0.08)
                : Colors.white.withOpacity(0.04),
            border: Border.all(
              color: hasUnread
                  ? _emerald.withOpacity(0.6)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Row(
            children: [
              _buildChatAvatar(chat),
              const SizedBox(width: 10),
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
                              fontSize: 15,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                              color: Colors.white.withOpacity(0.95),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          chat.lastMessageTime,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(hasUnread ? 0.6 : 0.35),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.lastMessagePreview,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(hasUnread ? 0.6 : 0.4),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${chat.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
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
                GestureDetector(
                  onTap: () => _openShopChatMembers(chat),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Icon(Icons.group, color: Colors.white.withOpacity(0.6), size: 18),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatAvatar(EmployeeChat chat) {
    final hasImage = chat.type == EmployeeChatType.group && chat.imageUrl != null;
    final colors = _getAvatarColors(chat.type);

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: hasImage ? null : colors[0].withOpacity(0.2),
        shape: BoxShape.circle,
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
                style: const TextStyle(fontSize: 18),
              ),
            ),
    );
  }

  List<Color> _getAvatarColors(EmployeeChatType type) {
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
