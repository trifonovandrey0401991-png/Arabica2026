import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../models/message_model.dart';
import 'video_note_player.dart';
import 'inline_chat_video_player.dart';

class MessageBubble extends StatelessWidget {
  final MessengerMessage message;
  final bool isMine;
  final bool showSenderName;
  /// Override for sender name display (privacy filter for clients)
  final String? displaySenderName;
  final VoidCallback? onLongPress;
  final VoidCallback? onPlayVoice;
  final bool isPlayingVoice;
  final bool isVoicePaused;
  final double voiceProgress;
  final int voicePositionSec;
  final void Function(double progress)? onSeekVoice;
  /// How many OTHER participants have last_read_at >= message.createdAt
  final int readersCount;
  /// Total number of other participants (excluding sender)
  final int totalOtherCount;
  /// Original message this is a reply to (for showing quote block)
  final MessengerMessage? replyToMessage;
  /// Optional poll widget to render inside bubble for poll messages
  final Widget? pollWidget;
  /// Callback when user taps "Написать" on a contact card
  final void Function(String phone, String name)? onContactTap;
  /// Callback when user taps an image to view fullscreen
  final void Function(String imageUrl)? onImageTap;
  /// Callback when user taps a video to play fullscreen
  final void Function(String videoUrl)? onVideoTap;
  /// Callback when user taps a file to download/open
  final void Function(String fileUrl, String fileName)? onFileTap;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showSenderName = false,
    this.displaySenderName,
    this.onLongPress,
    this.onPlayVoice,
    this.isPlayingVoice = false,
    this.isVoicePaused = false,
    this.voiceProgress = 0.0,
    this.voicePositionSec = 0,
    this.onSeekVoice,
    this.readersCount = 0,
    this.totalOtherCount = 1,
    this.replyToMessage,
    this.pollWidget,
    this.onContactTap,
    this.onImageTap,
    this.onVideoTap,
    this.onFileTap,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      return _buildDeletedBubble();
    }

    // Video notes render as a bare circle (no bubble background)
    if (message.type == MessageType.videoNote) {
      return _buildVideoNoteBubble();
    }

    // Stickers render as a large image without bubble background
    if (message.type == MessageType.sticker) {
      return _buildStickerBubble();
    }

    // Emoji-only messages (1-3 emoji, no text) — large, no bubble
    final emojiCount = _emojiOnlyCount(message.content);
    if (emojiCount != null && (message.type == MessageType.text || message.type == MessageType.emoji)) {
      return _buildEmojiBubble(emojiCount);
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
                    if (message.isForwarded)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shortcut, size: 12, color: Colors.white.withOpacity(0.45)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Переслано от ${message.forwardedFromName ?? 'неизвестно'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.white.withOpacity(0.45),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (replyToMessage != null)
                      _buildReplyQuote(),
                    _buildContent(context),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.formattedTime,
                          style: TextStyle(
                            fontSize: 10,
                            color: isMine
                                ? Colors.white.withOpacity(0.6)
                                : Colors.white.withOpacity(0.35),
                          ),
                        ),
                        if (message.isEdited) ...[
                          const SizedBox(width: 4),
                          Text(
                            'ред.',
                            style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: isMine
                                  ? Colors.white.withOpacity(0.5)
                                  : Colors.white.withOpacity(0.3),
                            ),
                          ),
                        ],
                        if (isMine && !message.isDeleted) ...[
                          const SizedBox(width: 3),
                          _buildReadTick(),
                        ],
                      ],
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
    if (message.type == MessageType.image || message.type == MessageType.video || message.type == MessageType.gif) {
      return const EdgeInsets.all(4);
    }
    if (message.type == MessageType.videoNote || message.type == MessageType.sticker) {
      return const EdgeInsets.all(4);
    }
    if (message.type == MessageType.emoji) {
      return const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    }
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  }

  /// Derive thumbnail URL from video media URL.
  /// e.g. https://arabica26.ru/messenger-media/abc.mp4 → .../messenger-media/thumb/abc.jpg
  static String? _videoThumbnailUrl(String? mediaUrl) {
    if (mediaUrl == null) return null;
    final lastSlash = mediaUrl.lastIndexOf('/');
    if (lastSlash < 0) return null;
    final filename = mediaUrl.substring(lastSlash + 1);
    final nameWithoutExt = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final basePath = mediaUrl.substring(0, lastSlash);
    return '$basePath/thumb/$nameWithoutExt.jpg';
  }

  Widget _buildReplyQuote() {
    final reply = replyToMessage!;
    final authorName = reply.senderName ?? reply.senderPhone;
    final preview = reply.preview;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: const Border(
          left: BorderSide(color: AppColors.turquoise, width: 2),
        ),
        color: isMine
            ? Colors.white.withOpacity(0.1)
            : Colors.white.withOpacity(0.06),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            authorName,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.turquoise,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            preview,
            style: TextStyle(
              fontSize: 12,
              color: isMine
                  ? Colors.white.withOpacity(0.6)
                  : Colors.white.withOpacity(0.45),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
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
        return GestureDetector(
          onTap: message.mediaUrl != null && onImageTap != null
              ? () => onImageTap!(message.mediaUrl!)
              : null,
          child: ClipRRect(
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
          ),
        );

      case MessageType.video:
        return InlineChatVideoPlayer(
          videoUrl: message.mediaUrl ?? '',
          thumbnailUrl: _videoThumbnailUrl(message.mediaUrl),
          onTap: message.mediaUrl != null && onVideoTap != null
              ? () => onVideoTap!(message.mediaUrl!)
              : null,
        );

      case MessageType.videoNote:
        return VideoNotePlayer(
          mediaUrl: message.mediaUrl ?? '',
          durationSeconds: message.voiceDuration,
        );

      case MessageType.voice:
        final duration = message.voiceDuration ?? 0;
        final isActive = isPlayingVoice || isVoicePaused;
        final showSec = isActive ? voicePositionSec : duration;
        final timeStr = '${showSec ~/ 60}:${(showSec % 60).toString().padLeft(2, '0')}';
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTapDown: onSeekVoice != null ? (details) {
                      final progress = details.localPosition.dx / constraints.maxWidth;
                      onSeekVoice!(progress.clamp(0.0, 1.0));
                    } : null,
                    onHorizontalDragUpdate: onSeekVoice != null ? (details) {
                      final progress = details.localPosition.dx / constraints.maxWidth;
                      onSeekVoice!(progress.clamp(0.0, 1.0));
                    } : null,
                    child: Container(
                      height: 30,
                      constraints: const BoxConstraints(minWidth: 80, maxWidth: 150),
                      child: CustomPaint(
                        painter: _WaveformPainter(
                          color: isMine
                              ? Colors.white.withOpacity(0.3)
                              : AppColors.turquoise.withOpacity(0.3),
                          activeColor: isMine
                              ? Colors.white
                              : AppColors.turquoise,
                          progress: voiceProgress,
                        ),
                        size: const Size(double.infinity, 30),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 12,
                color: isMine
                    ? Colors.white.withOpacity(0.7)
                    : Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        );

      case MessageType.call:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.call,
              size: 16,
              color: isMine ? Colors.white.withOpacity(0.85) : AppColors.turquoise,
            ),
            const SizedBox(width: 6),
            Text(
              message.content ?? '📞 Звонок',
              style: TextStyle(
                fontSize: 13,
                color: isMine ? Colors.white.withOpacity(0.85) : Colors.white.withOpacity(0.75),
              ),
            ),
          ],
        );

      case MessageType.file:
        return GestureDetector(
          onTap: message.mediaUrl != null && onFileTap != null
              ? () => onFileTap!(message.mediaUrl!, message.fileName ?? 'Документ')
              : null,
          child: _buildFileContent(),
        );

      case MessageType.poll:
        return pollWidget ?? Text(
          '📊 ${message.content ?? 'Опрос'}',
          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
        );

      case MessageType.sticker:
        // Rendered in _buildStickerBubble, fallback here
        return const SizedBox.shrink();

      case MessageType.gif:
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250, maxHeight: 250),
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
                      child: Icon(Icons.gif, size: 40, color: Colors.white.withOpacity(0.3)),
                    ),
                  )
                : const SizedBox(width: 200, height: 150),
          ),
        );

      case MessageType.contact:
        return _buildContactContent();
    }
  }

  Widget _buildFileContent() {
    final name = message.fileName ?? 'Документ';
    final size = message.fileSize;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';

    IconData icon;
    Color iconColor;
    switch (ext) {
      case 'pdf':
        icon = Icons.picture_as_pdf;
        iconColor = Colors.redAccent;
        break;
      case 'doc':
      case 'docx':
        icon = Icons.description;
        iconColor = Colors.blueAccent;
        break;
      case 'xls':
      case 'xlsx':
      case 'csv':
        icon = Icons.table_chart;
        iconColor = Colors.green;
        break;
      case 'zip':
        icon = Icons.folder_zip;
        iconColor = Colors.amber;
        break;
      default:
        icon = Icons.insert_drive_file;
        iconColor = Colors.white70;
    }

    String sizeStr = '';
    if (size != null) {
      if (size >= 1024 * 1024) {
        sizeStr = '${(size / (1024 * 1024)).toStringAsFixed(1)} МБ';
      } else {
        sizeStr = '${(size / 1024).toStringAsFixed(0)} КБ';
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isMine ? Colors.white.withOpacity(0.95) : Colors.white.withOpacity(0.85),
                ),
              ),
              if (sizeStr.isNotEmpty)
                Text(
                  sizeStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: isMine ? Colors.white.withOpacity(0.6) : Colors.white.withOpacity(0.4),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Returns a tick icon indicating delivery/read status.
  /// 3 states:
  /// - ✓ (grey)  = sent, not yet delivered
  /// - ✓✓ (grey) = delivered but not read
  /// - ✓✓ (white) = read
  Widget _buildReadTick() {
    final isPrivate = totalOtherCount <= 1;
    final deliveredCount = message.deliveredTo.length;

    if (isPrivate) {
      if (readersCount >= 1) {
        // Read → 2 white ticks
        return Icon(Icons.done_all, size: 12, color: Colors.white.withOpacity(0.85));
      }
      if (deliveredCount >= 1) {
        // Delivered but not read → 2 grey ticks
        return Icon(Icons.done_all, size: 12, color: Colors.white.withOpacity(0.45));
      }
      // Sent only → 1 grey tick
      return Icon(Icons.check, size: 12, color: Colors.white.withOpacity(0.45));
    } else {
      // Group chat
      if (readersCount >= totalOtherCount) {
        // All read → 2 white ticks
        return Icon(Icons.done_all, size: 12, color: Colors.white.withOpacity(0.85));
      } else if (readersCount > 0) {
        // Some read → 2 half-white ticks
        return Icon(Icons.done_all, size: 12, color: Colors.white.withOpacity(0.6));
      } else if (deliveredCount > 0) {
        // Delivered but nobody read → 2 grey ticks
        return Icon(Icons.done_all, size: 12, color: Colors.white.withOpacity(0.45));
      } else {
        // Nobody received → 1 grey tick
        return Icon(Icons.check, size: 12, color: Colors.white.withOpacity(0.45));
      }
    }
  }

  Widget _buildVideoNoteBubble() {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(
            left: isMine ? 40 : 8,
            right: isMine ? 8 : 40,
            top: 2,
            bottom: 2,
          ),
          child: Column(
            crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showSenderName && !isMine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text(
                    displaySenderName ?? message.senderName ?? message.senderPhone,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.turquoise,
                    ),
                  ),
                ),
              VideoNotePlayer(
                mediaUrl: message.mediaUrl ?? '',
                durationSeconds: message.voiceDuration,
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.formattedTime,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 3),
                    _buildReadTick(),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactContent() {
    String contactName = '';
    String contactPhone = '';
    try {
      final data = jsonDecode(message.content ?? '{}') as Map<String, dynamic>;
      contactName = data['name'] as String? ?? '';
      contactPhone = data['phone'] as String? ?? '';
    } catch (_) {
      contactName = message.content ?? 'Контакт';
    }

    final letter = contactName.isNotEmpty ? contactName[0].toUpperCase() : '?';

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.emeraldLight, AppColors.emerald],
                  ),
                ),
                child: Center(
                  child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contactName,
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (contactPhone.isNotEmpty)
                      Text(
                        contactPhone,
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (onContactTap != null && contactPhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 1,
              color: Colors.white.withOpacity(0.08),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => onContactTap!(contactPhone, contactName),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 14, color: AppColors.turquoise),
                  SizedBox(width: 6),
                  Text('Написать', style: TextStyle(color: AppColors.turquoise, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Returns emoji count (1-3) if text is emoji-only, null otherwise.
  static int? _emojiOnlyCount(String? text) {
    if (text == null) return null;
    final t = text.trim();
    if (t.isEmpty) return null;
    final count = t.characters.length;
    if (count < 1 || count > 3) return null;
    // Contains latin/cyrillic/digit → not emoji-only
    if (RegExp(r'[a-zA-Zа-яА-ЯёЁ0-9]').hasMatch(t)) return null;
    // Each grapheme cluster must have at least one high codepoint (emoji range)
    for (final ch in t.characters) {
      if (!ch.runes.any((r) => r > 0xFF)) return null;
    }
    return count;
  }

  Widget _buildEmojiBubble(int count) {
    final fontSize = count == 1 ? 64.0 : count == 2 ? 52.0 : 40.0;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(
            left: isMine ? 80 : 8,
            right: isMine ? 8 : 80,
            top: 2,
            bottom: 2,
          ),
          child: Column(
            crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showSenderName && !isMine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text(
                    displaySenderName ?? message.senderName ?? message.senderPhone,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.turquoise,
                    ),
                  ),
                ),
              if (replyToMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildReplyQuote(),
                ),
              Text(
                message.content ?? '',
                style: TextStyle(fontSize: fontSize),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.formattedTime,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 3),
                    _buildReadTick(),
                  ],
                ],
              ),
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

  Widget _buildStickerBubble() {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(
            left: isMine ? 80 : 8,
            right: isMine ? 8 : 80,
            top: 2,
            bottom: 2,
          ),
          child: Column(
            crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showSenderName && !isMine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  child: Text(
                    displaySenderName ?? message.senderName ?? message.senderPhone,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.turquoise,
                    ),
                  ),
                ),
              SizedBox(
                width: 150,
                height: 150,
                child: message.mediaUrl != null
                    ? CachedNetworkImage(
                        imageUrl: message.mediaUrl!,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.turquoise.withOpacity(0.5),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Icon(
                          Icons.emoji_emotions,
                          size: 48,
                          color: Colors.white.withOpacity(0.2),
                        ),
                      )
                    : Icon(
                        Icons.emoji_emotions,
                        size: 48,
                        color: Colors.white.withOpacity(0.2),
                      ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.formattedTime,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withOpacity(0.35),
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 3),
                    _buildReadTick(),
                  ],
                ],
              ),
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
  final Color activeColor;
  final double progress;

  _WaveformPainter({
    required this.color,
    Color? activeColor,
    this.progress = 0.0,
  }) : activeColor = activeColor ?? color;

  @override
  void paint(Canvas canvas, Size size) {
    final inactivePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const barCount = 20;
    final barWidth = size.width / (barCount * 2);
    final progressX = size.width * progress;

    for (int i = 0; i < barCount; i++) {
      final x = barWidth + i * (size.width / barCount);
      final height = (size.height * 0.3) + (size.height * 0.7 * ((i * 7 + 3) % 11) / 11);
      final y1 = (size.height - height) / 2;
      final y2 = y1 + height;
      canvas.drawLine(
        Offset(x, y1),
        Offset(x, y2),
        x <= progressX ? activePaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress || old.color != color || old.activeColor != activeColor;
}

/// Swipe-to-reply wrapper (Telegram-style).
/// Own messages swipe left, others' swipe right.
class SwipeableMessage extends StatefulWidget {
  final Widget child;
  final bool isMine;
  final VoidCallback? onSwipeToReply;

  const SwipeableMessage({
    super.key,
    required this.child,
    required this.isMine,
    this.onSwipeToReply,
  });

  @override
  State<SwipeableMessage> createState() => _SwipeableMessageState();
}

class _SwipeableMessageState extends State<SwipeableMessage>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  double _springStart = 0;
  bool _thresholdReached = false;
  late AnimationController _springBack;

  static const double _threshold = 64.0;
  static const double _maxDrag = 100.0;

  @override
  void initState() {
    super.initState();
    _springBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(_onSpringTick);
  }

  @override
  void dispose() {
    _springBack.dispose();
    super.dispose();
  }

  void _onSpringTick() {
    if (mounted) {
      setState(() {
        _dragOffset = lerpDouble(
          _springStart,
          0,
          Curves.easeOutCubic.transform(_springBack.value),
        )!;
      });
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (widget.onSwipeToReply == null) return;

    if (_springBack.isAnimating) _springBack.stop();

    setState(() {
      if (widget.isMine) {
        _dragOffset = (_dragOffset + details.delta.dx).clamp(-_maxDrag, 0.0);
      } else {
        _dragOffset = (_dragOffset + details.delta.dx).clamp(0.0, _maxDrag);
      }
    });

    if (!_thresholdReached && _dragOffset.abs() >= _threshold) {
      _thresholdReached = true;
      HapticFeedback.mediumImpact();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_thresholdReached) {
      widget.onSwipeToReply?.call();
    }
    _thresholdReached = false;
    _animateBack();
  }

  void _onDragCancel() {
    _thresholdReached = false;
    _animateBack();
  }

  void _animateBack() {
    _springStart = _dragOffset;
    if (_springStart == 0) return;
    _springBack.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onSwipeToReply == null) return widget.child;

    final progress = (_dragOffset.abs() / _threshold).clamp(0.0, 1.0);

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_dragOffset != 0)
            Positioned.fill(
              child: Align(
                alignment: widget.isMine
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                    right: widget.isMine ? 16 : 0,
                    left: widget.isMine ? 0 : 16,
                  ),
                  child: Opacity(
                    opacity: progress,
                    child: Transform.scale(
                      scale: 0.5 + progress * 0.5,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.emerald.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.reply,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
