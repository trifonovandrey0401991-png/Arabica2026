import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/api_constants.dart';
import '../models/contact_model.dart';
import '../models/conversation_model.dart';
import '../models/participant_model.dart';
import '../services/messenger_service.dart';
import 'contact_search_page.dart';

class GroupInfoPage extends StatefulWidget {
  final Conversation conversation;
  final String userPhone;
  final String userName;

  const GroupInfoPage({
    super.key,
    required this.conversation,
    required this.userPhone,
    required this.userName,
  });

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  late Conversation _conversation;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _conversation = widget.conversation;
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final conv = await MessengerService.getConversation(widget.conversation.id);
      if (conv != null && mounted) {
        setState(() {
          _conversation = conv;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isCreator => _conversation.creatorPhone == widget.userPhone;
  bool get _isChannel => _conversation.type == ConversationType.channel;

  Future<void> _changeAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF0A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.camera_alt, color: AppColors.turquoise.withOpacity(0.8)),
                title: Text('Камера', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: AppColors.turquoise.withOpacity(0.8)),
                title: Text('Галерея', style: TextStyle(color: Colors.white.withOpacity(0.9))),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 75,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked == null) return;

      final url = await MessengerService.uploadMedia(File(picked.path));
      if (url != null) {
        await MessengerService.updateGroup(
          _conversation.id,
          phone: widget.userPhone,
          avatarUrl: url,
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки фото: $e')),
        );
      }
    }
  }

  Future<void> _removeMember(Participant participant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Удалить участника?',
          style: TextStyle(color: Colors.white.withOpacity(0.9)),
        ),
        content: Text(
          'Удалить ${participant.name ?? participant.phone} из группы?',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
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

    if (confirmed == true) {
      await MessengerService.removeParticipant(
        _conversation.id,
        participant.phone,
        requesterPhone: widget.userPhone,
      );
      _refresh();
    }
  }

  Future<void> _toggleWriterRole(Participant participant) async {
    final newRole = participant.role == 'writer' ? 'member' : 'writer';
    final success = await MessengerService.setChannelRole(
      _conversation.id,
      phone: participant.phone,
      role: newRole,
    );
    if (success) {
      _refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось изменить роль')),
      );
    }
  }

  Future<void> _editGroupName() async {
    final controller = TextEditingController(text: _conversation.name ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Название группы',
          style: TextStyle(color: Colors.white.withOpacity(0.9)),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Введите название',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.turquoise),
            ),
            counterStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Сохранить', style: TextStyle(color: AppColors.turquoise)),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newName == null || newName.isEmpty || newName == _conversation.name || !mounted) return;

    final success = await MessengerService.updateGroup(
      _conversation.id,
      phone: widget.userPhone,
      name: newName,
    );

    if (success) {
      _refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось переименовать группу')),
      );
    }
  }

  Future<void> _addMembers() async {
    final existingPhones = _conversation.participants.map((p) => p.phone).toSet();

    final result = await Navigator.push<List<MessengerContact>>(
      context,
      MaterialPageRoute(
        builder: (_) => ContactSearchPage(
          userPhone: widget.userPhone,
          userName: widget.userName,
          selectMode: true,
          excludePhones: existingPhones,
        ),
      ),
    );

    if (result == null || result.isEmpty || !mounted) return;

    final phones = result.map((c) => {'phone': c.phone, 'name': c.name ?? c.phone}).toList();
    final success = await MessengerService.addParticipants(
      _conversation.id,
      requesterPhone: widget.userPhone,
      phones: phones,
    );

    if (success) {
      _refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось добавить участников')),
      );
    }
  }

  Future<void> _leaveGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Покинуть группу?',
          style: TextStyle(color: Colors.white.withOpacity(0.9)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Покинуть', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await MessengerService.leaveGroup(_conversation.id, widget.userPhone);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Удалить группу?',
          style: TextStyle(color: Colors.white.withOpacity(0.9)),
        ),
        content: Text(
          'Все сообщения будут удалены безвозвратно.',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
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

    if (confirmed == true) {
      await MessengerService.deleteConversation(_conversation.id, widget.userPhone);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          _isChannel ? 'Информация о канале' : 'Информация о группе',
          style: TextStyle(color: Colors.white.withOpacity(0.95)),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.emerald.withOpacity(0.3),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.turquoise, strokeWidth: 2.5))
          : ListView(
              children: [
                // Group header
                Container(
                  padding: const EdgeInsets.all(24),
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
                      GestureDetector(
                        onTap: _changeAvatar,
                        child: Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: _conversation.avatarUrl == null
                                    ? const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [AppColors.turquoise, AppColors.emerald],
                                      )
                                    : null,
                                border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _conversation.avatarUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: _conversation.avatarUrl!.startsWith('http')
                                          ? _conversation.avatarUrl!
                                          : '${ApiConstants.serverUrl}${_conversation.avatarUrl}',
                                      fit: BoxFit.cover,
                                      width: 80,
                                      height: 80,
                                      placeholder: (_, __) => Center(
                                        child: Text(
                                          (_conversation.name ?? 'Г')[0].toUpperCase(),
                                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      errorWidget: (_, __, ___) => Center(
                                        child: Text(
                                          (_conversation.name ?? 'Г')[0].toUpperCase(),
                                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Text(
                                        (_conversation.name ?? 'Г')[0].toUpperCase(),
                                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.turquoise,
                                  border: Border.all(color: AppColors.night, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _isCreator ? _editGroupName : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _conversation.name ?? (_isChannel ? 'Канал' : 'Группа'),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white.withOpacity(0.95),
                              ),
                            ),
                            if (_isCreator) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.edit, size: 18, color: Colors.white.withOpacity(0.4)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_conversation.participants.length} ${_isChannel ? 'подписчиков' : 'участников'}',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                      if (_conversation.creatorName != null)
                        Text(
                          'Создатель: ${_conversation.creatorName}',
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.35)),
                        ),
                    ],
                  ),
                ),

                // Participants header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    _isChannel ? 'Подписчики' : 'Участники',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ),

                // Add member button (only for creator)
                if (_isCreator)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      splashColor: Colors.white.withOpacity(0.05),
                      highlightColor: Colors.white.withOpacity(0.03),
                      onTap: _addMembers,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.turquoise.withOpacity(0.15),
                                border: Border.all(color: AppColors.turquoise.withOpacity(0.3)),
                              ),
                              child: const Icon(Icons.person_add, color: AppColors.turquoise, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Добавить участника',
                              style: TextStyle(
                                color: AppColors.turquoise,
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                ..._conversation.participants.map((p) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: p.isAdmin
                                ? [AppColors.gold, AppColors.darkGold]
                                : [AppColors.emeraldLight, AppColors.emerald],
                          ),
                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Center(
                          child: Text(
                            (p.name ?? p.phone)[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    p.name ?? p.phone,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (p.isAdmin)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.gold.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      'Создатель',
                                      style: TextStyle(fontSize: 10, color: AppColors.gold.withOpacity(0.9)),
                                    ),
                                  ),
                                if (_isChannel && p.role == 'writer')
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.turquoise.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.turquoise.withOpacity(0.3)),
                                    ),
                                    child: Text(
                                      'Писатель',
                                      style: TextStyle(fontSize: 10, color: AppColors.turquoise.withOpacity(0.9)),
                                    ),
                                  ),
                                if (p.phone == widget.userPhone)
                                  Text(
                                    ' (вы)',
                                    style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12),
                                  ),
                              ],
                            ),
                            Text(
                              p.phone,
                              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.35)),
                            ),
                          ],
                        ),
                      ),
                      if (_isCreator && !p.isAdmin && p.phone != widget.userPhone && _isChannel)
                        IconButton(
                          icon: Icon(
                            p.role == 'writer' ? Icons.edit_off : Icons.edit,
                            color: p.role == 'writer'
                                ? AppColors.turquoise.withOpacity(0.7)
                                : Colors.white.withOpacity(0.4),
                          ),
                          tooltip: p.role == 'writer' ? 'Убрать право писать' : 'Разрешить писать',
                          onPressed: () => _toggleWriterRole(p),
                        ),
                      if (_isCreator && p.phone != widget.userPhone)
                        IconButton(
                          icon: Icon(Icons.remove_circle_outline, color: AppColors.error.withOpacity(0.7)),
                          onPressed: () => _removeMember(p),
                        ),
                    ],
                  ),
                )),

                Divider(color: Colors.white.withOpacity(0.08), height: 32),

                // Actions
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    splashColor: Colors.white.withOpacity(0.05),
                    onTap: _leaveGroup,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.exit_to_app, color: Colors.orange.withOpacity(0.8)),
                          const SizedBox(width: 16),
                          Text(
                            _isChannel ? 'Отписаться от канала' : 'Покинуть группу',
                            style: TextStyle(color: Colors.orange.withOpacity(0.9), fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_isCreator)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      splashColor: Colors.white.withOpacity(0.05),
                      onTap: _deleteGroup,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.delete_forever, color: AppColors.error.withOpacity(0.8)),
                            const SizedBox(width: 16),
                            Text(
                              _isChannel ? 'Удалить канал' : 'Удалить группу',
                              style: TextStyle(color: AppColors.error.withOpacity(0.9), fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
