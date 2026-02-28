import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../models/recurring_task_model.dart';
import '../services/task_service.dart';
import '../services/recurring_task_service.dart';
import 'task_detail_page.dart';
import 'task_analytics_page.dart';
import '../../employees/services/user_role_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/models/user_role_model.dart';
import '../../../core/utils/cache_manager.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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
  List<RecurringTaskInstance> _allInstances = [];
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
      if (mounted) setState(() {
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

  static const _cacheKey = 'task_assignments_all';

  Future<void> _loadAssignments() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<List<TaskAssignment>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _allAssignments = cached;
        _isLoading = false;
      });
    }

    // Step 2: Fetch fresh data from server
    try {
      var assignments = await TaskService.getAllAssignments();

      // Фильтрация по мультитенантности — управляющий видит только задачи своих сотрудников
      final roleData = await UserRoleService.loadUserRole();
      if (roleData != null && roleData.role == UserRole.admin && roleData.managedEmployees.isNotEmpty) {
        final employees = await EmployeeService.getEmployees();
        final managedPhones = roleData.managedEmployees.map(
          (p) => p.replaceAll(RegExp(r'[\s\+]'), ''),
        ).toSet();

        final allowedIds = <String>{};
        for (final emp in employees) {
          final phone = emp.phone?.replaceAll(RegExp(r'[\s\+]'), '') ?? '';
          if (phone.isNotEmpty && managedPhones.contains(phone)) {
            allowedIds.add(emp.id);
          }
        }

        assignments = assignments.where((a) => allowedIds.contains(a.assigneeId)).toList();
      }

      if (!mounted) return;
      setState(() {
        _allAssignments = assignments;
        _isLoading = false;
        _error = null;
      });

      // Step 3: Save to cache
      CacheManager.set(_cacheKey, assignments);
    } catch (e) {
      if (!mounted) return;
      if (_allAssignments.isEmpty) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }

    // Step 4: Load recurring task instances (current month)
    try {
      final now = DateTime.now();
      final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final instances = await RecurringTaskService.getAllInstances(yearMonth: monthStr);
      if (mounted) setState(() { _allInstances = instances; });
    } catch (e) {
      // Non-critical: show regular assignments even if instances fail
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

  List<RecurringTaskInstance> _filterInstancesByStatuses(List<String> statuses) {
    final filtered = _allInstances
        .where((i) => statuses.contains(i.status))
        .toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar Row
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
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
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    SizedBox(width: 12),
                    // Title
                    Expanded(
                      child: Text(
                        'Отчёты по задачам',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Analytics button
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TaskAnalyticsPage(),
                        ),
                      ),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Icon(Icons.analytics, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              // TabBar in dark container
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: AppColors.gold,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.5),
                  dividerColor: Colors.transparent,
                  tabAlignment: TabAlignment.start,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.sp),
                  unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w400, fontSize: 14.sp),
                  tabs: [
                    Tab(text: 'Ожидают'),
                    Tab(text: 'Выполнено'),
                    Tab(text: 'Отказано'),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Не в срок'),
                          if (_unviewedExpiredCount > 0) ...[
                            SizedBox(width: 6),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Text(
                                '$_unviewedExpiredCount',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.sp,
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

              SizedBox(height: 8),

              // Body content
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Ошибка: $_error',
                                  style: TextStyle(color: Colors.white.withOpacity(0.9)),
                                ),
                                SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _loadAssignments,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.emerald,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text('Повторить'),
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
                                instances: _filterInstancesByStatuses(['pending']),
                              ),
                              // Выполнено (approved + completed recurring)
                              _buildAssignmentsList(
                                _filterByStatuses([TaskStatus.approved]),
                                emptyMessage: 'Нет выполненных задач',
                                instances: _filterInstancesByStatuses(['completed']),
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
                                instances: _filterInstancesByStatuses(['expired']),
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

  Widget _buildAssignmentsList(
    List<TaskAssignment> assignments, {
    required String emptyMessage,
    List<RecurringTaskInstance> instances = const [],
  }) {
    final total = assignments.length + instances.length;
    if (total == 0) {
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
            SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16.sp),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAssignments,
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: assignments.length + instances.length,
        itemBuilder: (context, index) {
          if (index < assignments.length) {
            return _buildAssignmentCard(assignments[index]);
          } else {
            return _buildInstanceCard(instances[index - assignments.length]);
          }
        },
      ),
    );
  }

  Widget _buildInstanceCard(RecurringTaskInstance instance) {
    final Color statusColor;
    final String statusLabel;
    switch (instance.status) {
      case 'completed':
        statusColor = Colors.green;
        statusLabel = 'Выполнено';
        break;
      case 'expired':
        statusColor = Colors.grey;
        statusLabel = 'Просрочено';
        break;
      default:
        statusColor = Colors.blue;
        statusLabel = 'В работе';
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.replay, size: 16, color: Colors.blue.withOpacity(0.7)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    instance.title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.replay, size: 12, color: statusColor),
                      SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Divider(color: Colors.white.withOpacity(0.1), height: 1),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.white.withOpacity(0.3)),
                SizedBox(width: 4),
                Text(
                  instance.assigneeName,
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: _isOverdue(instance.deadline) && instance.status == 'pending'
                      ? Colors.red[300]
                      : Colors.white.withOpacity(0.3),
                ),
                SizedBox(width: 4),
                Text(
                  'До: ${_formatDateTime(instance.deadline)}',
                  style: TextStyle(
                    color: _isOverdue(instance.deadline) && instance.status == 'pending'
                        ? Colors.red[300]
                        : Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
            if (instance.completedAt != null) ...[
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green[300]),
                  SizedBox(width: 4),
                  Text(
                    'Выполнено: ${_formatDateTime(instance.completedAt!)}',
                    style: TextStyle(color: Colors.green[300], fontSize: 12.sp),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(TaskAssignment assignment) {
    final task = assignment.task;
    final statusInfo = _getStatusInfo(assignment.status);

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
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
          borderRadius: BorderRadius.circular(14.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
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
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: statusInfo.color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusInfo.icon, size: 14, color: statusInfo.color),
                          SizedBox(width: 4),
                          Text(
                            statusInfo.label,
                            style: TextStyle(
                              color: statusInfo.color,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),

                // Divider
                Divider(color: Colors.white.withOpacity(0.1), height: 1),
                SizedBox(height: 8),

                // Исполнитель
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: Colors.white.withOpacity(0.3)),
                    SizedBox(width: 4),
                    Text(
                      assignment.assigneeName,
                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                    ),
                  ],
                ),
                SizedBox(height: 4),

                // Дедлайн
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: _isOverdue(assignment.deadline) ? Colors.red[300] : Colors.white.withOpacity(0.3),
                    ),
                    SizedBox(width: 4),
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
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _getResponseTypeIcon(task.responseType),
                        size: 16,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      SizedBox(width: 4),
                      Text(
                        _getResponseTypeText(task.responseType),
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp),
                      ),
                    ],
                  ),
                ],

                // Время ответа (если есть)
                if (assignment.respondedAt != null) ...[
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.reply, size: 16, color: Colors.blue[300]),
                      SizedBox(width: 4),
                      Text(
                        'Ответ: ${_formatDateTime(assignment.respondedAt!)}',
                        style: TextStyle(color: Colors.blue[300], fontSize: 12.sp),
                      ),
                    ],
                  ),
                ],

                // Время проверки (если есть)
                if (assignment.reviewedAt != null) ...[
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        assignment.status == TaskStatus.approved ? Icons.check_circle : Icons.cancel,
                        size: 16,
                        color: assignment.status == TaskStatus.approved ? Colors.green[300] : Colors.red[300],
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Проверено: ${_formatDateTime(assignment.reviewedAt!)}',
                        style: TextStyle(
                          color: assignment.status == TaskStatus.approved ? Colors.green[300] : Colors.red[300],
                          fontSize: 12.sp,
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
