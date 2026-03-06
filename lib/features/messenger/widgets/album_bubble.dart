import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../models/message_model.dart';

/// Telegram-style media album bubble.
/// Renders 2-10 photos/videos in a compact grid layout.
class AlbumBubble extends StatelessWidget {
  final List<MessengerMessage> messages;
  final bool isMine;
  final bool showSenderName;
  final String? displaySenderName;
  final VoidCallback? onLongPress;
  final void Function(String imageUrl)? onImageTap;
  final void Function(String videoUrl)? onVideoTap;

  const AlbumBubble({
    super.key,
    required this.messages,
    required this.isMine,
    this.showSenderName = false,
    this.displaySenderName,
    this.onLongPress,
    this.onImageTap,
    this.onVideoTap,
  });

  String _fullUrl(String? url) {
    if (url == null) return '';
    return url.startsWith('http') ? url : '${ApiConstants.serverUrl}$url';
  }

  @override
  Widget build(BuildContext context) {
    // Caption from the first message (if any)
    final caption = messages.first.content;
    final hasCaption = caption != null && caption.isNotEmpty;
    final time = messages.last.formattedTime;

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
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showSenderName && !isMine && displaySenderName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text(
                    displaySenderName!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.turquoise,
                    ),
                  ),
                ),
              // Media grid
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft:
                      hasCaption ? Radius.zero : const Radius.circular(14),
                  bottomRight:
                      hasCaption ? Radius.zero : const Radius.circular(14),
                ),
                child: _buildGrid(),
              ),
              // Caption
              if (hasCaption)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isMine
                        ? const LinearGradient(
                            colors: [AppColors.emeraldLight, AppColors.emerald],
                          )
                        : null,
                    color: isMine ? null : Colors.white.withOpacity(0.08),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  child: Text(
                    caption,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
              // Time
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    final count = messages.length;
    switch (count) {
      case 2:
        return _buildRow(messages, height: 150);
      case 3:
        return Column(
          children: [
            _buildMediaItem(messages[0], height: 180, width: double.infinity),
            const SizedBox(height: 2),
            _buildRow(messages.sublist(1), height: 100),
          ],
        );
      case 4:
        return Column(
          children: [
            _buildRow(messages.sublist(0, 2), height: 130),
            const SizedBox(height: 2),
            _buildRow(messages.sublist(2, 4), height: 130),
          ],
        );
      default: // 5-10
        final rows = <Widget>[];
        rows.add(_buildRow(messages.sublist(0, 2), height: 130));
        int i = 2;
        while (i < count && i < 10) {
          final end = (i + 3).clamp(0, count);
          rows.add(const SizedBox(height: 2));
          rows.add(_buildRow(messages.sublist(i, end), height: 90));
          i = end;
        }
        return Column(children: rows);
    }
  }

  Widget _buildRow(List<MessengerMessage> items, {required double height}) {
    return SizedBox(
      height: height,
      child: Row(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final msg = entry.value;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i > 0 ? 2 : 0),
              child: _buildMediaItem(msg, height: height),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMediaItem(MessengerMessage msg,
      {required double height, double? width}) {
    final url = _fullUrl(msg.mediaUrl);
    if (url.isEmpty) return SizedBox(height: height, width: width);

    final isVideo =
        msg.type == MessageType.video || msg.type == MessageType.videoNote;

    return GestureDetector(
      onTap: () {
        if (isVideo) {
          onVideoTap?.call(url);
        } else {
          onImageTap?.call(url);
        }
      },
      child: SizedBox(
        height: height,
        width: width,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: Colors.white.withOpacity(0.06),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.turquoise,
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                color: Colors.white.withOpacity(0.06),
                child: Icon(Icons.broken_image,
                    color: Colors.white.withOpacity(0.3)),
              ),
            ),
            if (isVideo)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 24),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
