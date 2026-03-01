import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../models/message_model.dart';

class MessageBubble extends StatelessWidget {
  final MessengerMessage message;
  final bool isMine;
  final bool showSenderName;
  /// Override for sender name display (privacy filter for clients)
  final String? displaySenderName;
  final VoidCallback? onLongPress;
  final VoidCallback? onPlayVoice;
  final bool isPlayingVoice;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showSenderName = false,
    this.displaySenderName,
    this.onLongPress,
    this.onPlayVoice,
    this.isPlayingVoice = false,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return _buildDeletedBubble();
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(
            left: isMine ? 60 : 8,
            right: isMine ? 8 : 60,
            top: 2,
            bottom: 2,
          ),
          child: Column(
            crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: _getPadding(),
                decoration: BoxDecoration(
                  gradient: isMine
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.emeraldLight, AppColors.emerald],
                        )
                      : null,
                  color: isMine ? null : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMine ? 18 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 18),
                  ),
                  border: isMine
                      ? null
                      : Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showSenderName && !isMine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          displaySenderName ?? message.senderName ?? message.senderPhone,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.turquoise,
                          ),
                        ),
                      ),
                    _buildContent(context),
                    const SizedBox(height: 4),
                    Text(
                      message.formattedTime,
                      style: TextStyle(
                        fontSize: 10,
                        color: isMine
                            ? Colors.white.withOpacity(0.6)
                            : Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ],
                ),
              ),
              // Reactions
              if (message.reactions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _buildReactions(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  EdgeInsets _getPadding() {
    if (message.type == MessageType.image || message.type == MessageType.video) {
      return const EdgeInsets.all(4);
    }
    if (message.type == MessageType.emoji) {
      return const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    }
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  }

  Widget _buildContent(BuildContext context) {
    switch (message.type) {
      case MessageType.text:
        return Text(
          message.content ?? '',
          style: TextStyle(
            fontSize: 15,
            color: isMine
                ? Colors.white.withOpacity(0.95)
                : Colors.white.withOpacity(0.85),
          ),
        );

      case MessageType.emoji:
        return Text(
          message.content ?? '😀',
          style: const TextStyle(fontSize: 48),
        );

      case MessageType.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
            child: message.mediaUrl != null
                ? CachedNetworkImage(
                    imageUrl: message.mediaUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 200,
                      height: 150,
                      color: Colors.white.withOpacity(0.06),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.turquoise,
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 200,
                      height: 150,
                      color: Colors.white.withOpacity(0.06),
                      child: Icon(Icons.broken_image, size: 40, color: Colors.white.withOpacity(0.3)),
                    ),
                  )
                : const SizedBox(width: 200, height: 150),
          ),
        );

      case MessageType.video:
        return Container(
          width: 220,
          height: 160,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Center(
            child: Icon(Icons.play_circle_outline, size: 50, color: Colors.white),
          ),
        );

      case MessageType.voice:
        final duration = message.voiceDuration ?? 0;
        final durationStr = '${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: onPlayVoice,
              child: Icon(
                isPlayingVoice ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: isMine ? Colors.white : AppColors.turquoise,
                size: 36,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                height: 30,
                constraints: const BoxConstraints(minWidth: 80, maxWidth: 150),
                child: CustomPaint(
                  painter: _WaveformPainter(
                    color: isMine
                        ? Colors.white.withOpacity(0.5)
                        : AppColors.turquoise.withOpacity(0.5),
                  ),
                  size: const Size(double.infinity, 30),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              durationStr,
              style: TextStyle(
                fontSize: 12,
                color: isMine
                    ? Colors.white.withOpacity(0.7)
                    : Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildDeletedBubble() {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isMine ? 60 : 8,
          right: isMine ? 8 : 60,
          top: 2,
          bottom: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14, color: Colors.white.withOpacity(0.3)),
            const SizedBox(width: 4),
            Text(
              'Сообщение удалено',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.35),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactions() {
    return Wrap(
      spacing: 4,
      children: message.reactions.entries.map((entry) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Text(
            '${entry.key} ${entry.value.length}',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
          ),
        );
      }).toList(),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Color color;
  _WaveformPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const barCount = 20;
    final barWidth = size.width / (barCount * 2);

    for (int i = 0; i < barCount; i++) {
      final x = barWidth + i * (size.width / barCount);
      final height = (size.height * 0.3) + (size.height * 0.7 * ((i * 7 + 3) % 11) / 11);
      final y1 = (size.height - height) / 2;
      final y2 = y1 + height;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
