import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../models/message_model.dart';
import '../services/messenger_service.dart';

/// Context menu shown on long-press of a message bubble.
/// Popup style with quick reactions row + action items (Telegram-like).
class MessageContextMenu {
  MessageContextMenu._();

  static const _reactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

  /// Show the popup context menu near the message.
  static void show(
    BuildContext context, {
    required MessengerMessage message,
    required String userPhone,
    required String conversationId,
    required VoidCallback onReply,
    required List<Map<String, dynamic>> readers,
    required VoidCallback Function(MessengerMessage) onDeleteConfirmed,
    void Function(MessengerMessage)? onDeleteForMe,
    void Function(MessengerMessage)? onEdit,
    void Function(MessengerMessage)? onForward,
    void Function(MessengerMessage)? onPin,
    void Function(MessengerMessage)? onSaveToFavorites,
    void Function(MessengerMessage)? onSaveStickerToFavorites,
    void Function(MessengerMessage)? onSaveGifToFavorites,
  }) {
    HapticFeedback.mediumImpact();

    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: _ContextMenuOverlay(
            message: message,
            userPhone: userPhone,
            conversationId: conversationId,
            onReply: onReply,
            readers: readers,
            onDeleteConfirmed: onDeleteConfirmed,
            onDeleteForMe: onDeleteForMe,
            onEdit: onEdit,
            onForward: onForward,
            onPin: onPin,
            onSaveToFavorites: onSaveToFavorites,
            onSaveStickerToFavorites: onSaveStickerToFavorites,
            onSaveGifToFavorites: onSaveGifToFavorites,
          ),
        ),
      ),
    );
  }

  /// Share message to external apps (WhatsApp, Telegram, etc.)
  static Future<void> shareMessage(BuildContext context, MessengerMessage message) async {
    try {
      if (message.type == MessageType.text || message.type == MessageType.emoji) {
        await SharePlus.instance.share(ShareParams(text: message.content ?? ''));
        return;
      }
      if (message.mediaUrl != null) {
        final url = message.mediaUrl!.startsWith('http')
            ? message.mediaUrl!
            : '${ApiConstants.serverUrl}${message.mediaUrl!}';
        String ext = '.dat';
        if (message.type == MessageType.image) {
          ext = '.jpg';
        } else if (message.type == MessageType.video || message.type == MessageType.videoNote) {
          ext = '.mp4';
        } else if (message.type == MessageType.voice) {
          ext = '.m4a';
        } else if (message.type == MessageType.file) {
          ext = _extFromName(message.fileName);
        }
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/share_${DateTime.now().millisecondsSinceEpoch}$ext');
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes);
          await SharePlus.instance.share(ShareParams(
            text: message.content,
            files: [XFile(file.path)],
          ));
        }
      }
    } catch (e) {
      debugPrint('Share failed: $e');
    }
  }

  static String _extFromName(String? fileName) {
    if (fileName == null || !fileName.contains('.')) return '.dat';
    return '.${fileName.split('.').last}';
  }

  /// Readers list bottom sheet.
  static void showReadersDialog(
    BuildContext context, {
    required List<Map<String, dynamic>> readers,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.emeraldDark,
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

  /// Delete confirmation dialog.
  static Future<bool> confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
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
    return confirmed == true;
  }
}

// =====================================================================
// Overlay widget (full-screen with blurred background + popup card)
// =====================================================================

class _ContextMenuOverlay extends StatelessWidget {
  final MessengerMessage message;
  final String userPhone;
  final String conversationId;
  final VoidCallback onReply;
  final List<Map<String, dynamic>> readers;
  final VoidCallback Function(MessengerMessage) onDeleteConfirmed;
  final void Function(MessengerMessage)? onDeleteForMe;
  final void Function(MessengerMessage)? onEdit;
  final void Function(MessengerMessage)? onForward;
  final void Function(MessengerMessage)? onPin;
  final void Function(MessengerMessage)? onSaveToFavorites;
  final void Function(MessengerMessage)? onSaveStickerToFavorites;
  final void Function(MessengerMessage)? onSaveGifToFavorites;

  const _ContextMenuOverlay({
    required this.message,
    required this.userPhone,
    required this.conversationId,
    required this.onReply,
    required this.readers,
    required this.onDeleteConfirmed,
    this.onDeleteForMe,
    this.onEdit,
    this.onForward,
    this.onPin,
    this.onSaveToFavorites,
    this.onSaveStickerToFavorites,
    this.onSaveGifToFavorites,
  });

