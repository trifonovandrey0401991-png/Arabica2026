import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../models/management_message_model.dart';
import '../services/management_message_service.dart';
import '../../../core/services/media_upload_service.dart';
import '../../../shared/widgets/media_message_widget.dart';

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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: Color(0xFF004D40)),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'image'}),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF004D40)),
              title: const Text('Выбрать фото из галереи'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'image'}),
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Color(0xFF004D40)),
              title: const Text('Записать видео'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'video'}),
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: Color(0xFF004D40)),
              title: const Text('Выбрать видео из галереи'),
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
          left: isFromManager ? 8 : 48,
          right: isFromManager ? 48 : 8,
          bottom: 8,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isFromManager ? Colors.grey[200] : const Color(0xFF004D40),
          borderRadius: BorderRadius.circular(16),
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
                    Icon(Icons.business, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Руководство',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
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
                  color: isFromManager ? Colors.black87 : Colors.white,
                ),
              ),
            if (message.imageUrl != null) ...[
              const SizedBox(height: 8),
              MediaMessageWidget(mediaUrl: message.imageUrl, maxHeight: 200),
            ],
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isFromManager ? Colors.grey : Colors.white70,
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
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.business, size: 24),
            const SizedBox(width: 8),
            const Text('Связь с Руководством'),
          ],
        ),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Нет сообщений',
                              style: TextStyle(color: Colors.grey[600], fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Напишите сообщение руководству',
                              style: TextStyle(color: Colors.grey[500], fontSize: 14),
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
              padding: const EdgeInsets.all(8),
              color: Colors.grey[100],
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _pendingIsVideo
                        ? Container(
                            width: 60,
                            height: 60,
                            color: Colors.black87,
                            child: const Icon(Icons.videocam, color: Colors.white),
                          )
                        : Image.network(
                            _pendingMediaUrl!,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey,
                              child: const Icon(Icons.image),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pendingIsVideo ? 'Видео прикреплено' : 'Фото прикреплено',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: _clearPendingMedia,
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _isUploading ? null : _showMediaPicker,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file, color: Color(0xFF004D40)),
                  tooltip: 'Прикрепить фото/видео',
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Написать руководству...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, color: Color(0xFF004D40)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
