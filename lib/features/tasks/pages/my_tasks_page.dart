import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../models/task_model.dart';
import '../models/recurring_task_model.dart';
import '../services/task_service.dart';
import '../services/recurring_task_service.dart';
import '../widgets/task_common_widgets.dart';
import 'task_response_page.dart';
import 'recurring_task_response_page.dart';
import '../../shifts/models/shift_report_model.dart';
import '../../shifts/services/shift_report_service.dart';
import '../../shifts/pages/shift_report_view_page.dart';
import '../../recount/models/recount_report_model.dart';
import '../../recount/services/recount_service.dart';
import '../../recount/pages/recount_report_view_page.dart';
import '../../envelope/models/envelope_report_model.dart';
import '../../envelope/services/envelope_report_service.dart';
import '../../envelope/pages/envelope_report_view_page.dart';
import '../../coffee_machine/models/coffee_machine_report_model.dart';
import '../../coffee_machine/services/coffee_machine_report_service.dart';
import '../../coffee_machine/pages/coffee_machine_report_view_page.dart';
import '../../shift_handover/models/shift_handover_report_model.dart';
import '../../shift_handover/services/shift_handover_report_service.dart';
import '../../shift_handover/pages/shift_handover_report_view_page.dart';
import '../../employees/services/user_role_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/cache_manager.dart';

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
  static final _orangeGradient = [Color(0xFFFF6B35), Color(0xFFF7C200)];
  static final _greenGradient = [Color(0xFF00b09b), Color(0xFF96c93d)];
  static final _redGradient = [Color(0xFFE53935), Color(0xFFFF5252)];
  static final _purpleGradient = [Color(0xFF7B1FA2), Color(0xFFBA68C8)];
  static final _amberGradient = [Color(0xFFFF8F00), Color(0xFFFFCA28)];

  List<TaskAssignment> _assignments = [];
  List<ShiftReport> _shiftReviewReports = [];
  List<RecountReport> _recountReviewReports = [];
  List<EnvelopeReport> _envelopePendingReports = [];
  List<CoffeeMachineReport> _coffeeMachinePendingReports = [];
  List<ShiftHandoverReport> _shiftHandoverPendingReports = [];
  List<RecurringTaskInstance> _recurringInstances = [];
  bool _isLoading = true;
  String? _userPhone;
  String? _employeeId;
  // Фильтр по месяцу
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

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

    if (mounted) _loadAssignments();
  }

  static const Duration _reportCacheDuration = Duration(seconds: 90);

  Future<void> _loadAssignments({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      if (_employeeId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Очищаем кеш отчётов при forceRefresh
      if (forceRefresh) {
        CacheManager.clearByPattern('my_tasks_');
      }

      List<TaskAssignment> assignments = [];
      List<RecurringTaskInstance> recurringInstances = [];
      List<ShiftReport> shiftReviews = [];
      List<RecountReport> recountReviews = [];
      List<EnvelopeReport> envelopePending = [];
      List<CoffeeMachineReport> coffeeMachinePending = [];
      List<ShiftHandoverReport> shiftHandoverPending = [];

      // Роль загружаем один раз, а не 4 раза
      final role = await UserRoleService.loadUserRole();
      final isAdmin = role != null && (role.isAdminOrAbove || role.isManager);

      await Future.wait([
        // Обычные задачи (уже имеют кеш в TaskService)
        () async {
          try {
            assignments = await TaskService.getMyAssignmentsCached(
              assigneeId: _employeeId!,
              year: _selectedYear,
              month: _selectedMonth,
              forceRefresh: forceRefresh,
            );
            assignments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          } catch (e) {
            Logger.warning('Ошибка загрузки задач: $e');
          }
        }(),
        // Циклические задачи
        () async {
          if (_userPhone != null && _userPhone!.isNotEmpty) {
            try {
              final yearMonth = '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';
              recurringInstances = await CacheManager.getOrFetch<List<RecurringTaskInstance>>(
                'my_tasks_recurring_${_userPhone}_$yearMonth',
                () async {
                  final result = await RecurringTaskService.getInstancesForAssignee(
                    assigneePhone: _userPhone!,
                    yearMonth: yearMonth,
                  );
                  result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  return result;
                },
                duration: _reportCacheDuration,
              );
            } catch (e) {
              Logger.warning('Ошибка загрузки циклических задач: $e');
            }
          }
        }(),
        // Отчёты пересменки на проверке (только для управляющей/developer)
        () async {
          if (!isAdmin) return;
          try {
            final allReports = await CacheManager.getOrFetch<List<ShiftReport>>(
              'my_tasks_shift_reviews',
              () => ShiftReportService.getReportsForCurrentUser(),
              duration: _reportCacheDuration,
            );
            shiftReviews = allReports
                .where((r) => r.status == 'review')
                .toList();
            shiftReviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          } catch (e) {
            Logger.warning('Ошибка загрузки отчётов пересменки: $e');
          }
        }(),
        // Отчёты пересчёта на проверке (только для управляющей/developer)
        () async {
          if (!isAdmin) return;
          try {
            final allReports = await CacheManager.getOrFetch<List<RecountReport>>(
              'my_tasks_recount_reviews',
              () => RecountService.getReportsForCurrentUser(),
              duration: _reportCacheDuration,
            );
            recountReviews = allReports
                .where((r) => r.status == 'review')
                .toList();
            recountReviews.sort((a, b) => b.completedAt.compareTo(a.completedAt));
          } catch (e) {
            Logger.warning('Ошибка загрузки отчётов пересчёта: $e');
          }
        }(),
        // Конверты на проверке (только для управляющей/developer)
        () async {
          if (!isAdmin) return;
          try {
            final allReports = await CacheManager.getOrFetch<List<EnvelopeReport>>(
              'my_tasks_envelope_pending',
              () => EnvelopeReportService.getReportsForCurrentUser(),
              duration: _reportCacheDuration,
            );
            envelopePending = allReports
                .where((r) => r.status == 'pending')
                .toList();
            envelopePending.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          } catch (e) {
            Logger.warning('Ошибка загрузки конвертов: $e');
          }
        }(),
        // Счётчики кофемашин на проверке (только для управляющей/developer)
        () async {
          if (!isAdmin) return;
          try {
            final allReports = await CacheManager.getOrFetch<List<CoffeeMachineReport>>(
              'my_tasks_coffee_pending',
              () => CoffeeMachineReportService.getReportsForCurrentUser(),
              duration: _reportCacheDuration,
            );
            coffeeMachinePending = allReports
                .where((r) => r.status == 'pending')
                .toList();
            coffeeMachinePending.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          } catch (e) {
            Logger.warning('Ошибка загрузки счётчиков кофемашин: $e');
          }
        }(),
        // Отчёты "Сдать смену" на проверке (только для управляющей/developer)
        () async {
          if (!isAdmin) return;
          try {
            final allReports = await CacheManager.getOrFetch<List<ShiftHandoverReport>>(
              'my_tasks_shift_handover_pending',
              () => ShiftHandoverReportService.getReportsForCurrentUser(),
              duration: _reportCacheDuration,
            );
            shiftHandoverPending = allReports
                .where((r) => !r.isConfirmed && !r.isExpired && r.status != 'rejected' && r.status != 'pending' && r.status != 'failed')
                .toList();
            shiftHandoverPending.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          } catch (e) {
            Logger.warning('Ошибка загрузки отчётов сдачи смены: $e');
          }
        }(),
      ]);

      if (!mounted) return;
      setState(() {
        _assignments = assignments;
        _recurringInstances = recurringInstances;
        _shiftReviewReports = shiftReviews;
        _recountReviewReports = recountReviews;
        _envelopePendingReports = envelopePending;
        _coffeeMachinePendingReports = coffeeMachinePending;
        _shiftHandoverPendingReports = shiftHandoverPending;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
        return [AppColors.info, Color(0xFF21CBF3)];
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

  @override
  Widget build(BuildContext context) {
    final activeCount = _activeAssignments.length + _activeRecurring.length + _shiftReviewReports.length + _recountReviewReports.length + _envelopePendingReports.length + _coffeeMachinePendingReports.length + _shiftHandoverPendingReports.length;
    final completedCount = _completedAssignments.length + _completedRecurring.length;
    final expiredCount = _expiredAssignments.length + _expiredRecurring.length;

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
              _buildAppBar(context),
              _buildTabBar(activeCount, completedCount, expiredCount),
              Expanded(
                child: _isLoading
                    ? _buildLoadingState()
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildTaskList(_activeAssignments, _activeRecurring, 'Нет активных задач', isActive: true, shiftReviews: _shiftReviewReports, recountReviews: _recountReviewReports, envelopePending: _envelopePendingReports, coffeeMachinePending: _coffeeMachinePendingReports, shiftHandoverPending: _shiftHandoverPendingReports),
                          _buildTaskList(_completedAssignments, _completedRecurring, 'Нет выполненных задач', isCompleted: true),
                          _buildTaskList(_expiredAssignments, _expiredRecurring, 'Нет просроченных задач', isExpired: true),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 4.h),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Мои Задачи',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 3.h),
                  child: Text(
                    TaskUtils.getMonthName(_selectedMonth, _selectedYear),
                    style: TextStyle(
                      color: AppColors.gold.withOpacity(0.7),
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Кнопка выбора месяца
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: PopupMenuButton<Map<String, dynamic>>(
              icon: Icon(Icons.calendar_month, color: Colors.white.withOpacity(0.8), size: 20),
              tooltip: 'Выбрать месяц',
              color: AppColors.emeraldDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
              onSelected: (monthData) {
                if (mounted) setState(() {
                  _selectedYear = monthData['year'] as int;
                  _selectedMonth = monthData['month'] as int;
                });
                _loadAssignments();
              },
              itemBuilder: (context) {
                final months = TaskUtils.generateMonthsList(count: 6);
                return months.map((m) {
                  final isSelected = m['year'] == _selectedYear && m['month'] == _selectedMonth;
                  return PopupMenuItem<Map<String, dynamic>>(
                    value: m,
                    child: Row(
                      children: [
                        if (isSelected)
                          Icon(Icons.check, size: 18, color: AppColors.gold)
                        else
                          SizedBox(width: 18),
                        SizedBox(width: 8),
                        Text(
                          m['name'] as String,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();
              },
            ),
          ),
          SizedBox(width: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white.withOpacity(0.8), size: 20),
              onPressed: () => _loadAssignments(forceRefresh: true),
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(int activeCount, int completedCount, int expiredCount) {
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: AppColors.gold.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.gold.withOpacity(0.4)),
        ),
        dividerColor: Colors.transparent,
        labelColor: AppColors.gold,
        unselectedLabelColor: Colors.white.withOpacity(0.5),
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.sp),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w400, fontSize: 12.sp),
        labelPadding: EdgeInsets.symmetric(horizontal: 4.w),
        tabs: [
          _buildModernTab('Активные', activeCount, _orangeGradient),
          _buildModernTab('Выполнено', completedCount, _greenGradient),
          _buildModernTab('Просрочено', expiredCount, _redGradient),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.gold.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Загрузка задач...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14.sp,
            ),
          ),
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
            SizedBox(width: 5),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10.sp,
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
    List<ShiftReport> shiftReviews = const [],
    List<RecountReport> recountReviews = const [],
    List<EnvelopeReport> envelopePending = const [],
    List<CoffeeMachineReport> coffeeMachinePending = const [],
    List<ShiftHandoverReport> shiftHandoverPending = const [],
  }) {
    if (assignments.isEmpty && recurring.isEmpty && shiftReviews.isEmpty && recountReviews.isEmpty && envelopePending.isEmpty && coffeeMachinePending.isEmpty && shiftHandoverPending.isEmpty) {
      return _buildEmptyState(emptyMessage, isActive: isActive, isCompleted: isCompleted, isExpired: isExpired);
    }

    return RefreshIndicator(
      onRefresh: _loadAssignments,
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        children: [
          // Пересменка на проверке (показываем первыми — срочные)
          if (shiftReviews.isNotEmpty) ...[
            _buildModernSectionHeader('Пересменка на проверке', Icons.rate_review, shiftReviews.length),
            ...shiftReviews.map((report) => _buildShiftReviewCard(report)),
            SizedBox(height: 16),
          ],
          // Сдать смену на проверке
          if (shiftHandoverPending.isNotEmpty) ...[
            _buildModernSectionHeader('Сдать смену на проверке', Icons.check_circle_outline, shiftHandoverPending.length),
            ...shiftHandoverPending.map((report) => _buildShiftHandoverCard(report)),
            SizedBox(height: 16),
          ],
          // Конверты на проверке
          if (envelopePending.isNotEmpty) ...[
            _buildModernSectionHeader('Конверты на проверке', Icons.mail_outline, envelopePending.length),
            ...envelopePending.map((report) => _buildEnvelopeCard(report)),
            SizedBox(height: 16),
          ],
          // Счётчики кофемашин на проверке
          if (coffeeMachinePending.isNotEmpty) ...[
            _buildModernSectionHeader('Счётчики на проверке', Icons.coffee_outlined, coffeeMachinePending.length),
            ...coffeeMachinePending.map((report) => _buildCoffeeMachineCard(report)),
            SizedBox(height: 16),
          ],
          // Пересчёт на проверке
          if (recountReviews.isNotEmpty) ...[
            _buildModernSectionHeader('Пересчёт на проверке', Icons.inventory, recountReviews.length),
            ...recountReviews.map((report) => _buildRecountReviewCard(report)),
            SizedBox(height: 16),
          ],
          // Циклические задачи
          if (recurring.isNotEmpty) ...[
            _buildModernSectionHeader('Циклические задачи', Icons.repeat, recurring.length),
            ...recurring.map((instance) => _buildModernRecurringCard(instance)),
            SizedBox(height: 16),
          ],
          // Обычные задачи
          if (assignments.isNotEmpty) ...[
            if (recurring.isNotEmpty || shiftReviews.isNotEmpty || recountReviews.isNotEmpty || envelopePending.isNotEmpty || coffeeMachinePending.isNotEmpty || shiftHandoverPending.isNotEmpty)
              _buildModernSectionHeader('Разовые задачи', Icons.assignment, assignments.length),
            ...assignments.map((assignment) => _buildModernAssignmentCard(assignment)),
          ],
        ],
      ),
    );
  }

  Widget _buildModernSectionHeader(String title, IconData icon, int count) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: AppColors.gold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.gold.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.w),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
            ),
            child: Icon(icon, size: 16, color: AppColors.gold),
          ),
          SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.gold,
            ),
          ),
          Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 12.sp,
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
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradientColors.map((c) => c.withOpacity(0.12)).toList()),
              shape: BoxShape.circle,
              border: Border.all(color: gradientColors[0].withOpacity(0.2)),
            ),
            child: Icon(
              icon,
              size: 48,
              color: gradientColors[0].withOpacity(0.7),
            ),
          ),
          SizedBox(height: 20),
          Text(
            message,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          SizedBox(height: 8),
          Text(
            isActive ? 'Новые задачи появятся здесь' :
            isCompleted ? 'Выполненные задачи появятся здесь' :
            'Просроченные задачи появятся здесь',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.4),
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
      statusGradient = [AppColors.info, Color(0xFF21CBF3)];
      statusIcon = Icons.repeat;
      statusText = 'В работе';
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openRecurringTaskDetail(instance),
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                // Status icon
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: statusGradient),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: statusGradient[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    statusIcon,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                SizedBox(width: 14),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        instance.title,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.white.withOpacity(0.4)),
                          SizedBox(width: 4),
                          Text(
                            isCompleted ? 'Выполнено' : 'До: ${dateFormat.format(instance.deadline)}',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: isExpired ? Colors.red[300] : Colors.white.withOpacity(0.5),
                            ),
                          ),
                          Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: statusGradient.map((c) => c.withOpacity(0.2)).toList()),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(color: statusGradient[0].withOpacity(0.3)),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: statusGradient[0],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isExpired) ...[
                            SizedBox(width: 6),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.red.withOpacity(0.3)),
                              ),
                              child: Text(
                                '-3',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.red[300],
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
                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 22),
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
    if (result == true && mounted) {
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

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openTaskDetail(assignment),
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: isOverdue ? Colors.red.withOpacity(0.4) : Colors.white.withOpacity(0.1),
                width: isOverdue ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Status icon
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: statusGradient),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: statusGradient[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _getStatusIcon(assignment.status),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                SizedBox(width: 14),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assignment.taskTitle,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: isOverdue ? Colors.red[300] : Colors.white.withOpacity(0.4)),
                          SizedBox(width: 4),
                          Text(
                            'До: ${dateFormat.format(assignment.deadline)}',
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: isOverdue ? Colors.red[300] : Colors.white.withOpacity(0.5),
                              fontWeight: isOverdue ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                          Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: statusGradient.map((c) => c.withOpacity(0.2)).toList()),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(color: statusGradient[0].withOpacity(0.3)),
                            ),
                            child: Text(
                              assignment.status.displayName,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: statusGradient[0],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isExpiredStatus) ...[
                            SizedBox(width: 6),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8.r),
                                border: Border.all(color: Colors.red.withOpacity(0.3)),
                              ),
                              child: Text(
                                '-3',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.red[300],
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
                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShiftReviewCard(ShiftReport report) {
    final dateFormat = DateFormat('dd.MM HH:mm');
    final shopDisplay = report.shopName ?? report.shopAddress;
    final shiftLabel = report.shiftType == 'morning' ? 'утро' : 'вечер';

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openShiftReviewDetail(report),
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: _purpleGradient[0].withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _purpleGradient),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: _purpleGradient[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.rate_review, color: Colors.white, size: 20),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shopDisplay,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 14, color: Colors.white.withOpacity(0.4)),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${report.employeeName} · $shiftLabel · ${dateFormat.format(report.createdAt)}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: _purpleGradient.map((c) => c.withOpacity(0.2)).toList()),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(color: _purpleGradient[0].withOpacity(0.3)),
                            ),
                            child: Text(
                              'На проверке',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: _purpleGradient[1],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openShiftReviewDetail(ShiftReport report) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftReportViewPage(report: report),
      ),
    );
    if (mounted) {
      CacheManager.clearByPattern('my_tasks_');
      _loadAssignments();
    }
  }

  Widget _buildRecountReviewCard(RecountReport report) {
    final dateFormat = DateFormat('dd.MM HH:mm');
    final tealGradient = [Color(0xFF00897B), Color(0xFF4DB6AC)];

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openRecountReviewDetail(report),
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: tealGradient[0].withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: tealGradient),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: tealGradient[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.inventory, color: Colors.white, size: 20),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.shopAddress,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 14, color: Colors.white.withOpacity(0.4)),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${report.employeeName} · ${dateFormat.format(report.completedAt)}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: tealGradient.map((c) => c.withOpacity(0.2)).toList()),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(color: tealGradient[0].withOpacity(0.3)),
                            ),
                            child: Text(
                              'На проверке',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: tealGradient[1],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openRecountReviewDetail(RecountReport report) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RecountReportViewPage(report: report),
      ),
    );
    if (mounted) {
      CacheManager.clearByPattern('my_tasks_');
      _loadAssignments();
    }
  }

  Widget _buildEnvelopeCard(EnvelopeReport report) {
    final dateFormat = DateFormat('dd.MM HH:mm');
    final shiftLabel = report.shiftType == 'morning' ? 'утро' : 'вечер';

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openEnvelopeDetail(report),
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: _amberGradient[0].withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _amberGradient),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: _amberGradient[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.mail_outline, color: Colors.white, size: 20),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.shopAddress,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 14, color: Colors.white.withOpacity(0.4)),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${report.employeeName} · $shiftLabel · ${dateFormat.format(report.createdAt)}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: _amberGradient.map((c) => c.withOpacity(0.2)).toList()),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(color: _amberGradient[0].withOpacity(0.3)),
                            ),
                            child: Text(
                              'Ожидает',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: _amberGradient[1],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openEnvelopeDetail(EnvelopeReport report) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EnvelopeReportViewPage(report: report, isAdmin: true),
      ),
    );
    if (mounted) {
      CacheManager.clearByPattern('my_tasks_');
      _loadAssignments();
    }
  }

  Widget _buildCoffeeMachineCard(CoffeeMachineReport report) {
    final dateFormat = DateFormat('dd.MM HH:mm');
    final shiftLabel = report.shiftType == 'morning' ? 'утро' : 'вечер';
    final coffeeGradient = [Color(0xFF795548), Color(0xFFA1887F)];

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openCoffeeMachineDetail(report),
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: coffeeGradient[0].withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: coffeeGradient),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: coffeeGradient[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.coffee_outlined, color: Colors.white, size: 20),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.shopAddress,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 14, color: Colors.white.withOpacity(0.4)),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${report.employeeName} · $shiftLabel · ${dateFormat.format(report.createdAt)}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: coffeeGradient.map((c) => c.withOpacity(0.2)).toList()),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(color: coffeeGradient[0].withOpacity(0.3)),
                            ),
                            child: Text(
                              'Ожидает',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: coffeeGradient[1],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCoffeeMachineDetail(CoffeeMachineReport report) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CoffeeMachineReportViewPage(report: report),
      ),
    );
    if (mounted) {
      CacheManager.clearByPattern('my_tasks_');
      _loadAssignments();
    }
  }

  Widget _buildShiftHandoverCard(ShiftHandoverReport report) {
    final dateFormat = DateFormat('dd.MM HH:mm');
    final blueGradient = [Color(0xFF1565C0), Color(0xFF42A5F5)];

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openShiftHandoverDetail(report),
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: blueGradient[0].withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: blueGradient),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: blueGradient[0].withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.shopAddress,
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 14, color: Colors.white.withOpacity(0.4)),
                          SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${report.employeeName} · ${dateFormat.format(report.createdAt)}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: blueGradient.map((c) => c.withOpacity(0.2)).toList()),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(color: blueGradient[0].withOpacity(0.3)),
                            ),
                            child: Text(
                              'Ожидает',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: blueGradient[1],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openShiftHandoverDetail(ShiftHandoverReport report) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShiftHandoverReportViewPage(report: report),
      ),
    );
    if (mounted) {
      CacheManager.clearByPattern('my_tasks_');
      _loadAssignments();
    }
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
