import 'package:flutter/material.dart';
import '../models/employee_chat_message_model.dart';

/// Доступные реакции
const List<String> availableReactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

/// Виджет пузыря сообщения
class ChatMessageBubble extends StatelessWidget {
  final EmployeeChatMessage message;
  final bool isMe;
  final bool showSenderName;
  final String? userPhone;
  final Function(String reaction)? onReactionTap;
  final VoidCallback? onForwardTap;
  final VoidCallback? onLongPress;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showSenderName = false,
    this.userPhone,
    this.onReactionTap,
    this.onForwardTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isMe) const Spacer(flex: 1),
          Flexible(
            flex: 4,
            child: GestureDetector(
              onLongPress: () => _showMessageMenu(context),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF004D40) : Colors.grey[200],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                        bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Информация о пересылке
                        if (message.forwardedFrom != null) _buildForwardedHeader(),
                        // Имя отправителя
                        if (showSenderName)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              message.senderName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isMe ? Colors.white70 : const Color(0xFF004D40),
                              ),
                            ),
                          ),
                        // Изображение
                        if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
                          GestureDetector(
                            onTap: () => _showFullImage(context),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                message.imageUrl!,
                                width: 200,
                                height: 200,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: 200,
                                    height: 200,
                                    color: Colors.grey[300],
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 200,
                                    height: 200,
                                    color: Colors.grey[300],
                                    child: const Icon(
                                      Icons.broken_image,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        // Текст
                        if (message.text.isNotEmpty) ...[
                          if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
                            const SizedBox(height: 8),
                          Text(
                            message.text,
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontSize: 15,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        // Время и статус
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.formattedTime,
                              style: TextStyle(
                                fontSize: 11,
                                color: isMe ? Colors.white54 : Colors.grey[600],
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                message.readBy.length > 1 ? Icons.done_all : Icons.done,
                                size: 14,
                                color: message.readBy.length > 1
                                    ? Colors.lightBlueAccent
                                    : Colors.white54,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Реакции
                  if (message.hasReactions) _buildReactions(),
                ],
              ),
            ),
          ),
          if (!isMe) const Spacer(flex: 1),
        ],
      ),
    );
  }

  /// Заголовок пересланного сообщения
  Widget _buildForwardedHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isMe ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white54 : const Color(0xFF004D40),
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.reply,
            size: 14,
            color: isMe ? Colors.white70 : Colors.grey[600],
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Переслано от ${message.forwardedFrom!.originalSenderName}',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: isMe ? Colors.white70 : Colors.grey[600],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Виджет реакций
  Widget _buildReactions() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: message.reactions.entries.map((entry) {
          final reaction = entry.key;
          final phones = entry.value;
          final count = phones.length;
          final hasMyReaction = userPhone != null && phones.contains(userPhone);

          return GestureDetector(
            onTap: () {
              if (onReactionTap != null) {
                onReactionTap!(reaction);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: hasMyReaction
                    ? const Color(0xFF004D40).withOpacity(0.2)
                    : Colors.grey.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: hasMyReaction
                    ? Border.all(color: const Color(0xFF004D40), width: 1)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reaction, style: const TextStyle(fontSize: 14)),
                  if (count > 1) ...[
                    const SizedBox(width: 2),
                    Text(
                      count.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        color: hasMyReaction
                            ? const Color(0xFF004D40)
                            : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Показать меню сообщения
  void _showMessageMenu(BuildContext context) {
    if (onLongPress != null) {
      onLongPress!();
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Линия-индикатор
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Реакции
              if (onReactionTap != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: availableReactions.map((reaction) {
                      final hasMyReaction = userPhone != null &&
                          message.hasReactionFrom(userPhone!, reaction);
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          onReactionTap!(reaction);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: hasMyReaction
                                ? const Color(0xFF004D40).withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            reaction,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(),
              ],
              // Переслать
              if (onForwardTap != null)
                ListTile(
                  leading: const Icon(Icons.forward, color: Color(0xFF004D40)),
                  title: const Text('Переслать'),
                  onTap: () {
                    Navigator.pop(context);
                    onForwardTap!();
                  },
                ),
              // Копировать текст
              if (message.text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy, color: Color(0xFF004D40)),
                  title: const Text('Копировать'),
                  onTap: () {
                    Navigator.pop(context);
                    // Копирование реализуется в родительском виджете
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    if (message.imageUrl == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: InteractiveViewer(
                child: Image.network(
                  message.imageUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
