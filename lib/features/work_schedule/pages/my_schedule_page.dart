import 'package:flutter/material.dart';
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

  // Кэш времени смен для магазинов
  Map<String, Map<ShiftType, ShiftTimeInfo>> _shiftTimes = {};

  // Уведомления (входящие)
  List<ShiftTransferRequest> _notifications = [];
  int _unreadCount = 0;
  bool _isLoadingNotifications = false;

  // Мои заявки (исходящие)
  List<ShiftTransferRequest> _outgoingRequests = [];
  bool _isLoadingOutgoing = false;
  int _outgoingUpdatesCount = 0; // Количество заявок с обновлённым статусом

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
    // Автоматическое обновление при открытии страницы
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
      print('Начало загрузки данных сотрудника...');

      // Используем новый метод для получения employeeId (основной способ)
      final employeeId = await EmployeesPage.getCurrentEmployeeId();

      if (employeeId == null) {
        print('Не удалось определить ID сотрудника');
        setState(() {
          _error = 'Не удалось определить сотрудника. Убедитесь, что вы вошли в систему.';
          _isLoading = false;
        });
        return;
      }

      print('Получен employeeId: $employeeId');

      // Получаем имя сотрудника
      final employeeName = await EmployeesPage.getCurrentEmployeeName();

      // Если имя не получено, загружаем из списка сотрудников
      String? name = employeeName;
      if (name == null) {
        print('Имя не получено, загружаем из списка сотрудников...');
        final employees = await EmployeeService.getEmployees();
        try {
          final employee = employees.firstWhere((e) => e.id == employeeId);
          name = employee.name;
          print('Имя получено из списка: $name');
        } catch (e) {
          print('Сотрудник не найден в списке: $e');
        }
      }

      if (mounted) {
        setState(() {
          _employeeId = employeeId;
          _employeeName = name ?? 'Неизвестно';
        });
        print('Данные сотрудника загружены: ID=$employeeId, имя=$name');
      }

      await _loadSchedule();
      await _loadUnreadCount();
      await _loadOutgoingUpdatesCount();
    } catch (e) {
      print('Ошибка загрузки данных сотрудника: $e');
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
      print('_loadSchedule: employeeId равен null');
      return;
    }

    print('Загрузка графика для сотрудника: $_employeeId');
    print('   Месяц: ${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final schedule = await WorkScheduleService.getEmployeeSchedule(
        _employeeId!,
        _selectedMonth,
      );

      print('График загружен: ${schedule.entries.length} записей');

      // Загружаем время смен из настроек магазинов
      final shiftTimes = await WorkScheduleService.getShiftTimesForEntries(schedule.entries);

      if (mounted) {
        setState(() {
          _schedule = schedule;
          _shiftTimes = shiftTimes;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Ошибка загрузки графика: $e');
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
      print('Ошибка загрузки уведомлений: $e');
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
      print('Ошибка загрузки счётчика: $e');
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
          // Сбрасываем счётчик при просмотре вкладки
          _outgoingUpdatesCount = 0;
        });
      }
    } catch (e) {
      print('Ошибка загрузки исходящих заявок: $e');
      if (mounted) {
        setState(() {
          _isLoadingOutgoing = false;
        });
      }
    }
  }

  /// Загрузить количество заявок с обновлённым статусом (одобрено/отклонено)
  Future<void> _loadOutgoingUpdatesCount() async {
    if (_employeeId == null) return;

    try {
      final requests = await ShiftTransferService.getOutgoingRequests(_employeeId!);
      // Считаем заявки с финальным статусом (одобрено, отклонено сотрудником, отклонено админом)
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
      print('Ошибка загрузки счётчика исходящих: $e');
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

  WorkScheduleEntry? _getEntryForDate(DateTime date) {
    if (_schedule == null) return null;
    try {
      return _schedule!.getEntry(_employeeId!, date);
    } catch (e) {
      return null;
    }
  }

  /// Получить время смены для записи (из настроек магазина или дефолт)
  String _getShiftTimeRange(WorkScheduleEntry entry) {
    final shopTimes = _shiftTimes[entry.shopAddress];
    if (shopTimes != null) {
      final timeInfo = shopTimes[entry.shiftType];
      if (timeInfo != null) {
        return timeInfo.timeRange;
      }
    }
    // Дефолтное значение из enum
    return entry.shiftType.timeRange;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой график'),
        backgroundColor: const Color(0xFF004D40),
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(text: 'Расписание', icon: Icon(Icons.calendar_month)),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notifications, size: 20),
                  const SizedBox(width: 4),
                  const Text('Входящие'),
                  if (_unreadCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_unreadCount',
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.send, size: 18),
                  const SizedBox(width: 2),
                  const Text('Заявки', style: TextStyle(fontSize: 13)),
                  if (_outgoingUpdatesCount > 0) ...[
                    const SizedBox(width: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_outgoingUpdatesCount',
                        style: const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
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

  Widget _buildScheduleTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Ошибка: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadEmployeeId,
              child: const Text('Повторить'),
            ),
          ],
        ),
      );
    }
    if (_schedule == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'График не загружен',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadSchedule,
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    }
    if (_schedule!.entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.event_busy, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'На ${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year} смен не назначено',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadSchedule,
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    }
    return _buildCalendarView();
  }

  Widget _buildCalendarView() {
    // Получаем только дни со сменами (сортируем по дате)
    final entriesWithDates = List<WorkScheduleEntry>.from(_schedule!.entries);
    entriesWithDates.sort((a, b) => a.date.compareTo(b.date));

    return Column(
      children: [
        // Заголовок с месяцем
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[200],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (_employeeName != null)
                Text(
                  _employeeName!,
                  style: TextStyle(color: Colors.grey[700]),
                ),
            ],
          ),
        ),
        // Календарь с событиями (только дни со сменами)
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: entriesWithDates.length,
            itemBuilder: (context, index) {
              final entry = entriesWithDates[index];
              final day = DateTime(entry.date.year, entry.date.month, entry.date.day);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: entry.shiftType.color.withOpacity(0.3),
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: entry.shiftType.color,
                      ),
                    ),
                  ),
                  title: Text(
                    '${day.day} ${_getMonthName(day.month)} ${_getWeekdayName(day.weekday)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: entry.shiftType.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${entry.shiftType.label} (${_getShiftTimeRange(entry)})',
                            style: TextStyle(
                              color: entry.shiftType.color,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.store,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              entry.shopAddress,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: Icon(Icons.work, color: entry.shiftType.color),
                ),
              );
            },
          ),
        ),
        // Статистика
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Всего смен', '${_schedule!.entries.length}'),
              _buildStatItem('Утро', '${_schedule!.entries.where((e) => e.shiftType == ShiftType.morning).length}'),
              _buildStatItem('День', '${_schedule!.entries.where((e) => e.shiftType == ShiftType.day).length}'),
              _buildStatItem('Вечер', '${_schedule!.entries.where((e) => e.shiftType == ShiftType.evening).length}'),
            ],
          ),
        ),
        // Кнопка "Передать смену"
        Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _showSwapDialog,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Передать смену'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationsTab() {
    if (_isLoadingNotifications) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Нет входящих запросов',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Здесь появятся запросы на передачу смен от других сотрудников',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadNotifications,
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotifications,
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
      return const Center(child: CircularProgressIndicator());
    }

    if (_outgoingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              'Нет отправленных заявок',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Здесь будут отображаться ваши заявки на передачу смен',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadOutgoingRequests,
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOutgoingRequests,
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

    // Определяем цвет и иконку статуса
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (request.status) {
      case ShiftTransferStatus.pending:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Ожидает ответа';
        break;
      case ShiftTransferStatus.accepted:
        statusColor = Colors.blue;
        statusIcon = Icons.schedule;
        statusText = 'Ожидает одобрения админа';
        break;
      case ShiftTransferStatus.approved:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Одобрено! Смена передана';
        break;
      case ShiftTransferStatus.rejected:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Отклонено сотрудником';
        break;
      case ShiftTransferStatus.declined:
        statusColor = Colors.red;
        statusIcon = Icons.block;
        statusText = 'Отклонено администратором';
        break;
      case ShiftTransferStatus.expired:
        statusColor = Colors.grey;
        statusIcon = Icons.timer_off;
        statusText = 'Истёк срок';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: request.status == ShiftTransferStatus.approved ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: request.status == ShiftTransferStatus.approved
            ? const BorderSide(color: Colors.green, width: 2)
            : request.status == ShiftTransferStatus.declined || request.status == ShiftTransferStatus.rejected
                ? const BorderSide(color: Colors.red, width: 1)
                : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Статус заявки
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Информация о смене
            _buildInfoRow(
              Icons.calendar_today,
              'Дата',
              '${shiftDate.day} ${_getMonthName(shiftDate.month)} ${shiftDate.year}',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.access_time,
              'Смена',
              request.shiftType.label,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.store,
              'Магазин',
              request.shopName.isNotEmpty ? request.shopName : request.shopAddress,
            ),

            // Кому отправлено
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.person_outline,
              'Кому',
              request.isBroadcast ? 'Всем сотрудникам' : request.toEmployeeName ?? 'Неизвестно',
            ),

            // Кто принял (если есть)
            if (request.acceptedByEmployeeName != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.person,
                'Принял',
                request.acceptedByEmployeeName!,
              ),
            ],

            // Комментарий
            if (request.comment != null && request.comment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.comment, 'Комментарий', request.comment!),
            ],

            // Дата создания
            const SizedBox(height: 8),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isUnread ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isUnread ? const BorderSide(color: Colors.orange, width: 2) : BorderSide.none,
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
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                const Icon(Icons.swap_horiz, color: Color(0xFF004D40)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    request.isBroadcast ? 'Запрос на передачу смены' : 'Запрос на передачу смены вам',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            // Информация
            _buildInfoRow(Icons.person, 'От', request.fromEmployeeName),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.calendar_today,
              'Дата',
              '${shiftDate.day} ${_getMonthName(shiftDate.month)} ${shiftDate.year}',
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.access_time,
              'Смена',
              request.shiftType.label,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.store, 'Магазин', request.shopName.isNotEmpty ? request.shopName : request.shopAddress),
            if (request.comment != null && request.comment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.comment, 'Комментарий', request.comment!),
            ],
            const SizedBox(height: 16),
            // Кнопки действий
            if (request.status == ShiftTransferStatus.pending)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => _rejectRequest(request),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    child: const Text('Отклонить'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _acceptRequest(request),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF004D40),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Принять'),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: request.status == ShiftTransferStatus.accepted
                      ? Colors.orange[100]
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  request.status.label,
                  style: TextStyle(
                    color: request.status == ShiftTransferStatus.accepted
                        ? Colors.orange[800]
                        : Colors.grey[700],
                    fontWeight: FontWeight.w500,
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
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Future<void> _acceptRequest(ShiftTransferRequest request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Принять смену?'),
        content: Text(
          'Вы хотите принять смену от ${request.fromEmployeeName} '
          'на ${request.shiftDate.day} ${_getMonthName(request.shiftDate.month)}?\n\n'
          'После принятия запрос будет отправлен администратору на одобрение.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
            ),
            child: const Text('Принять'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await ShiftTransferService.acceptRequest(
      request.id,
      _employeeId!,
      _employeeName!,
    );

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Запрос принят! Ожидает одобрения администратора.'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadNotifications();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка при принятии запроса'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectRequest(ShiftTransferRequest request) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отклонить запрос?'),
        content: Text(
          'Вы уверены, что хотите отклонить запрос на передачу смены от ${request.fromEmployeeName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await ShiftTransferService.rejectRequest(request.id);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Запрос отклонён'),
          backgroundColor: Colors.orange,
        ),
      );
      await _loadNotifications();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка при отклонении запроса'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Показать диалог для передачи смены
  Future<void> _showSwapDialog() async {
    if (_schedule == null || _schedule!.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('У вас нет смен для передачи'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Показываем диалог выбора смены
    final selectedEntry = await showDialog<WorkScheduleEntry>(
      context: context,
      builder: (context) => _ShiftSelectionDialog(
        entries: _schedule!.entries,
        shiftTimes: _shiftTimes,
      ),
    );

    if (selectedEntry == null) return;

    // Показываем диалог выбора получателя
    await _showRecipientSelectionDialog(selectedEntry);
  }

  Future<void> _showRecipientSelectionDialog(WorkScheduleEntry entry) async {
    // Загружаем список сотрудников и магазинов
    final employees = await EmployeeService.getEmployees();
    final shops = await ShopService.getShops();

    print('📋 Загружено сотрудников с API: ${employees.length}');
    print('📋 Текущий сотрудник ID: $_employeeId');

    // Находим название магазина
    String shopName = entry.shopAddress;
    try {
      final shop = shops.firstWhere((s) => s.address == entry.shopAddress);
      shopName = shop.name;
    } catch (e) {
      // Магазин не найден
    }

    // Исключаем себя из списка
    final otherEmployees = employees.where((e) => e.id != _employeeId).toList();
    print('📋 Сотрудников после фильтрации (без себя): ${otherEmployees.length}');

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

    // Создаём запрос на передачу
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

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['toEmployeeId'] == null
                ? 'Запрос отправлен всем сотрудникам'
                : 'Запрос отправлен ${result['toEmployeeName']}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка при создании запроса'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  String _getMonthName(int month) {
    const months = [
      'Январь',
      'Февраль',
      'Март',
      'Апрель',
      'Май',
      'Июнь',
      'Июль',
      'Август',
      'Сентябрь',
      'Октябрь',
      'Ноябрь',
      'Декабрь',
    ];
    return months[month - 1];
  }

  String _getWeekdayName(int weekday) {
    const weekdays = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
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

  @override
  Widget build(BuildContext context) {
    // Сортируем смены по дате
    final sortedEntries = List<WorkScheduleEntry>.from(entries)
      ..sort((a, b) => a.date.compareTo(b.date));

    // Фильтруем только будущие смены
    final now = DateTime.now();
    final futureEntries = sortedEntries.where((e) =>
      e.date.isAfter(now) ||
      (e.date.year == now.year && e.date.month == now.month && e.date.day == now.day)
    ).toList();

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.swap_horiz, color: Color(0xFF004D40)),
          SizedBox(width: 8),
          Text('Выберите смену'),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.5,
        child: futureEntries.isEmpty
            ? const Center(
                child: Text(
                  'Нет доступных смен для передачи',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            : ListView.builder(
                itemCount: futureEntries.length,
                itemBuilder: (context, index) {
                  final entry = futureEntries[index];
                  final day = entry.date;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: entry.shiftType.color.withOpacity(0.3),
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: entry.shiftType.color,
                          ),
                        ),
                      ),
                      title: Text(
                        '${day.day} ${_getMonthName(day.month)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${entry.shiftType.label} (${_getShiftTimeRange(entry)})',
                        style: TextStyle(color: entry.shiftType.color),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, entry),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
      ],
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
    const months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.entry.date;

    return AlertDialog(
      title: const Text('Кому передать смену?'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Информация о смене
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${day.day} ${_getMonthName(day.month)} ${day.year}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.entry.shiftType.label} (${widget.shiftTimeRange})',
                      style: TextStyle(color: widget.entry.shiftType.color),
                    ),
                    Text(
                      widget.shopName,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Кнопка "Отправить всем"
              InkWell(
                onTap: () {
                  setState(() {
                    _sendToAll = true;
                    _selectedEmployeeId = null;
                    _selectedEmployeeName = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _sendToAll ? const Color(0xFF004D40).withOpacity(0.1) : Colors.white,
                    border: Border.all(
                      color: _sendToAll ? const Color(0xFF004D40) : Colors.grey[300]!,
                      width: _sendToAll ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.campaign,
                        color: _sendToAll ? const Color(0xFF004D40) : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Отправить всем сотрудникам',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (_sendToAll)
                        const Icon(Icons.check_circle, color: Color(0xFF004D40)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Список сотрудников
              Text(
                'Или выберите сотрудника (${widget.employees.length}):',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.employees.length,
                  itemBuilder: (context, index) {
                    final employee = widget.employees[index];
                    final isSelected = _selectedEmployeeId == employee.id && !_sendToAll;

                    return RadioListTile<String>(
                      title: Text(employee.name),
                      subtitle: employee.phone != null ? Text(employee.phone!) : null,
                      value: employee.id,
                      groupValue: _sendToAll ? null : _selectedEmployeeId,
                      onChanged: (value) {
                        setState(() {
                          _sendToAll = false;
                          _selectedEmployeeId = value;
                          _selectedEmployeeName = employee.name;
                        });
                      },
                      selected: isSelected,
                      activeColor: const Color(0xFF004D40),
                      dense: true,
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Комментарий
              TextField(
                controller: _commentController,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (необязательно)',
                  hintText: 'Причина передачи смены...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: (_sendToAll || _selectedEmployeeId != null)
              ? () {
                  Navigator.pop(context, {
                    'toEmployeeId': _sendToAll ? null : _selectedEmployeeId,
                    'toEmployeeName': _sendToAll ? null : _selectedEmployeeName,
                    'comment': _commentController.text.isEmpty ? null : _commentController.text,
                  });
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004D40),
            foregroundColor: Colors.white,
          ),
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}
