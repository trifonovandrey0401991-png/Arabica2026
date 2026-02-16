import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/employee_chat_message_model.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Доступные реакции
List<String> availableReactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

/// Виджет пузыря сообщения — dark emerald стиль
class ChatMessageBubble extends StatelessWidget {
  final EmployeeChatMessage message;
  final bool isMe;
  final bool showSenderName;
  final String? userPhone;
  final Function(String reaction)? onReactionTap;
  final VoidCallback? onForwardTap;
  final VoidCallback? onLongPress;

  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);

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
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isMe) Spacer(flex: 1),
          Flexible(
            flex: 4,
            child: GestureDetector(
              onLongPress: () => _showMessageMenu(context),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      gradient: isMe
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_emerald, _emeraldDark],
                            )
                          : null,
                      color: isMe ? null : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(18.r),
                        topRight: Radius.circular(18.r),
                        bottomLeft: isMe ? Radius.circular(18.r) : Radius.circular(4.r),
                        bottomRight: isMe ? Radius.circular(4.r) : Radius.circular(18.r),
                      ),
                      border: Border.all(
                        color: isMe
                            ? Colors.white.withOpacity(0.1)
                            : Colors.white.withOpacity(0.12),
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
                            padding: EdgeInsets.only(bottom: 6.h),
                            child: Text(
                              message.senderName,
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                                color: isMe
                                    ? Colors.white.withOpacity(0.7)
                                    : Color(0xFF4DB6AC),
                              ),
                            ),
                          ),
                        // Изображение
                        if (message.imageUrl != null && message.imageUrl!.isNotEmpty)
                          GestureDetector(
                            onTap: () => _showFullImage(context),
                            child: Container(
                              margin: EdgeInsets.only(bottom: 6.h),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12.r),
                                child: AppCachedImage(
                                  imageUrl: message.imageUrl!,
                                  width: 220,
                                  height: 220,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, error, stackTrace) {
                                    return Container(
                                      width: 220,
                                      height: 220,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(12.r),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.broken_image_rounded,
                                            size: 48,
                                            color: Colors.white.withOpacity(0.3),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Не удалось загрузить',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.4),
                                              fontSize: 12.sp,
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
                              color: Colors.white.withOpacity(isMe ? 0.95 : 0.85),
                              fontSize: 15.sp,
                              height: 1.4,
                            ),
                          ),
                        SizedBox(height: 6),
                        // Время и статус
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.formattedTime,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: Colors.white.withOpacity(isMe ? 0.5 : 0.35),
                              ),
                            ),
                            if (isMe) ...[
                              SizedBox(width: 4),
                              Icon(
                                message.readBy.length > 1 ? Icons.done_all_rounded : Icons.done_rounded,
                                size: 15,
                                color: message.readBy.length > 1
                                    ? Colors.lightBlueAccent
                                    : Colors.white.withOpacity(0.5),
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
          if (!isMe) Spacer(flex: 1),
        ],
      ),
    );
  }

  /// Заголовок пересланного сообщения
  Widget _buildForwardedHeader() {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6.r),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white.withOpacity(0.5) : Color(0xFF4DB6AC),
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
            color: isMe ? Colors.white.withOpacity(0.7) : Color(0xFF4DB6AC),
          ),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Переслано от ${message.forwardedFrom!.originalSenderName}',
              style: TextStyle(
                fontSize: 11.sp,
                fontStyle: FontStyle.italic,
                color: Colors.white.withOpacity(isMe ? 0.7 : 0.5),
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
      padding: EdgeInsets.only(top: 6.h),
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
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: hasMyReaction
                    ? _emerald.withOpacity(0.4)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14.r),
                border: hasMyReaction
                    ? Border.all(color: _emerald.withOpacity(0.7), width: 1.5)
                    : Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reaction, style: TextStyle(fontSize: 14.sp)),
                  if (count > 1) ...[
                    SizedBox(width: 4),
                    Text(
                      count.toString(),
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: hasMyReaction
                            ? Colors.white.withOpacity(0.9)
                            : Colors.white.withOpacity(0.5),
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
        decoration: BoxDecoration(
          color: _night.withOpacity(0.98),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Линия-индикатор
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.symmetric(vertical: 12.h),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              // Реакции
              if (onReactionTap != null) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
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
                          duration: Duration(milliseconds: 200),
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            color: hasMyReaction
                                ? _emerald.withOpacity(0.4)
                                : Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12.r),
                            border: hasMyReaction
                                ? Border.all(color: _emerald.withOpacity(0.7))
                                : Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Text(
                            reaction,
                            style: TextStyle(fontSize: 28.sp),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Divider(height: 1, color: Colors.white.withOpacity(0.08)),
              ],
              // Переслать
              if (onForwardTap != null)
                ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: _emerald.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(Icons.forward_rounded, color: Colors.white.withOpacity(0.8)),
                  ),
                  title: Text(
                    'Переслать',
                    style: TextStyle(color: Colors.white.withOpacity(0.9)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onForwardTap!();
                  },
                ),
              // Копировать текст
              if (message.text.isNotEmpty)
                ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(Icons.copy_rounded, color: Colors.blue[300]),
                  ),
                  title: Text(
                    'Копировать',
                    style: TextStyle(color: Colors.white.withOpacity(0.9)),
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Текст скопирован'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                        backgroundColor: _emerald,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              SizedBox(height: 12),
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
                        child: AppCachedImage(
                          imageUrl: message.imageUrl!,
                          fit: BoxFit.contain,
                          errorWidget: (context, error, stackTrace) {
                            return Center(
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
                  right: 10.w,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(24.r),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.close_rounded, color: Colors.white, size: 28),
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
