import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/conversation_model.dart';
import '../services/messenger_service.dart';

/// Page to pick one or more conversations for forwarding messages.
class ConversationPickerPage extends StatefulWidget {
  final String userPhone;

  const ConversationPickerPage({super.key, required this.userPhone});

  @override
  State<ConversationPickerPage> createState() => _ConversationPickerPageState();
}

class _ConversationPickerPageState extends State<ConversationPickerPage> {
  List<Conversation> _conversations = [];
  final Set<String> _selected = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await MessengerService.getConversations(widget.userPhone);
    if (mounted) {
      setState(() {
        _conversations = list;
        _isLoading = false;
      });
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _confirm() {
    Navigator.pop(context, _selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.night,
        title: Text(
          _selected.isEmpty ? 'Переслать' : 'Выбрано: ${_selected.length}',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _confirm,
              child: const Text('Отправить', style: TextStyle(color: AppColors.turquoise, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.turquoise))
          : ListView.builder(
              itemCount: _conversations.length,
              itemBuilder: (context, index) {
                final conv = _conversations[index];
                final isSelected = _selected.contains(conv.id);
                final name = conv.displayName(widget.userPhone);

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSelected ? AppColors.turquoise : AppColors.emerald,
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                  ),
                  title: Text(name, style: TextStyle(color: Colors.white.withOpacity(0.9))),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: AppColors.turquoise, size: 22)
                      : null,
                  onTap: () => _toggleSelection(conv.id),
                );
              },
            ),
    );
  }
}
