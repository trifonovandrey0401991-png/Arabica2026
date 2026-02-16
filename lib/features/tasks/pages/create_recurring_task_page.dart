import 'package:flutter/material.dart';
import '../models/recurring_task_model.dart';
import '../models/task_model.dart' show TaskResponseType, TaskResponseTypeExtension;
import '../services/recurring_task_service.dart';
import 'recurring_recipient_selection_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница создания/редактирования циклической задачи
class CreateRecurringTaskPage extends StatefulWidget {
  final String createdBy;
  final RecurringTask? editTask;

  const CreateRecurringTaskPage({
    super.key,
    required this.createdBy,
    this.editTask,
  });

  @override
  State<CreateRecurringTaskPage> createState() =>
      _CreateRecurringTaskPageState();
}

class _CreateRecurringTaskPageState extends State<CreateRecurringTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  TaskResponseType _responseType = TaskResponseType.text;
  final Set<int> _selectedDays = {};
  TimeOfDay _startTime = TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = TimeOfDay(hour: 18, minute: 0);
  final List<TimeOfDay> _reminderTimes = [
    TimeOfDay(hour: 9, minute: 0),
    TimeOfDay(hour: 12, minute: 0),
    TimeOfDay(hour: 17, minute: 0),
  ];
  List<TaskRecipient> _recipients = [];
  bool _isSubmitting = false;

  // Цвета темы
  static final Color _emerald = Color(0xFF1A4D4D);
  static final Color _emeraldDark = Color(0xFF0D2E2E);
  static final Color _night = Color(0xFF051515);
  static final Color _gold = Color(0xFFD4AF37);

  bool get _isEditing => widget.editTask != null;

  @override
  void initState() {
    super.initState();
    if (widget.editTask != null) {
      _loadEditData();
    }
  }

  void _loadEditData() {
    final task = widget.editTask!;
    _titleController.text = task.title;
    _descriptionController.text = task.description;
    _responseType = task.responseType;
    _selectedDays.addAll(task.daysOfWeek);
    _startTime = _parseTime(task.startTime);
    _endTime = _parseTime(task.endTime);

    if (task.reminderTimes.length >= 3) {
      _reminderTimes[0] = _parseTime(task.reminderTimes[0]);
      _reminderTimes[1] = _parseTime(task.reminderTimes[1]);
      _reminderTimes[2] = _parseTime(task.reminderTimes[2]);
    }

    _recipients = task.assignees;
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _isFormValid {
    return _titleController.text.trim().isNotEmpty &&
        _selectedDays.isNotEmpty &&
        _recipients.isNotEmpty;
  }

  Future<void> _selectTime(int reminderIndex) async {
    final time = await showTimePicker(
      context: context,
      initialTime: _reminderTimes[reminderIndex],
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

    if (time != null) {
      setState(() {
        _reminderTimes[reminderIndex] = time;
      });
    }
  }

  Future<void> _selectStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _startTime,
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

    if (time != null) {
      setState(() {
        _startTime = time;
      });
    }
  }

  Future<void> _selectEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _endTime,
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

    if (time != null) {
      setState(() {
        _endTime = time;
      });
    }
  }

  Future<void> _selectRecipients() async {
    final result = await Navigator.push<List<TaskRecipient>>(
      context,
      MaterialPageRoute(
        builder: (context) => RecurringRecipientSelectionPage(
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

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate() || !_isFormValid) return;

    setState(() => _isSubmitting = true);

    try {
      if (_isEditing) {
        await RecurringTaskService.updateTemplate(
          widget.editTask!.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          responseType: _responseType,
          daysOfWeek: _selectedDays.toList()..sort(),
          startTime: _formatTime(_startTime),
          endTime: _formatTime(_endTime),
          reminderTimes: _reminderTimes.map(_formatTime).toList(),
          assignees: _recipients,
        );
      } else {
        await RecurringTaskService.createTemplate(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          responseType: _responseType,
          daysOfWeek: _selectedDays.toList()..sort(),
          startTime: _formatTime(_startTime),
          endTime: _formatTime(_endTime),
          reminderTimes: _reminderTimes.map(_formatTime).toList(),
          assignees: _recipients,
          createdBy: widget.createdBy,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  _isEditing ? 'Задача обновлена' : 'Циклическая задача создана',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            backgroundColor: _emeraldDark,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Ошибка: $e', style: TextStyle(color: Colors.white))),
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
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Custom AppBar
                Padding(
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
                          child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _isEditing ? 'Редактировать задачу' : 'Циклическая задача',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
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
                                label: 'Заголовок',
                                hint: 'Например: Сделать заказ поставщику',
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

                        // Карточка дней выполнения
                        _buildCard(
                          icon: Icons.calendar_month,
                          title: 'Дни выполнения',
                          subtitle: _selectedDays.isNotEmpty
                              ? 'Выбрано: ${_selectedDays.length} дн.'
                              : 'Выберите хотя бы один день',
                          isRequired: true,
                          hasError: _selectedDays.isEmpty,
                          child: _buildDaySelector(),
                        ),
                        SizedBox(height: 16),

                        // Карточка периода выполнения
                        _buildCard(
                          icon: Icons.access_time,
                          title: 'Период выполнения',
                          subtitle: '${_formatTime(_startTime)} - ${_formatTime(_endTime)}',
                          child: _buildTimePeriodSelector(),
                        ),
                        SizedBox(height: 16),

                        // Карточка напоминаний
                        _buildCard(
                          icon: Icons.notifications_active,
                          title: 'Напоминания',
                          subtitle: 'Push-уведомления в указанное время',
                          child: _buildRemindersSection(),
                        ),
                        SizedBox(height: 16),

                        // Карточка типа ответа
                        _buildCard(
                          icon: Icons.question_answer,
                          title: 'Тип ответа',
                          child: _buildResponseTypeSelector(),
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
                        SizedBox(height: 16),

                        // Информация о баллах
                        _buildInfoCard(),
                        SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Кнопка сохранения
                _buildSubmitButton(),
              ],
            ),
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
                            color: hasError
                                ? Colors.red[300]
                                : Colors.white.withOpacity(0.6),
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
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.1),
          ),
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

  Widget _buildDaySelector() {
    final days = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(7, (index) {
        final isSelected = _selectedDays.contains(index);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedDays.remove(index);
              } else {
                _selectedDays.add(index);
              }
            });
          },
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSelected ? _gold : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: isSelected ? _gold : Colors.white.withOpacity(0.1),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                days[index],
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13.sp,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTimePeriodSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildTimeButton(
            label: 'Начало',
            time: _startTime,
            onTap: _selectStartTime,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Icon(Icons.arrow_forward, color: _gold.withOpacity(0.6)),
        ),
        Expanded(
          child: _buildTimeButton(
            label: 'Конец',
            time: _endTime,
            onTap: _selectEndTime,
          ),
        ),
      ],
    );
  }

  Widget _buildTimeButton({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 16.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12.sp,
              ),
            ),
            SizedBox(height: 4),
            Text(
              _formatTime(time),
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemindersSection() {
    return Column(
      children: List.generate(3, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index < 2 ? 12 : 0),
          child: InkWell(
            onTap: () => _selectTime(index),
            borderRadius: BorderRadius.circular(12.r),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 16.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Напоминание ${index + 1}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14.sp,
                    ),
                  ),
                  Spacer(),
                  Text(
                    _formatTime(_reminderTimes[index]),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.edit,
                    color: _gold.withOpacity(0.5),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      }),
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
                  color: isSelected ? _gold : Colors.white.withOpacity(0.06),
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
                      color: isSelected ? Colors.black : Colors.white60,
                      size: 24,
                    ),
                    SizedBox(height: 6),
                    Text(
                      type.displayName,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 11.sp,
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
                border: Border.all(color: _gold.withOpacity(0.3)),
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

  Widget _buildInfoCard() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: _gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: _gold.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(
              Icons.info_outline,
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
                  'Система баллов',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'За выполнение: 0 баллов\nЗа невыполнение: -3 балла',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13.sp,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isFormValid && !_isSubmitting ? _saveTask : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isFormValid ? _gold : Colors.grey[800],
              foregroundColor: Colors.black,
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isFormValid
                            ? (_isEditing ? Icons.save : Icons.add_task)
                            : Icons.block,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        _isFormValid
                            ? (_isEditing ? 'СОХРАНИТЬ ИЗМЕНЕНИЯ' : 'СОЗДАТЬ ЗАДАЧУ')
                            : 'ЗАПОЛНИТЕ ВСЕ ПОЛЯ',
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
