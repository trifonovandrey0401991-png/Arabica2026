import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/contact_model.dart';
import '../models/conversation_model.dart';
import '../services/messenger_service.dart';
import '../services/messenger_ws_service.dart';
import '../widgets/chat_list_tile.dart';
import 'messenger_chat_page.dart';
import 'messenger_profile_page.dart';
import 'contact_search_page.dart';

class MessengerListPage extends StatefulWidget {
  final String userPhone;
  final String userName;
  final List<MessengerContact> matchedContacts;
  final bool contactsGranted;
  final bool isClient;
  final Map<String, String> phoneBookNames;

  const MessengerListPage({
    super.key,
    required this.userPhone,
    required this.userName,
    required this.matchedContacts,
    required this.contactsGranted,
    this.isClient = false,
    this.phoneBookNames = const {},
  });

  @override
  State<MessengerListPage> createState() => _MessengerListPageState();
}

class _MessengerListPageState extends State<MessengerListPage> {
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;
  late String _userName;

  StreamSubscription? _newMessageSub;
  StreamSubscription? _readReceiptSub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _userName = widget.userName;
    _loadConversations();
    _setupWebSocket();
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
          userName: _userName,
          isClient: widget.isClient,
          phoneBookNames: widget.phoneBookNames,
        ),
      ),
    ).then((_) => _loadConversations(silent: true));
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessengerProfilePage(
          userPhone: widget.userPhone,
          userName: _userName,
        ),
      ),
    ).then((result) {
      if (result is ProfileResult && result.displayName != null && mounted) {
        setState(() => _userName = result.displayName!);
      }
    });
  }

  void _openContactSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContactSearchPage(
          userPhone: widget.userPhone,
          userName: _userName,
          matchedContacts: widget.contactsGranted ? widget.matchedContacts : null,
        ),
      ),
    ).then((_) => _loadConversations(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Назад в приложение',
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Мессенджер',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.95),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: Colors.white.withOpacity(0.6)),
            tooltip: 'Профиль',
            onPressed: _openProfile,
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white.withOpacity(0.6)),
            onPressed: () => _loadConversations(),
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.emerald.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.turquoise, AppColors.emerald],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.turquoise.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: _openContactSearch,
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.chat, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.turquoise, AppColors.emerald],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: _loadConversations,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Повторить', style: TextStyle(color: Colors.white)),
              ),
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
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text(
              'Нет диалогов',
              style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.5)),
            ),
            const SizedBox(height: 8),
            Text(
              'Нажмите + чтобы начать чат',
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.3)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.turquoise,
      backgroundColor: AppColors.night,
      onRefresh: () => _loadConversations(),
      child: ListView.builder(
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final conv = _conversations[index];
          return ChatListTile(
            conversation: conv,
            myPhone: widget.userPhone,
            onTap: () => _openChat(conv),
            isClient: widget.isClient,
            phoneBookNames: widget.phoneBookNames,
          );
        },
      ),
    );
  }
}
