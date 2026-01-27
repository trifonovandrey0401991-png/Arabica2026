import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
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
  final List<File> _attachments = [];
  bool _isSubmitting = false;

  // Цвета темы
  static const _primaryColor = Color(0xFF004D40);
  static const _accentColor = Color(0xFF00796B);
  static const _cardColor = Color(0xFF00574B);
  static const _backgroundColor = Color(0xFF003D33);

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('ru');
  }

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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _accentColor,
              onPrimary: Colors.white,
              surface: _cardColor,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_deadline),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.dark(
                primary: _accentColor,
                onPrimary: Colors.white,
                surface: _cardColor,
                onSurface: Colors.white,
              ),
            ),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
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
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Задача отправлена ${_recipients.length} получателям',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Text('Ошибка при создании задачи', style: TextStyle(color: Colors.white)),
              ],
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text('Новая задача', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: _primaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Карточка основной информации
                    _buildCard(
                      icon: Icons.edit_note,
                      title: 'Основная информация',
                      child: Column(
                        children: [
                          _buildTextField(
                            controller: _titleController,
                            label: 'Заголовок задачи',
                            hint: 'Например: Проверить витрину',
                            icon: Icons.title,
                            required: true,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите заголовок';
                              }
                              return null;
                            },
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _descriptionController,
                            label: 'Описание',
                            hint: 'Подробное описание задачи...',
                            icon: Icons.description,
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Карточка типа ответа
                    _buildCard(
                      icon: Icons.question_answer,
                      title: 'Тип ответа',
                      child: _buildResponseTypeSelector(),
                    ),
                    const SizedBox(height: 16),

                    // Карточка дедлайна
                    _buildCard(
                      icon: Icons.schedule,
                      title: 'Дедлайн',
                      child: _buildDeadlinePicker(),
                    ),
                    const SizedBox(height: 16),

                    // Карточка вложений
                    _buildCard(
                      icon: Icons.attach_file,
                      title: 'Прикрепленные файлы',
                      subtitle: _attachments.isNotEmpty ? '${_attachments.length} фото' : null,
                      child: _buildAttachmentsSection(),
                    ),
                    const SizedBox(height: 16),

                    // Карточка получателей
                    _buildCard(
                      icon: Icons.people,
                      title: 'Получатели',
                      subtitle: _recipients.isNotEmpty ? 'Выбрано: ${_recipients.length}' : null,
                      isRequired: true,
                      hasError: _recipients.isEmpty,
                      child: _buildRecipientsSection(),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Кнопка создания
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
    bool isRequired = false,
    bool hasError = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: hasError
            ? Border.all(color: Colors.red.withOpacity(0.5), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок карточки
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white70, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isRequired) ...[
                            const SizedBox(width: 4),
                            Text(
                              '*',
                              style: TextStyle(
                                color: hasError ? Colors.red : Colors.amber,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Разделитель
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.1),
          ),
          // Контент
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    int maxLines = 1,
    bool required = false,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accentColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        errorStyle: const TextStyle(color: Colors.red),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }

  Widget _buildResponseTypeSelector() {
    return Row(
      children: TaskResponseType.values.map((type) {
        final isSelected = _responseType == type;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: type != TaskResponseType.values.last ? 8 : 0,
            ),
            child: GestureDetector(
              onTap: () => setState(() => _responseType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? _accentColor : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? _accentColor : Colors.white.withOpacity(0.2),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _getResponseTypeIcon(type),
                      color: isSelected ? Colors.white : Colors.white60,
                      size: 24,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      type.displayName,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _getResponseTypeIcon(TaskResponseType type) {
    switch (type) {
      case TaskResponseType.photo:
        return Icons.camera_alt;
      case TaskResponseType.photoAndText:
        return Icons.photo_camera_back;
      case TaskResponseType.text:
        return Icons.text_fields;
    }
  }

  Widget _buildDeadlinePicker() {
    final dateFormat = DateFormat('dd MMMM yyyy, HH:mm', 'ru');
    final now = DateTime.now();
    final isToday = _deadline.year == now.year &&
                    _deadline.month == now.month &&
                    _deadline.day == now.day;
    final isTomorrow = _deadline.year == now.year &&
                       _deadline.month == now.month &&
                       _deadline.day == now.day + 1;

    String dateLabel;
    if (isToday) {
      dateLabel = 'Сегодня, ${DateFormat('HH:mm').format(_deadline)}';
    } else if (isTomorrow) {
      dateLabel = 'Завтра, ${DateFormat('HH:mm').format(_deadline)}';
    } else {
      dateLabel = dateFormat.format(_deadline);
    }

    return InkWell(
      onTap: _selectDeadline,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.event,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Нажмите для изменения',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.edit_calendar,
                color: Colors.white70,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection() {
    return Column(
      children: [
        if (_attachments.isNotEmpty) ...[
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _attachments.length,
              itemBuilder: (context, index) => _buildAttachmentPreview(index),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.camera_alt,
                label: 'Камера',
                onTap: _pickPhoto,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.photo_library,
                label: 'Галерея',
                onTap: _pickFromGallery,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAttachmentPreview(int index) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(right: 12),
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            image: DecorationImage(
              image: FileImage(_attachments[index]),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 16,
          child: GestureDetector(
            onTap: () => _removeAttachment(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.close,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accentColor.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _accentColor, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientsSection() {
    return Column(
      children: [
        InkWell(
          onTap: _selectRecipients,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _recipients.isEmpty
                    ? Colors.red.withOpacity(0.5)
                    : Colors.white.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _recipients.isEmpty
                        ? Colors.red.withOpacity(0.2)
                        : _accentColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _recipients.isEmpty ? Icons.person_add : Icons.group,
                    color: _recipients.isEmpty ? Colors.red[300] : Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _recipients.isEmpty
                      ? Text(
                          'Выберите получателей',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 16,
                          ),
                        )
                      : Text(
                          '${_recipients.length} ${_getRecipientsWord(_recipients.length)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.chevron_right,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Список выбранных получателей
        if (_recipients.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recipients.map((r) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _accentColor.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _recipients.remove(r);
                      });
                    },
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ],
      ],
    );
  }

  String _getRecipientsWord(int count) {
    if (count % 10 == 1 && count % 100 != 11) {
      return 'человек';
    } else if ([2, 3, 4].contains(count % 10) && ![12, 13, 14].contains(count % 100)) {
      return 'человека';
    } else {
      return 'человек';
    }
  }

  Widget _buildSubmitButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isFormValid && !_isSubmitting ? _createTask : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isFormValid ? _accentColor : Colors.grey[700],
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[700],
              disabledForegroundColor: Colors.white54,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: _isFormValid ? 4 : 0,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isFormValid ? Icons.send : Icons.block,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isFormValid ? 'СОЗДАТЬ ЗАДАЧУ' : 'ЗАПОЛНИТЕ ВСЕ ПОЛЯ',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
