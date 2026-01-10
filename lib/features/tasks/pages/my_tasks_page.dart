import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../models/task_model.dart';
import '../models/recurring_task_model.dart';
import '../services/task_service.dart';
import '../services/recurring_task_service.dart';
import 'task_response_page.dart';
import 'recurring_task_response_page.dart';

/// Страница "Мои Задачи" для работника
class MyTasksPage extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const MyTasksPage({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<MyTasksPage> createState() => _MyTasksPageState();
}

class _MyTasksPageState extends State<MyTasksPage> {
  List<TaskAssignment> _assignments = [];
  List<RecurringTaskInstance> _recurringInstances = [];
  bool _isLoading = true;
  String? _userPhone;

  @override
  void initState() {
    super.initState();
    _loadUserPhone();
  }

  Future<void> _loadUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
    if (phone != null) {
      _userPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
    }
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() => _isLoading = true);

    try {
      // Загружаем обычные задачи
      final assignments = await TaskService.getMyAssignments(widget.employeeId);
      assignments.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Загружаем циклические задачи (если есть телефон)
      List<RecurringTaskInstance> recurringInstances = [];
      if (_userPhone != null && _userPhone!.isNotEmpty) {
        try {
          recurringInstances = await RecurringTaskService.getInstancesForAssignee(
            assigneePhone: _userPhone!,
          );
          // Фильтруем только pending задачи и сортируем по дедлайну
          recurringInstances = recurringInstances
              .where((i) => i.status == 'pending')
              .toList()
            ..sort((a, b) => a.deadline.compareTo(b.deadline));
        } catch (e) {
          // Игнорируем ошибки загрузки циклических задач
          Logger.warning('Ошибка загрузки циклических задач: $e');
        }
      }

      setState(() {
        _assignments = assignments;
        _recurringInstances = recurringInstances;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Colors.orange;
      case TaskStatus.submitted:
        return Colors.blue;
      case TaskStatus.approved:
        return Colors.green;
      case TaskStatus.rejected:
        return Colors.red;
      case TaskStatus.expired:
        return Colors.grey;
      case TaskStatus.declined:
        return Colors.purple;
    }
  }

  IconData _getStatusIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Icons.pending_actions;
      case TaskStatus.submitted:
        return Icons.hourglass_top;
      case TaskStatus.approved:
        return Icons.check_circle;
      case TaskStatus.rejected:
        return Icons.cancel;
      case TaskStatus.expired:
        return Icons.timer_off;
      case TaskStatus.declined:
        return Icons.block;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои Задачи'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAssignments,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_assignments.isEmpty && _recurringInstances.isEmpty)
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadAssignments,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Циклические задачи (показываем первыми)
                      if (_recurringInstances.isNotEmpty) ...[
                        _buildSectionHeader('Циклические задачи', Icons.repeat),
                        ..._recurringInstances.map(_buildRecurringInstanceCard),
                        const SizedBox(height: 16),
                      ],
                      // Обычные задачи
                      if (_assignments.isNotEmpty) ...[
                        if (_recurringInstances.isNotEmpty)
                          _buildSectionHeader('Обычные задачи', Icons.assignment),
                        ..._assignments.map(_buildAssignmentCard),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF004D40)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF004D40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Нет задач',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Новые задачи появятся здесь',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringInstanceCard(RecurringTaskInstance instance) {
    final dateFormat = DateFormat('dd.MM HH:mm');
    final isOverdue = instance.isExpired;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isOverdue
            ? const BorderSide(color: Colors.red, width: 1)
            : const BorderSide(color: Colors.blue, width: 0.5),
      ),
      child: InkWell(
        onTap: () => _openRecurringTaskDetail(instance),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.repeat,
                color: isOverdue ? Colors.red : Colors.blue,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instance.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'До: ${dateFormat.format(instance.deadline)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOverdue ? Colors.red : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              if (isOverdue)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '-3',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red[700],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _openRecurringTaskDetail(RecurringTaskInstance instance) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecurringTaskResponsePage(instance: instance),
      ),
    );
    if (result == true) {
      _loadAssignments();
    }
  }

  Widget _buildAssignmentCard(TaskAssignment assignment) {
    final dateFormat = DateFormat('dd.MM HH:mm');
    final isOverdue = assignment.isOverdue && assignment.status == TaskStatus.pending;
    final statusColor = _getStatusColor(assignment.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isOverdue
            ? const BorderSide(color: Colors.red, width: 1)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _openTaskDetail(assignment),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                _getStatusIcon(assignment.status),
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assignment.taskTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'До: ${dateFormat.format(assignment.deadline)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isOverdue ? Colors.red : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            assignment.status.displayName,
                            style: TextStyle(
                              fontSize: 10,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResponseTypeChip(TaskResponseType type) {
    IconData icon;
    String label;

    switch (type) {
      case TaskResponseType.photo:
        icon = Icons.photo_camera;
        label = 'Фото';
        break;
      case TaskResponseType.photoAndText:
        icon = Icons.photo_camera;
        label = 'Фото+Текст';
        break;
      case TaskResponseType.text:
        icon = Icons.text_fields;
        label = 'Текст';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  void _openTaskDetail(TaskAssignment assignment) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TaskResponsePage(
          assignment: assignment,
          onUpdated: _loadAssignments,
        ),
      ),
    );
  }
}
