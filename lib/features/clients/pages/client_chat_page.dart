import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../models/client_model.dart';
import '../models/client_message_model.dart';
import '../services/client_service.dart';
import '../../../core/services/media_upload_service.dart';
import '../../../shared/widgets/media_message_widget.dart';

/// Страница переписки с клиентом
class ClientChatPage extends StatefulWidget {
  final Client client;

  const ClientChatPage({super.key, required this.client});

  @override
  State<ClientChatPage> createState() => _ClientChatPageState();
}

class _ClientChatPageState extends State<ClientChatPage> {
  List<ClientMessage> _messages = [];
  bool _isLoading = true;
  bool _isUploading = false;
  String? _pendingMediaUrl;
  bool _pendingIsVideo = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    // Автообновление каждые 5 секунд
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _loadMessages();
        _startAutoRefresh();
      }
    });
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await ClientService.getClientMessages(widget.client.phone);
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
        // Прокручиваем вниз после загрузки
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки сообщений: $e'),
            backgroundColor: Colors.red,
          ),
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

    if (text.isEmpty && !hasMedia) {
      return;
    }

    if (_isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final senderPhone = prefs.getString('user_phone') ?? '';

      final result = await ClientService.sendMessage(
        clientPhone: widget.client.phone,
        text: text.isNotEmpty ? text : (_pendingIsVideo ? 'Видео' : 'Фото'),
        senderPhone: senderPhone,
        imageUrl: _pendingMediaUrl,
      );

      if (result != null) {
        _messageController.clear();
        setState(() {
          _pendingMediaUrl = null;
          _pendingIsVideo = false;
        });
        await _loadMessages();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка отправки сообщения'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.client.name.isNotEmpty ? widget.client.name : 'Клиент',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              widget.client.phone,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет сообщений',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isFromAdmin = message.senderPhone != widget.client.phone;
                          
                          return Align(
                            alignment: isFromAdmin 
                                ? Alignment.centerRight 
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isFromAdmin 
                                    ? const Color(0xFF004D40)
                                    : Colors.grey[300],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.7,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.text,
                                    style: TextStyle(
                                      color: isFromAdmin ? Colors.white : Colors.black87,
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
                                      color: isFromAdmin 
                                          ? Colors.white70 
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          // Предпросмотр прикреплённого медиа
          if (_pendingMediaUrl != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey[200],
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
              color: Colors.grey[100],
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
                      hintText: 'Введите сообщение...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF004D40)),
                          ),
                        )
                      : const Icon(Icons.send, color: Color(0xFF004D40)),
                  onPressed: _isSending ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
        return '${date.day}.${date.month}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return timestamp;
    }
  }
}


