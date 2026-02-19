import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/client_model.dart';
import '../models/management_message_model.dart';
import '../services/management_message_service.dart';
import '../../../core/services/media_upload_service.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/widgets/media_message_widget.dart';
import '../../../shared/widgets/app_cached_image.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница диалога "Связь с Руководством" для админа
class AdminManagementDialogPage extends StatefulWidget {
  final Client client;

  const AdminManagementDialogPage({super.key, required this.client});

  @override
  State<AdminManagementDialogPage> createState() => _AdminManagementDialogPageState();
}

class _AdminManagementDialogPageState extends State<AdminManagementDialogPage> {
  List<ManagementMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploading = false;
  String? _pendingMediaUrl;
  bool _pendingIsVideo = false;
  String? _adminPhone; // SECURITY: Телефон админа для проверки на сервере
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadAdminPhone();
    _loadMessages();

    // Only start auto-refresh if phone is not empty
    if (widget.client.phone.isNotEmpty) {
      _startAutoRefresh();
    } else {
      Logger.debug('Auto-refresh disabled: empty phone number');
    }
  }

  Future<void> _loadAdminPhone() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _adminPhone = prefs.getString('user_phone') ?? prefs.getString('userPhone');
    });
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
    // Guard against empty phone
    if (widget.client.phone.isEmpty) {
      Logger.debug('Cannot load messages: empty phone number');
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await ManagementMessageService.getManagementMessages(widget.client.phone);

      // Отмечаем сообщения как прочитанные руководством
      if (data.messages.any((m) => m.senderType == 'client' && !m.isReadByManager)) {
        ManagementMessageService.markAsReadByManager(widget.client.phone);
      }

      if (mounted) {
        setState(() {
          _messages = data.messages;
          _isLoading = false;
        });

        // Прокручиваем к последнему сообщению
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _messages.isNotEmpty) {
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
        setState(() => _isLoading = false);
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
              leading: Icon(Icons.photo_camera, color: AppColors.primaryGreen),
              title: Text('Сделать фото'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'image'}),
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: AppColors.primaryGreen),
              title: Text('Выбрать фото из галереи'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'image'}),
            ),
            ListTile(
              leading: Icon(Icons.videocam, color: AppColors.primaryGreen),
              title: Text('Записать видео'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.camera, 'type': 'video'}),
            ),
            ListTile(
              leading: Icon(Icons.video_library, color: AppColors.primaryGreen),
              title: Text('Выбрать видео из галереи'),
              onTap: () => Navigator.pop(context, {'source': ImageSource.gallery, 'type': 'video'}),
            ),
            SizedBox(height: 8),
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

    if (!mounted) return;
    setState(() => _isUploading = true);

    final mediaUrl = await MediaUploadService.uploadMedia(
      file.path,
      type: isVideo ? MediaType.video : MediaType.image,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (mediaUrl != null) {
      if (mounted) setState(() {
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
    if (mounted) setState(() {
      _pendingMediaUrl = null;
      _pendingIsVideo = false;
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final hasMedia = _pendingMediaUrl != null;

    if (text.isEmpty && !hasMedia) return;

    if (mounted) setState(() => _isSending = true);

    // SECURITY: Проверяем что adminPhone загружен
    if (_adminPhone == null || _adminPhone!.isEmpty) {
      if (mounted) setState(() => _isSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: не удалось определить телефон админа'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final message = await ManagementMessageService.sendManagerMessage(
      clientPhone: widget.client.phone,
      text: text.isNotEmpty ? text : (_pendingIsVideo ? 'Видео' : 'Фото'),
      senderPhone: _adminPhone!, // SECURITY: Передаём телефон админа для проверки
      imageUrl: _pendingMediaUrl,
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (message != null) {
      if (mounted) setState(() {
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
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки'), backgroundColor: Colors.red),
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
      alignment: isFromManager ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isFromManager ? 48 : 8,
          right: isFromManager ? 8 : 48,
          bottom: 8.h,
        ),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: isFromManager ? AppColors.primaryGreen : Colors.grey[200],
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isFromManager)
              Padding(
                padding: EdgeInsets.only(bottom: 4.h),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person, size: 14, color: Colors.grey[600]),
                    SizedBox(width: 4),
                    Text(
                      message.senderName.isNotEmpty ? message.senderName : 'Клиент',
                      style: TextStyle(
                        fontSize: 12.sp,
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
                  color: isFromManager ? Colors.white : Colors.black87,
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
                color: isFromManager ? Colors.white70 : Colors.grey,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.business, size: 20),
                SizedBox(width: 8),
                Text('Связь с Руководством', style: TextStyle(fontSize: 16.sp)),
              ],
            ),
            Text(
              widget.client.name.isNotEmpty ? widget.client.name : widget.client.phone,
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: AppColors.primaryGreen,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                            SizedBox(height: 16),
                            Text(
                              'Нет сообщений',
                              style: TextStyle(color: Colors.grey[600], fontSize: 18.sp),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Клиент ещё не писал руководству',
                              style: TextStyle(color: Colors.grey[500], fontSize: 14.sp),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessage(_messages[index]);
                        },
                      ),
          ),
          // Предпросмотр прикреплённого медиа
          if (_pendingMediaUrl != null)
            Container(
              padding: EdgeInsets.all(8.w),
              color: Colors.grey[100],
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: _pendingIsVideo
                        ? Container(
                            width: 60,
                            height: 60,
                            color: Colors.black87,
                            child: Icon(Icons.videocam, color: Colors.white),
                          )
                        : AppCachedImage(
                            imageUrl: _pendingMediaUrl!,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey,
                              child: Icon(Icons.image),
                            ),
                          ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pendingIsVideo ? 'Видео прикреплено' : 'Фото прикреплено',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.red),
                    onPressed: _clearPendingMedia,
                  ),
                ],
              ),
            ),
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _isUploading ? null : _showMediaPicker,
                  icon: _isUploading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.attach_file, color: AppColors.primaryGreen),
                  tooltip: 'Прикрепить фото/видео',
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Ответить клиенту...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24.r),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    ),
                    maxLines: 3,
                    minLines: 1,
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _sendMessage,
                  icon: _isSending
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.send, color: AppColors.primaryGreen),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
