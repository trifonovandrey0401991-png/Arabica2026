import 'package:flutter/material.dart';
import 'create_task_page.dart';
import 'create_recurring_task_page.dart';
import '../models/recurring_task_model.dart';
import '../services/recurring_task_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница управления задачами с вкладками (Обычные / Циклические)
class TaskManagementPage extends StatefulWidget {
  final String createdBy;

  const TaskManagementPage({
    super.key,
    required this.createdBy,
  });

  @override
  State<TaskManagementPage> createState() => _TaskManagementPageState();
}

class _TaskManagementPageState extends State<TaskManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
              // Custom AppBar
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Управление задачами',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Обычные и циклические',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // TabBar
              Container(
                margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.gold,
                  indicatorWeight: 2.5,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.5),
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(text: 'Обычные задачи'),
                    Tab(text: 'Циклические'),
                  ],
                ),
              ),

              // TabBarView
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Вкладка обычных задач - переходит на CreateTaskPage
                    _RegularTasksTab(createdBy: widget.createdBy),
                    // Вкладка циклических задач
                    _RecurringTasksTab(createdBy: widget.createdBy),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Вкладка обычных задач
class _RegularTasksTab extends StatelessWidget {
  final String createdBy;

  _RegularTasksTab({required this.createdBy});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: Icon(
                Icons.assignment_add,
                size: 40,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Создание обычных задач',
              style: TextStyle(
                fontSize: 18.sp,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Одноразовые задачи с дедлайном',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateTaskPage(createdBy: createdBy),
                  ),
                );
              },
              icon: Icon(Icons.add, color: AppColors.emeraldDark),
              label: Text(
                'Создать задачу',
                style: TextStyle(color: AppColors.emeraldDark),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                padding: EdgeInsets.symmetric(
                  horizontal: 32.w,
                  vertical: 16.h,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Вкладка циклических задач
class _RecurringTasksTab extends StatefulWidget {
  final String createdBy;

  _RecurringTasksTab({required this.createdBy});

  @override
  State<_RecurringTasksTab> createState() => _RecurringTasksTabState();
}

class _RecurringTasksTabState extends State<_RecurringTasksTab> {
  List<RecurringTask> _tasks = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    if (mounted) setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tasks = await RecurringTaskService.getAllTemplates();
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _togglePause(RecurringTask task) async {
    try {
      await RecurringTaskService.togglePause(task.id);
      _loadTasks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteTask(RecurringTask task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        title: Text(
          'Удалить задачу?',
          style: TextStyle(color: Colors.white.withOpacity(0.9)),
        ),
        content: Text(
          'Вы уверены, что хотите удалить "${task.title}"?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[300]),
            child: Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await RecurringTaskService.deleteTemplate(task.id);
        _loadTasks();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Задача удалена', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка: $e', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Icon(Icons.error_outline, size: 32, color: Colors.red[300]),
            ),
            SizedBox(height: 16),
            Text(
              'Ошибка загрузки: $_error',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTasks,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.emeraldDark,
              ),
              child: Text('Повторить'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Кнопка создания
        Padding(
          padding: EdgeInsets.all(16.w),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        CreateRecurringTaskPage(createdBy: widget.createdBy),
                  ),
                );
                if (result == true) {
                  _loadTasks();
                }
              },
              icon: Icon(Icons.add, color: AppColors.emeraldDark),
              label: Text(
                'Создать циклическую задачу',
                style: TextStyle(color: AppColors.emeraldDark),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
        ),

        // Список задач
        Expanded(
          child: _tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20.r),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Icon(
                          Icons.repeat,
                          size: 40,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Нет циклических задач',
                        style: TextStyle(
                          fontSize: 16.sp,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTasks,
                  color: AppColors.gold,
                  backgroundColor: AppColors.emeraldDark,
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      return _RecurringTaskCard(
                        task: task,
                        onTogglePause: () => _togglePause(task),
                        onDelete: () => _deleteTask(task),
                        onEdit: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CreateRecurringTaskPage(
                                createdBy: widget.createdBy,
                                editTask: task,
                              ),
                            ),
                          );
                          if (result == true) {
                            _loadTasks();
                          }
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// Карточка циклической задачи
class _RecurringTaskCard extends StatelessWidget {
  final RecurringTask task;
  final VoidCallback onTogglePause;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  _RecurringTaskCard({
    required this.task,
    required this.onTogglePause,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок и статус
            Row(
              children: [
                Icon(
                  Icons.repeat,
                  color: task.isPaused
                      ? Colors.white.withOpacity(0.3)
                      : AppColors.gold,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: task.isPaused
                          ? Colors.white.withOpacity(0.4)
                          : Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.w,
                    vertical: 4.h,
                  ),
                  decoration: BoxDecoration(
                    color: task.isPaused
                        ? Colors.orange.withOpacity(0.15)
                        : Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    task.isPaused ? 'Пауза' : 'Активна',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: task.isPaused
                          ? Colors.orange[300]
                          : Colors.green[300],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),

            if (task.description.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                task.description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14.sp,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            SizedBox(height: 12),

            // Дни и время
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 16, color: Colors.white.withOpacity(0.5)),
                SizedBox(width: 4),
                Text(
                  task.daysOfWeekDisplay,
                  style: TextStyle(
                      fontSize: 13.sp, color: Colors.white.withOpacity(0.6)),
                ),
                SizedBox(width: 16),
                Icon(Icons.access_time,
                    size: 16, color: Colors.white.withOpacity(0.5)),
                SizedBox(width: 4),
                Text(
                  task.periodDisplay,
                  style: TextStyle(
                      fontSize: 13.sp, color: Colors.white.withOpacity(0.6)),
                ),
              ],
            ),

            SizedBox(height: 8),

            // Получатели
            Row(
              children: [
                Icon(Icons.people,
                    size: 16, color: Colors.white.withOpacity(0.5)),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task.assignees.length == 1
                        ? task.assignees.first.name
                        : '${task.assignees.length} получателей',
                    style: TextStyle(
                        fontSize: 13.sp, color: Colors.white.withOpacity(0.6)),
                  ),
                ),
              ],
            ),

            Divider(
              height: 24,
              color: Colors.white.withOpacity(0.1),
            ),

            // Кнопки действий
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit, size: 18),
                  label: Text('Изменить'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue[300],
                  ),
                ),
                TextButton.icon(
                  onPressed: onTogglePause,
                  icon: Icon(
                    task.isPaused ? Icons.play_arrow : Icons.pause,
                    size: 18,
                  ),
                  label: Text(task.isPaused ? 'Возобновить' : 'Пауза'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange[300],
                  ),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete, size: 18),
                  label: Text('Удалить'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red[300],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
