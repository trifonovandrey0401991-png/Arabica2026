import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../services/messenger_service.dart';
import 'messenger_chat_page.dart';

/// Catalog of available channels.
class ChannelListPage extends StatefulWidget {
  final String userPhone;
  final String userName;
  final bool isClient;
  final Map<String, String> phoneBookNames;

  const ChannelListPage({
    super.key,
    required this.userPhone,
    required this.userName,
    this.isClient = false,
    this.phoneBookNames = const {},
  });

  @override
  State<ChannelListPage> createState() => _ChannelListPageState();
}

class _ChannelListPageState extends State<ChannelListPage> {
  List<Map<String, dynamic>> _channels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  String? _error;

  Future<void> _loadChannels() async {
    try {
      final channels = await MessengerService.getChannels();
      if (mounted) {
        setState(() {
          _channels = channels;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Не удалось загрузить каналы';
        });
      }
    }
  }

  Future<void> _subscribe(Map<String, dynamic> channel) async {
    final channelId = channel['id'] as String;
    final success = await MessengerService.subscribeToChannel(channelId);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подписка оформлена'), backgroundColor: AppColors.emerald),
      );
      // Open channel chat
      final conv = await MessengerService.getConversation(channelId);
      if (conv != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MessengerChatPage(
              conversation: conv,
              userPhone: widget.userPhone,
              userName: widget.userName,
              isClient: widget.isClient,
              phoneBookNames: widget.phoneBookNames,
            ),
          ),
        );
      }
    }
  }

  Future<void> _createChannel() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    File? avatarFile;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Новый канал', style: TextStyle(color: Colors.white.withOpacity(0.9))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar picker
              GestureDetector(
                onTap: () async {
                  final picked = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 75,
                    maxWidth: 800,
                    maxHeight: 800,
                  );
                  if (picked != null) {
                    setDialogState(() => avatarFile = File(picked.path));
                  }
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                    image: avatarFile != null
                        ? DecorationImage(image: FileImage(avatarFile!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: avatarFile == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, color: AppColors.turquoise.withOpacity(0.7), size: 24),
                            const SizedBox(height: 4),
                            Text('Фото', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11)),
                          ],
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Название канала',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.turquoise),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Описание (необязательно)',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.turquoise),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Создать', style: TextStyle(color: AppColors.turquoise)),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      // Upload avatar if picked
      String? avatarUrl;
      if (avatarFile != null) {
        avatarUrl = await MessengerService.uploadMedia(avatarFile!);
      }

      final conv = await MessengerService.createChannel(
        name: nameController.text.trim(),
        description: descController.text.trim().isNotEmpty ? descController.text.trim() : null,
        avatarUrl: avatarUrl,
      );
      if (conv != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Канал создан'), backgroundColor: AppColors.emerald),
        );
        _loadChannels();
      } else if (conv == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось создать канал (нет прав)'), backgroundColor: AppColors.error),
        );
      }
    }

    nameController.dispose();
    descController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      appBar: AppBar(
        backgroundColor: AppColors.night,
        title: const Text('Каналы', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.turquoise),
            tooltip: 'Создать канал',
            onPressed: _createChannel,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.turquoise))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.white.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: Colors.white.withOpacity(0.5))),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          setState(() { _isLoading = true; _error = null; });
                          _loadChannels();
                        },
                        child: const Text('Повторить', style: TextStyle(color: AppColors.turquoise)),
                      ),
                    ],
                  ),
                )
          : _channels.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.campaign_outlined, size: 64, color: Colors.white.withOpacity(0.15)),
                      const SizedBox(height: 16),
                      Text('Нет каналов', style: TextStyle(fontSize: 18, color: Colors.white.withOpacity(0.5))),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _channels.length,
                  itemBuilder: (context, index) {
                    final ch = _channels[index];
                    final name = ch['name'] as String? ?? 'Канал';
                    final desc = ch['description'] as String?;
                    final subs = (ch['subscriber_count'] as num?)?.toInt() ?? 0;

                    return ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppColors.turquoise, AppColors.emerald],
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.campaign, color: Colors.white, size: 24),
                        ),
                      ),
                      title: Text(name, style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        desc ?? '$subs подписчиков',
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: () => _subscribe(ch),
                        child: const Text('Подписаться', style: TextStyle(color: AppColors.turquoise, fontSize: 12)),
                      ),
                    );
                  },
                ),
    );
  }
}
