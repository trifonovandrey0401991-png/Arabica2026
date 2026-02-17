import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../models/client_model.dart';
import '../models/client_message_model.dart';
import '../services/client_service.dart';
import '../../../core/services/media_upload_service.dart';
import '../../../shared/widgets/media_message_widget.dart';
import '../../../shared/widgets/app_cached_image.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
    Future.delayed(Duration(seconds: 5), () {
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
              duration: Duration(milliseconds: 300),
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
      backgroundColor: AppColors.emeraldDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.only(top: 12.h, bottom: 8.h),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            _buildMediaTile(
              icon: Icons.photo_camera,
              title: 'Сделать фото',
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'image'}),
            ),
            _buildMediaTile(
              icon: Icons.photo_library,
              title: 'Выбрать фото из галереи',
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'image'}),
            ),
            _buildMediaTile(
              icon: Icons.videocam,
              title: 'Записать видео',
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'video'}),
            ),
            _buildMediaTile(
              icon: Icons.video_library,
              title: 'Выбрать видео из галереи',
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'video'}),
            ),
            SizedBox(height: 12),
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
        maxDuration: Duration(minutes: 2),
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

  Widget _buildMediaTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: AppColors.gold.withOpacity(0.3)),
        ),
        child: Icon(icon, color: AppColors.gold, size: 20),
      ),
      title: Text(title, style: TextStyle(color: Colors.white.withOpacity(0.9))),
      onTap: onTap,
    );
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
            SnackBar(
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.client.name.isNotEmpty ? widget.client.name : 'Клиент',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.client.phone,
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.normal, color: Colors.white.withOpacity(0.6)),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(Icons.refresh, size: 18, color: Colors.white.withOpacity(0.7)),
            ),
            onPressed: _loadMessages,
            tooltip: 'Обновить',
          ),
          SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppColors.gold.withOpacity(0.7),
                          strokeWidth: 2,
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: EdgeInsets.all(16.w),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(16.r),
                                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                                  ),
                                  child: Icon(Icons.chat_bubble_outline, size: 40, color: AppColors.gold.withOpacity(0.5)),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Нет сообщений',
                                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.all(16.w),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final isFromAdmin = message.senderPhone != widget.client.phone;

                              return Align(
                                alignment: isFromAdmin
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: EdgeInsets.only(bottom: 8.h),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14.w,
                                    vertical: 10.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isFromAdmin
                                        ? AppColors.emerald.withOpacity(0.8)
                                        : Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(14.r),
                                    border: Border.all(
                                      color: isFromAdmin
                                          ? AppColors.gold.withOpacity(0.2)
                                          : Colors.white.withOpacity(0.08),
                                    ),
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
                                          color: Colors.white.withOpacity(isFromAdmin ? 0.95 : 0.85),
                                        ),
                                      ),
                                      if (message.imageUrl != null) ...[
                                        SizedBox(height: 8),
                                        MediaMessageWidget(mediaUrl: message.imageUrl, maxHeight: 200),
                                      ],
                                      SizedBox(height: 4),
                                      Text(
                                        _formatTimestamp(message.timestamp),
                                        style: TextStyle(
                                          fontSize: 10.sp,
                                          color: isFromAdmin
                                              ? AppColors.gold.withOpacity(0.6)
                                              : Colors.white.withOpacity(0.35),
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
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: AppColors.emeraldDark,
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10.r),
                        child: _pendingIsVideo
                            ? Container(
                                width: 56,
                                height: 56,
                                color: AppColors.night,
                                child: Icon(Icons.videocam, color: AppColors.gold, size: 24),
                              )
                            : AppCachedImage(
                                imageUrl: _pendingMediaUrl!,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  width: 56,
                                  height: 56,
                                  color: AppColors.night,
                                  child: Icon(Icons.image, color: Colors.white38),
                                ),
                              ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _pendingIsVideo ? 'Видео прикреплено' : 'Фото прикреплено',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.red[300], size: 20),
                        onPressed: _clearPendingMedia,
                      ),
                    ],
                  ),
                ),
              // Поле ввода
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  color: AppColors.emeraldDark,
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: IconButton(
                        onPressed: _isUploading ? null : _showMediaPicker,
                        icon: _isUploading
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                              )
                            : Icon(Icons.attach_file, color: AppColors.gold.withOpacity(0.7), size: 22),
                        tooltip: 'Прикрепить фото/видео',
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(22.r),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: TextField(
                          controller: _messageController,
                          style: TextStyle(color: Colors.white.withOpacity(0.9)),
                          cursorColor: AppColors.gold,
                          decoration: InputDecoration(
                            hintText: 'Введите сообщение...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 10.h,
                            ),
                          ),
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                      ),
                      child: IconButton(
                        icon: _isSending
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
                                ),
                              )
                            : Icon(Icons.send, color: AppColors.gold, size: 22),
                        onPressed: _isSending ? null : _sendMessage,
                      ),
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
