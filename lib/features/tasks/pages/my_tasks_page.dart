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

/// Страница "Мои Задачи" для работника с вкладками
class MyTasksPage extends StatefulWidget {
  final String? employeeId;
  final String? employeeName;

  const MyTasksPage({
    super.key,
    this.employeeId,
    this.employeeName,
  });

  @override
  State<MyTasksPage> createState() => _MyTasksPageState();
}

class _MyTasksPageState extends State<MyTasksPage> with SingleTickerProviderStateMixin {
  List<TaskAssignment> _assignments = [];
  List<RecurringTaskInstance> _recurringInstances = [];
  bool _isLoading = true;
  String? _userPhone;
  String? _employeeId;
  String? _employeeName;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
    if (phone != null) {
      _userPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
    }

    // Используем переданные значения или загружаем из SharedPreferences
    _employeeId = widget.employeeId ?? prefs.getString('user_phone') ?? _userPhone;
    _employeeName = widget.employeeName ?? prefs.getString('userName') ?? prefs.getString('user_name');

    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() => _isLoading = true);

    try {
      // Загружаем обычные задачи
      if (_employeeId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final assignments = await TaskService.getMyAssignments(_employeeId!);
      assignments.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Загружаем циклические задачи (если есть телефон)
      List<RecurringTaskInstance> recurringInstances = [];
      if (_userPhone != null && _userPhone!.isNotEmpty) {
        try {
          recurringInstances = await RecurringTaskService.getInstancesForAssignee(
            assigneePhone: _userPhone!,
          );
          recurringInstances.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

  // Фильтры для обычных задач
  List<TaskAssignment> get _activeAssignments => _assignments
      .where((a) => a.status == TaskStatus.pending || a.status == TaskStatus.submitted)
      .toList();

  List<TaskAssignment> get _completedAssignments => _assignments
      .where((a) => a.status == TaskStatus.approved)
      .toList();

  List<TaskAssignment> get _expiredAssignments => _assignments
      .where((a) => a.status == TaskStatus.expired || a.status == TaskStatus.rejected || a.status == TaskStatus.declined)
      .toList();

  // Фильтры для циклических задач
  List<RecurringTaskInstance> get _activeRecurring => _recurringInstances
      .where((i) => i.status == 'pending')
      .toList();

  List<RecurringTaskInstance> get _completedRecurring => _recurringInstances
      .where((i) => i.status == 'completed')
      .toList();

  List<RecurringTaskInstance> get _expiredRecurring => _recurringInstances
      .where((i) => i.status == 'expired')
      .toList();

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
    final activeCount = _activeAssignments.length + _activeRecurring.length;
    final completedCount = _completedAssignments.length + _completedRecurring.length;
    final expiredCount = _expiredAssignments.length + _expiredRecurring.length;

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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Активные ($activeCount)'),
            Tab(text: 'Выполненные ($completedCount)'),
            Tab(text: 'Просроченные ($expiredCount)'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Вкладка "Активные"
                _buildTaskList(_activeAssignments, _activeRecurring, 'Нет активных задач'),
                // Вкладка "Выполненные"
                _buildTaskList(_completedAssignments, _completedRecurring, 'Нет выполненных задач'),
                // Вкладка "Просроченные"
                _buildTaskList(_expiredAssignments, _expiredRecurring, 'Нет просроченных задач'),
              ],
            ),
    );
  }

  Widget _buildTaskList(
    List<TaskAssignment> assignments,
    List<RecurringTaskInstance> recurring,
    String emptyMessage,
  ) {
    if (assignments.isEmpty && recurring.isEmpty) {
      return _buildEmptyState(emptyMessage);
    }

    return RefreshIndicator(
      onRefresh: _loadAssignments,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Циклические задачи (показываем первыми)
          if (recurring.isNotEmpty) ...[
            _buildSectionHeader('Циклические задачи', Icons.repeat),
            ...recurring.map(_buildRecurringInstanceCard),
            const SizedBox(height: 16),
          ],
          // Обычные задачи
          if (assignments.isNotEmpty) ...[
            if (recurring.isNotEmpty)
              _buildSectionHeader('Разовые задачи', Icons.assignment),
            ...assignments.map(_buildAssignmentCard),
          ],
        ],
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

  Widget _buildEmptyState(String message) {
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
            message,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecurringInstanceCard(RecurringTaskInstance instance) {
    final dateFormat = DateFormat('dd.MM HH:mm');
    final isExpired = instance.status == 'expired';
    final isCompleted = instance.status == 'completed';

    Color borderColor;
    Color iconColor;
    if (isExpired) {
      borderColor = Colors.red;
      iconColor = Colors.red;
    } else if (isCompleted) {
      borderColor = Colors.green;
      iconColor = Colors.green;
    } else {
      borderColor = Colors.blue;
      iconColor = Colors.blue;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor, width: 0.5),
      ),
      child: InkWell(
        onTap: () => _openRecurringTaskDetail(instance),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                isCompleted ? Icons.check_circle : (isExpired ? Icons.timer_off : Icons.repeat),
                color: iconColor,
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
                    Row(
                      children: [
                        Text(
                          isCompleted
                              ? 'Выполнено'
                              : (isExpired ? 'Просрочено' : 'До: ${dateFormat.format(instance.deadline)}'),
                          style: TextStyle(
                            fontSize: 11,
                            color: isExpired ? Colors.red : (isCompleted ? Colors.green : Colors.grey[600]),
                          ),
                        ),
                        if (isExpired) ...[
                          const SizedBox(width: 8),
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
                        ],
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
    final isExpired = assignment.status == TaskStatus.expired ||
                      assignment.status == TaskStatus.rejected ||
                      assignment.status == TaskStatus.declined;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isOverdue
            ? const BorderSide(color: Colors.red, width: 1)
            : BorderSide(color: statusColor.withOpacity(0.3), width: 0.5),
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
                        if (isExpired) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '-3',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
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
