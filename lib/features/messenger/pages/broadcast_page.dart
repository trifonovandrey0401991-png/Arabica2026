import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/conversation_model.dart';
import '../services/messenger_service.dart';

/// Page for sending a broadcast message to multiple conversations at once.
/// Available to managers (управляющие/заведующие).
class BroadcastPage extends StatefulWidget {
  final String userPhone;

  const BroadcastPage({super.key, required this.userPhone});

  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  final _messageController = TextEditingController();
  List<Conversation> _conversations = [];
  final Set<String> _selectedIds = {};
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      final convos = await MessengerService.getConversations(
        widget.userPhone,
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        _conversations = convos;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить чаты';
        _isLoading = false;
      });
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        if (_selectedIds.length < 50) {
          _selectedIds.add(id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Максимум 50 чатов для рассылки')),
          );
        }
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _conversations.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.clear();
        for (final c in _conversations.take(50)) {
          _selectedIds.add(c.id);
        }
      }
    });
  }

  Future<void> _sendBroadcast() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedIds.isEmpty) return;

    setState(() => _isSending = true);

    final result = await MessengerService.broadcast(
      conversationIds: _selectedIds.toList(),
      content: text,
    );

    if (!mounted) return;

    if (result != null && result['success'] == true) {
      final sent = result['sent'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Отправлено в $sent чатов')),
      );
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка отправки')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.emeraldDark,
        title: Text(
          'Рассылка (${_selectedIds.length})',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_conversations.isNotEmpty)
            TextButton(
              onPressed: _selectAll,
              child: Text(
                _selectedIds.length == _conversations.length
                    ? 'Снять все'
                    : 'Выбрать все',
                style: TextStyle(color: AppColors.gold),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Message input
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.emeraldDark,
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Текст сообщения...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: AppColors.night,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // Conversations list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      )
                    : _conversations.isEmpty
                        ? Center(
                            child: Text(
                              'Нет чатов',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _conversations.length,
                            itemBuilder: (context, index) {
                              final conv = _conversations[index];
                              final isSelected = _selectedIds.contains(conv.id);
                              final name = conv.displayName(widget.userPhone);
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isSelected
                                      ? AppColors.gold
                                      : AppColors.emerald,
                                  child: isSelected
                                      ? const Icon(Icons.check,
                                          color: Colors.white, size: 20)
                                      : Text(
                                          (name.isNotEmpty
                                                  ? name[0]
                                                  : '?')
                                              .toUpperCase(),
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  conv.type == ConversationType.group
                                      ? 'Группа'
                                      : conv.type == ConversationType.channel
                                          ? 'Канал'
                                          : 'Личный чат',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(Icons.check_circle,
                                        color: AppColors.gold)
                                    : Icon(Icons.circle_outlined,
                                        color:
                                            Colors.white.withOpacity(0.3)),
                                onTap: () => _toggleSelection(conv.id),
                              );
                            },
                          ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _isSending ||
                    _selectedIds.isEmpty ||
                    _messageController.text.trim().isEmpty
                ? null
                : _sendBroadcast,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              disabledBackgroundColor: AppColors.gold.withOpacity(0.3),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSending
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Отправить (${_selectedIds.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
