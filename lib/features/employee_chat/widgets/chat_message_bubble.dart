import 'package:flutter/material.dart';
import '../models/employee_chat_message_model.dart';

/// Виджет пузыря сообщения
class ChatMessageBubble extends StatelessWidget {
  final EmployeeChatMessage message;
  final bool isMe;
  final bool showSenderName;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showSenderName = false,
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
            child: Container(
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
          ),
          if (!isMe) const Spacer(flex: 1),
        ],
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
