import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/employee_chat_message_model.dart';

/// Доступные реакции
const List<String> availableReactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

/// Виджет пузыря сообщения с улучшенным визуалом
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: isMe
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF00695C), Color(0xFF004D40)],
                            )
                          : null,
                      color: isMe ? null : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
                        bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isMe
                              ? const Color(0xFF004D40).withOpacity(0.2)
                              : Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Информация о пересылке
                        if (message.forwardedFrom != null) _buildForwardedHeader(),
                        // Имя отправителя
                        if (showSenderName)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              message.senderName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isMe ? Colors.white70 : const Color(0xFF004D40),
                              ),
                            ),
                          ),
                        // Изображение
                        if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
                          GestureDetector(
                            onTap: () => _showFullImage(context),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  message.imageUrl!,
                                  width: 220,
                                  height: 220,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      width: 220,
                                      height: 220,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          value: loadingProgress.expectedTotalBytes != null
                                              ? loadingProgress.cumulativeBytesLoaded /
                                                  loadingProgress.expectedTotalBytes!
                                              : null,
                                          color: const Color(0xFF004D40),
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 220,
                                      height: 220,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.broken_image_rounded,
                                            size: 48,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Не удалось загрузить',
                                            style: TextStyle(
                                              color: Colors.grey[500],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        // Текст
                        if (message.text.isNotEmpty)
                          Text(
                            message.text,
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.grey[850],
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        const SizedBox(height: 6),
                        // Время и статус
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.formattedTime,
                              style: TextStyle(
                                fontSize: 11,
                                color: isMe ? Colors.white54 : Colors.grey[500],
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              Icon(
                                message.readBy.length > 1 ? Icons.done_all_rounded : Icons.done_rounded,
                                size: 15,
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMe ? Colors.white.withOpacity(0.1) : const Color(0xFF004D40).withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white54 : const Color(0xFF004D40),
            width: 3,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.reply_rounded,
            size: 14,
            color: isMe ? Colors.white70 : const Color(0xFF004D40),
          ),
          const SizedBox(width: 6),
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
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: message.reactions.entries.map((entry) {
          final reaction = entry.key;
          final phones = entry.value;
          final count = phones.length;
          final hasMyReaction = userPhone != null && phones.contains(userPhone);

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              if (onReactionTap != null) {
                onReactionTap!(reaction);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasMyReaction
                    ? const Color(0xFF004D40).withOpacity(0.15)
                    : Colors.grey.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: hasMyReaction
                    ? Border.all(color: const Color(0xFF004D40).withOpacity(0.5), width: 1.5)
                    : null,
                boxShadow: hasMyReaction
                    ? [
                        BoxShadow(
                          color: const Color(0xFF004D40).withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reaction, style: const TextStyle(fontSize: 14)),
                  if (count > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      count.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: hasMyReaction
                            ? const Color(0xFF004D40)
                            : Colors.grey[600],
                        fontWeight: FontWeight.w600,
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
    HapticFeedback.mediumImpact();

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
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: availableReactions.map((reaction) {
                      final hasMyReaction = userPhone != null &&
                          message.hasReactionFrom(userPhone!, reaction);
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context);
                          onReactionTap!(reaction);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: hasMyReaction
                                ? const Color(0xFF004D40).withOpacity(0.12)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: hasMyReaction
                                ? Border.all(color: const Color(0xFF004D40).withOpacity(0.3))
                                : null,
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
                Divider(height: 1, color: Colors.grey[200]),
              ],
              // Переслать
              if (onForwardTap != null)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF004D40).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.forward_rounded, color: Color(0xFF004D40)),
                  ),
                  title: const Text('Переслать'),
                  onTap: () {
                    Navigator.pop(context);
                    onForwardTap!();
                  },
                ),
              // Копировать текст
              if (message.text.isNotEmpty)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.copy_rounded, color: Colors.blue),
                  ),
                  title: const Text('Копировать'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Текст скопирован'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        backgroundColor: const Color(0xFF004D40),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    if (message.imageUrl == null) return;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: Scaffold(
            backgroundColor: Colors.black.withOpacity(0.95),
            body: Stack(
              children: [
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Hero(
                        tag: 'image_${message.id}',
                        child: Image.network(
                          message.imageUrl!,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                                color: Colors.white,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.broken_image_rounded,
                                size: 64,
                                color: Colors.white54,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  right: 10,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
