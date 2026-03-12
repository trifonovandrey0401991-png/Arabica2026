import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../models/conversation_model.dart';
import '../services/messenger_service.dart';
import '../pages/messenger_shell_page.dart';


/// Telegram-style contact profile bottom sheet for private chats.
/// Shows: avatar, name, phone, shared media, common groups, actions.
class ContactProfileSheet extends StatefulWidget {
  final Conversation conversation;
  final String myPhone;
  final String myName;
  final Map<String, String> phoneBookNames;
  final bool isBlocked;
  final bool isMuted;
  final VoidCallback onCall;
  final VoidCallback onSearch;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleBlock;
  final VoidCallback onDeleteChat;
  final VoidCallback onOpenMediaGallery;

  const ContactProfileSheet({
    super.key,
    required this.conversation,
    required this.myPhone,
    required this.myName,
    required this.phoneBookNames,
    required this.isBlocked,
    this.isMuted = false,
    required this.onCall,
    required this.onSearch,
    required this.onToggleMute,
    required this.onToggleBlock,
    required this.onDeleteChat,
    required this.onOpenMediaGallery,
  });

  @override
  State<ContactProfileSheet> createState() => _ContactProfileSheetState();
}

class _ContactProfileSheetState extends State<ContactProfileSheet> {
  List<Map<String, dynamic>> _media = [];
  List<Map<String, dynamic>> _commonGroups = [];
  bool _loadingMedia = true;
  bool _loadingGroups = true;

  String get _otherPhone {
    final other = widget.conversation.participants
        .where((p) => p.phone != widget.myPhone)
        .toList();
    return other.isNotEmpty ? other.first.phone : '';
  }

  String? get _otherAvatarUrl {
    final other = widget.conversation.participants
        .where((p) => p.phone != widget.myPhone)
        .toList();
    return other.isNotEmpty ? other.first.avatarUrl : null;
  }

  String? get _otherServerName {
    final other = widget.conversation.participants
        .where((p) => p.phone != widget.myPhone)
        .toList();
    return other.isNotEmpty ? other.first.name : null;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    // Load media and common groups in parallel
    final futures = await Future.wait([
      MessengerService.getConversationMedia(widget.conversation.id, limit: 20)
          .catchError((_) => <Map<String, dynamic>>[]),
      MessengerService.getCommonGroups(_otherPhone)
          .catchError((_) => <Map<String, dynamic>>[]),
    ]);

    if (!mounted) return;
    setState(() {
      _media = futures[0];
      _commonGroups = futures[1];
      _loadingMedia = false;
      _loadingGroups = false;
    });
  }

  String _formatPhone(String phone) {
    if (phone.length == 11 && phone.startsWith('7')) {
      return '+${phone[0]} (${phone.substring(1, 4)}) ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}';
    }
    return '+$phone';
  }

