import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/conversation_model.dart';
import '../services/messenger_service.dart';
import '../services/messenger_ws_service.dart';
import '../widgets/chat_list_tile.dart';
import 'messenger_chat_page.dart';
import 'contact_search_page.dart';

class MessengerListPage extends StatefulWidget {
  final String userPhone;
  final String userName;

  const MessengerListPage({
    super.key,
    required this.userPhone,
    required this.userName,
  });

  @override
  State<MessengerListPage> createState() => _MessengerListPageState();
}

class _MessengerListPageState extends State<MessengerListPage> {
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;

  StreamSubscription? _newMessageSub;
  StreamSubscription? _readReceiptSub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _setupWebSocket();
    // Авто-обновление каждые 30 сек
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadConversations(silent: true);
    });
  }

  @override
  void dispose() {
    _newMessageSub?.cancel();
    _readReceiptSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _setupWebSocket() {
    final ws = MessengerWsService.instance;
    ws.connect(widget.userPhone);

    _newMessageSub = ws.onNewMessage.listen((event) {
      // При новом сообщении — перезагружаем список
      _loadConversations(silent: true);
    });

    _readReceiptSub = ws.onReadReceipt.listen((event) {
      _loadConversations(silent: true);
    });
  }

  Future<void> _loadConversations({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final conversations = await MessengerService.getConversations(widget.userPhone);
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _openChat(Conversation conversation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessengerChatPage(
          conversation: conversation,
          userPhone: widget.userPhone,
          userName: widget.userName,
        ),
      ),
    ).then((_) => _loadConversations(silent: true));
  }

  void _openContactSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactSearchPage(
          userPhone: widget.userPhone,
          userName: widget.userName,
        ),
      ),
    ).then((_) => _loadConversations(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Назад в приложение',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Мессенджер', style: TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadConversations(),
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openContactSearch,
        backgroundColor: AppColors.emerald,
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.emerald));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadConversations,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.emerald),
              child: const Text('Повторить', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Нет диалогов', style: TextStyle(fontSize: 18, color: Colors.grey[500])),
            const SizedBox(height: 8),
            Text('Нажмите + чтобы начать чат', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.emerald,
      onRefresh: () => _loadConversations(),
      child: ListView.separated(
        itemCount: _conversations.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final conv = _conversations[index];
          return ChatListTile(
            conversation: conv,
            myPhone: widget.userPhone,
            onTap: () => _openChat(conv),
          );
        },
      ),
    );
  }
}
