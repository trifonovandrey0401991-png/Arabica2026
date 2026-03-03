import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../models/conversation_model.dart';
import '../pages/messenger_shell_page.dart';

class ChatListTile extends StatelessWidget {
  final Conversation conversation;
  final String myPhone;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isClient;
  final Map<String, String> phoneBookNames;

  const ChatListTile({
    super.key,
    required this.conversation,
    required this.myPhone,
    required this.onTap,
    this.onLongPress,
    this.isClient = false,
    this.phoneBookNames = const {},
  });

  Widget _buildAvatar(String displayName, bool isGroup) {
    final letter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    // For groups: use group avatar. For private: use other participant's profile avatar.
    String? avatarUrl;
    if (isGroup) {
      avatarUrl = conversation.avatarUrl;
    } else {
      final other = conversation.participants.where((p) => p.phone != myPhone).toList();
      if (other.isNotEmpty) avatarUrl = other.first.avatarUrl;
    }
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: !hasAvatar
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isGroup
                    ? [AppColors.turquoise, AppColors.emerald]
                    : [AppColors.emeraldLight, AppColors.emerald],
              )
            : null,
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasAvatar
          ? CachedNetworkImage(
              imageUrl: avatarUrl!.startsWith('http')
                  ? avatarUrl
                  : '${ApiConstants.serverUrl}$avatarUrl',
              fit: BoxFit.cover,
              width: 50,
              height: 50,
              placeholder: (_, __) => Center(
                child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              errorWidget: (_, __, ___) => Center(
                child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            )
          : Center(
              child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
    );
  }

  Widget _buildChannelAvatar() {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.turquoise, AppColors.emerald],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
      ),
      child: const Center(
        child: Icon(Icons.campaign, color: Colors.white, size: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Privacy: for clients, replace unknown contact names with "Сотрудник"
    final rawName = conversation.displayName(myPhone);
    final otherPhone = conversation.otherPhone(myPhone);
    final displayName = (otherPhone != null)
        ? MessengerShellPage.resolveDisplayName(otherPhone, rawName, isClient, phoneBookNames)
        : rawName;
    final lastMsg = conversation.lastMessage;
    final unread = conversation.unreadCount;
    final isGroup = conversation.type == ConversationType.group;
    final isChannel = conversation.type == ConversationType.channel;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: Colors.white.withOpacity(0.05),
        highlightColor: Colors.white.withOpacity(0.03),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
            ),
          ),
          child: Row(
            children: [
              // Avatar
              isChannel ? _buildChannelAvatar() : _buildAvatar(displayName, isGroup),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + time
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w500,
                              fontSize: 15,
                              color: Colors.white.withOpacity(unread > 0 ? 0.95 : 0.8),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (lastMsg != null)
                          Text(
                            lastMsg.formattedTime,
                            style: TextStyle(
                              fontSize: 12,
                              color: unread > 0 ? AppColors.turquoise : Colors.white.withOpacity(0.35),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Last message + unread badge
                    Row(
                      children: [
                        if (isGroup && lastMsg != null && !lastMsg.isDeleted)
                          Text(
                            '${MessengerShellPage.resolveDisplayName(lastMsg.senderPhone, lastMsg.senderName, isClient, phoneBookNames)}: ',
                            style: TextStyle(fontSize: 13, color: AppColors.turquoise.withOpacity(0.7)),
                            maxLines: 1,
                          ),
                        Expanded(
                          child: Text(
                            lastMsg?.preview ?? 'Нет сообщений',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(unread > 0 ? 0.6 : 0.35),
                              fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unread > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.turquoise,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : unread.toString(),
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