  @override
  Widget build(BuildContext context) {
    final displayName = MessengerShellPage.resolveDisplayName(
      _otherPhone, _otherServerName, widget.phoneBookNames,
    );
    final profileName = _otherServerName ?? _otherPhone;
    final hasAvatar = _otherAvatarUrl != null && _otherAvatarUrl!.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Avatar + Name + Phone
              _buildHeader(displayName, profileName, hasAvatar),

              // Action buttons row
              _buildActionButtons(),

              _divider(),

              // Phone number section
              _buildInfoRow(Icons.phone, 'Телефон', _formatPhone(_otherPhone)),

              // Profile name (if different from display name)
              if (profileName != displayName && profileName != _otherPhone)
                _buildInfoRow(Icons.person, 'Имя в профиле', profileName),

              _divider(),

              // Shared media
              _buildMediaSection(),

              // Common groups
              _buildCommonGroupsSection(),

              _divider(),

              // Danger zone
              _buildDangerActions(),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(String displayName, String profileName, bool hasAvatar) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.emerald.withOpacity(0.15),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        children: [
          // Large avatar
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: !hasAvatar
                  ? const LinearGradient(
                      colors: [AppColors.emeraldLight, AppColors.emerald],
                    )
                  : null,
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasAvatar
                ? CachedNetworkImage(
                    imageUrl: _otherAvatarUrl!.startsWith('http')
                        ? _otherAvatarUrl!
                        : '${ApiConstants.serverUrl}${_otherAvatarUrl!}',
                    fit: BoxFit.cover,
                    width: 90,
                    height: 90,
                    placeholder: (_, __) => _avatarLetter(displayName),
                    errorWidget: (_, __, ___) => _avatarLetter(displayName),
                  )
                : _avatarLetter(displayName),
          ),
          const SizedBox(height: 14),
          // Display name
          Text(
            displayName,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.95),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          // Online status placeholder
          Text(
            'последний раз недавно',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarLetter(String name) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Center(
      child: Text(
        letter,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 36,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionButton(Icons.call, 'Позвонить', AppColors.turquoise, () {
            Navigator.pop(context);
            widget.onCall();
          }),
          _actionButton(Icons.search, 'Поиск', AppColors.turquoise, () {
            Navigator.pop(context);
            widget.onSearch();
          }),
          _actionButton(
            widget.isMuted ? Icons.notifications_active : Icons.notifications_off_outlined,
            widget.isMuted ? 'Со звуком' : 'Без звука',
            widget.isMuted ? AppColors.turquoise : AppColors.turquoise,
            () {
              Navigator.pop(context);
              widget.onToggleMute();
            },
          ),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback? onTap) {
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.4,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.15),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(isEnabled ? 0.8 : 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.turquoise.withOpacity(0.6), size: 22),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _media.isNotEmpty ? () {
            Navigator.pop(context);
            widget.onOpenMediaGallery();
          } : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'Медиа',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const Spacer(),
                if (_media.isNotEmpty)
                  Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 20),
              ],
            ),
          ),
        ),
        if (_loadingMedia)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5),
            ),
          )
        else if (_media.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Нет медиа файлов',
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.35)),
            ),
          )
        else
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              widget.onOpenMediaGallery();
            },
            child: SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _media.length,
                itemBuilder: (context, index) {
                  return _buildMediaThumbnail(_media[index]);
                },
              ),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildMediaThumbnail(Map<String, dynamic> item) {
    final type = item['type'] as String? ?? '';
    final mediaUrl = item['media_url'] as String? ?? '';
    final isImage = type == 'image';
    final isVideo = type == 'video' || type == 'video_note';
    final fullUrl = mediaUrl.startsWith('http')
        ? mediaUrl
        : '${ApiConstants.serverUrl}$mediaUrl';

    return Container(
      width: 80,
      height: 80,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.emerald.withOpacity(0.2),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: isImage
          ? CachedNetworkImage(
              imageUrl: fullUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => const Center(
                child: Icon(Icons.image, color: AppColors.turquoise, size: 28),
              ),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, color: AppColors.turquoise, size: 28),
              ),
            )
          : Center(
              child: Icon(
                isVideo ? Icons.videocam : Icons.insert_drive_file,
                color: AppColors.turquoise,
                size: 28,
              ),
            ),
    );
  }

  Widget _buildCommonGroupsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                'Общие группы',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              if (!_loadingGroups && _commonGroups.isNotEmpty)
                Text(
                  '  ${_commonGroups.length}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.35),
                  ),
                ),
            ],
          ),
        ),
        if (_loadingGroups)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5),
            ),
          )
        else if (_commonGroups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Нет общих групп',
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.35)),
            ),
          )
        else
          ...List.generate(_commonGroups.length, (index) {
            final group = _commonGroups[index];
            return _buildGroupRow(group);
          }),
      ],
    );
  }

  Widget _buildGroupRow(Map<String, dynamic> group) {
    final name = group['name'] as String? ?? 'Группа';
    final count = group['participants_count'] as int? ?? 0;
    final avatarUrl = group['avatar_url'] as String?;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'Г';

    return InkWell(
      onTap: () {}, // Could navigate to group
      splashColor: Colors.white.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: !hasAvatar
                    ? const LinearGradient(
                        colors: [AppColors.turquoise, AppColors.emerald],
                      )
                    : null,
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasAvatar
                  ? CachedNetworkImage(
                      imageUrl: avatarUrl.startsWith('http')
                          ? avatarUrl
                          : '${ApiConstants.serverUrl}$avatarUrl',
                      fit: BoxFit.cover,
                      width: 44,
                      height: 44,
                      placeholder: (_, __) => Center(
                        child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      errorWidget: (_, __, ___) => Center(
                        child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    )
                  : Center(
                      child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$count участников',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDangerActions() {
    return Column(
      children: [
        // Block/Unblock
        InkWell(
          onTap: () {
            widget.onToggleBlock();
            Navigator.pop(context);
          },
          splashColor: Colors.white.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  widget.isBlocked ? Icons.lock_open : Icons.block,
                  color: widget.isBlocked ? Colors.orange : AppColors.error,
                  size: 22,
                ),
                const SizedBox(width: 16),
                Text(
                  widget.isBlocked ? 'Разблокировать' : 'Заблокировать',
                  style: TextStyle(
                    fontSize: 15,
                    color: widget.isBlocked ? Colors.orange : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Delete chat
        InkWell(
          onTap: () => _confirmDeleteChat(),
          splashColor: Colors.white.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.delete_outline, color: AppColors.error, size: 22),
                const SizedBox(width: 16),
                Text(
                  'Удалить чат',
                  style: TextStyle(fontSize: 15, color: AppColors.error),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _confirmDeleteChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Удалить чат?',
          style: TextStyle(color: Colors.white.withOpacity(0.95)),
        ),
        content: Text(
          'Вся переписка будет удалена без возможности восстановления.',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // close dialog
              Navigator.pop(context); // close bottom sheet
              widget.onDeleteChat();
            },
            child: const Text('Удалить', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      color: Colors.white.withOpacity(0.08),
    );
  }
}

/// Shows the contact profile bottom sheet for a private chat.
void showContactProfileSheet({
  required BuildContext context,
  required Conversation conversation,
  required String myPhone,
  required String myName,
  required Map<String, String> phoneBookNames,
  required bool isBlocked,
  bool isMuted = false,
  required VoidCallback onCall,
  required VoidCallback onSearch,
  required VoidCallback onToggleMute,
  required VoidCallback onToggleBlock,
  required VoidCallback onDeleteChat,
  required VoidCallback onOpenMediaGallery,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ContactProfileSheet(
      conversation: conversation,
      myPhone: myPhone,
      myName: myName,
      phoneBookNames: phoneBookNames,
      isBlocked: isBlocked,
      isMuted: isMuted,
      onCall: onCall,
      onSearch: onSearch,
      onToggleMute: onToggleMute,
      onToggleBlock: onToggleBlock,
      onDeleteChat: onDeleteChat,
      onOpenMediaGallery: onOpenMediaGallery,
    ),
  );
}
