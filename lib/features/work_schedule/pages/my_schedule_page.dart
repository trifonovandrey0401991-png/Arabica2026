import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../models/work_schedule_model.dart';
import '../models/shift_transfer_model.dart';
import '../services/work_schedule_service.dart';
import '../services/shift_transfer_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../shops/services/shop_service.dart';
import '../../shops/models/shop_model.dart';
import '../../kpi/services/kpi_service.dart';
import '../../kpi/models/kpi_models.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница моего графика (для просмотра личного графика сотрудника)
class MySchedulePage extends StatefulWidget {
  const MySchedulePage({super.key});

  @override
  State<MySchedulePage> createState() => _MySchedulePageState();
}

class _MySchedulePageState extends State<MySchedulePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = DateTime.now();
  WorkSchedule? _schedule;
  String? _employeeId;
  String? _employeeName;
  bool _isLoading = false;
  String? _error;

  // Кэш времени смен для магазинов
  Map<String, Map<ShiftType, ShiftTimeInfo>> _shiftTimes = {};

  // Уведомления (входящие)
  List<ShiftTransferRequest> _notifications = [];
  int _unreadCount = 0;
  bool _isLoadingNotifications = false;

  // Мои заявки (исходящие)
  List<ShiftTransferRequest> _outgoingRequests = [];
  bool _isLoadingOutgoing = false;
  int _outgoingUpdatesCount = 0;

  // Вкладка "Отработал"
  List<_WorkedShiftInfo> _workedShifts = [];
  bool _isLoadingWorked = false;

  // Вкладка "Общий"
  WorkSchedule? _generalSchedule;
  bool _isLoadingGeneral = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadEmployeeId();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    // Обновляем UI для кастомного TabBar только когда анимация завершена
    if (!_tabController.indexIsChanging && mounted) {
      setState(() {});
    }

    if (_tabController.index == 1 && _employeeId != null) {
      _loadNotifications();
    } else if (_tabController.index == 2 && _employeeId != null) {
      _loadOutgoingRequests();
    } else if (_tabController.index == 3 && _employeeId != null) {
      _loadWorkedHistory();
    } else if (_tabController.index == 4) {
      _loadGeneralSchedule();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_employeeId != null && _schedule == null && !_isLoading) {
      _loadSchedule();
    }
  }

  Future<void> _loadEmployeeId() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      Logger.debug('Начало загрузки данных сотрудника...');
      final employeeId = await EmployeesPage.getCurrentEmployeeId();

      if (employeeId == null) {
        Logger.warning('Не удалось определить ID сотрудника');
        setState(() {
          _error = 'Не удалось определить сотрудника. Убедитесь, что вы вошли в систему.';
          _isLoading = false;
        });
        return;
      }

      Logger.debug('Получен employeeId: $employeeId');
      final employeeName = await EmployeesPage.getCurrentEmployeeName();

      String? name = employeeName;
      if (name == null) {
        Logger.debug('Имя не получено, загружаем из списка сотрудников...');
        final employees = await EmployeeService.getEmployees();
        try {
          final employee = employees.firstWhere((e) => e.id == employeeId);
          name = employee.name;
          Logger.debug('Имя получено из списка: $name');
        } catch (e) {
          Logger.warning('Сотрудник не найден в списке: $e');
        }
      }

      if (mounted) {
        setState(() {
          _employeeId = employeeId;
          _employeeName = name ?? 'Неизвестно';
        });
        Logger.info('Данные сотрудника загружены: ID=$employeeId, имя=$name');
      }

      await _loadSchedule();
      await _loadUnreadCount();
      await _loadOutgoingUpdatesCount();
    } catch (e) {
      Logger.error('Ошибка загрузки данных сотрудника', e);
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки данных: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSchedule() async {
    if (_employeeId == null) {
      Logger.warning('_loadSchedule: employeeId равен null');
      return;
    }

    Logger.debug('Загрузка графика для сотрудника: $_employeeId');
    Logger.debug('Месяц: ${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final schedule = await WorkScheduleService.getEmployeeSchedule(
        _employeeId!,
        _selectedMonth,
      );

      Logger.info('График загружен: ${schedule.entries.length} записей');
      final shiftTimes = await WorkScheduleService.getShiftTimesForEntries(schedule.entries);

      if (mounted) {
        setState(() {
          _schedule = schedule;
          _shiftTimes = shiftTimes;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки графика', e);
      if (mounted) {
        setState(() {
          _error = 'Ошибка загрузки графика: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadNotifications() async {
    if (_employeeId == null) return;

    setState(() {
      _isLoadingNotifications = true;
    });

    try {
      final notifications = await ShiftTransferService.getEmployeeRequests(_employeeId!);
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoadingNotifications = false;
        });
      }
      await _loadUnreadCount();
    } catch (e) {
      Logger.error('Ошибка загрузки уведомлений', e);
      if (mounted) {
        setState(() {
          _isLoadingNotifications = false;
        });
      }
    }
  }

  Future<void> _loadUnreadCount() async {
    if (_employeeId == null) return;

    try {
      final count = await ShiftTransferService.getUnreadCount(_employeeId!);
      if (mounted) {
        setState(() {
          _unreadCount = count;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика', e);
    }
  }

  Future<void> _loadOutgoingRequests() async {
    if (_employeeId == null) return;

    setState(() {
      _isLoadingOutgoing = true;
    });

    try {
      final requests = await ShiftTransferService.getOutgoingRequests(_employeeId!);
      if (mounted) {
        setState(() {
          _outgoingRequests = requests;
          _isLoadingOutgoing = false;
          _outgoingUpdatesCount = 0;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки исходящих заявок', e);
      if (mounted) {
        setState(() {
          _isLoadingOutgoing = false;
        });
      }
    }
  }

  Future<void> _loadOutgoingUpdatesCount() async {
    if (_employeeId == null) return;

    try {
      final requests = await ShiftTransferService.getOutgoingRequests(_employeeId!);
      final updatesCount = requests.where((r) =>
        r.status == ShiftTransferStatus.approved ||
        r.status == ShiftTransferStatus.rejected ||
        r.status == ShiftTransferStatus.declined
      ).length;

      if (mounted) {
        setState(() {
          _outgoingUpdatesCount = updatesCount;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика исходящих', e);
    }
  }

  Future<void> _selectMonth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Выберите месяц',
      initialDatePickerMode: DatePickerMode.year,
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
      });
      await _loadSchedule();
    }
  }

  String _getShiftTimeRange(WorkScheduleEntry entry) {
    final shopTimes = _shiftTimes[entry.shopAddress];
    if (shopTimes != null) {
      final timeInfo = shopTimes[entry.shiftType];
      if (timeInfo != null) {
        return timeInfo.timeRange;
      }
    }
    return entry.shiftType.timeRange;
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
                padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 0),
                child: Row(
                  children: [
                    _buildAppBarButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Мой график',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    _buildAppBarButton(
                      icon: Icons.calendar_today,
                      onTap: _selectMonth,
                    ),
                    SizedBox(width: 8),
                    _buildAppBarButton(
                      icon: Icons.refresh,
                      onTap: () {
                        _loadSchedule();
                        if (_tabController.index == 1) _loadNotifications();
                      },
                    ),
                  ],
                ),
              ),
              // Tabs
              Padding(
                padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 8.h),
                child: Column(
                  children: [
                    // Верхний ряд - 3 вкладки
                    Row(
                      children: [
                        Expanded(child: _buildTabButton(0, Icons.calendar_month, 'Расписание', null)),
                        SizedBox(width: 6),
                        Expanded(child: _buildTabButton(1, Icons.notifications, 'Входящие', _unreadCount > 0 ? _unreadCount : null, Colors.red)),
                        SizedBox(width: 6),
                        Expanded(child: _buildTabButton(2, Icons.send, 'Заявки', _outgoingUpdatesCount > 0 ? _outgoingUpdatesCount : null, Colors.green)),
                      ],
                    ),
                    SizedBox(height: 6),
                    // Нижний ряд - 2 вкладки
                    Row(
                      children: [
                        Expanded(child: _buildTabButton(3, Icons.check_circle_outline, 'Отработал', null)),
                        SizedBox(width: 6),
                        Expanded(child: _buildTabButton(4, Icons.calendar_view_month, 'Общий', null)),
                      ],
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildScheduleTab(),
                    _buildNotificationsTab(),
                    _buildOutgoingRequestsTab(),
                    _buildWorkedTab(),
                    _buildGeneralScheduleTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBarButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.8), size: 20),
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label, int? badge, [Color? badgeColor]) {
    final isSelected = _tabController.index == index;
    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() {});
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.gold.withOpacity(0.2) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isSelected ? AppColors.gold.withOpacity(0.5) : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.5)),
            SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.6),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null) ...[
              SizedBox(width: 4),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
                decoration: BoxDecoration(
                  color: badgeColor ?? Colors.red,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(fontSize: 10.sp, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleTab() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.gold, strokeWidth: 3),
            SizedBox(height: 20),
            Text('Загрузка графика...', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ],
        ),
      );
    }
    if (_error != null) {
      return _buildErrorState(_error!, _loadEmployeeId);
    }
    if (_schedule == null) {
      return _buildEmptyState(
        Icons.calendar_today,
        'График не загружен',
        'Нажмите "Обновить" для загрузки',
        _loadSchedule,
      );
    }
    // Проверяем только будущие смены (прошедшие во вкладке "Отработал")
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final futureEntries = _schedule!.entries
        .where((e) => !DateTime(e.date.year, e.date.month, e.date.day).isBefore(today))
        .toList();

    if (futureEntries.isEmpty) {
      return _buildEmptyState(
        Icons.event_busy,
        'Нет предстоящих смен',
        'Прошедшие смены можно посмотреть во вкладке "Отработал"',
        _loadSchedule,
      );
    }
    return _buildCalendarView();
  }

  Widget _buildErrorState(String error, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 56, color: Colors.red[400]),
            ),
            SizedBox(height: 20),
            Text(
              'Ошибка',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9)),
            ),
            SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
            SizedBox(height: 24),
            _buildGradientButton('Повторить', Icons.refresh, onRetry),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle, VoidCallback onAction) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                color: AppColors.emerald.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 56, color: Colors.white.withOpacity(0.4)),
            ),
            SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9)),
            ),
            SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
            SizedBox(height: 24),
            _buildGradientButton('Обновить', Icons.refresh, onAction),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientButton(String label, IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.emerald,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
        ),
      ),
    );
  }

  Widget _buildCalendarView() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Фильтруем: показываем только сегодняшние и будущие смены
    // Прошедшие смены переносятся во вкладку "Отработал"
    final entriesWithDates = _schedule!.entries
        .where((e) => !DateTime(e.date.year, e.date.month, e.date.day).isBefore(today))
        .toList();
    entriesWithDates.sort((a, b) => a.date.compareTo(b.date));

    return Column(
      children: [
        // Заголовок с месяцем
        Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
                    style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.95)),
                  ),
                  if (_employeeName != null)
                    Text(
                      _employeeName!,
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14.sp),
                    ),
                ],
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                ),
                child: Text(
                  '${entriesWithDates.length} смен',
                  style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 13.sp),
                ),
              ),
            ],
          ),
        ),
        // Список смен
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            itemCount: entriesWithDates.length,
            itemBuilder: (context, index) {
              final entry = entriesWithDates[index];
              return _buildShiftCard(entry);
            },
          ),
        ),
        // Статистика
        _buildStatisticsBar(),
        // Кнопка "Передать смену"
        _buildTransferButton(),
      ],
    );
  }

  Widget _buildShiftCard(WorkScheduleEntry entry) {
    final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
    final isToday = day.year == DateTime.now().year &&
        day.month == DateTime.now().month &&
        day.day == DateTime.now().day;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isToday ? AppColors.gold.withOpacity(0.6) : Colors.white.withOpacity(0.1),
          width: isToday ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Row(
          children: [
            // Дата
            Container(
              width: 56,
              height: 66,
              decoration: BoxDecoration(
                color: isToday
                    ? AppColors.gold.withOpacity(0.2)
                    : entry.shiftType.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12.r),
                border: isToday
                    ? Border.all(color: AppColors.gold.withOpacity(0.4))
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.bold,
                      color: isToday ? AppColors.gold : entry.shiftType.color,
                    ),
                  ),
                  Text(
                    _getWeekdayShort(day.weekday),
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: isToday ? AppColors.gold.withOpacity(0.7) : entry.shiftType.color.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 14),
            // Информация о смене
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                        decoration: BoxDecoration(
                          color: entry.shiftType.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time, size: 14, color: entry.shiftType.color),
                            SizedBox(width: 4),
                            Text(
                              entry.shiftType.label,
                              style: TextStyle(
                                color: entry.shiftType.color,
                                fontWeight: FontWeight.w600,
                                fontSize: 13.sp,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        _getShiftTimeRange(entry),
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.store, size: 16, color: Colors.white.withOpacity(0.4)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.shopAddress,
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13.sp),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Индикатор
            if (isToday)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                ),
                child: Text(
                  'Сегодня',
                  style: TextStyle(color: AppColors.gold, fontSize: 11.sp, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsBar() {
    // Фильтруем только будущие смены для статистики
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final futureEntries = _schedule!.entries
        .where((e) => !DateTime(e.date.year, e.date.month, e.date.day).isBefore(today))
        .toList();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatChip('Всего', '${futureEntries.length}', AppColors.gold),
          _buildStatChip('Утро', '${futureEntries.where((e) => e.shiftType == ShiftType.morning).length}', ShiftType.morning.color),
          _buildStatChip('День', '${futureEntries.where((e) => e.shiftType == ShiftType.day).length}', ShiftType.day.color),
          _buildStatChip('Вечер', '${futureEntries.where((e) => e.shiftType == ShiftType.evening).length}', ShiftType.evening.color),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
        ),
      ],
    );
  }

  Widget _buildTransferButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 12.h),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFF6B35), Color(0xFFF7C200)],
          ),
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Color(0xFFFF6B35).withOpacity(0.3),
              blurRadius: 15,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _showSwapDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: EdgeInsets.symmetric(vertical: 16.h),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.swap_horiz, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Text(
                'Передать смену',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16.sp,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationsTab() {
    if (_isLoadingNotifications) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 3),
      );
    }

    if (_notifications.isEmpty) {
      return _buildEmptyState(
        Icons.notifications_off,
        'Нет входящих запросов',
        'Здесь появятся запросы на передачу смен от других сотрудников',
        _loadNotifications,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      color: AppColors.gold,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final request = _notifications[index];
          return _buildNotificationCard(request);
        },
      ),
    );
  }

  Widget _buildOutgoingRequestsTab() {
    if (_isLoadingOutgoing) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 3),
      );
    }

    if (_outgoingRequests.isEmpty) {
      return _buildEmptyState(
        Icons.send_outlined,
        'Нет отправленных заявок',
        'Здесь будут отображаться ваши заявки на передачу смен',
        _loadOutgoingRequests,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOutgoingRequests,
      color: AppColors.gold,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: _outgoingRequests.length,
        itemBuilder: (context, index) {
          final request = _outgoingRequests[index];
          return _buildOutgoingRequestCard(request);
        },
      ),
    );
  }

  Widget _buildOutgoingRequestCard(ShiftTransferRequest request) {
    final shiftDate = request.shiftDate;

    IconData statusIcon;
    String statusText;
    List<Color> statusGradient;

    switch (request.status) {
      case ShiftTransferStatus.pending:
        statusIcon = Icons.hourglass_empty;
        statusText = 'Ожидает ответа';
        statusGradient = [Colors.orange, Colors.amber];
        break;
      case ShiftTransferStatus.hasAcceptances:
        statusIcon = Icons.people;
        statusText = 'Есть принявшие (${request.acceptedBy.length})';
        statusGradient = [Colors.blue, Colors.lightBlue];
        break;
      case ShiftTransferStatus.accepted:
        statusIcon = Icons.schedule;
        statusText = 'Ожидает одобрения админа';
        statusGradient = [Colors.blue, Colors.lightBlue];
        break;
      case ShiftTransferStatus.approved:
        statusIcon = Icons.check_circle;
        statusText = 'Одобрено! Смена передана';
        statusGradient = [Color(0xFF00b09b), Color(0xFF96c93d)];
        break;
      case ShiftTransferStatus.rejected:
        statusIcon = Icons.cancel;
        statusText = 'Отклонено сотрудником';
        statusGradient = [Colors.red, Colors.redAccent];
        break;
      case ShiftTransferStatus.declined:
        statusIcon = Icons.block;
        statusText = 'Отклонено администратором';
        statusGradient = [Colors.red[700]!, Colors.red];
        break;
      case ShiftTransferStatus.expired:
        statusIcon = Icons.timer_off;
        statusText = 'Истёк срок';
        statusGradient = [Colors.grey, Colors.blueGrey];
        break;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: request.status == ShiftTransferStatus.approved
              ? Colors.green.withOpacity(0.5)
              : request.status == ShiftTransferStatus.declined || request.status == ShiftTransferStatus.rejected
                  ? Colors.red.withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
          width: request.status == ShiftTransferStatus.approved ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Статус
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: statusGradient),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            // Информация
            _buildInfoRow(Icons.calendar_today, 'Дата', '${shiftDate.day} ${_getMonthName(shiftDate.month)} ${shiftDate.year}'),
            SizedBox(height: 10),
            _buildInfoRow(Icons.access_time, 'Смена', request.shiftType.label),
            SizedBox(height: 10),
            _buildInfoRow(Icons.store, 'Магазин', request.shopName.isNotEmpty ? request.shopName : request.shopAddress),
            SizedBox(height: 10),
            _buildInfoRow(Icons.person_outline, 'Кому', request.isBroadcast ? 'Всем сотрудникам' : request.toEmployeeName ?? 'Неизвестно'),
            if (request.acceptedByEmployeeName != null) ...[
              SizedBox(height: 10),
              _buildInfoRow(Icons.person, 'Принял', request.acceptedByEmployeeName!),
            ],
            if (request.comment != null && request.comment!.isNotEmpty) ...[
              SizedBox(height: 10),
              _buildInfoRow(Icons.comment, 'Комментарий', request.comment!),
            ],
            SizedBox(height: 12),
            Text(
              'Отправлено: ${_formatDateTime(request.createdAt)}',
              style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.4)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildNotificationCard(ShiftTransferRequest request) {
    final isUnread = !request.isReadByRecipient;
    final shiftDate = request.shiftDate;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isUnread ? Colors.orange.withOpacity(0.5) : Colors.white.withOpacity(0.1),
          width: isUnread ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Row(
              children: [
                if (isUnread)
                  Container(
                    width: 12,
                    height: 12,
                    margin: EdgeInsets.only(right: 10.w),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: AppColors.emerald,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: Colors.white.withOpacity(0.15)),
                  ),
                  child: Icon(Icons.swap_horiz, color: Colors.white, size: 20),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.isBroadcast ? 'Запрос на передачу смены' : 'Запрос на передачу смены вам',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.sp, color: Colors.white.withOpacity(0.9)),
                      ),
                      Text(
                        'от ${request.fromEmployeeName}',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Divider(height: 24, color: Colors.white.withOpacity(0.1)),
            // Информация
            _buildInfoRow(Icons.calendar_today, 'Дата', '${shiftDate.day} ${_getMonthName(shiftDate.month)} ${shiftDate.year}'),
            SizedBox(height: 10),
            _buildInfoRow(Icons.access_time, 'Смена', request.shiftType.label),
            SizedBox(height: 10),
            _buildInfoRow(Icons.store, 'Магазин', request.shopName.isNotEmpty ? request.shopName : request.shopAddress),
            if (request.comment != null && request.comment!.isNotEmpty) ...[
              SizedBox(height: 10),
              _buildInfoRow(Icons.comment, 'Комментарий', request.comment!),
            ],
            SizedBox(height: 16),
            // Показываем сколько человек уже приняли (если есть)
            if (request.acceptedBy.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                margin: EdgeInsets.only(bottom: 12.h),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people, size: 16, color: Colors.orange[300]),
                    SizedBox(width: 8),
                    Text(
                      'Уже приняли: ${request.acceptedBy.length} чел.',
                      style: TextStyle(
                        color: Colors.orange[300],
                        fontWeight: FontWeight.w500,
                        fontSize: 13.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Кнопки - показываем если запрос активен (pending или has_acceptances)
            if (request.isActive)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rejectRequest(request),
                      icon: Icon(Icons.close, size: 18),
                      label: Text('Отклонить'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[300],
                        side: BorderSide(color: Colors.red.withOpacity(0.5)),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.emerald,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _acceptRequest(request),
                        icon: Icon(Icons.check, color: Colors.white, size: 18),
                        label: Text('Принять', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: request.status == ShiftTransferStatus.accepted
                      ? Colors.orange.withOpacity(0.15)
                      : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  request.status.label,
                  style: TextStyle(
                    color: request.status == ShiftTransferStatus.accepted
                        ? Colors.orange[300]
                        : Colors.white.withOpacity(0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(6.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(icon, size: 16, color: Colors.white.withOpacity(0.5)),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.sp)),
              Text(value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.9))),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _acceptRequest(ShiftTransferRequest request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => _buildConfirmDialog(
        title: 'Принять смену?',
        content: 'Вы хотите принять смену от ${request.fromEmployeeName} '
            'на ${request.shiftDate.day} ${_getMonthName(request.shiftDate.month)}?\n\n'
            'После принятия запрос будет отправлен администратору на одобрение.',
        confirmText: 'Принять',
        confirmColor: AppColors.emerald,
      ),
    );

    if (confirm != true) return;

    final success = await ShiftTransferService.acceptRequest(
      request.id,
      _employeeId!,
      _employeeName!,
    );

    if (!mounted) return;

    if (success) {
      _showSuccessSnackBar('Запрос принят! Ожидает одобрения администратора.');
      await _loadNotifications();
    } else {
      _showErrorSnackBar('Ошибка при принятии запроса');
    }
  }

  Future<void> _rejectRequest(ShiftTransferRequest request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => _buildConfirmDialog(
        title: 'Отклонить запрос?',
        content: 'Вы уверены, что хотите отклонить запрос на передачу смены от ${request.fromEmployeeName}?',
        confirmText: 'Отклонить',
        confirmColor: Colors.red,
      ),
    );

    if (confirm != true) return;

    final success = await ShiftTransferService.rejectRequest(
      request.id,
      employeeId: _employeeId,
      employeeName: _employeeName,
    );

    if (!mounted) return;

    if (success) {
      _showSuccessSnackBar('Запрос отклонён');
      await _loadNotifications();
    } else {
      _showErrorSnackBar('Ошибка при отклонении запроса');
    }
  }

  Widget _buildConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    required Color confirmColor,
  }) {
    return AlertDialog(
      backgroundColor: AppColors.emeraldDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      title: Text(title, style: TextStyle(color: Colors.white.withOpacity(0.9))),
      content: Text(content, style: TextStyle(color: Colors.white.withOpacity(0.7))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        ),
        Container(
          decoration: BoxDecoration(
            color: confirmColor,
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
            ),
            child: Text(confirmText, style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        margin: EdgeInsets.all(16.w),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        margin: EdgeInsets.all(16.w),
      ),
    );
  }

  Future<void> _showSwapDialog() async {
    if (_schedule == null || _schedule!.entries.isEmpty) {
      _showErrorSnackBar('У вас нет смен для передачи');
      return;
    }

    final selectedEntry = await showDialog<WorkScheduleEntry>(
      context: context,
      builder: (context) => _ShiftSelectionDialog(
        entries: _schedule!.entries,
        shiftTimes: _shiftTimes,
      ),
    );

    if (selectedEntry == null) return;

    await _showRecipientSelectionDialog(selectedEntry);
  }

  Future<void> _showRecipientSelectionDialog(WorkScheduleEntry entry) async {
    final employees = await EmployeeService.getEmployees();
    final shops = await ShopService.getShops();

    Logger.debug('Загружено сотрудников с API: ${employees.length}');
    Logger.debug('Текущий сотрудник ID: $_employeeId');

    String shopName = entry.shopAddress;
    try {
      final shop = shops.firstWhere((s) => s.address == entry.shopAddress);
      shopName = shop.name;
    } catch (e) {
      // Магазин не найден
    }

    final otherEmployees = employees.where((e) => e.id != _employeeId).toList();
    Logger.debug('Сотрудников после фильтрации (без себя): ${otherEmployees.length}');

    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _RecipientSelectionDialog(
        entry: entry,
        employees: otherEmployees,
        shopName: shopName,
        shiftTimeRange: _getShiftTimeRange(entry),
      ),
    );

    if (result == null) return;

    final request = ShiftTransferRequest(
      id: '',
      fromEmployeeId: _employeeId!,
      fromEmployeeName: _employeeName!,
      toEmployeeId: result['toEmployeeId'],
      toEmployeeName: result['toEmployeeName'],
      scheduleEntryId: entry.id,
      shiftDate: entry.date,
      shopAddress: entry.shopAddress,
      shopName: shopName,
      shiftType: entry.shiftType,
      comment: result['comment'],
      createdAt: DateTime.now(),
    );

    final success = await ShiftTransferService.createRequest(request);

    if (!mounted) return;

    if (success) {
      _showSuccessSnackBar(
        result['toEmployeeId'] == null
            ? 'Запрос отправлен всем сотрудникам'
            : 'Запрос отправлен ${result['toEmployeeName']}',
      );
    } else {
      _showErrorSnackBar('Ошибка при создании запроса');
    }
  }

  String _getMonthName(int month) {
    final months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
    ];
    return months[month - 1];
  }

  String _getWeekdayShort(int weekday) {
    final weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return weekdays[weekday - 1];
  }

  // ============== Вкладка "Отработал" ==============

  Future<void> _loadWorkedHistory() async {
    if (_employeeId == null || _employeeName == null) return;
    if (_isLoadingWorked) return;

    setState(() => _isLoadingWorked = true);

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Получаем прошедшие смены из текущего расписания
      final pastEntries = _schedule?.entries
          .where((e) => DateTime(e.date.year, e.date.month, e.date.day).isBefore(today))
          .toList() ?? [];

      // Сортируем: ближайшие первыми (по убыванию даты)
      pastEntries.sort((a, b) => b.date.compareTo(a.date));

      // Собираем уникальные комбинации магазин+дата для запросов
      final uniqueRequests = <String, MapEntry<String, DateTime>>{};
      for (final entry in pastEntries) {
        final key = '${entry.shopAddress}_${entry.date.toIso8601String().split('T')[0]}';
        uniqueRequests[key] = MapEntry(entry.shopAddress, entry.date);
      }

      // Загружаем KPI данные параллельно
      final kpiCache = <String, KPIShopDayData>{};
      final futures = uniqueRequests.entries.map((e) async {
        try {
          final kpi = await KPIService.getShopDayData(e.value.key, e.value.value);
          kpiCache[e.key] = kpi;
        } catch (_) {
          // Игнорируем ошибки отдельных запросов
        }
      });
      await Future.wait(futures);

      // Формируем результат
      final worked = <_WorkedShiftInfo>[];
      for (final entry in pastEntries) {
        final key = '${entry.shopAddress}_${entry.date.toIso8601String().split('T')[0]}';
        final kpiData = kpiCache[key];

        // Ищем данные для текущего сотрудника
        KPIDayData? employeeKpi;
        if (kpiData != null) {
          try {
            employeeKpi = kpiData.employeesData.firstWhere(
              (e) => e.employeeName == _employeeName,
            );
          } catch (_) {
            employeeKpi = null;
          }
        }

        // Определяем, отработана ли смена
        final wasWorked = employeeKpi != null && (
            employeeKpi.attendanceTime != null ||
            employeeKpi.hasShift ||
            employeeKpi.hasShiftHandover
        );

        String? details;
        if (employeeKpi != null) {
          if (employeeKpi.attendanceTime != null) {
            final time = employeeKpi.attendanceTime!;
            details = 'Отметился в ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          } else if (employeeKpi.hasShift) {
            details = 'Прошёл пересменку';
          } else if (employeeKpi.hasShiftHandover) {
            details = 'Сдал смену';
          }
        }

        worked.add(_WorkedShiftInfo(
          entry: entry,
          wasWorked: wasWorked,
          details: details,
        ));
      }

      if (mounted) {
        setState(() {
          _workedShifts = worked;
          _isLoadingWorked = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки истории работы', e);
      if (mounted) {
        setState(() => _isLoadingWorked = false);
      }
    }
  }

  Widget _buildWorkedTab() {
    if (_isLoadingWorked) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 3),
      );
    }

    if (_workedShifts.isEmpty) {
      return _buildEmptyState(
        Icons.history,
        'Нет прошедших смен',
        'Здесь появятся смены, которые уже прошли',
        _loadWorkedHistory,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadWorkedHistory,
      color: AppColors.gold,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: _workedShifts.length,
        itemBuilder: (context, index) {
          final item = _workedShifts[index];
          return _buildWorkedShiftCard(item);
        },
      ),
    );
  }

  Widget _buildWorkedShiftCard(_WorkedShiftInfo item) {
    final day = item.entry.date;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: item.wasWorked ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Row(
          children: [
            // Дата
            Container(
              width: 56,
              height: 66,
              decoration: BoxDecoration(
                color: (item.wasWorked ? Colors.green : Colors.red).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.bold,
                      color: item.wasWorked ? Colors.green[400] : Colors.red[400],
                    ),
                  ),
                  Text(
                    _getWeekdayShort(day.weekday),
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: (item.wasWorked ? Colors.green : Colors.red).withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 14),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                        decoration: BoxDecoration(
                          color: item.entry.shiftType.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Text(
                          item.entry.shiftType.label,
                          style: TextStyle(
                            color: item.entry.shiftType.color,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.store, size: 16, color: Colors.white.withOpacity(0.4)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.entry.shopAddress,
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13.sp),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (item.details != null) ...[
                    SizedBox(height: 4),
                    Text(
                      item.details!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12.sp,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Галочка/Крестик
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (item.wasWorked ? Colors.green : Colors.red).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                item.wasWorked ? Icons.check : Icons.close,
                color: item.wasWorked ? Colors.green[400] : Colors.red[400],
                size: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============== Вкладка "Общий" ==============

  Future<void> _loadGeneralSchedule() async {
    Logger.debug('_loadGeneralSchedule вызван, _isLoadingGeneral=$_isLoadingGeneral');
    if (_isLoadingGeneral) return;

    setState(() => _isLoadingGeneral = true);

    try {
      Logger.debug('Загрузка общего графика на месяц: $_selectedMonth');
      final schedule = await WorkScheduleService.getSchedule(_selectedMonth);
      Logger.debug('Общий график загружен: ${schedule.entries.length} записей');

      final shops = await Shop.loadShopsFromServer();
      Logger.debug('Магазины загружены: ${shops.length}');

      if (mounted) {
        setState(() {
          _generalSchedule = schedule;
          _isLoadingGeneral = false;
        });
        Logger.debug('Состояние обновлено, _generalSchedule записей: ${_generalSchedule?.entries.length}');
      }
    } catch (e) {
      Logger.error('Ошибка загрузки общего графика', e);
      if (mounted) {
        setState(() => _isLoadingGeneral = false);
      }
    }
  }

  Widget _buildGeneralScheduleTab() {
    if (_isLoadingGeneral) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 3),
      );
    }

    if (_generalSchedule == null || _generalSchedule!.entries.isEmpty) {
      return _buildEmptyState(
        Icons.calendar_view_month,
        'График не загружен',
        'Общий график работы за ${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
        _loadGeneralSchedule,
      );
    }

    // Группируем по дням
    final entriesByDate = <DateTime, List<WorkScheduleEntry>>{};
    for (final entry in _generalSchedule!.entries) {
      final dateKey = DateTime(entry.date.year, entry.date.month, entry.date.day);
      entriesByDate.putIfAbsent(dateKey, () => []).add(entry);
    }

    final sortedDates = entriesByDate.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _loadGeneralSchedule,
      color: AppColors.gold,
      child: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: sortedDates.length,
        itemBuilder: (context, index) {
          final date = sortedDates[index];
          final entries = entriesByDate[date]!;
          return _buildGeneralDayCard(date, entries);
        },
      ),
    );
  }

  Widget _buildGeneralDayCard(DateTime date, List<WorkScheduleEntry> entries) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;

    // Группируем по магазинам
    final byShop = <String, List<WorkScheduleEntry>>{};
    for (final e in entries) {
      byShop.putIfAbsent(e.shopAddress, () => []).add(e);
    }

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isToday ? AppColors.gold.withOpacity(0.5) : Colors.white.withOpacity(0.1),
          width: isToday ? 1.5 : 1,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          expansionTileTheme: ExpansionTileThemeData(
            iconColor: Colors.white.withOpacity(0.6),
            collapsedIconColor: Colors.white.withOpacity(0.4),
          ),
        ),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 14.w),
          title: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isToday ? AppColors.gold.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12.r),
                  border: isToday ? Border.all(color: AppColors.gold.withOpacity(0.4)) : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17.sp,
                        color: isToday ? AppColors.gold : Colors.white.withOpacity(0.9),
                      ),
                    ),
                    Text(
                      _getWeekdayShort(date.weekday),
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: isToday ? AppColors.gold.withOpacity(0.7) : Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${date.day} ${_getMonthName(date.month)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9)),
                    ),
                    Text(
                      '${entries.length} сотр. в ${byShop.length} маг.',
                      style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
                    ),
                  ],
                ),
              ),
              if (isToday)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                  ),
                  child: Text(
                    'Сегодня',
                    style: TextStyle(color: AppColors.gold, fontSize: 11.sp, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          children: [
            for (final shopAddress in byShop.keys)
              _buildShopSection(shopAddress, byShop[shopAddress]!),
          ],
        ),
      ),
    );
  }

  Widget _buildShopSection(String shopAddress, List<WorkScheduleEntry> entries) {
    // Сортируем по типу смены
    final sortedEntries = List<WorkScheduleEntry>.from(entries)
      ..sort((a, b) => a.shiftType.index.compareTo(b.shiftType.index));

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.store, size: 16, color: Colors.white.withOpacity(0.4)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  shopAddress,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13.sp,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: sortedEntries.map((e) => Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: e.shiftType.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.employeeName,
                    style: TextStyle(fontSize: 12.sp, color: e.shiftType.color),
                  ),
                  SizedBox(width: 6),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: e.shiftType.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                    child: Text(
                      e.shiftType.label.isNotEmpty ? e.shiftType.label.substring(0, 1) : '?',
                      style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.bold,
                        color: e.shiftType.color,
                      ),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

/// Модель данных для вкладки "Отработал"
class _WorkedShiftInfo {
  final WorkScheduleEntry entry;
  final bool wasWorked;
  final String? details;

  _WorkedShiftInfo({
    required this.entry,
    required this.wasWorked,
    this.details,
  });
}

/// Диалог выбора смены для передачи
class _ShiftSelectionDialog extends StatelessWidget {
  final List<WorkScheduleEntry> entries;
  final Map<String, Map<ShiftType, ShiftTimeInfo>> shiftTimes;

  const _ShiftSelectionDialog({
    required this.entries,
    required this.shiftTimes,
  });

  String _getShiftTimeRange(WorkScheduleEntry entry) {
    final shopTimes = shiftTimes[entry.shopAddress];
    if (shopTimes != null) {
      final timeInfo = shopTimes[entry.shiftType];
      if (timeInfo != null) {
        return timeInfo.timeRange;
      }
    }
    return entry.shiftType.timeRange;
  }

  String _getMonthName(int month) {
    final months = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
    return months[month - 1];
  }

  String _getWeekdayShort(int weekday) {
    final weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return weekdays[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final sortedEntries = List<WorkScheduleEntry>.from(entries)
      ..sort((a, b) => a.date.compareTo(b.date));

    final now = DateTime.now();
    final futureEntries = sortedEntries.where((e) =>
      e.date.isAfter(now) ||
      (e.date.year == now.year && e.date.month == now.month && e.date.day == now.day)
    ).toList();

    return Dialog(
      backgroundColor: AppColors.night,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.4, 1.0],
          ),
          borderRadius: BorderRadius.circular(24.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Padding(
              padding: EdgeInsets.all(20.w),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Icon(Icons.swap_horiz, color: Colors.white, size: 24),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Выберите смену',
                          style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 18.sp, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'для передачи другому сотруднику',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Icon(Icons.close, color: Colors.white.withOpacity(0.7), size: 20),
                    ),
                  ),
                ],
              ),
            ),
            // Список
            Flexible(
              child: futureEntries.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(40.w),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_busy, size: 56, color: Colors.white.withOpacity(0.3)),
                          SizedBox(height: 16),
                          Text(
                            'Нет доступных смен',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16.sp),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                      shrinkWrap: true,
                      itemCount: futureEntries.length,
                      itemBuilder: (context, index) {
                        final entry = futureEntries[index];
                        final day = entry.date;

                        return GestureDetector(
                          onTap: () => Navigator.pop(context, entry),
                          child: Container(
                            margin: EdgeInsets.only(bottom: 10.h),
                            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: entry.shiftType.color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${day.day}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17.sp,
                                          color: entry.shiftType.color,
                                        ),
                                      ),
                                      Text(
                                        _getWeekdayShort(day.weekday),
                                        style: TextStyle(fontSize: 10.sp, color: entry.shiftType.color),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${day.day} ${_getMonthName(day.month)}',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9)),
                                      ),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                                            decoration: BoxDecoration(
                                              color: entry.shiftType.color.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(6.r),
                                            ),
                                            child: Text(
                                              entry.shiftType.label,
                                              style: TextStyle(color: entry.shiftType.color, fontSize: 12.sp),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            _getShiftTimeRange(entry),
                                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.sp),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.all(8.w),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                  child: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.5)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Диалог выбора получателя
