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

class _EmployeeChatsListPageState extends State<EmployeeChatsListPage> {
  List<EmployeeChat> _chats = [];
  bool _isLoading = true;
  String? _userPhone;
  String? _userName;
  bool _isAdmin = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();

    // Получаем телефон
    final phone = prefs.getString('user_phone') ?? prefs.getString('userPhone') ?? '';

    // Получаем имя из системы сотрудников (как в employee_panel_page)
    final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
    final fallbackName = prefs.getString('user_display_name') ?? prefs.getString('user_name') ?? '';

    // Проверяем, является ли пользователь админом (роль хранится как 'admin', 'employee', 'client')
    final userRole = prefs.getString('user_role') ?? '';
    final isAdmin = userRole == 'admin';

    // Debug: выводим роль в консоль
    debugPrint('🔐 EmployeeChatsListPage: userRole=$userRole, isAdmin=$isAdmin');

    setState(() {
      _userPhone = phone;
      _userName = systemEmployeeName ?? fallbackName;
      _isAdmin = isAdmin;
    });
    await _loadChats();
    _startAutoRefresh();
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
            ),
          );
        }
      }
    }
  }

  void _openChat(EmployeeChat chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeChatPage(
          chat: chat,
          userPhone: _userPhone!,
          userName: _userName!,
          isAdmin: _isAdmin,
        ),
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
      MaterialPageRoute(
        builder: (context) => NewChatPage(
          userPhone: _userPhone!,
          userName: _userName!,
          isAdmin: _isAdmin,
        ),
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
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Чат'),
            if (_totalUnread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChats,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Нет чатов',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Нажмите + чтобы начать общение',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadChats,
                  child: ListView.builder(
                    itemCount: _chats.length,
                    itemBuilder: (context, index) {
                      final chat = _chats[index];
                      return _buildChatTile(chat);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewChat,
        backgroundColor: const Color(0xFF004D40),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildChatTile(EmployeeChat chat) {
    final showMembersButton = _isAdmin && chat.type == EmployeeChatType.shop;

    return ListTile(
      leading: _buildChatAvatar(chat),
      title: Row(
        children: [
          Expanded(
            child: Text(
              chat.displayName,
              style: TextStyle(
                fontWeight: chat.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (chat.lastMessageTime.isNotEmpty)
            Text(
              chat.lastMessageTime,
              style: TextStyle(
                fontSize: 12,
                color: chat.unreadCount > 0 ? const Color(0xFF004D40) : Colors.grey,
                fontWeight: chat.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              chat.lastMessagePreview,
              style: TextStyle(
                color: chat.unreadCount > 0 ? Colors.black87 : Colors.grey[600],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (chat.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF004D40),
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
      ),
      trailing: showMembersButton
          ? Container(
              decoration: BoxDecoration(
                color: const Color(0xFF004D40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: const Icon(Icons.group, color: Colors.white),
                onPressed: () => _openShopChatMembers(chat),
                tooltip: 'Управление участниками',
              ),
            )
          : null,
      onTap: () => _openChat(chat),
    );
  }

  Widget _buildChatAvatar(EmployeeChat chat) {
    // Для групп показываем imageUrl если есть
    if (chat.type == EmployeeChatType.group && chat.imageUrl != null) {
      return CircleAvatar(
        backgroundImage: NetworkImage(chat.imageUrl!),
        backgroundColor: Colors.purple[100],
        onBackgroundImageError: (_, __) {},
      );
    }

    return CircleAvatar(
      backgroundColor: _getChatColor(chat.type),
      child: Text(
        chat.typeIcon,
        style: const TextStyle(fontSize: 20),
      ),
    );
  }

  Color _getChatColor(EmployeeChatType type) {
    switch (type) {
      case EmployeeChatType.general:
        return Colors.blue[100]!;
      case EmployeeChatType.shop:
        return Colors.orange[100]!;
      case EmployeeChatType.private:
        return Colors.green[100]!;
      case EmployeeChatType.group:
        return Colors.purple[100]!;
    }
  }
}
