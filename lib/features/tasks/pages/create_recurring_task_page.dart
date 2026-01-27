import 'package:flutter/material.dart';
import '../models/recurring_task_model.dart';
import '../models/task_model.dart' show TaskResponseType, TaskResponseTypeExtension;
import '../services/recurring_task_service.dart';
import 'recurring_recipient_selection_page.dart';

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
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);
  final List<TimeOfDay> _reminderTimes = [
    const TimeOfDay(hour: 9, minute: 0),
    const TimeOfDay(hour: 12, minute: 0),
    const TimeOfDay(hour: 17, minute: 0),
  ];
  List<TaskRecipient> _recipients = [];
  bool _isSubmitting = false;

  // Цвета темы
  static const _primaryColor = Color(0xFF004D40);
  static const _accentColor = Color(0xFF00796B);
  static const _cardColor = Color(0xFF00574B);
  static const _backgroundColor = Color(0xFF003D33);

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
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(
                  _isEditing ? 'Задача обновлена' : 'Циклическая задача создана',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Ошибка: $e', style: const TextStyle(color: Colors.white))),
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
        title: Text(
          _isEditing ? 'Редактировать задачу' : 'Циклическая задача',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
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
                    const SizedBox(height: 16),

                    // Карточка периода выполнения
                    _buildCard(
                      icon: Icons.access_time,
                      title: 'Период выполнения',
                      subtitle: '${_formatTime(_startTime)} - ${_formatTime(_endTime)}',
                      child: _buildTimePeriodSelector(),
                    ),
                    const SizedBox(height: 16),

                    // Карточка напоминаний
                    _buildCard(
                      icon: Icons.notifications_active,
                      title: 'Напоминания',
                      subtitle: 'Push-уведомления в указанное время',
                      child: _buildRemindersSection(),
                    ),
                    const SizedBox(height: 16),

                    // Карточка типа ответа
                    _buildCard(
                      icon: Icons.question_answer,
                      title: 'Тип ответа',
                      child: _buildResponseTypeSelector(),
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
                    const SizedBox(height: 16),

                    // Информация о баллах
                    _buildInfoCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Кнопка сохранения
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
                            color: hasError
                                ? Colors.red[300]
                                : Colors.white.withOpacity(0.6),
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
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.1),
          ),
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

  Widget _buildDaySelector() {
    const days = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];

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
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isSelected ? _accentColor : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _accentColor : Colors.white.withOpacity(0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(
                days[index],
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.arrow_forward, color: Colors.white54),
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(time),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
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
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Напоминание ${index + 1}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(_reminderTimes[index]),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit,
                    color: Colors.white.withOpacity(0.5),
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
                        fontSize: 11,
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

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.info_outline,
              color: Colors.orange,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Система баллов',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'За выполнение: 0 баллов\nЗа невыполнение: -3 балла',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
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
            onPressed: _isFormValid && !_isSubmitting ? _saveTask : null,
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
                        _isFormValid
                            ? (_isEditing ? Icons.save : Icons.add_task)
                            : Icons.block,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isFormValid
                            ? (_isEditing ? 'СОХРАНИТЬ ИЗМЕНЕНИЯ' : 'СОЗДАТЬ ЗАДАЧУ')
                            : 'ЗАПОЛНИТЕ ВСЕ ПОЛЯ',
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
