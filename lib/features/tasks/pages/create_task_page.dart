import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/task_model.dart';
import '../services/task_service.dart';
import '../../../core/services/media_upload_service.dart';
import 'task_recipient_selection_page.dart';

/// Страница создания задачи (для админа)
class CreateTaskPage extends StatefulWidget {
  final String createdBy;

  const CreateTaskPage({
    super.key,
    required this.createdBy,
  });

  @override
  State<CreateTaskPage> createState() => _CreateTaskPageState();
}

class _CreateTaskPageState extends State<CreateTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  TaskResponseType _responseType = TaskResponseType.photo;
  DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  List<TaskRecipient> _recipients = [];
  final List<File> _attachments = []; // Прикрепленные фото
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    return _titleController.text.trim().isNotEmpty && _recipients.isNotEmpty;
  }

  Future<void> _selectDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_deadline),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          );
        },
      );

      if (time != null && mounted) {
        setState(() {
          _deadline = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _selectRecipients() async {
    final result = await Navigator.push<List<TaskRecipient>>(
      context,
      MaterialPageRoute(
        builder: (context) => TaskRecipientSelectionPage(
          initialSelected: _recipients,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _recipients = result;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      setState(() {
        _attachments.add(File(pickedFile.path));
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();

    setState(() {
      for (final file in pickedFiles) {
        _attachments.add(File(file.path));
      }
    });
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  Future<void> _createTask() async {
    if (!_formKey.currentState!.validate() || !_isFormValid) return;

    setState(() => _isSubmitting = true);

    try {
      // Загружаем прикрепленные фото
      List<String> attachmentUrls = [];
      if (_attachments.isNotEmpty) {
        for (final photo in _attachments) {
          final url = await MediaUploadService.uploadTaskPhoto(photo);
          if (url != null) {
            attachmentUrls.add(url);
          }
        }
      }

      final task = await TaskService.createTask(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        responseType: _responseType,
        deadline: _deadline,
        recipients: _recipients,
        createdBy: widget.createdBy,
        attachments: attachmentUrls,
      );

      if (task != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Задача создана и отправлена ${_recipients.length} получателям', style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при создании задачи', style: TextStyle(color: Colors.white)),
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

  Widget _buildAttachmentPreview(int index) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: FileImage(_attachments[index]),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 12,
          child: GestureDetector(
            onTap: () => _removeAttachment(index),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Новая задача'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Заголовок задачи *',
                  hintText: 'Например: Проверить витрину',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите заголовок';
                  }
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // Описание
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Описание',
                  hintText: 'Подробное описание задачи...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),

              // Тип ответа
              const Text(
                'Тип ответа',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: TaskResponseType.values.map((type) {
                  final isSelected = _responseType == type;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: type != TaskResponseType.values.last ? 8 : 0,
                      ),
                      child: ChoiceChip(
                        label: Text(
                          type.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _responseType = type);
                          }
                        },
                        selectedColor: const Color(0xFF004D40),
                        backgroundColor: Colors.grey[200],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Дедлайн
              const Text(
                'Дедлайн',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectDeadline,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[400]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Color(0xFF004D40)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          dateFormat.format(_deadline),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      const Icon(Icons.edit, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Прикрепленные фото
              const Text(
                'Прикрепленные фото',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              if (_attachments.isNotEmpty) ...[
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _attachments.length,
                    itemBuilder: (context, index) => _buildAttachmentPreview(index),
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

              // Получатели
              const Text(
                'Получатели',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectRecipients,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _recipients.isEmpty ? Colors.red[300]! : Colors.grey[400]!,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.people,
                        color: _recipients.isEmpty ? Colors.red : const Color(0xFF004D40),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _recipients.isEmpty
                            ? Text(
                                'Выберите получателей *',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              )
                            : Text(
                                'Выбрано: ${_recipients.length} человек',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),

              // Список выбранных получателей
              if (_recipients.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _recipients.map((r) => Chip(
                    label: Text(r.name, style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      setState(() {
                        _recipients.remove(r);
                      });
                    },
                  )).toList(),
                ),
              ],

              const SizedBox(height: 32),

              // Кнопка создания
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isFormValid && !_isSubmitting ? _createTask : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
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
                          'СОЗДАТЬ ЗАДАЧУ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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
