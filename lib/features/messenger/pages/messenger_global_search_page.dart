import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/conversation_model.dart';
import '../services/messenger_service.dart';
import 'messenger_chat_page.dart';

/// Global search page for the messenger.
/// Searches across contacts, groups, and messages using fuzzy matching.
class MessengerGlobalSearchPage extends StatefulWidget {
  final String userPhone;
  final String userName;
  final bool isClient;
  final Map<String, String> phoneBookNames;

  const MessengerGlobalSearchPage({
    super.key,
    required this.userPhone,
    required this.userName,
    this.isClient = false,
    this.phoneBookNames = const {},
  });

  @override
  State<MessengerGlobalSearchPage> createState() => _MessengerGlobalSearchPageState();
}

class _MessengerGlobalSearchPageState extends State<MessengerGlobalSearchPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      if (mounted) {
        setState(() {
          _contacts = [];
          _groups = [];
          _messages = [];
          _hasSearched = false;
        });
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final results = await MessengerService.globalSearch(query);
      if (!mounted) return;
      setState(() {
        _contacts = List<Map<String, dynamic>>.from(results['contacts'] ?? []);
        _groups = List<Map<String, dynamic>>.from(results['groups'] ?? []);
        _messages = List<Map<String, dynamic>>.from(results['messages'] ?? []);
        _isLoading = false;
        _hasSearched = true;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openPrivateChat(String phone, String name) {
    final phones = [widget.userPhone, phone]..sort();
    final conversationId = 'private_${phones[0]}_${phones[1]}';
    final conversation = Conversation(
      id: conversationId,
      type: ConversationType.private_,
      name: name,
      participants: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessengerChatPage(
          conversation: conversation,
          userPhone: widget.userPhone,
          userName: widget.userName,
          isClient: widget.isClient,
          phoneBookNames: widget.phoneBookNames,
        ),
      ),
    );
  }

  void _openGroupChat(String conversationId, String name) {
    final conversation = Conversation(
      id: conversationId,
      type: ConversationType.group,
      name: name,
      participants: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessengerChatPage(
          conversation: conversation,
          userPhone: widget.userPhone,
          userName: widget.userName,
          isClient: widget.isClient,
          phoneBookNames: widget.phoneBookNames,
        ),
      ),
    );
  }

  void _openMessageChat(Map<String, dynamic> msg) {
    final convId = msg['conversation_id'] as String? ?? '';
    final convType = msg['conversation_type'] as String? ?? 'private';
    final convName = msg['conversation_name'] as String?;

    final conversation = Conversation(
      id: convId,
      type: convType == 'group' ? ConversationType.group : ConversationType.private_,
      name: convName,
      participants: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessengerChatPage(
          conversation: conversation,
          userPhone: widget.userPhone,
          userName: widget.userName,
          isClient: widget.isClient,
          phoneBookNames: widget.phoneBookNames,
        ),
      ),
    );
  }

  String _resolveContactName(Map<String, dynamic> contact) {
    final phone = contact['phone'] as String? ?? '';
    final bookName = widget.phoneBookNames[phone];
    if (bookName != null) return bookName;
    final serverName = contact['name'] as String? ?? '';
    return serverName.isNotEmpty ? serverName : phone;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.emeraldDark,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            onChanged: _onSearchChanged,
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Поиск по мессенджеру...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(Icons.search, size: 20, color: Colors.white.withOpacity(0.4)),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, size: 18, color: Colors.white.withOpacity(0.4)),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 16),
            Text(
              'Введите запрос для поиска',
              style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Поиск по контактам, группам и сообщениям',
              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 13),
            ),
          ],
        ),
      );
    }

    final totalResults = _contacts.length + _groups.length + _messages.length;
    if (totalResults == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 12),
            Text(
              'Ничего не найдено',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (_contacts.isNotEmpty) ...[
          _buildSectionHeader('Контакты', Icons.person, _contacts.length),
          ..._contacts.map(_buildContactTile),
        ],
        if (_groups.isNotEmpty) ...[
          _buildSectionHeader('Группы', Icons.group, _groups.length),
          ..._groups.map(_buildGroupTile),
        ],
        if (_messages.isNotEmpty) ...[
          _buildSectionHeader('Сообщения', Icons.chat_bubble_outline, _messages.length),
          ..._messages.map(_buildMessageTile),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.turquoise.withOpacity(0.7)),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: AppColors.turquoise.withOpacity(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile(Map<String, dynamic> contact) {
    final phone = contact['phone'] as String? ?? '';
    final name = _resolveContactName(contact);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.emerald,
        radius: 22,
        child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      title: Text(name, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15)),
      subtitle: name != phone
          ? Text(phone, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13))
          : null,
      onTap: () => _openPrivateChat(phone, name),
    );
  }

  Widget _buildGroupTile(Map<String, dynamic> group) {
    final id = group['id'] as String? ?? '';
    final name = group['name'] as String? ?? 'Группа';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.turquoise.withOpacity(0.3),
        radius: 22,
        child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      title: Text(name, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15)),
      subtitle: Text('Группа', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
      onTap: () => _openGroupChat(id, name),
    );
  }

  Widget _buildMessageTile(Map<String, dynamic> msg) {
    final senderName = msg['sender_name'] as String? ?? msg['sender_phone'] as String? ?? '';
    final content = msg['content'] as String? ?? '';
    final convName = msg['conversation_name'] as String?;
    final convType = msg['conversation_type'] as String? ?? 'private';
    final createdAt = DateTime.tryParse(msg['created_at']?.toString() ?? '')?.toLocal();

    String subtitle = content;
    if (subtitle.length > 80) subtitle = '${subtitle.substring(0, 80)}...';

    String chatLabel = '';
    if (convType == 'group' && convName != null) {
      chatLabel = convName;
    }

    String timeStr = '';
    if (createdAt != null) {
      timeStr = '${createdAt.day.toString().padLeft(2, '0')}.${createdAt.month.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.white.withOpacity(0.08),
        radius: 22,
        child: Icon(Icons.chat_bubble_outline, size: 18, color: Colors.white.withOpacity(0.4)),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              senderName,
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (timeStr.isNotEmpty)
            Text(timeStr, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (chatLabel.isNotEmpty)
            Text(
              chatLabel,
              style: TextStyle(color: AppColors.turquoise.withOpacity(0.6), fontSize: 11),
            ),
        ],
      ),
      onTap: () => _openMessageChat(msg),
    );
  }
}
