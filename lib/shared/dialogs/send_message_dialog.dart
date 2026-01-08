import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../../features/clients/models/client_model.dart';
import '../../features/clients/services/client_service.dart';
import '../../core/services/media_upload_service.dart';
import '../../core/utils/logger.dart';

/// Диалог для отправки сообщения клиенту или всем клиентам
class SendMessageDialog extends StatefulWidget {
  final Client? client;

  const SendMessageDialog({super.key, this.client});

  @override
  State<SendMessageDialog> createState() => _SendMessageDialogState();
}

class _SendMessageDialogState extends State<SendMessageDialog> {
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

    if (file != null) {
      Logger.debug('📁 Выбран файл: ${file.path}');
      final mediaFile = File(file.path);
      final exists = await mediaFile.exists();
      Logger.debug('📁 Файл существует: $exists');
      if (exists) {
        final size = await mediaFile.length();
        Logger.debug('📁 Размер файла: ${(size / 1024).toStringAsFixed(2)} KB');
      }
      setState(() {
        _selectedMedia = mediaFile;
        _isVideo = isVideo;
      });
    }
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
        Logger.debug('📤 Начинаем загрузку медиа: ${_selectedMedia!.path}');
        setState(() => _isUploading = true);

        mediaUrl = await MediaUploadService.uploadMedia(
          _selectedMedia!.path,
          type: _isVideo ? MediaType.video : MediaType.image,
        );

        setState(() => _isUploading = false);
        Logger.debug('📤 Результат загрузки медиа: $mediaUrl');

        if (mediaUrl == null) {
          Logger.error('❌ Ошибка загрузки медиа - URL не получен');
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
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.client != null
        ? 'Отправить сообщение'
        : 'Отправить сообщение всем'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              if (widget.client != null) ...[
                Text(
                  'Клиент: ${widget.client!.name.isNotEmpty ? widget.client!.name : widget.client!.phone}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Текст сообщения',
                  border: OutlineInputBorder(),
                  hintText: 'Введите текст сообщения',
                ),
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Пожалуйста, введите текст сообщения';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (_selectedMedia != null) ...[
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _isVideo
                          ? Container(
                              height: 150,
                              width: double.infinity,
                              color: Colors.black87,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.videocam, color: Colors.white, size: 48),
                                    SizedBox(height: 8),
                                    Text('Видео выбрано', style: TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                            )
                          : Image.file(
                              _selectedMedia!,
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                Logger.error('❌ Ошибка загрузки изображения: $error');
                                return Container(
                                  height: 150,
                                  width: double.infinity,
                                  color: Colors.grey[300],
                                  child: const Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.broken_image, color: Colors.grey, size: 48),
                                        SizedBox(height: 8),
                                        Text('Ошибка загрузки', style: TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _clearMedia,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_isUploading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Загрузка...'),
                    ],
                  ),
                ),
              ElevatedButton.icon(
                onPressed: _isSending || _isUploading ? null : _showMediaPicker,
                icon: const Icon(Icons.attach_file),
                label: Text(_selectedMedia != null
                    ? (_isVideo ? 'Изменить видео' : 'Изменить фото')
                    : 'Прикрепить фото/видео'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isSending ? null : _sendMessage,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004D40),
          ),
          child: _isSending
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Отправить'),
        ),
      ],
    );
  }
}

