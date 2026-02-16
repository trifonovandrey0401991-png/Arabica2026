import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../../features/clients/models/client_model.dart';
import '../../features/clients/services/client_service.dart';
import '../../core/services/media_upload_service.dart';
import '../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Диалог для отправки сообщения клиенту или всем клиентам
class SendMessageDialog extends StatefulWidget {
  final Client? client;

  const SendMessageDialog({super.key, this.client});

  @override
  State<SendMessageDialog> createState() => _SendMessageDialogState();
}

class _SendMessageDialogState extends State<SendMessageDialog> {
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();
  File? _selectedMedia;
  bool _isVideo = false;
  bool _isSending = false;
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _showMediaPicker() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: _emeraldDark,
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

    if (file != null) {
      Logger.debug('Выбран файл: ${file.path}');
      final mediaFile = File(file.path);
      final exists = await mediaFile.exists();
      Logger.debug('Файл существует: $exists');
      if (exists) {
        final size = await mediaFile.length();
        Logger.debug('Размер файла: ${(size / 1024).toStringAsFixed(2)} KB');
      }
      setState(() {
        _selectedMedia = mediaFile;
        _isVideo = isVideo;
      });
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
          color: _gold.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: _gold.withOpacity(0.3)),
        ),
        child: Icon(icon, color: _gold, size: 20),
      ),
      title: Text(title, style: TextStyle(color: Colors.white.withOpacity(0.9))),
      onTap: onTap,
    );
  }

  void _clearMedia() {
    setState(() {
      _selectedMedia = null;
      _isVideo = false;
    });
  }

  Future<void> _sendMessage() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      String? mediaUrl;

      // Загружаем медиа, если выбрано
      if (_selectedMedia != null) {
        Logger.debug('Начинаем загрузку медиа: ${_selectedMedia!.path}');
        setState(() => _isUploading = true);

        mediaUrl = await MediaUploadService.uploadMedia(
          _selectedMedia!.path,
          type: _isVideo ? MediaType.video : MediaType.image,
        );

        setState(() => _isUploading = false);
        Logger.debug('Результат загрузки медиа: $mediaUrl');

        if (mediaUrl == null) {
          Logger.error('Ошибка загрузки медиа - URL не получен');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка загрузки ${_isVideo ? "видео" : "фото"}'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() => _isSending = false);
          return;
        }
      }

      // Получаем номер телефона отправителя
      final prefs = await SharedPreferences.getInstance();
      final senderPhone = prefs.getString('user_phone') ?? '';

      bool success;
      if (widget.client != null) {
        // Отправляем одному клиенту
        final result = await ClientService.sendMessage(
          clientPhone: widget.client!.phone,
          text: _textController.text.trim(),
          imageUrl: mediaUrl,
          senderPhone: senderPhone,
        );
        success = result != null;
      } else {
        // Отправляем всем клиентам
        final result = await ClientService.sendBroadcastMessage(
          text: _textController.text.trim(),
          imageUrl: mediaUrl,
          senderPhone: senderPhone,
        );
        success = result != null;
      }

      if (success && mounted) {
        Navigator.pop(context, true);
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
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBroadcast = widget.client == null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: _emeraldDark,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Шапка диалога
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isBroadcast
                      ? [Colors.orange.withOpacity(0.3), _emeraldDark]
                      : [_emerald, _emeraldDark],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20.r),
                  topRight: Radius.circular(20.r),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isBroadcast
                          ? Colors.orange.withOpacity(0.15)
                          : _gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(
                        color: isBroadcast
                            ? Colors.orange.withOpacity(0.3)
                            : _gold.withOpacity(0.3),
                      ),
                    ),
                    child: Icon(
                      isBroadcast ? Icons.campaign_rounded : Icons.send_rounded,
                      color: isBroadcast ? Colors.orange : _gold,
                      size: 26,
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isBroadcast ? 'Рассылка всем' : 'Новое сообщение',
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (!isBroadcast)
                          Text(
                            widget.client!.name.isNotEmpty
                                ? widget.client!.name
                                : widget.client!.phone,
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.white.withOpacity(0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        else
                          Text(
                            'Сообщение получат все клиенты',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded),
                    color: Colors.white70,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),

            // Контент
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20.w),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Информационный баннер для рассылки
                      if (isBroadcast)
                        Container(
                          padding: EdgeInsets.all(14.w),
                          margin: EdgeInsets.only(bottom: 20.h),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(color: Colors.orange.withOpacity(0.25)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(8.w),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                                child: Icon(Icons.info_outline, color: Colors.orange.withOpacity(0.8), size: 22),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Это сообщение будет отправлено всем зарегистрированным клиентам',
                                  style: TextStyle(
                                    fontSize: 13.sp,
                                    color: Colors.orange.withOpacity(0.9),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Поле ввода текста
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: TextFormField(
                          controller: _textController,
                          style: TextStyle(color: Colors.white.withOpacity(0.9)),
                          cursorColor: _gold,
                          decoration: InputDecoration(
                            labelText: 'Текст сообщения',
                            labelStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                            hintText: 'Введите текст сообщения...',
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(16.w),
                            prefixIcon: Padding(
                              padding: EdgeInsets.only(left: 12.w, right: 8.w),
                              child: Icon(Icons.message_rounded, color: Colors.white.withOpacity(0.3), size: 22),
                            ),
                            errorStyle: TextStyle(color: Colors.red[300]),
                          ),
                          maxLines: 5,
                          minLines: 3,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Пожалуйста, введите текст сообщения';
                            }
                            return null;
                          },
                        ),
                      ),

                      SizedBox(height: 20),

                      // Превью медиа
                      if (_selectedMedia != null) ...[
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14.r),
                                child: _isVideo
                                    ? Container(
                                        height: 160,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: _night,
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.videocam_rounded, color: _gold, size: 48),
                                            SizedBox(height: 8),
                                            Text(
                                              'Видео выбрано',
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.7),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Image.file(
                                        _selectedMedia!,
                                        height: 160,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          Logger.error('Ошибка загрузки изображения: $error');
                                          return Container(
                                            height: 160,
                                            width: double.infinity,
                                            color: _night,
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.broken_image_rounded, color: Colors.white.withOpacity(0.3), size: 48),
                                                SizedBox(height: 8),
                                                Text('Ошибка загрузки', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              Positioned(
                                top: 8.h,
                                right: 8.w,
                                child: Material(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(20.r),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(20.r),
                                    onTap: _clearMedia,
                                    child: Padding(
                                      padding: EdgeInsets.all(8.w),
                                      child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 8.h,
                                left: 8.w,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(20.r),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isVideo ? Icons.videocam_rounded : Icons.photo_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        _isVideo ? 'Видео' : 'Фото',
                                        style: TextStyle(color: Colors.white, fontSize: 12.sp, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                      ],

                      // Индикатор загрузки
                      if (_isUploading)
                        Container(
                          padding: EdgeInsets.all(14.w),
                          margin: EdgeInsets.only(bottom: 16.h),
                          decoration: BoxDecoration(
                            color: _gold.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: _gold.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: _gold,
                                ),
                              ),
                              SizedBox(width: 14),
                              Text(
                                'Загрузка медиа...',
                                style: TextStyle(color: _gold.withOpacity(0.9), fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),

                      // Кнопка добавления медиа
                      OutlinedButton.icon(
                        onPressed: _isSending || _isUploading ? null : _showMediaPicker,
                        icon: Icon(
                          _selectedMedia != null ? Icons.refresh_rounded : Icons.attach_file_rounded,
                          size: 20,
                        ),
                        label: Text(
                          _selectedMedia != null
                              ? (_isVideo ? 'Заменить видео' : 'Заменить фото')
                              : 'Прикрепить фото/видео',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white.withOpacity(0.7),
                          side: BorderSide(color: Colors.white.withOpacity(0.15)),
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Кнопки действий
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: _night,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20.r),
                  bottomRight: Radius.circular(20.r),
                ),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSending ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white.withOpacity(0.7),
                        side: BorderSide(color: Colors.white.withOpacity(0.15)),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text('Отмена', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: _isSending ? null : _sendMessage,
                      icon: _isSending
                          ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isBroadcast ? Colors.orange : _gold,
                                ),
                              ),
                            )
                          : Icon(
                              isBroadcast ? Icons.campaign_rounded : Icons.send_rounded,
                              size: 20,
                            ),
                      label: Text(
                        _isSending
                            ? 'Отправка...'
                            : (isBroadcast ? 'Отправить всем' : 'Отправить'),
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isBroadcast ? Colors.orange : _gold,
                        side: BorderSide(
                          color: isBroadcast
                              ? Colors.orange.withOpacity(0.4)
                              : _gold.withOpacity(0.4),
                        ),
                        backgroundColor: isBroadcast
                            ? Colors.orange.withOpacity(0.15)
                            : _gold.withOpacity(0.15),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
