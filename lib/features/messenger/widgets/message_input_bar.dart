import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class MessageInputBar extends StatefulWidget {
  final Function(String text) onSendText;
  final VoidCallback? onAttachmentTap;
  final VoidCallback? onEmojiTap;
  final VoidCallback? onVoiceStart;
  final VoidCallback? onVoiceStop;
  final Function(String)? onTyping;
  final String? replyToText;
  final VoidCallback? onCancelReply;
  final bool isRecording;

  const MessageInputBar({
    super.key,
    required this.onSendText,
    this.onAttachmentTap,
    this.onEmojiTap,
    this.onVoiceStart,
    this.onVoiceStop,
    this.onTyping,
    this.replyToText,
    this.onCancelReply,
    this.isRecording = false,
  });

  @override
  State<MessageInputBar> createState() => _MessageInputBarState();
}

class _MessageInputBarState extends State<MessageInputBar> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
      if (hasText) widget.onTyping?.call(_controller.text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
    setState(() => _hasText = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reply preview
        if (widget.replyToText != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: const Border(top: BorderSide(color: Colors.black12)),
            ),
            child: Row(
              children: [
                Container(width: 3, height: 30, color: AppColors.emerald),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.replyToText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onCancelReply,
                  child: const Icon(Icons.close, size: 18, color: Colors.grey),
                ),
              ],
            ),
          ),

        // Input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.black12)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                // Emoji button
                IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined),
                  color: Colors.grey[600],
                  iconSize: 24,
                  onPressed: widget.onEmojiTap,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),

                // Attachment button
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  color: Colors.grey[600],
                  iconSize: 24,
                  onPressed: widget.onAttachmentTap,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),

                // Text input
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _controller,
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ),

                const SizedBox(width: 4),

                // Send or voice button
                if (_hasText)
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: AppColors.emerald,
                    iconSize: 24,
                    onPressed: _handleSend,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  )
                else
                  GestureDetector(
                    onLongPressStart: (_) => widget.onVoiceStart?.call(),
                    onLongPressEnd: (_) => widget.onVoiceStop?.call(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: widget.isRecording ? AppColors.error : AppColors.emerald,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.isRecording ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
