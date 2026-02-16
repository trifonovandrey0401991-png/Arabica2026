import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/task_model.dart';
import '../services/task_service.dart';
import '../../../core/services/media_upload_service.dart';
import 'task_recipient_selection_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  DateTime _deadline = DateTime.now().add(Duration(days: 1));
  List<TaskRecipient> _recipients = [];
  final List<File> _attachments = [];
  bool _isSubmitting = false;

  // Цвета темы — dark emerald
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

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
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: _gold,
              onPrimary: Colors.black,
              surface: _emeraldDark,
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
              colorScheme: ColorScheme.dark(
                primary: _gold,
                onPrimary: Colors.black,
                surface: _emeraldDark,
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
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Задача отправлена ${_recipients.length} получателям',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: _emeraldDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Text('Ошибка при создании задачи', style: TextStyle(color: Colors.white)),
              ],
            ),
            backgroundColor: Colors.red[900],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
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
      backgroundColor: _night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 0.7],
          ),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Custom AppBar
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Новая задача',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(width: 42),
                    ],
                  ),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16.w),
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
                            SizedBox(height: 16),
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
                      SizedBox(height: 16),

                      // Карточка типа ответа
                      _buildCard(
                        icon: Icons.question_answer,
                        title: 'Тип ответа',
                        child: _buildResponseTypeSelector(),
                      ),
                      SizedBox(height: 16),

                      // Карточка дедлайна
                      _buildCard(
                        icon: Icons.schedule,
                        title: 'Дедлайн',
                        child: _buildDeadlinePicker(),
                      ),
                      SizedBox(height: 16),

                      // Карточка вложений
                      _buildCard(
                        icon: Icons.attach_file,
                        title: 'Прикрепленные файлы',
                        subtitle: _attachments.isNotEmpty ? '${_attachments.length} фото' : null,
                        child: _buildAttachmentsSection(),
                      ),
                      SizedBox(height: 16),

                      // Карточка получателей
                      _buildCard(
                        icon: Icons.people,
                        title: 'Получатели',
                        subtitle: _recipients.isNotEmpty ? 'Выбрано: ${_recipients.length}' : null,
                        isRequired: true,
                        hasError: _recipients.isEmpty,
                        child: _buildRecipientsSection(),
                      ),
                      SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Кнопка создания
              _buildSubmitButton(),
            ],
          ),
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
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: hasError
              ? Colors.red.withOpacity(0.5)
              : Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок карточки
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: _gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(icon, color: _gold, size: 20),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isRequired) ...[
                            SizedBox(width: 4),
                            Text(
                              '*',
                              style: TextStyle(
                                color: hasError ? Colors.red : _gold,
                                fontSize: 16.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitle != null) ...[
                        SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12.sp,
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
            padding: EdgeInsets.all(16.w),
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
      style: TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: _gold, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.red),
        ),
        errorStyle: TextStyle(color: Colors.red),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
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
                duration: Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: 14.h),
                decoration: BoxDecoration(
                  color: isSelected ? _gold.withOpacity(0.15) : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: isSelected ? _gold : Colors.white.withOpacity(0.1),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _getResponseTypeIcon(type),
                      color: isSelected ? _gold : Colors.white60,
                      size: 24,
                    ),
                    SizedBox(height: 6),
                    Text(
                      type.displayName,
                      style: TextStyle(
                        color: isSelected ? _gold : Colors.white70,
                        fontSize: 12.sp,
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
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                Icons.event,
                color: _gold,
                size: 24,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateLabel,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Нажмите для изменения',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.all(8.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(
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
          SizedBox(height: 16),
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
            SizedBox(width: 12),
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
          margin: EdgeInsets.only(right: 12.w),
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            image: DecorationImage(
              image: FileImage(_attachments[index]),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 4.h,
          right: 16.w,
          child: GestureDetector(
            onTap: () => _removeAttachment(index),
            child: Container(
              padding: EdgeInsets.all(4.w),
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
              child: Icon(
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
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: _gold.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _gold, size: 20),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
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
          borderRadius: BorderRadius.circular(12.r),
          child: Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: _recipients.isEmpty
                    ? Colors.red.withOpacity(0.5)
                    : Colors.white.withOpacity(0.1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: _recipients.isEmpty
                        ? Colors.red.withOpacity(0.2)
                        : _gold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(
                    _recipients.isEmpty ? Icons.person_add : Icons.group,
                    color: _recipients.isEmpty ? Colors.red[300] : _gold,
                    size: 24,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: _recipients.isEmpty
                      ? Text(
                          'Выберите получателей',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 16.sp,
                          ),
                        )
                      : Text(
                          '${_recipients.length} ${_getRecipientsWord(_recipients.length)}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Icon(
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
          SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recipients.map((r) => Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: _gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: _gold.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.sp,
                    ),
                  ),
                  SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _recipients.remove(r);
                      });
                    },
                    child: Icon(
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
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: _emeraldDark,
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isFormValid && !_isSubmitting ? _createTask : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isFormValid ? _gold : Colors.grey[800],
              foregroundColor: _isFormValid ? _night : Colors.white54,
              disabledBackgroundColor: Colors.grey[800],
              disabledForegroundColor: Colors.white54,
              padding: EdgeInsets.symmetric(vertical: 16.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              elevation: _isFormValid ? 4 : 0,
            ),
            child: _isSubmitting
                ? SizedBox(
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
                      SizedBox(width: 10),
                      Text(
                        _isFormValid ? 'СОЗДАТЬ ЗАДАЧУ' : 'ЗАПОЛНИТЕ ВСЕ ПОЛЯ',
                        style: TextStyle(
                          fontSize: 16.sp,
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
