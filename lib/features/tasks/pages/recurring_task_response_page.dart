import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../models/recurring_task_model.dart';
import '../models/task_model.dart' show TaskResponseType, TaskResponseTypeExtension;
import '../services/recurring_task_service.dart';
import '../../../core/services/media_upload_service.dart';

/// Страница ответа на циклическую задачу
class RecurringTaskResponsePage extends StatefulWidget {
  final RecurringTaskInstance instance;

  const RecurringTaskResponsePage({
    super.key,
    required this.instance,
  });

  @override
  State<RecurringTaskResponsePage> createState() =>
      _RecurringTaskResponsePageState();
}

class _RecurringTaskResponsePageState extends State<RecurringTaskResponsePage> {
  final _textController = TextEditingController();
  final List<File> _photos = [];
  bool _isSubmitting = false;

  RecurringTaskInstance get instance => widget.instance;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    switch (instance.responseType) {
      case TaskResponseType.photo:
        return _photos.isNotEmpty;
      case TaskResponseType.photoAndText:
        return _photos.isNotEmpty && _textController.text.trim().isNotEmpty;
      case TaskResponseType.text:
        return _textController.text.trim().isNotEmpty;
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      setState(() {
        _photos.add(File(pickedFile.path));
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();

    setState(() {
      for (final file in pickedFiles) {
        _photos.add(File(file.path));
      }
    });
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
    });
  }

  Future<void> _completeTask() async {
    if (!_canSubmit) return;

    setState(() => _isSubmitting = true);

    try {
      // Загружаем фото
      List<String> photoUrls = [];
      if (_photos.isNotEmpty) {
        for (final photo in _photos) {
          final url = await MediaUploadService.uploadTaskPhoto(photo);
          if (url != null) {
            photoUrls.add(url);
          }
        }
      }

      await RecurringTaskService.completeInstance(
        instanceId: instance.id,
        responseText: _textController.text.trim().isNotEmpty
            ? _textController.text.trim()
            : null,
        responsePhotos: photoUrls.isNotEmpty ? photoUrls : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Задача выполнена!', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildPhotoPreview(int index) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: FileImage(_photos[index]),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 12,
          child: GestureDetector(
            onTap: () => _removePhoto(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');
    final needsPhoto = instance.responseType == TaskResponseType.photo ||
        instance.responseType == TaskResponseType.photoAndText;
    final needsText = instance.responseType == TaskResponseType.text ||
        instance.responseType == TaskResponseType.photoAndText;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Выполнение задачи'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Информация о задаче
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.repeat, color: Color(0xFF004D40)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Циклическая',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      instance.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (instance.description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        instance.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Выполнить до: ${dateFormat.format(instance.deadline)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          instance.isExpired
                              ? Icons.warning
                              : Icons.info_outline,
                          size: 16,
                          color: instance.isExpired ? Colors.red : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          instance.isExpired
                              ? 'Просрочено!'
                              : 'Требуется: ${instance.responseType.displayName}',
                          style: TextStyle(
                            fontSize: 13,
                            color: instance.isExpired ? Colors.red : Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Фото (если нужно)
            if (needsPhoto) ...[
              const Text(
                'Фото *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              if (_photos.isNotEmpty) ...[
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _photos.length,
                    itemBuilder: (context, index) => _buildPhotoPreview(index),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Камера'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Галерея'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Текст (если нужно)
            if (needsText) ...[
              Text(
                'Комментарий ${needsPhoto ? "" : "*"}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _textController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Опишите выполнение задачи...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
            ],

            // Информация о баллах
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[800], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'После нажатия "Выполнено" задача будет сразу закрыта без проверки',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Кнопка выполнения
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmit && !_isSubmitting && !instance.isExpired
                    ? _completeTask
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'ВЫПОЛНЕНО',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),

            if (instance.isExpired)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red[800], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Задача просрочена. Вы получили -3 балла.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