class _RecipientSelectionDialog extends StatefulWidget {
  final WorkScheduleEntry entry;
  final List<Employee> employees;
  final String shopName;
  final String shiftTimeRange;

  const _RecipientSelectionDialog({
    required this.entry,
    required this.employees,
    required this.shopName,
    required this.shiftTimeRange,
  });

  @override
  State<_RecipientSelectionDialog> createState() => _RecipientSelectionDialogState();
}

class _RecipientSelectionDialogState extends State<_RecipientSelectionDialog> {
  String? _selectedEmployeeId;
  String? _selectedEmployeeName;
  bool _sendToAll = false;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String _getMonthName(int month) {
    final months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.entry.date;

    return Dialog(
      backgroundColor: AppColors.night,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
          borderRadius: BorderRadius.circular(24.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Padding(
              padding: EdgeInsets.all(20.w),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: Icon(Icons.person_add, color: Colors.white, size: 24),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Кому передать смену?',
                          style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 18.sp, fontWeight: FontWeight.bold),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10.r),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Icon(Icons.close, color: Colors.white.withOpacity(0.7), size: 20),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  // Информация о смене
                  Container(
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14.r),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${day.day}',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18.sp),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${day.day} ${_getMonthName(day.month)} ${day.year}',
                                style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '${widget.entry.shiftType.label} (${widget.shiftTimeRange})',
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
                              ),
                              Text(
                                widget.shopName,
                                style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.sp),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Контент
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Кнопка "Отправить всем"
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _sendToAll = true;
                          _selectedEmployeeId = null;
                          _selectedEmployeeName = null;
                        });
                      },
                      child: Container(
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: _sendToAll ? AppColors.gold.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14.r),
                          border: Border.all(
                            color: _sendToAll ? AppColors.gold.withOpacity(0.5) : Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(10.w),
                              decoration: BoxDecoration(
                                color: _sendToAll ? AppColors.gold.withOpacity(0.2) : Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Icon(
                                Icons.campaign,
                                color: _sendToAll ? AppColors.gold : Colors.white.withOpacity(0.5),
                                size: 24,
                              ),
                            ),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Отправить всем',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _sendToAll ? AppColors.gold : Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                  Text(
                                    'Все сотрудники получат уведомление',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: _sendToAll ? AppColors.gold.withOpacity(0.7) : Colors.white.withOpacity(0.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_sendToAll)
                              Icon(Icons.check_circle, color: AppColors.gold),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    // Список сотрудников
                    Text(
                      'Или выберите сотрудника:',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.6)),
                    ),
                    SizedBox(height: 12),
                    Container(
                      constraints: BoxConstraints(maxHeight: 250),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14.r),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.symmetric(vertical: 8.h),
                        itemCount: widget.employees.length,
                        itemBuilder: (context, index) {
                          final employee = widget.employees[index];
                          final isSelected = _selectedEmployeeId == employee.id && !_sendToAll;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _sendToAll = false;
                                _selectedEmployeeId = employee.id;
                                _selectedEmployeeName = employee.name;
                              });
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                              margin: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.emerald.withOpacity(0.4) : Colors.transparent,
                                borderRadius: BorderRadius.circular(10.r),
                                border: isSelected ? Border.all(color: AppColors.emerald) : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppColors.emerald : Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10.r),
                                    ),
                                    child: Center(
                                      child: Text(
                                        employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          employee.name,
                                          style: TextStyle(
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            color: isSelected ? Colors.white : Colors.white.withOpacity(0.8),
                                          ),
                                        ),
                                        if (employee.phone != null)
                                          Text(
                                            employee.phone!,
                                            style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.4)),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(Icons.check_circle, color: AppColors.gold, size: 22),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(height: 20),
                    // Комментарий
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14.r),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: TextField(
                        controller: _commentController,
                        style: TextStyle(color: Colors.white.withOpacity(0.9)),
                        cursorColor: Colors.white,
                        decoration: InputDecoration(
                          labelText: 'Комментарий (необязательно)',
                          labelStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                          hintText: 'Причина передачи смены...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16.w),
                          prefixIcon: Icon(Icons.comment, color: Colors.white.withOpacity(0.3)),
                        ),
                        maxLines: 2,
                      ),
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            // Кнопки
            Container(
              padding: EdgeInsets.all(20.w),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Text('Отмена', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: (_sendToAll || _selectedEmployeeId != null) ? AppColors.emerald : Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: (_sendToAll || _selectedEmployeeId != null)
                              ? Colors.white.withOpacity(0.15)
                              : Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: (_sendToAll || _selectedEmployeeId != null)
                            ? () {
                                Navigator.pop(context, {
                                  'toEmployeeId': _sendToAll ? null : _selectedEmployeeId,
                                  'toEmployeeName': _sendToAll ? null : _selectedEmployeeName,
                                  'comment': _commentController.text.isEmpty ? null : _commentController.text,
                                });
                              }
                            : null,
                        icon: Icon(Icons.send, color: Colors.white),
                        label: Text('Отправить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          disabledBackgroundColor: Colors.transparent,
                          disabledForegroundColor: Colors.white.withOpacity(0.3),
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
