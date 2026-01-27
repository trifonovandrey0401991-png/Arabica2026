import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import 'task_detail_page.dart';
import 'task_analytics_page.dart';

/// Страница отчетов по задачам (для админа)
/// 4 вкладки: Ожидают, Выполнено, Отказано, Не выполнено в срок
class TaskReportsPage extends StatefulWidget {
  const TaskReportsPage({super.key});

  @override
  State<TaskReportsPage> createState() => _TaskReportsPageState();
}

class _TaskReportsPageState extends State<TaskReportsPage> with SingleTickerProviderStateMixin {
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
      final assignments = await TaskService.getAllAssignments();
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
      appBar: AppBar(
        title: const Text('Отчет по задачам'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            tooltip: 'Аналитика',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const TaskAnalyticsPage(),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
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
                        color: Colors.red,
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Ошибка: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadAssignments,
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
    );
  }

  Widget _buildAssignmentsList(List<TaskAssignment> assignments, {required String emptyMessage}) {
    if (assignments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAssignments,
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
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
        borderRadius: BorderRadius.circular(12),
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusInfo.color.withOpacity(0.1),
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

              // Исполнитель
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    assignment.assigneeName,
                    style: TextStyle(color: Colors.grey[700]),
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
                    color: _isOverdue(assignment.deadline) ? Colors.red : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'До: ${_formatDateTime(assignment.deadline)}',
                    style: TextStyle(
                      color: _isOverdue(assignment.deadline) ? Colors.red : Colors.grey[700],
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
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getResponseTypeText(task.responseType),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ],

              // Время ответа (если есть)
              if (assignment.respondedAt != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.reply, size: 16, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      'Ответ: ${_formatDateTime(assignment.respondedAt!)}',
                      style: const TextStyle(color: Colors.blue, fontSize: 12),
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
                      color: assignment.status == TaskStatus.approved ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Проверено: ${_formatDateTime(assignment.reviewedAt!)}',
                      style: TextStyle(
                        color: assignment.status == TaskStatus.approved ? Colors.green : Colors.red,
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
