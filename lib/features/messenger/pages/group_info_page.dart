import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/conversation_model.dart';
import '../models/participant_model.dart';
import '../services/messenger_service.dart';

class GroupInfoPage extends StatefulWidget {
  final Conversation conversation;
  final String userPhone;
  final String userName;

  const GroupInfoPage({
    super.key,
    required this.conversation,
    required this.userPhone,
    required this.userName,
  });

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late Conversation _conversation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      final conv = await MessengerService.getConversation(widget.conversation.id);
      if (conv != null && mounted) {
        setState(() {
          _conversation = conv;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isCreator => _conversation.creatorPhone == widget.userPhone;

  Future<void> _removeMember(Participant participant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('Удалить ${participant.name ?? participant.phone} из группы?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await MessengerService.removeParticipant(
        _conversation.id,
        participant.phone,
        requesterPhone: widget.userPhone,
      );
      _refresh();
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Покинуть группу?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Покинуть', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await MessengerService.leaveGroup(_conversation.id, widget.userPhone);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить группу?'),
        content: const Text('Все сообщения будут удалены безвозвратно.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await MessengerService.deleteConversation(_conversation.id, widget.userPhone);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.emerald,
        foregroundColor: Colors.white,
        title: const Text('Информация о группе'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.emerald))
          : ListView(
              children: [
                // Group header
                Container(
                  padding: const EdgeInsets.all(24),
                  color: AppColors.emerald.withOpacity(0.05),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: AppColors.emerald,
                        child: Text(
                          (_conversation.name ?? 'Г')[0].toUpperCase(),
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _conversation.name ?? 'Группа',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_conversation.participants.length} участников',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      if (_conversation.creatorName != null)
                        Text(
                          'Создатель: ${_conversation.creatorName}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),

                // Participants
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Участники',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.emerald),
                  ),
                ),

                ..._conversation.participants.map((p) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: p.isAdmin ? AppColors.gold : AppColors.emeraldLight,
                    child: Text(
                      (p.name ?? p.phone)[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(p.name ?? p.phone),
                      if (p.isAdmin)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Создатель', style: TextStyle(fontSize: 10, color: AppColors.darkGold)),
                        ),
                      if (p.phone == widget.userPhone)
                        const Text(' (вы)', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                  subtitle: Text(p.phone, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  trailing: _isCreator && p.phone != widget.userPhone
                      ? IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          onPressed: () => _removeMember(p),
                        )
                      : null,
                )),

                const Divider(),

                // Actions
                ListTile(
                  leading: const Icon(Icons.exit_to_app, color: Colors.orange),
                  title: const Text('Покинуть группу'),
                  onTap: _leaveGroup,
                ),

                if (_isCreator)
                  ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('Удалить группу', style: TextStyle(color: Colors.red)),
                    onTap: _deleteGroup,
                  ),
              ],
            ),
    );
  }
}
