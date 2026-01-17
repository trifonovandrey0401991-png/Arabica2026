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
  final Set<int> _selectedDays = {}; // 0=Вс, 1=Пн, ...
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);
  final List<TimeOfDay> _reminderTimes = [
    const TimeOfDay(hour: 9, minute: 0),
    const TimeOfDay(hour: 12, minute: 0),
    const TimeOfDay(hour: 17, minute: 0),
  ];
  List<TaskRecipient> _recipients = [];
  bool _isSubmitting = false;

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

    // Загружаем времена напоминаний
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
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
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
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
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
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
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
            content: Text(_isEditing ? 'Задача обновлена' : 'Задача создана', style: const TextStyle(color: Colors.white)),
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

  Widget _buildDaySelector() {
    const days = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(7, (index) {
        final isSelected = _selectedDays.contains(index);
        return FilterChip(
          label: Text(
            days[index],
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedDays.add(index);
              } else {
                _selectedDays.remove(index);
              }
            });
          },
          selectedColor: const Color(0xFF004D40),
          checkmarkColor: Colors.white,
          backgroundColor: Colors.grey[200],
        );
      }),
    );
  }

  Widget _buildTimeField(String label, TimeOfDay time, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[400]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const SizedBox(width: 8),
            Text(
              _formatTime(time),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.access_time, size: 16, color: Color(0xFF004D40)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Редактировать задачу' : 'Новая циклическая задача'),
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
                  labelText: 'Заголовок *',
                  hintText: 'Например: Сделать заказ поставщику',
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
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Описание / Комментарий',
                  hintText: 'Кому именно нужно сделать заказ...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),

              // Дни выполнения
              const Text(
                'Дни выполнения *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Выберите дни, когда задача будет создаваться',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              _buildDaySelector(),
              if (_selectedDays.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Выберите хотя бы один день',
                    style: TextStyle(fontSize: 12, color: Colors.red[700]),
                  ),
                ),
              const SizedBox(height: 24),

              // Период выполнения
              const Text(
                'Период выполнения',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildTimeField('С:', _startTime, _selectStartTime),
                  const SizedBox(width: 16),
                  _buildTimeField('До:', _endTime, _selectEndTime),
                ],
              ),
              const SizedBox(height: 24),

              // Напоминания
              const Text(
                'Напоминания (3 шт) *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Push-уведомления будут приходить в указанное время',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Column(
                children: List.generate(3, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          'Напоминание ${index + 1}:',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const Spacer(),
                        _buildTimeField('', _reminderTimes[index], () => _selectTime(index)),
                      ],
                    ),
                  );
                }),
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
                            fontSize: 11,
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

              // Получатели
              const Text(
                'Получатели *',
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
                  children: _recipients
                      .map((r) => Chip(
                            label: Text(r.name, style: const TextStyle(fontSize: 12)),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              setState(() {
                                _recipients.remove(r);
                              });
                            },
                          ))
                      .toList(),
                ),
              ],

              const SizedBox(height: 32),

              // Информация о баллах
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[800], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'За выполнение: 0 баллов\nЗа невыполнение: -3 балла',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Кнопка сохранения
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isFormValid && !_isSubmitting ? _saveTask : null,
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
                      : Text(
                          _isEditing ? 'СОХРАНИТЬ ИЗМЕНЕНИЯ' : 'СОЗДАТЬ ЗАДАЧУ',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
