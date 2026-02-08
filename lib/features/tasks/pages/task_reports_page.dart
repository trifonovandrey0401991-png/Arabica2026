import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import 'task_detail_page.dart';
import 'task_analytics_page.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/models/user_role_model.dart';

/// Страница отчетов по задачам (для админа)
/// 4 вкладки: Ожидают, Выполнено, Отказано, Не выполнено в срок
class TaskReportsPage extends StatefulWidget {
  const TaskReportsPage({super.key});

  @override
  State<TaskReportsPage> createState() => _TaskReportsPageState();
}

class _TaskReportsPageState extends State<TaskReportsPage> with SingleTickerProviderStateMixin {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  late TabController _tabController;
  List<TaskAssignment> _allAssignments = [];
  bool _isLoading = true;
  String? _error;
  int _unviewedExpiredCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadAssignments();
    _loadUnviewedExpiredCount();
  }

  void _onTabChanged() {
    // Если переключились на вкладку "Не в срок" (индекс 3) - отметить как просмотренные
    if (_tabController.index == 3 && _unviewedExpiredCount > 0) {
      _markExpiredAsViewed();
    }
  }

  Future<void> _loadUnviewedExpiredCount() async {
    final count = await TaskService.getUnviewedExpiredCount();
    if (mounted) {
      setState(() {
        _unviewedExpiredCount = count;
      });
    }
  }

  Future<void> _markExpiredAsViewed() async {
    final success = await TaskService.markExpiredAsViewed();
    if (success && mounted) {
      setState(() {
        _unviewedExpiredCount = 0;
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAssignments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      var assignments = await TaskService.getAllAssignments();

      // Фильтрация по мультитенантности — управляющий видит только задачи своих сотрудников
      final roleData = await UserRoleService.loadUserRole();
      if (roleData != null && roleData.role == UserRole.admin && roleData.managedEmployees.isNotEmpty) {
        final employees = await EmployeeService.getEmployees();
        final managedPhones = roleData.managedEmployees.map(
          (p) => p.replaceAll(RegExp(r'[\s\+]'), ''),
        ).toSet();

        // Строим Set разрешённых ID сотрудников
        final allowedIds = <String>{};
        for (final emp in employees) {
          final phone = emp.phone?.replaceAll(RegExp(r'[\s\+]'), '') ?? '';
          if (phone.isNotEmpty && managedPhones.contains(phone)) {
            allowedIds.add(emp.id);
          }
        }

        assignments = assignments.where((a) => allowedIds.contains(a.assigneeId)).toList();
      }

      setState(() {
        _allAssignments = assignments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<TaskAssignment> _filterByStatuses(List<TaskStatus> statuses) {
    final filtered = _allAssignments
        .where((a) => statuses.contains(a.status))
        .toList();
    // Сортировка: новые первыми (по дате создания descending)
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title
                    const Expanded(
                      child: Text(
                        'Отчёты по задачам',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Analytics button
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const TaskAnalyticsPage(),
                        ),
                      ),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.analytics, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // TabBar in dark container
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: _gold,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.5),
                  dividerColor: Colors.transparent,
                  tabAlignment: TabAlignment.start,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
                  tabs: [
                    const Tab(text: 'Ожидают'),
                    const Tab(text: 'Выполнено'),
                    const Tab(text: 'Отказано'),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Не в срок'),
                          if (_unviewedExpiredCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$_unviewedExpiredCount',
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
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Body content
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: _gold))
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Ошибка: $_error',
                                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadAssignments,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _emerald,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Повторить'),
                                ),
                              ],
                            ),
                          )
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              // Ожидают (pending + submitted)
                              _buildAssignmentsList(
                                _filterByStatuses([TaskStatus.pending, TaskStatus.submitted]),
                                emptyMessage: 'Нет задач в ожидании',
                              ),
                              // Выполнено (approved)
                              _buildAssignmentsList(
                                _filterByStatuses([TaskStatus.approved]),
                                emptyMessage: 'Нет выполненных задач',
                              ),
                              // Отказано (rejected + declined)
                              _buildAssignmentsList(
                                _filterByStatuses([TaskStatus.rejected, TaskStatus.declined]),
                                emptyMessage: 'Нет отказанных задач',
                              ),
                              // Не выполнено в срок (expired)
                              _buildAssignmentsList(
                                _filterByStatuses([TaskStatus.expired]),
                                emptyMessage: 'Нет просроченных задач',
                              ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssignmentsList(List<TaskAssignment> assignments, {required String emptyMessage}) {
    if (assignments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inbox, size: 40, color: Colors.white.withOpacity(0.3)),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAssignments,
      color: _gold,
      backgroundColor: _emeraldDark,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: assignments.length,
        itemBuilder: (context, index) {
          final assignment = assignments[index];
          return _buildAssignmentCard(assignment);
        },
      ),
    );
  }

  Widget _buildAssignmentCard(TaskAssignment assignment) {
    final task = assignment.task;
    final statusInfo = _getStatusInfo(assignment.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final result = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (context) => TaskDetailPage(assignment: assignment),
              ),
            );
            if (result == true) {
              _loadAssignments();
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Заголовок и статус
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task?.title ?? 'Задача',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusInfo.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusInfo.icon, size: 14, color: statusInfo.color),
                          const SizedBox(width: 4),
                          Text(
                            statusInfo.label,
                            style: TextStyle(
                              color: statusInfo.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Divider
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                const SizedBox(height: 8),

                // Исполнитель
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: Colors.white.withOpacity(0.3)),
                    const SizedBox(width: 4),
                    Text(
                      assignment.assigneeName,
                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Дедлайн
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: _isOverdue(assignment.deadline) ? Colors.red[300] : Colors.white.withOpacity(0.3),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'До: ${_formatDateTime(assignment.deadline)}',
                      style: TextStyle(
                        color: _isOverdue(assignment.deadline) ? Colors.red[300] : Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),

                // Информация о типе ответа
                if (task != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _getResponseTypeIcon(task.responseType),
                        size: 16,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getResponseTypeText(task.responseType),
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                      ),
                    ],
                  ),
                ],

                // Время ответа (если есть)
                if (assignment.respondedAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.reply, size: 16, color: Colors.blue[300]),
                      const SizedBox(width: 4),
                      Text(
                        'Ответ: ${_formatDateTime(assignment.respondedAt!)}',
                        style: TextStyle(color: Colors.blue[300], fontSize: 12),
                      ),
                    ],
                  ),
                ],

                // Время проверки (если есть)
                if (assignment.reviewedAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        assignment.status == TaskStatus.approved ? Icons.check_circle : Icons.cancel,
                        size: 16,
                        color: assignment.status == TaskStatus.approved ? Colors.green[300] : Colors.red[300],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Проверено: ${_formatDateTime(assignment.reviewedAt!)}',
                        style: TextStyle(
                          color: assignment.status == TaskStatus.approved ? Colors.green[300] : Colors.red[300],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  _StatusInfo _getStatusInfo(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return _StatusInfo('Ожидает', Colors.orange, Icons.hourglass_empty);
      case TaskStatus.submitted:
        return _StatusInfo('На проверке', Colors.blue, Icons.pending_actions);
      case TaskStatus.approved:
        return _StatusInfo('Выполнено', Colors.green, Icons.check_circle);
      case TaskStatus.rejected:
        return _StatusInfo('Отклонено', Colors.red, Icons.cancel);
      case TaskStatus.expired:
        return _StatusInfo('Просрочено', Colors.grey, Icons.timer_off);
      case TaskStatus.declined:
        return _StatusInfo('Отказ', Colors.deepOrange, Icons.block);
    }
  }

  bool _isOverdue(DateTime deadline) {
    return DateTime.now().isAfter(deadline);
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  IconData _getResponseTypeIcon(TaskResponseType type) {
    switch (type) {
      case TaskResponseType.photo:
        return Icons.photo_camera;
      case TaskResponseType.photoAndText:
        return Icons.photo_library;
      case TaskResponseType.text:
        return Icons.text_fields;
    }
  }

  String _getResponseTypeText(TaskResponseType type) {
    switch (type) {
      case TaskResponseType.photo:
        return 'Только фото';
      case TaskResponseType.photoAndText:
        return 'Фото и текст';
      case TaskResponseType.text:
        return 'Только текст';
    }
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;

  _StatusInfo(this.label, this.color, this.icon);
}
