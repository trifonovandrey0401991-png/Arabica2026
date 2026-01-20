import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../models/work_schedule_model.dart';
import '../models/shift_transfer_model.dart';
import '../services/work_schedule_service.dart';
import '../services/shift_transfer_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../shops/services/shop_service.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
    if (_tabController.index == 1 && _employeeId != null) {
      _loadNotifications();
    } else if (_tabController.index == 2 && _employeeId != null) {
      _loadOutgoingRequests();
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
          preferredSize: const Size.fromHeight(60),
          child: Container(
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.9),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                _buildTab(Icons.calendar_month, 'Расписание', null),
                _buildTab(Icons.notifications, 'Входящие', _unreadCount > 0 ? _unreadCount : null, Colors.red),
                _buildTab(Icons.send, 'Заявки', _outgoingUpdatesCount > 0 ? _outgoingUpdatesCount : null, Colors.green),
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
        ],
      ),
    );
  }

  Widget _buildTab(IconData icon, String label, int? badge, [Color? badgeColor]) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 6),
          Text(label),
          if (badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor ?? Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
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
    if (_schedule!.entries.isEmpty) {
      return _buildEmptyState(
        Icons.event_busy,
        'Нет смен',
        'На ${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year} смен не назначено',
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
    final entriesWithDates = List<WorkScheduleEntry>.from(_schedule!.entries);
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
                  '${_schedule!.entries.length} смен',
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
          _buildStatChip('Всего', '${_schedule!.entries.length}', _primaryColor),
          _buildStatChip('Утро', '${_schedule!.entries.where((e) => e.shiftType == ShiftType.morning).length}', ShiftType.morning.color),
          _buildStatChip('День', '${_schedule!.entries.where((e) => e.shiftType == ShiftType.day).length}', ShiftType.day.color),
          _buildStatChip('Вечер', '${_schedule!.entries.where((e) => e.shiftType == ShiftType.evening).length}', ShiftType.evening.color),
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
            // Кнопки
            if (request.status == ShiftTransferStatus.pending)
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

    final success = await ShiftTransferService.rejectRequest(request.id);

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
