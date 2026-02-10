import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../models/management_message_model.dart';
import '../services/management_message_service.dart';
import '../../../core/services/media_upload_service.dart';
import '../../../shared/widgets/media_message_widget.dart';
import '../../../shared/widgets/app_cached_image.dart';

/// Страница диалога "Связь с Руководством"
class ManagementDialogPage extends StatefulWidget {
  const ManagementDialogPage({super.key});

  @override
  State<ManagementDialogPage> createState() => _ManagementDialogPageState();
}

class _ManagementDialogPageState extends State<ManagementDialogPage> {
  List<ManagementMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploading = false;
  String? _userPhone;
  String? _userName;
  String? _pendingMediaUrl;
  bool _pendingIsVideo = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  static const _emerald = Color(0xFF1A4D4D);
  static const _emeraldDark = Color(0xFF0D2E2E);
  static const _night = Color(0xFF051515);
  static const _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      _userPhone = prefs.getString('user_phone') ?? prefs.getString('userPhone') ?? '';
      _userName = prefs.getString('user_name') ?? prefs.getString('userName');

      if (_userPhone!.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final data = await ManagementMessageService.getManagementMessages(_userPhone!);

      // Отмечаем сообщения как прочитанные клиентом
      if (data.hasUnread) {
        ManagementMessageService.markAsReadByClient(_userPhone!);
      }

      setState(() {
        _messages = data.messages;
        _isLoading = false;
      });

      // Прокручиваем к последнему сообщению
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _messages.isNotEmpty) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showMediaPicker() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: _emeraldDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera, color: _gold),
              title: Text('Сделать фото', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'image'}),
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: _gold),
              title: Text('Выбрать фото из галереи', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'image'}),
            ),
            ListTile(
              leading: Icon(Icons.videocam, color: _gold),
              title: Text('Записать видео', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'video'}),
            ),
            ListTile(
              leading: Icon(Icons.video_library, color: _gold),
              title: Text('Выбрать видео из галереи', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'video'}),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == null) return;

    XFile? file;
    bool isVideo = result['type'] == 'video';

    if (isVideo) {
      file = await _picker.pickVideo(
        source: result['source'] as ImageSource,
        maxDuration: const Duration(minutes: 2),
      );
    } else {
      file = await _picker.pickImage(
        source: result['source'] as ImageSource,
        imageQuality: 80,
        maxWidth: 1920,
        maxHeight: 1920,
      );
    }

    if (file == null) return;

    setState(() => _isUploading = true);

    final mediaUrl = await MediaUploadService.uploadMedia(
      file.path,
      type: isVideo ? MediaType.video : MediaType.image,
    );

    setState(() => _isUploading = false);

    if (mediaUrl != null) {
      setState(() {
        _pendingMediaUrl = mediaUrl;
        _pendingIsVideo = isVideo;
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки ${isVideo ? "видео" : "фото"}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearPendingMedia() {
    setState(() {
      _pendingMediaUrl = null;
      _pendingIsVideo = false;
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final hasMedia = _pendingMediaUrl != null;

    if (text.isEmpty && !hasMedia) return;
    if (_userPhone == null || _userPhone!.isEmpty) return;

    setState(() => _isSending = true);

    final message = await ManagementMessageService.sendMessage(
      clientPhone: _userPhone!,
      text: text.isNotEmpty ? text : (_pendingIsVideo ? 'Видео' : 'Фото'),
      imageUrl: _pendingMediaUrl,
      clientName: _userName,
    );

    setState(() => _isSending = false);

    if (message != null) {
      setState(() {
        _messages.add(message);
        _messageController.clear();
        _pendingMediaUrl = null;
        _pendingIsVideo = false;
      });

      // Прокручиваем к новому сообщению
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка отправки'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatTimestamp(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else if (difference.inDays == 1) {
        return 'Вчера ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else {
        return '${date.day}.${date.month}.${date.year}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  Widget _buildMessage(ManagementMessage message) {
    final isFromManager = message.isFromManager;

    return Align(
      alignment: isFromManager ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(
          left: isFromManager ? 12 : 56,
          right: isFromManager ? 56 : 12,
          bottom: 8,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isFromManager
              ? Colors.white.withOpacity(0.08)
              : _gold.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFromManager
                ? Colors.white.withOpacity(0.1)
                : _gold.withOpacity(0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isFromManager)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.business, size: 14, color: _gold.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Text(
                      'Руководство',
                      style: TextStyle(
                        fontSize: 12,
                        color: _gold.withOpacity(0.8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            if (message.imageUrl != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: MediaMessageWidget(mediaUrl: message.imageUrl, maxHeight: 200),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _gold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.business, size: 20, color: _gold),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Связь с Руководством',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadMessages,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // Messages
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: _gold))
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.chat_bubble_outline, size: 40, color: Colors.white.withOpacity(0.3)),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Нет сообщений',
                                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Напишите сообщение руководству',
                                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) => _buildMessage(_messages[index]),
                          ),
              ),

              // Предпросмотр прикреплённого медиа
              if (_pendingMediaUrl != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _night.withOpacity(0.9),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _pendingIsVideo
                            ? Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.videocam, color: _gold),
                              )
                            : AppCachedImage(
                                imageUrl: _pendingMediaUrl!,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.image, color: Colors.white.withOpacity(0.3)),
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _pendingIsVideo ? 'Видео прикреплено' : 'Фото прикреплено',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                        ),
                      ),
                      GestureDetector(
                        onTap: _clearPendingMedia,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.close, color: Colors.red.shade300, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),

              // Input bar
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _night.withOpacity(0.9),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _isUploading ? null : _showMediaPicker,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _isUploading
                              ? Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                                  ),
                                )
                              : Icon(Icons.attach_file, color: _gold.withOpacity(0.7), size: 20),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 15),
                          cursorColor: _gold,
                          decoration: InputDecoration(
                            hintText: 'Написать руководству...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.06),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          maxLines: 3,
                          minLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _isSending ? null : _sendMessage,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _gold.withOpacity(0.25)),
                          ),
                          child: _isSending
                              ? Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                                  ),
                                )
                              : Icon(Icons.send, color: _gold, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
