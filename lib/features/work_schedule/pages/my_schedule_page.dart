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

  // Цвета и градиенты
  static const _primaryColor = Color(0xFF004D40);
  static const _accentColor = Color(0xFF00897B);
  static const _gradientColors = [Color(0xFF004D40), Color(0xFF00796B)];

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
  List<Shop> _allShops = [];
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
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Мой график'),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectMonth,
            tooltip: 'Выбрать месяц',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadSchedule();
              if (_tabController.index == 1) {
                _loadNotifications();
              }
            },
            tooltip: 'Обновить',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Container(
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.9),
            ),
            child: Column(
              children: [
                // Верхний ряд - 3 вкладки
                Row(
                  children: [
                    Expanded(child: _buildTabButton(0, Icons.calendar_month, 'Расписание', null)),
                    Expanded(child: _buildTabButton(1, Icons.notifications, 'Входящие', _unreadCount > 0 ? _unreadCount : null, Colors.red)),
                    Expanded(child: _buildTabButton(2, Icons.send, 'Заявки', _outgoingUpdatesCount > 0 ? _outgoingUpdatesCount : null, Colors.green)),
                  ],
                ),
                // Нижний ряд - 2 вкладки
                Row(
                  children: [
                    Expanded(child: _buildTabButton(3, Icons.check_circle_outline, 'Отработал', null)),
                    Expanded(child: _buildTabButton(4, Icons.calendar_view_month, 'Общий', null)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildScheduleTab(),
          _buildNotificationsTab(),
          _buildOutgoingRequestsTab(),
          _buildWorkedTab(),
          _buildGeneralScheduleTab(),
        ],
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.white60),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? Colors.white : Colors.white60,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: badgeColor ?? Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text('Загрузка графика...', style: TextStyle(color: Colors.grey[600])),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, size: 56, color: Colors.red[400]),
            ),
            const SizedBox(height: 20),
            Text(
              'Ошибка',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800]),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            _buildGradientButton('Повторить', Icons.refresh, onRetry),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle, VoidCallback onAction) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_primaryColor.withOpacity(0.1), _accentColor.withOpacity(0.05)],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 56, color: _primaryColor.withOpacity(0.5)),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[800]),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            _buildGradientButton('Обновить', Icons.refresh, onAction),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientButton(String label, IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: _gradientColors),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_primaryColor.withOpacity(0.1), Colors.transparent],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2D3436)),
                  ),
                  if (_employeeName != null)
                    Text(
                      _employeeName!,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: _gradientColors),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${entriesWithDates.length} смен',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        // Список смен
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isToday ? Border.all(color: _primaryColor, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Дата
            Container(
              width: 60,
              height: 70,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isToday
                      ? _gradientColors
                      : [entry.shiftType.color.withOpacity(0.2), entry.shiftType.color.withOpacity(0.1)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isToday ? Colors.white : entry.shiftType.color,
                    ),
                  ),
                  Text(
                    _getWeekdayShort(day.weekday),
                    style: TextStyle(
                      fontSize: 12,
                      color: isToday ? Colors.white70 : entry.shiftType.color.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Информация о смене
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: entry.shiftType.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time, size: 14, color: entry.shiftType.color),
                            const SizedBox(width: 4),
                            Text(
                              entry.shiftType.label,
                              style: TextStyle(
                                color: entry.shiftType.color,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getShiftTimeRange(entry),
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.store, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.shopAddress,
                          style: TextStyle(color: Colors.grey[700], fontSize: 13),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _primaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Сегодня',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
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
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatChip('Всего', '${futureEntries.length}', _primaryColor),
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
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildTransferButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B35), Color(0xFFF7C200)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6B35).withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _showSwapDialog,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.swap_horiz, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Text(
                'Передать смену',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.2), blurRadius: 20)],
              ),
              child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 3),
            ),
          ],
        ),
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
      color: _primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.2), blurRadius: 20)],
              ),
              child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 3),
            ),
          ],
        ),
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
      color: _primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
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

    Color statusColor;
    IconData statusIcon;
    String statusText;
    List<Color> statusGradient;

    switch (request.status) {
      case ShiftTransferStatus.pending:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Ожидает ответа';
        statusGradient = [Colors.orange, Colors.amber];
        break;
      case ShiftTransferStatus.hasAcceptances:
        statusColor = Colors.blue;
        statusIcon = Icons.people;
        statusText = 'Есть принявшие (${request.acceptedBy.length})';
        statusGradient = [Colors.blue, Colors.lightBlue];
        break;
      case ShiftTransferStatus.accepted:
        statusColor = Colors.blue;
        statusIcon = Icons.schedule;
        statusText = 'Ожидает одобрения админа';
        statusGradient = [Colors.blue, Colors.lightBlue];
        break;
      case ShiftTransferStatus.approved:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Одобрено! Смена передана';
        statusGradient = [const Color(0xFF00b09b), const Color(0xFF96c93d)];
        break;
      case ShiftTransferStatus.rejected:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Отклонено сотрудником';
        statusGradient = [Colors.red, Colors.redAccent];
        break;
      case ShiftTransferStatus.declined:
        statusColor = Colors.red;
        statusIcon = Icons.block;
        statusText = 'Отклонено администратором';
        statusGradient = [Colors.red[700]!, Colors.red];
        break;
      case ShiftTransferStatus.expired:
        statusColor = Colors.grey;
        statusIcon = Icons.timer_off;
        statusText = 'Истёк срок';
        statusGradient = [Colors.grey, Colors.blueGrey];
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: request.status == ShiftTransferStatus.approved
            ? Border.all(color: Colors.green, width: 2)
            : request.status == ShiftTransferStatus.declined || request.status == ShiftTransferStatus.rejected
                ? Border.all(color: Colors.red.withOpacity(0.5), width: 1)
                : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Статус
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: statusGradient),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusText,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Информация
            _buildInfoRow(Icons.calendar_today, 'Дата', '${shiftDate.day} ${_getMonthName(shiftDate.month)} ${shiftDate.year}'),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.access_time, 'Смена', request.shiftType.label),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.store, 'Магазин', request.shopName.isNotEmpty ? request.shopName : request.shopAddress),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.person_outline, 'Кому', request.isBroadcast ? 'Всем сотрудникам' : request.toEmployeeName ?? 'Неизвестно'),
            if (request.acceptedByEmployeeName != null) ...[
              const SizedBox(height: 10),
              _buildInfoRow(Icons.person, 'Принял', request.acceptedByEmployeeName!),
            ],
            if (request.comment != null && request.comment!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildInfoRow(Icons.comment, 'Комментарий', request.comment!),
            ],
            const SizedBox(height: 12),
            Text(
              'Отправлено: ${_formatDateTime(request.createdAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isUnread ? Border.all(color: Colors.orange, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isUnread ? 0.1 : 0.05),
            blurRadius: isUnread ? 15 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    margin: const EdgeInsets.only(right: 10),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: _gradientColors),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.swap_horiz, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.isBroadcast ? 'Запрос на передачу смены' : 'Запрос на передачу смены вам',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'от ${request.fromEmployeeName}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            // Информация
            _buildInfoRow(Icons.calendar_today, 'Дата', '${shiftDate.day} ${_getMonthName(shiftDate.month)} ${shiftDate.year}'),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.access_time, 'Смена', request.shiftType.label),
            const SizedBox(height: 10),
            _buildInfoRow(Icons.store, 'Магазин', request.shopName.isNotEmpty ? request.shopName : request.shopAddress),
            if (request.comment != null && request.comment!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildInfoRow(Icons.comment, 'Комментарий', request.comment!),
            ],
            const SizedBox(height: 16),
            // Показываем сколько человек уже приняли (если есть)
            if (request.acceptedBy.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people, size: 16, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Text(
                      'Уже приняли: ${request.acceptedBy.length} чел.',
                      style: TextStyle(
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
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
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Отклонить'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: _gradientColors),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _acceptRequest(request),
                        icon: const Icon(Icons.check, color: Colors.white, size: 18),
                        label: const Text('Принять', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: request.status == ShiftTransferStatus.accepted
                      ? Colors.orange.withOpacity(0.15)
                      : Colors.grey.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  request.status.label,
                  style: TextStyle(
                    color: request.status == ShiftTransferStatus.accepted ? Colors.orange[800] : Colors.grey[700],
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
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _primaryColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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
        confirmColor: _primaryColor,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Отмена', style: TextStyle(color: Colors.grey[600])),
        ),
        Container(
          decoration: BoxDecoration(
            color: confirmColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
            ),
            child: Text(confirmText, style: const TextStyle(color: Colors.white)),
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
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
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
    const months = [
      'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
    ];
    return months[month - 1];
  }

  String _getWeekdayShort(int weekday) {
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
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
      return const Center(
        child: CircularProgressIndicator(color: _primaryColor),
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
      color: _primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.wasWorked ? Colors.green.withOpacity(0.5) : Colors.red.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Дата
            Container(
              width: 60,
              height: 70,
              decoration: BoxDecoration(
                color: (item.wasWorked ? Colors.green : Colors.red).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: item.wasWorked ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                  Text(
                    _getWeekdayShort(day.weekday),
                    style: TextStyle(
                      fontSize: 12,
                      color: (item.wasWorked ? Colors.green : Colors.red).withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Информация
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: item.entry.shiftType.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.entry.shiftType.label,
                          style: TextStyle(
                            color: item.entry.shiftType.color,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.store, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.entry.shopAddress,
                          style: TextStyle(color: Colors.grey[700], fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (item.details != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.details!,
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
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
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item.wasWorked ? Icons.check : Icons.close,
                color: item.wasWorked ? Colors.green : Colors.red,
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
    Logger.debug('📅 _loadGeneralSchedule вызван, _isLoadingGeneral=$_isLoadingGeneral');
    if (_isLoadingGeneral) return;

    setState(() => _isLoadingGeneral = true);

    try {
      Logger.debug('📅 Загрузка общего графика на месяц: $_selectedMonth');
      final schedule = await WorkScheduleService.getSchedule(_selectedMonth);
      Logger.debug('📅 Общий график загружен: ${schedule.entries.length} записей');

      final shops = await Shop.loadShopsFromGoogleSheets();
      Logger.debug('📅 Магазины загружены: ${shops.length}');

      if (mounted) {
        setState(() {
          _generalSchedule = schedule;
          _allShops = shops;
          _isLoadingGeneral = false;
        });
        Logger.debug('📅 Состояние обновлено, _generalSchedule записей: ${_generalSchedule?.entries.length}');
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
      return const Center(
        child: CircularProgressIndicator(color: _primaryColor),
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
      color: _primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isToday ? Border.all(color: _primaryColor, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isToday ? _gradientColors : [Colors.grey[200]!, Colors.grey[100]!],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: isToday ? Colors.white : Colors.grey[700],
                      ),
                    ),
                    Text(
                      _getWeekdayShort(date.weekday),
                      style: TextStyle(
                        fontSize: 11,
                        color: isToday ? Colors.white70 : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${date.day} ${_getMonthName(date.month)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${entries.length} сотр. в ${byShop.length} маг.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (isToday)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Сегодня',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.store, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shopAddress,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: sortedEntries.map((e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: e.shiftType.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.employeeName,
                    style: TextStyle(fontSize: 12, color: e.shiftType.color),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: e.shiftType.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      e.shiftType.label.isNotEmpty ? e.shiftType.label.substring(0, 1) : '?',
                      style: TextStyle(
                        fontSize: 10,
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

  static const _primaryColor = Color(0xFF004D40);
  static const _gradientColors = [Color(0xFF004D40), Color(0xFF00796B)];

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
    const months = ['Янв', 'Фев', 'Мар', 'Апр', 'Май', 'Июн', 'Июл', 'Авг', 'Сен', 'Окт', 'Ноя', 'Дек'];
    return months[month - 1];
  }

  String _getWeekdayShort(int weekday) {
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: _gradientColors),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.swap_horiz, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Выберите смену',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'для передачи другому сотруднику',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Список
            Flexible(
              child: futureEntries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_busy, size: 56, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'Нет доступных смен',
                            style: TextStyle(color: Colors.grey[600], fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      shrinkWrap: true,
                      itemCount: futureEntries.length,
                      itemBuilder: (context, index) {
                        final entry = futureEntries[index];
                        final day = entry.date;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.withOpacity(0.2)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: entry.shiftType.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: entry.shiftType.color,
                                    ),
                                  ),
                                  Text(
                                    _getWeekdayShort(day.weekday),
                                    style: TextStyle(fontSize: 10, color: entry.shiftType.color),
                                  ),
                                ],
                              ),
                            ),
                            title: Text(
                              '${day.day} ${_getMonthName(day.month)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: entry.shiftType.color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    entry.shiftType.label,
                                    style: TextStyle(color: entry.shiftType.color, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getShiftTimeRange(entry),
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                ),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.chevron_right, color: _primaryColor),
                            ),
                            onTap: () => Navigator.pop(context, entry),
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

  static const _primaryColor = Color(0xFF004D40);
  static const _gradientColors = [Color(0xFF004D40), Color(0xFF00796B)];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  String _getMonthName(int month) {
    const months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.entry.date;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: _gradientColors),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.person_add, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Кому передать смену?',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Информация о смене
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${day.day}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${day.day} ${_getMonthName(day.month)} ${day.year}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${widget.entry.shiftType.label} (${widget.shiftTimeRange})',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                              Text(
                                widget.shopName,
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
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
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Кнопка "Отправить всем"
                    InkWell(
                      onTap: () {
                        setState(() {
                          _sendToAll = true;
                          _selectedEmployeeId = null;
                          _selectedEmployeeName = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: _sendToAll
                              ? const LinearGradient(colors: _gradientColors)
                              : null,
                          color: _sendToAll ? null : Colors.grey[100],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _sendToAll ? Colors.transparent : Colors.grey[300]!,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _sendToAll ? Colors.white.withOpacity(0.2) : _primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.campaign,
                                color: _sendToAll ? Colors.white : _primaryColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Отправить всем',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _sendToAll ? Colors.white : Colors.grey[800],
                                    ),
                                  ),
                                  Text(
                                    'Все сотрудники получат уведомление',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _sendToAll ? Colors.white70 : Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_sendToAll)
                              const Icon(Icons.check_circle, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Список сотрудников
                    Text(
                      'Или выберите сотрудника:',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: widget.employees.length,
                        itemBuilder: (context, index) {
                          final employee = widget.employees[index];
                          final isSelected = _selectedEmployeeId == employee.id && !_sendToAll;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _sendToAll = false;
                                _selectedEmployeeId = employee.id;
                                _selectedEmployeeName = employee.name;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? _primaryColor.withOpacity(0.1) : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: isSelected ? Border.all(color: _primaryColor) : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isSelected ? _primaryColor : Colors.grey[300],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.grey[600],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          employee.name,
                                          style: TextStyle(
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            color: isSelected ? _primaryColor : Colors.grey[800],
                                          ),
                                        ),
                                        if (employee.phone != null)
                                          Text(
                                            employee.phone!,
                                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle, color: _primaryColor, size: 22),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Комментарий
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: TextField(
                        controller: _commentController,
                        decoration: InputDecoration(
                          labelText: 'Комментарий (необязательно)',
                          labelStyle: TextStyle(color: Colors.grey[600]),
                          hintText: 'Причина передачи смены...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(16),
                          prefixIcon: Icon(Icons.comment, color: Colors.grey[400]),
                        ),
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Кнопки
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey[400]!),
                      ),
                      child: Text('Отмена', style: TextStyle(color: Colors.grey[600])),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: (_sendToAll || _selectedEmployeeId != null)
                            ? const LinearGradient(colors: _gradientColors)
                            : null,
                        color: (_sendToAll || _selectedEmployeeId != null) ? null : Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: (_sendToAll || _selectedEmployeeId != null)
                            ? [
                                BoxShadow(
                                  color: _primaryColor.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
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
                        icon: const Icon(Icons.send, color: Colors.white),
                        label: const Text('Отправить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
