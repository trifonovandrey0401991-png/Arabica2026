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
  // Цветовая схема
  static const _primaryColor = Color(0xFF004D40);
  static const _accentColor = Color(0xFF00897B);
  static const _orangeGradient = [Color(0xFFFF6B35), Color(0xFFF7C200)];
  static const _greenGradient = [Color(0xFF00b09b), Color(0xFF96c93d)];
  static const _redGradient = [Color(0xFFE53935), Color(0xFFFF5252)];
  static const _blueGradient = [Color(0xFF2196F3), Color(0xFF64B5F6)];

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

    _employeeId = widget.employeeId ?? prefs.getString('user_phone') ?? _userPhone;
    _employeeName = widget.employeeName ?? prefs.getString('userName') ?? prefs.getString('user_name');

    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() => _isLoading = true);

    try {
      if (_employeeId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final assignments = await TaskService.getMyAssignments(_employeeId!);
      assignments.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      List<RecurringTaskInstance> recurringInstances = [];
      if (_userPhone != null && _userPhone!.isNotEmpty) {
        try {
          recurringInstances = await RecurringTaskService.getInstancesForAssignee(
            assigneePhone: _userPhone!,
          );
          recurringInstances.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        } catch (e) {
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

  List<Color> _getStatusGradient(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return _orangeGradient;
      case TaskStatus.submitted:
        return _blueGradient;
      case TaskStatus.approved:
        return _greenGradient;
      case TaskStatus.rejected:
      case TaskStatus.expired:
      case TaskStatus.declined:
        return _redGradient;
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

  void _showFloatingSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : (isSuccess ? Icons.check_circle : Icons.info_outline),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red[700] : (isSuccess ? Colors.green[700] : _primaryColor),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _activeAssignments.length + _activeRecurring.length;
    final completedCount = _completedAssignments.length + _completedRecurring.length;
    final expiredCount = _expiredAssignments.length + _expiredRecurring.length;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Мои Задачи'),
        backgroundColor: _primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAssignments,
            tooltip: 'Обновить',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: _primaryColor,
              indicatorWeight: 3,
              labelColor: _primaryColor,
              unselectedLabelColor: Colors.grey[600],
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              tabs: [
                _buildModernTab('Активные', activeCount, _orangeGradient),
                _buildModernTab('Выполненные', completedCount, _greenGradient),
                _buildModernTab('Просроченные', expiredCount, _redGradient),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Загрузка задач...',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTaskList(_activeAssignments, _activeRecurring, 'Нет активных задач', isActive: true),
                _buildTaskList(_completedAssignments, _completedRecurring, 'Нет выполненных задач', isCompleted: true),
                _buildTaskList(_expiredAssignments, _expiredRecurring, 'Нет просроченных задач', isExpired: true),
              ],
            ),
    );
  }

  Widget _buildModernTab(String text, int count, List<Color> gradientColors) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: gradientColors[0].withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaskList(
    List<TaskAssignment> assignments,
    List<RecurringTaskInstance> recurring,
    String emptyMessage, {
    bool isActive = false,
    bool isCompleted = false,
    bool isExpired = false,
  }) {
    if (assignments.isEmpty && recurring.isEmpty) {
      return _buildEmptyState(emptyMessage, isActive: isActive, isCompleted: isCompleted, isExpired: isExpired);
    }

    return RefreshIndicator(
      onRefresh: _loadAssignments,
      color: _primaryColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Циклические задачи (показываем первыми)
          if (recurring.isNotEmpty) ...[
            _buildModernSectionHeader('Циклические задачи', Icons.repeat, recurring.length),
            ...recurring.map((instance) => _buildModernRecurringCard(instance)),
            const SizedBox(height: 16),
          ],
          // Обычные задачи
          if (assignments.isNotEmpty) ...[
            if (recurring.isNotEmpty)
              _buildModernSectionHeader('Разовые задачи', Icons.assignment, assignments.length),
            ...assignments.map((assignment) => _buildModernAssignmentCard(assignment)),
          ],
        ],
      ),
    );
  }

  Widget _buildModernSectionHeader(String title, IconData icon, int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _primaryColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _primaryColor,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _primaryColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, {bool isActive = false, bool isCompleted = false, bool isExpired = false}) {
    IconData icon;
    List<Color> gradientColors;

    if (isActive) {
      icon = Icons.pending_actions;
      gradientColors = _orangeGradient;
    } else if (isCompleted) {
      icon = Icons.check_circle_outline;
      gradientColors = _greenGradient;
    } else {
      icon = Icons.timer_off;
      gradientColors = _redGradient;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradientColors.map((c) => c.withOpacity(0.15)).toList()),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 48,
              color: gradientColors[0],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isActive ? 'Новые задачи появятся здесь' :
            isCompleted ? 'Выполненные задачи появятся здесь' :
            'Просроченные задачи появятся здесь',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernRecurringCard(RecurringTaskInstance instance) {
    final dateFormat = DateFormat('dd.MM HH:mm');
    final isExpired = instance.status == 'expired';
    final isCompleted = instance.status == 'completed';

    List<Color> statusGradient;
    IconData statusIcon;
    String statusText;

    if (isExpired) {
      statusGradient = _redGradient;
      statusIcon = Icons.timer_off;
      statusText = 'Просрочено';
    } else if (isCompleted) {
      statusGradient = _greenGradient;
      statusIcon = Icons.check_circle;
      statusText = 'Выполнено';
    } else {
      statusGradient = _blueGradient;
      statusIcon = Icons.repeat;
      statusText = 'В работе';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openRecurringTaskDetail(instance),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: statusGradient),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: statusGradient[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    statusIcon,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        instance.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            isCompleted ? 'Выполнено' : 'До: ${dateFormat.format(instance.deadline)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isExpired ? Colors.red[600] : Colors.grey[600],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: statusGradient.map((c) => c.withOpacity(0.15)).toList()),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 11,
                                color: statusGradient[0],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isExpired) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(8),
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
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 22),
              ],
            ),
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

  Widget _buildModernAssignmentCard(TaskAssignment assignment) {
    final dateFormat = DateFormat('dd.MM HH:mm');
    final isOverdue = assignment.isOverdue && assignment.status == TaskStatus.pending;
    final statusGradient = _getStatusGradient(assignment.status);
    final isExpiredStatus = assignment.status == TaskStatus.expired ||
                      assignment.status == TaskStatus.rejected ||
                      assignment.status == TaskStatus.declined;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isOverdue ? Border.all(color: Colors.red[300]!, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: isOverdue ? Colors.red.withOpacity(0.15) : Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openTaskDetail(assignment),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Status icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: statusGradient),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: statusGradient[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _getStatusIcon(assignment.status),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignment.taskTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: isOverdue ? Colors.red : Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'До: ${dateFormat.format(assignment.deadline)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isOverdue ? Colors.red[600] : Colors.grey[600],
                              fontWeight: isOverdue ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: statusGradient.map((c) => c.withOpacity(0.15)).toList()),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              assignment.status.displayName,
                              style: TextStyle(
                                fontSize: 11,
                                color: statusGradient[0],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isExpiredStatus) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(8),
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
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 22),
              ],
            ),
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