  @override
  Widget build(BuildContext context) {
    final isMine = message.senderPhone == userPhone;
    final canEdit = isMine &&
        message.type == MessageType.text &&
        !message.isDeleted &&
        DateTime.now().difference(message.createdAt).inMinutes < 5;
    final canDeleteForAll = isMine &&
        !message.isDeleted &&
        DateTime.now().difference(message.createdAt).inMinutes < 60;

    // Build menu items
    final items = <_MenuItem>[];

    items.add(_MenuItem(Icons.reply_rounded, 'Ответить', () {
      Navigator.pop(context);
      onReply();
    }));

    if (canEdit && onEdit != null) {
      items.add(_MenuItem(Icons.edit_outlined, 'Редактировать', () {
        Navigator.pop(context);
        onEdit!(message);
      }));
    }

    if (!message.isDeleted && onForward != null) {
      items.add(_MenuItem(Icons.shortcut_rounded, 'Переслать', () {
        Navigator.pop(context);
        onForward!(message);
      }));
    }

    if (!message.isDeleted && onSaveToFavorites != null) {
      items.add(_MenuItem(Icons.bookmark_outline_rounded, 'В Избранное', () {
        Navigator.pop(context);
        onSaveToFavorites!(message);
      }));
    }

    if (!message.isDeleted && message.type == MessageType.sticker && message.mediaUrl != null && onSaveStickerToFavorites != null) {
      items.add(_MenuItem(Icons.star_outline_rounded, 'Сохранить стикер', () {
        Navigator.pop(context);
        onSaveStickerToFavorites!(message);
      }, iconColor: AppColors.gold));
    }

    if (!message.isDeleted && message.type == MessageType.gif && message.mediaUrl != null && onSaveGifToFavorites != null) {
      items.add(_MenuItem(Icons.star_outline_rounded, 'Сохранить GIF', () {
        Navigator.pop(context);
        onSaveGifToFavorites!(message);
      }, iconColor: AppColors.gold));
    }

    if (!message.isDeleted) {
      items.add(_MenuItem(Icons.share_outlined, 'Поделиться', () {
        Navigator.pop(context);
        MessageContextMenu.shareMessage(context, message);
      }));
    }

    if (!message.isDeleted && onPin != null) {
      items.add(_MenuItem(
        message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
        message.isPinned ? 'Открепить' : 'Закрепить',
        () {
          Navigator.pop(context);
          onPin!(message);
        },
      ));
    }

    if (isMine && readers.isNotEmpty) {
      items.add(_MenuItem(Icons.done_all_rounded, 'Кто прочитал', () {
        Navigator.pop(context);
        MessageContextMenu.showReadersDialog(context, readers: readers);
      }, iconColor: AppColors.turquoise));
    }

    if (!message.isDeleted && onDeleteForMe != null) {
      items.add(_MenuItem(Icons.delete_outline_rounded, 'Удалить у меня', () {
        Navigator.pop(context);
        onDeleteForMe!(message);
      }, iconColor: AppColors.errorLight));
    }

    if (canDeleteForAll) {
      items.add(_MenuItem(Icons.delete_forever_rounded, 'Удалить у всех', () async {
        final ok = await MessageContextMenu.confirmDelete(context);
        if (!context.mounted) return;
        Navigator.pop(context);
        if (ok) onDeleteConfirmed(message)();
      }, iconColor: AppColors.error, textColor: AppColors.error));
    }

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Blurred dark background with emerald tint
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.2,
                      colors: [
                        AppColors.emeraldDark.withOpacity(0.7),
                        AppColors.night.withOpacity(0.85),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Popup menu centered on screen
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: GestureDetector(
                  onTap: () {}, // prevent closing when tapping on menu
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 310),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF112E2E),
                            Color(0xFF0A2222),
                            Color(0xFF081C1C),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: AppColors.turquoise.withOpacity(0.12),
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.turquoise.withOpacity(0.06),
                            blurRadius: 40,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Quick reactions row
                            _buildReactionsRow(context),
                            // Gold accent divider
                            Container(
                              height: 0.5,
                              margin: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    AppColors.gold.withOpacity(0.3),
                                    AppColors.turquoise.withOpacity(0.2),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            // Action items — compact, no scroll
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: items.asMap().entries.map((entry) =>
                                  _buildMenuItem(entry.value, isLast: entry.key == items.length - 1),
                                ).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionsRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: MessageContextMenu._reactions.map((emoji) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                MessengerService.addReaction(
                  conversationId,
                  message.id,
                  phone: userPhone,
                  reaction: emoji,
                );
              },
              borderRadius: BorderRadius.circular(14),
              splashColor: AppColors.turquoise.withOpacity(0.15),
              highlightColor: AppColors.turquoise.withOpacity(0.08),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.emerald.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.turquoise.withOpacity(0.08),
                    width: 0.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMenuItem(_MenuItem item, {bool isLast = false}) {
    final defaultIconColor = AppColors.turquoise.withOpacity(0.7);
    final defaultTextColor = Colors.white.withOpacity(0.92);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            item.onTap();
          },
          borderRadius: BorderRadius.circular(8),
          splashColor: AppColors.turquoise.withOpacity(0.08),
          highlightColor: AppColors.emerald.withOpacity(0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: (item.iconColor ?? defaultIconColor).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    item.icon,
                    size: 15,
                    color: item.iconColor ?? defaultIconColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: item.textColor ?? defaultTextColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: Colors.white.withOpacity(0.12),
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Container(
            height: 0.5,
            margin: const EdgeInsets.only(left: 50, right: 14),
            color: Colors.white.withOpacity(0.04),
          ),
      ],
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  _MenuItem(this.icon, this.label, this.onTap, {this.iconColor, this.textColor});
}
