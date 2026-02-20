import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/conversation_model.dart';

class ChatListTile extends StatelessWidget {
  final Conversation conversation;
  final String myPhone;
  final VoidCallback onTap;

  const ChatListTile({
    super.key,
    required this.conversation,
    required this.myPhone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = conversation.displayName(myPhone);
    final lastMsg = conversation.lastMessage;
    final unread = conversation.unreadCount;
    final isGroup = conversation.type == ConversationType.group;

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: isGroup ? AppColors.emeraldLight : AppColors.emerald,
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: TextStyle(
                fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (lastMsg != null)
            Text(
              lastMsg.formattedTime,
              style: TextStyle(
                fontSize: 12,
                color: unread > 0 ? AppColors.emeraldGreen : Colors.grey,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          if (isGroup && lastMsg != null && !lastMsg.isDeleted)
            Text(
              '${lastMsg.senderName ?? lastMsg.senderPhone}: ',
              style: const TextStyle(fontSize: 13, color: AppColors.emeraldLight),
              maxLines: 1,
            ),
          Expanded(
            child: Text(
              lastMsg?.preview ?? 'Нет сообщений',
              style: TextStyle(
                fontSize: 13,
                color: unread > 0 ? Colors.black87 : Colors.grey[600],
                fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (unread > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.emeraldGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                unread > 99 ? '99+' : unread.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
