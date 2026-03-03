import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../models/message_model.dart';
import '../services/messenger_service.dart';

/// Context menu shown on long-press of a message bubble.
/// Extracted from MessengerChatPage for maintainability — new features
/// (edit, forward, pin, etc.) add items here instead of bloating chat_page.
class MessageContextMenu {
  MessageContextMenu._();

  /// Show the long-press context menu for a message.
  static void show(
    BuildContext context, {
    required MessengerMessage message,
    required String userPhone,
    required String conversationId,
    required VoidCallback onReply,
    required List<Map<String, dynamic>> readers,
    required VoidCallback Function(MessengerMessage) onDeleteConfirmed,
    void Function(MessengerMessage)? onEdit,
    void Function(MessengerMessage)? onForward,
    void Function(MessengerMessage)? onPin,
    void Function(MessengerMessage)? onSaveToFavorites,
  }) {
    final isMine = message.senderPhone == userPhone;
    final canEdit = isMine &&
        message.type == MessageType.text &&
        !message.isDeleted &&
        DateTime.now().difference(message.createdAt).inHours < 48;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Reply
            ListTile(
              leading: Icon(Icons.reply, color: Colors.white.withOpacity(0.7)),
              title: Text('Ответить', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                onReply();
              },
            ),
            // Edit (own text messages within 48h)
            if (canEdit && onEdit != null)
              ListTile(
                leading: Icon(Icons.edit_outlined, color: Colors.white.withOpacity(0.7)),
                title: Text('Редактировать', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                onTap: () {
                  Navigator.pop(ctx);
                  onEdit(message);
                },
              ),
            // Forward
            if (!message.isDeleted && onForward != null)
              ListTile(
                leading: Icon(Icons.shortcut, color: Colors.white.withOpacity(0.7)),
                title: Text('Переслать', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                onTap: () {
                  Navigator.pop(ctx);
                  onForward(message);
                },
              ),
            // Save to Favorites
            if (!message.isDeleted && onSaveToFavorites != null)
              ListTile(
                leading: Icon(Icons.bookmark_outline, color: Colors.white.withOpacity(0.7)),
                title: Text('В Избранное', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                onTap: () {
                  Navigator.pop(ctx);
                  onSaveToFavorites(message);
                },
              ),
            // Reaction
            ListTile(
              leading: Icon(Icons.emoji_emotions_outlined, color: Colors.white.withOpacity(0.7)),
              title: Text('Реакция', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _showReactionPicker(context,
                  message: message,
                  userPhone: userPhone,
                  conversationId: conversationId,
                );
              },
            ),
            // Pin / Unpin
            if (!message.isDeleted && onPin != null)
              ListTile(
                leading: Icon(
                  message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: Colors.white.withOpacity(0.7),
                ),
                title: Text(
                  message.isPinned ? 'Открепить' : 'Закрепить',
                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onPin(message);
                },
              ),
            // Who read (only for own messages with readers)
            if (isMine && readers.isNotEmpty)
              ListTile(
                leading: Icon(Icons.done_all, color: Colors.white.withOpacity(0.7)),
                title: Text('Кто прочитал', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                onTap: () {
                  Navigator.pop(ctx);
                  _showReadersDialog(context, readers: readers);
                },
              ),
            // Delete (only own messages)
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Удалить', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(context, message: message, onConfirmed: onDeleteConfirmed);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Reaction picker dialog (6 emoji).
  static void _showReactionPicker(
    BuildContext context, {
    required MessengerMessage message,
    required String userPhone,
    required String conversationId,
  }) {
    final reactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Wrap(
          spacing: 12,
          children: reactions.map((emoji) => GestureDetector(
            onTap: () {
              Navigator.pop(ctx);
              MessengerService.addReaction(
                conversationId,
                message.id,
                phone: userPhone,
                reaction: emoji,
              );
            },
            child: Text(emoji, style: const TextStyle(fontSize: 32)),
          )).toList(),
        ),
      ),
    );
  }

  /// Delete confirmation dialog.
  static void _confirmDelete(
    BuildContext context, {
    required MessengerMessage message,
    required VoidCallback Function(MessengerMessage) onConfirmed,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Удалить сообщение?', style: TextStyle(color: Colors.white.withOpacity(0.9))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onConfirmed(message)();
    }
  }

  /// Readers list bottom sheet.
  static void _showReadersDialog(
    BuildContext context, {
    required List<Map<String, dynamic>> readers,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.done_all, color: AppColors.turquoise, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Прочитали (${readers.length})',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            ...readers.map((r) {
              final name = r['name'] as String;
              final readAt = r['readAt'] as DateTime;
              final timeStr = '${readAt.toLocal().hour.toString().padLeft(2, '0')}:${readAt.toLocal().minute.toString().padLeft(2, '0')}';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.emerald,
                  radius: 18,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(name, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
                trailing: Text(timeStr, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
