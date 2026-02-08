import 'package:flutter/material.dart';
import 'create_task_page.dart';
import 'create_recurring_task_page.dart';
import '../models/recurring_task_model.dart';
import '../services/recurring_task_service.dart';

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

  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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
              // Custom AppBar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Управление задачами',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Обычные и циклические',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // TabBar
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: _gold,
                  indicatorWeight: 2.5,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.5),
                  dividerColor: Colors.transparent,
                  tabs: const [
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

  const _RegularTasksTab({required this.createdBy});

  static const Color _gold = Color(0xFFD4AF37);
  static const Color _emeraldDark = Color(0xFF0D2E2E);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
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
            const SizedBox(height: 16),
            Text(
              'Создание обычных задач',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Одноразовые задачи с дедлайном',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateTaskPage(createdBy: createdBy),
                  ),
                );
              },
              icon: Icon(Icons.add, color: _emeraldDark),
              label: Text(
                'Создать задачу',
                style: TextStyle(color: _emeraldDark),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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

  const _RecurringTasksTab({required this.createdBy});

  @override
  State<_RecurringTasksTab> createState() => _RecurringTasksTabState();
}

class _RecurringTasksTabState extends State<_RecurringTasksTab> {
  List<RecurringTask> _tasks = [];
  bool _isLoading = true;
  String? _error;

  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
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
            content: Text('Ошибка: $e', style: const TextStyle(color: Colors.white)),
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
        backgroundColor: _emeraldDark,
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
            child: const Text('Удалить'),
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
            const SnackBar(
              content: Text('Задача удалена', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.green,
            ),
          );
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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: _gold),
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
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.error_outline, size: 32, color: Colors.red[300]),
            ),
            const SizedBox(height: 16),
            Text(
              'Ошибка загрузки: $_error',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTasks,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _emeraldDark,
              ),
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Кнопка создания
        Padding(
          padding: const EdgeInsets.all(16),
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
              icon: Icon(Icons.add, color: _emeraldDark),
              label: Text(
                'Создать циклическую задачу',
                style: TextStyle(color: _emeraldDark),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
                          borderRadius: BorderRadius.circular(20),
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
                      const SizedBox(height: 16),
                      Text(
                        'Нет циклических задач',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTasks,
                  color: _gold,
                  backgroundColor: _emeraldDark,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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

  const _RecurringTaskCard({
    required this.task,
    required this.onTogglePause,
    required this.onDelete,
    required this.onEdit,
  });

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                      : _gold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: task.isPaused
                          ? Colors.white.withOpacity(0.4)
                          : Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: task.isPaused
                        ? Colors.orange.withOpacity(0.15)
                        : Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    task.isPaused ? 'Пауза' : 'Активна',
                    style: TextStyle(
                      fontSize: 12,
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
              const SizedBox(height: 8),
              Text(
                task.description,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 12),

            // Дни и время
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 16, color: Colors.white.withOpacity(0.5)),
                const SizedBox(width: 4),
                Text(
                  task.daysOfWeekDisplay,
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withOpacity(0.6)),
                ),
                const SizedBox(width: 16),
                Icon(Icons.access_time,
                    size: 16, color: Colors.white.withOpacity(0.5)),
                const SizedBox(width: 4),
                Text(
                  task.periodDisplay,
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withOpacity(0.6)),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Получатели
            Row(
              children: [
                Icon(Icons.people,
                    size: 16, color: Colors.white.withOpacity(0.5)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task.assignees.length == 1
                        ? task.assignees.first.name
                        : '${task.assignees.length} получателей',
                    style: TextStyle(
                        fontSize: 13, color: Colors.white.withOpacity(0.6)),
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
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Изменить'),
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
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Удалить'),
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
