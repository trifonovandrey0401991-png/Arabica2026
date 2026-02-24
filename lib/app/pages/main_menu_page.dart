import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../../features/menu/pages/menu_groups_page.dart';
import '../../features/orders/pages/cart_page.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/loyalty/pages/loyalty_page.dart';
import '../../features/shops/models/shop_model.dart';
import '../../features/shops/services/shop_service.dart';
import '../../features/shifts/services/shift_sync_service.dart';
import '../../features/recipes/models/recipe_model.dart';
import '../../features/reviews/pages/review_type_selection_page.dart';
import '../../features/employees/services/user_role_service.dart';
import '../../features/employees/models/user_role_model.dart';
import '../../features/clients/pages/registration_page.dart';
import '../../features/loyalty/services/loyalty_storage.dart';
import '../../features/product_questions/pages/product_search_shop_selection_page.dart';
import '../../features/employees/pages/employee_panel_page.dart';
import '../../features/shops/pages/shops_on_map_page.dart';
import '../../features/job_application/pages/job_application_welcome_page.dart';
import '../../features/rating/services/rating_service.dart';
import '../../features/rating/models/employee_rating_model.dart';
import '../../core/utils/logger.dart';
import '../../core/services/firebase_service.dart';
import '../../shared/dialogs/notification_required_dialog.dart';
import 'my_dialogs_page.dart';
import 'data_management_page.dart';
import 'reports_page.dart';
import '../services/my_dialogs_counter_service.dart';
import '../services/reports_counter_service.dart';
import '../services/dashboard_batch_service.dart';
// Импорты для функций сотрудника
import 'client_functions_page.dart';
import '../../features/training/pages/training_page.dart';
import '../../features/tests/pages/test_page.dart';
import '../../features/shifts/pages/shift_shop_selection_page.dart';
import '../../features/shift_handover/pages/shift_handover_shop_selection_page.dart';
import '../../features/recount/pages/recount_shop_selection_page.dart';
import '../../features/recipes/pages/recipes_list_page.dart';
import '../../features/attendance/services/attendance_service.dart';
import '../../features/rko/pages/rko_type_selection_page.dart';
import '../../features/employees/services/employee_registration_service.dart';
import '../../features/orders/pages/employee_orders_page.dart';
import '../../features/orders/services/order_service.dart';
import '../../features/messenger/pages/messenger_shell_page.dart';
import '../../features/messenger/services/messenger_service.dart';
import '../../features/work_schedule/services/shift_transfer_service.dart';
import '../../features/loyalty/pages/loyalty_scanner_page.dart';
import '../../features/loyalty/pages/prize_scanner_page.dart';
import '../../features/work_schedule/pages/my_schedule_page.dart';
import '../../features/product_questions/pages/product_questions_management_page.dart';
import '../../features/product_questions/pages/product_search_page.dart';
import '../../features/product_questions/services/product_question_service.dart';
import '../../features/efficiency/pages/my_efficiency_page.dart';
import '../../features/tasks/pages/my_tasks_page.dart';
import '../../features/fortune_wheel/pages/fortune_wheel_page.dart';
import '../../features/fortune_wheel/services/fortune_wheel_service.dart';
import '../../features/tasks/services/task_service.dart';
import '../../features/tasks/models/task_model.dart';
import '../../features/employees/services/employee_service.dart';
import '../../features/ai_training/pages/ai_training_page.dart';
import '../../features/ai_training/pages/ai_dashboard_page.dart';
import '../../features/work_schedule/services/work_schedule_service.dart';
import '../../features/work_schedule/models/work_schedule_model.dart';
import '../../core/services/app_update_service.dart';
import '../../core/services/counters_ws_service.dart';
import '../../features/efficiency/services/efficiency_data_service.dart';
import '../../features/network_management/pages/network_management_page.dart';
import 'manager_grid_page.dart';
import '../../features/main_cash/pages/main_cash_page.dart';
import '../../features/execution_chain/services/execution_chain_service.dart';
import '../../features/execution_chain/models/execution_chain_model.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_colors.dart';

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> with WidgetsBindingObserver {
  String? _userName;
  UserRoleData? _userRole;
  String? _employeeId;
  bool _isLoadingRole = false;
  int _totalReportsCount = 0; // Общий счётчик для бейджа "Отчёты" (все дочерние счётчики)
  int _myDialogsUnreadCount = 0;
  EmployeeRating? _employeeRating;

  // Поля для бейджей сотрудника
  int _pendingOrdersCount = 0;
  int _unreadProductQuestionsCount = 0;
  int _activeTasksCount = 0;
  int _availableSpins = 0;
  int _shiftTransferUnreadCount = 0;
  int _messengerUnreadCount = 0;
  int? _referralCode;

  // Флаг доступности обновления
  bool _isUpdateAvailable = false;

  // Баллы эффективности за текущий месяц
  double? _efficiencyPoints;

  // Кэш цепочки выполнений (обновляется каждые 30 секунд)
  ExecutionChainStatus? _chainStatus;
  DateTime? _chainStatusLoadedAt;

  // WebSocket live counters
  StreamSubscription<CounterUpdateEvent>? _countersSub;
  DateTime? _lastLifecycleReload;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCachedRole(); // Мгновенно: из SharedPreferences
    _loadPhased();     // Фазовая загрузка данных
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh all badges when app returns to foreground (e.g. after push)
    // Debounce 60 seconds — camera also triggers resumed
    if (state == AppLifecycleState.resumed && mounted) {
      final now = DateTime.now();
      if (_lastLifecycleReload == null ||
          now.difference(_lastLifecycleReload!) > const Duration(seconds: 60)) {
        _lastLifecycleReload = now;
        _loadDashboardBatch();
        _loadMyDialogsCount();
        _loadMessengerUnreadCount();
        _loadEmployeeCounters();
      }
    }
  }

  /// Фазовая загрузка: критичные данные сначала, фон потом.
  /// Предотвращает взрыв 40+ параллельных запросов к серверу.
  Future<void> _loadPhased() async {
    // ФАЗА 1: Критичные данные (роль и ID определяют интерфейс)
    await _loadUserData();
    await _loadEmployeeId();

    // ФАЗА 2: Бейджи (видны на кнопках меню)
    _loadDashboardBatch();
    _loadMyDialogsCount();
    _loadMessengerUnreadCount();
    _loadEmployeeCounters();

    // ФАЗА 3: Фоновые данные (не видны сразу)
    await Future.delayed(Duration(milliseconds: 300));
    _syncReports();
    _checkForUpdates();
    _loadEmployeeRating();
    _loadEfficiencyPoints();
    _connectCountersWs();
  }

  Future<void> _checkForUpdates() async {
    final hasUpdate = await AppUpdateService.checkUpdateAvailability();
    if (mounted) {
      setState(() => _isUpdateAvailable = hasUpdate);
    }
  }

  Future<void> _loadEfficiencyPoints() async {
    try {
      // Получаем имя текущего сотрудника
      final employeeName = await EmployeesPage.getCurrentEmployeeName();
      if (employeeName == null || employeeName.isEmpty) return;

      // Загружаем данные эффективности за текущий месяц
      final now = DateTime.now();
      final data = await EfficiencyDataService.loadMonthData(now.year, now.month);

      // Ищем сотрудника в данных
      final employeeSummary = data.byEmployee.firstWhere(
        (summary) => summary.entityName == employeeName,
        orElse: () => throw StateError('Employee not found'),
      );

      if (mounted) {
        setState(() => _efficiencyPoints = employeeSummary.totalPoints);
      }
    } catch (e) {
      Logger.warning('Ошибка загрузки эффективности: $e');
    }
  }

  /// Connect to counters WebSocket for live badge updates
  Future<void> _connectCountersWs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');
      if (phone == null || phone.isEmpty) return;

      final roleName = _userRole?.role.name ?? 'employee';
      await CountersWsService.instance.connect(phone, role: roleName);

      _countersSub?.cancel();
      _countersSub = CountersWsService.instance.onCounterUpdate.listen((event) {
        if (!mounted) return;
        _handleCounterUpdate(event.counter);
      });
    } catch (e) {
      Logger.warning('Counters WS connection error: $e');
    }
  }

  /// Handle a counter update from WebSocket — reload only the affected badge
  void _handleCounterUpdate(String counter) {
    switch (counter) {
      case 'pendingShiftReports':
      case 'pendingRecountReports':
      case 'pendingHandoverReports':
      case 'unconfirmedWithdrawals':
      case 'unconfirmedEnvelopes':
      case 'reportNotifications':
        _loadDashboardBatch();
        break;
      case 'pendingOrders':
        _loadPendingOrdersCount();
        break;
      case 'activeTaskAssignments':
        if (_employeeId != null) _loadActiveTasksCount(_employeeId);
        break;
      case 'unreadProductQuestions':
        _loadUnreadProductQuestionsCount();
        break;
      case 'shiftTransferRequests':
        if (_employeeId != null) _loadShiftTransferUnreadCount(_employeeId);
        break;
      case 'myDialogs':
      case 'unreadReviews':
      case 'managementMessages':
        _loadMyDialogsCount();
        break;
      case 'availableSpins':
        if (_employeeId != null) _loadAvailableSpins(_employeeId);
        break;
      default:
        // Unknown counter — reload main badges as fallback
        _loadDashboardBatch();
        break;
    }
  }

  /// Batch-загрузка счётчиков: один запрос вместо 3 отдельных
  /// (totalReports, pendingOrders, activeTasks)
  Future<void> _loadDashboardBatch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone');
      final counters = await DashboardBatchService.getCounters(
        phone: phone,
        employeeId: _employeeId,
      );
      if (counters != null && mounted) {
        if (mounted) setState(() {
          _totalReportsCount = counters.totalPendingReports;
          _pendingOrdersCount = counters.pendingOrders;
          _activeTasksCount = counters.activeTaskAssignments;
        });
      }
    } catch (e) {
      Logger.warning('Dashboard batch fallback to individual calls');
      // Fallback: индивидуальные вызовы
      _loadTotalReportsCount();
    }
  }

  /// Загрузка общего счётчика для бейджа "Отчёты" (fallback)
  Future<void> _loadTotalReportsCount() async {
    try {
      final count = await ReportsCounterService.getTotalUnreadCount();
      if (mounted) setState(() => _totalReportsCount = count);
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика отчётов', e);
    }
  }

  Future<void> _loadMyDialogsCount() async {
    try {
      final count = await MyDialogsCounterService.getTotalUnreadCount();
      if (mounted) setState(() => _myDialogsUnreadCount = count);
    } catch (e) {
      Logger.error('Ошибка загрузки счетчика диалогов', e);
    }
  }

  Future<void> _loadMessengerUnreadCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone') ?? '';
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      if (normalizedPhone.isEmpty) return;
      final count = await MessengerService.getUnreadCount(normalizedPhone);
      if (mounted) setState(() => _messengerUnreadCount = count);
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика мессенджера', e);
    }
  }

  /// Загрузка всех счётчиков для сотрудника.
  /// Получаем employeeId один раз и передаём во все методы,
  /// вместо 5 параллельных вызовов getCurrentEmployeeId().
  Future<void> _loadEmployeeCounters() async {
    final employeeId = await EmployeesPage.getCurrentEmployeeId();
    // pendingOrders и activeTasks загружены через batch в _loadDashboardBatch
    _loadUnreadProductQuestionsCount();
    _loadAvailableSpins(employeeId);
    _loadShiftTransferUnreadCount(employeeId);
    _loadReferralCode(employeeId);
  }

  Future<void> _loadPendingOrdersCount() async {
    try {
      final orders = await OrderService.getAllOrders(status: 'pending');
      if (mounted) setState(() => _pendingOrdersCount = orders.length);
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика заказов', e);
    }
  }

  Future<void> _loadUnreadProductQuestionsCount() async {
    try {
      final dialogs = await ProductQuestionService.getAllPersonalDialogs();
      final unreadDialogsCount = dialogs.where((d) => d.hasUnreadFromClient).length;
      final unansweredQuestionsCount = await ProductQuestionService.getUnansweredQuestionsCount();
      final totalCount = unreadDialogsCount + unansweredQuestionsCount;
      if (mounted) setState(() => _unreadProductQuestionsCount = totalCount);
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика вопросов о товарах', e);
    }
  }

  Future<void> _loadActiveTasksCount(String? employeeId) async {
    if (employeeId == null) return;
    try {
      final assignments = await TaskService.getMyAssignments(employeeId);
      final activeCount = assignments.where((a) =>
        a.status == TaskStatus.pending || a.status == TaskStatus.submitted
      ).length;
      if (mounted) setState(() => _activeTasksCount = activeCount);
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика задач', e);
    }
  }

  Future<void> _loadAvailableSpins(String? employeeId) async {
    if (employeeId == null) return;
    try {
      final spins = await FortuneWheelService.getAvailableSpins(employeeId);
      if (mounted) setState(() => _availableSpins = spins.availableSpins);
    } catch (e) {
      Logger.error('Ошибка загрузки прокруток', e);
    }
  }

  Future<void> _loadShiftTransferUnreadCount(String? employeeId) async {
    if (employeeId == null) return;
    try {
      final count = await ShiftTransferService.getUnreadCount(employeeId);
      if (mounted) setState(() => _shiftTransferUnreadCount = count);
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика пересменок', e);
    }
  }

  Future<void> _loadReferralCode(String? employeeId) async {
    if (employeeId == null) return;
    try {
      final employees = await EmployeeService.getEmployees();
      final employee = employees.firstWhere(
        (e) => e.id == employeeId,
        orElse: () => throw StateError('Employee not found'),
      );
      if (mounted && employee.referralCode != null) {
        if (mounted) setState(() => _referralCode = employee.referralCode);
      }
    } catch (e) {
      Logger.error('Ошибка загрузки referralCode', e);
    }
  }

  Future<void> _loadEmployeeRating() async {
    if (_employeeId == null) {
      // Подождём загрузки employeeId
      await Future.delayed(Duration(milliseconds: 500));
      if (_employeeId == null) return;
    }
    try {
      final rating = await RatingService.getCurrentEmployeeRating(_employeeId!);
      if (mounted) setState(() => _employeeRating = rating);
    } catch (e) {
      Logger.error('Ошибка загрузки рейтинга', e);
    }
  }

  Future<void> _loadEmployeeId() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (mounted && employeeId != null) {
        if (mounted) setState(() => _employeeId = employeeId);
        _loadEmployeeRating();
      }
    } catch (e) {
      Logger.error('Ошибка загрузки employeeId', e);
    }
  }

  /// Извлечь имя (второе слово) из ФИО
  /// Например: "Иванов Иван Иванович" -> "Иван"
  String _getFirstName(String? fullName) {
    if (fullName == null || fullName.isEmpty) return 'Гость';
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return parts[1];
    }
    return parts[0];
  }

  Future<void> _loadCachedRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('user_name');
      final cachedRole = await UserRoleService.loadUserRole();
      if (mounted) {
        setState(() {
          _userName = cachedRole?.displayName ?? name;
          _userRole = cachedRole;
        });
      }
    } catch (e) {
      Logger.warning('Ошибка загрузки роли: $e');
    }
  }

  Future<void> _syncReports() async {
    try {
      await ShiftSyncService.syncAllReports();
    } catch (e) {
      Logger.warning('Ошибка синхронизации: $e');
    }
  }

  Future<void> _loadUserData() async {
    if (_isLoadingRole) return;
    _isLoadingRole = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('user_name');
      final phone = prefs.getString('user_phone');

      UserRoleData? cachedRole = await UserRoleService.loadUserRole();
      UserRoleData? roleData = cachedRole;

      if (phone != null && phone.isNotEmpty) {
        try {
          final freshRole = await UserRoleService.getUserRole(phone);

          // Защита: не понижаем developer/admin до client при сбое API
          final cachedRoleName = cachedRole?.role.name;
          if (freshRole.role == UserRole.client &&
              (cachedRoleName == 'developer' || cachedRoleName == 'admin')) {
            Logger.warning('⚠️ API вернул client, но кэш: $cachedRoleName — не понижаем');
          } else {
            roleData = freshRole;
            await UserRoleService.saveUserRole(roleData!);
            if (roleData!.displayName.isNotEmpty) {
              await prefs.setString('user_name', roleData!.displayName);
            }
          }
        } catch (e) {
          roleData = cachedRole ?? UserRoleData(
            role: UserRole.client,
            displayName: name ?? '',
            phone: phone,
          );
        }
      }

      if (mounted) {
        setState(() {
          _userName = roleData?.displayName ?? name;
          _userRole = roleData;
        });
      }
    } finally {
      _isLoadingRole = false;
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        title: Text('Выход', style: TextStyle(color: Colors.white)),
        content: Text('Выйти из аккаунта?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Выйти', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_registered');
      await prefs.remove('user_name');
      await prefs.remove('user_phone');
      await UserRoleService.clearUserRole();
      await LoyaltyStorage.clear();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => RegistrationPage()),
          (_) => false,
        );
      }
    } catch (e) {
      Logger.error('Ошибка выхода', e);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countersSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final role = _userRole?.role ?? UserRole.client;

    // Админ и управляющий сразу видят ManagerGridPage
    if (role == UserRole.admin || role == UserRole.manager) {
      return ManagerGridPage(
        isHomePage: true,
        userName: _userName,
        onLogout: _logout,
      );
    }

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
              _buildHeader(),
              Expanded(
                child: _buildMenuForRole(role),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Выбор меню в зависимости от роли
  Widget _buildMenuForRole(UserRole role) {
    switch (role) {
      case UserRole.client:
        return _buildClientMenu();
      case UserRole.employee:
        return _buildEmployeeMenu();
      case UserRole.manager:
      case UserRole.admin:
        return _buildAdminMenu();
      case UserRole.developer:
        return _buildDeveloperMenu(); // Developer - расширенное меню
    }
  }

  /// Компактное меню для клиентов - помещается на экран без прокрутки
  Widget _buildClientMenu() {
    final items = _getClientMenuItems();
    // 8 пунктов, сетка 2x4 — плитки на весь экран
    final rows = 4;
    final cols = 2;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0.h, 20.w, 8.h),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight;
                final availableWidth = constraints.maxWidth;
                final spacing = 12.0;

                final tileWidth = (availableWidth - spacing) / cols;
                final tileHeight = (availableHeight - spacing * (rows - 1)) / rows;
                final aspectRatio = tileWidth / tileHeight;

                return GridView.count(
                  crossAxisCount: cols,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: aspectRatio,
                  physics: NeverScrollableScrollPhysics(),
                  children: items,
                );
              },
            ),
          ),
        ),
        // Кнопка мессенджера под сеткой
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 16.h),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const MessengerShellPage()));
                      _loadMessengerUnreadCount();
                    },
                    icon: const Icon(Icons.chat_rounded, size: 22),
                    label: const Text('Чат', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                  ),
                ),
                if (_messengerUnreadCount > 0)
                  Positioned(
                    right: 8,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      child: Text(
                        _messengerUnreadCount > 99 ? '99+' : '$_messengerUnreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Меню для админов - 4 широкие строки на весь экран
  Widget _buildAdminMenu() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 0.h, 20.w, 20.h),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;

          // 3 кнопки + 2 отступа между ними
          final buttonCount = 3;
          final spacing = 16.0;
          final totalSpacing = spacing * (buttonCount - 1);
          final buttonHeight = (availableHeight - totalSpacing) / buttonCount;

          return Column(
            children: [
              _buildAdminRow(
                Icons.analytics_outlined,
                'Отчёты',
                'Аналитика и статистика',
                buttonHeight,
                () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ReportsPage()));
                  _loadTotalReportsCount();
                },
                badge: _totalReportsCount,
              ),
              SizedBox(height: spacing),
              _buildAdminRow(
                Icons.grid_view_rounded,
                'Панель сотрудника',
                'Функции сотрудника',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeePanelPage())),
              ),
              SizedBox(height: spacing),
              _buildAdminRow(
                Icons.person_outline,
                'Клиент',
                'Клиентские функции',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientFunctionsPage())),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Меню для разработчиков - админ меню + "Управление сетью"
  Widget _buildDeveloperMenu() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 0.h, 20.w, 20.h),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;

          // 8 кнопок + 7 отступов между ними
          final buttonCount = 8;
          final spacing = 8.0;
          final totalSpacing = spacing * (buttonCount - 1);
          final buttonHeight = (availableHeight - totalSpacing) / buttonCount;

          return Column(
            children: [
              // Специальная кнопка "Управление сетью" для разработчика
              _buildAdminRow(
                Icons.hub_outlined,
                'Управление сетью',
                'Разработчики, управляющие, магазины',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => NetworkManagementPage())),
              ),
              SizedBox(height: spacing),
              _buildAdminRow(
                Icons.tune_rounded,
                'Управление',
                'Настройки системы и данные',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => DataManagementPage())),
              ),
              SizedBox(height: spacing),
              _buildAdminRow(
                Icons.analytics_outlined,
                'Отчёты',
                'Аналитика и статистика',
                buttonHeight,
                () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ReportsPage()));
                  _loadTotalReportsCount();
                },
                badge: _totalReportsCount,
              ),
              SizedBox(height: spacing),
              // Чат — золотая кнопка
              _buildAdminRow(
                Icons.chat_rounded,
                'Чат',
                'Сообщения и обсуждения',
                buttonHeight,
                () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const MessengerShellPage()));
                  _loadMessengerUnreadCount();
                },
                isGold: true,
                badge: _messengerUnreadCount,
              ),
              SizedBox(height: spacing),
              _buildAdminRow(
                Icons.manage_accounts_outlined,
                'Управляющая(ий)',
                'Отчёты и управление',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManagerGridPage())),
              ),
              SizedBox(height: spacing),
              _buildAdminRow(
                Icons.grid_view_rounded,
                'Панель сотрудника',
                'Функции сотрудника',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeePanelPage())),
              ),
              SizedBox(height: spacing),
              _buildAdminRow(
                Icons.person_outline,
                'Клиент',
                'Клиентские функции',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientFunctionsPage())),
              ),
              SizedBox(height: spacing),
              _buildAdminRow(
                Icons.smart_toy_outlined,
                'ДашБорд AI',
                'Метрики AI-систем',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiDashboardPage())),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdminRow(
    IconData icon,
    String title,
    String subtitle,
    double height,
    VoidCallback onTap, {
    int? badge,
    bool isGold = false,
  }) {
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20.r),
          splashColor: isGold ? AppColors.gold.withOpacity(0.2) : Colors.white.withOpacity(0.1),
          highlightColor: isGold ? AppColors.gold.withOpacity(0.1) : Colors.white.withOpacity(0.05),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: isGold ? AppColors.gold.withOpacity(0.5) : Colors.white.withOpacity(0.15)),
              gradient: LinearGradient(
                colors: isGold
                    ? [AppColors.gold.withOpacity(0.2), AppColors.darkGold.withOpacity(0.08)]
                    : [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.02)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Builder(
              builder: (context) {
                final iconContainerSize = height < 64 ? (height * 0.7).clamp(28.0, 56.0) : 56.0;
                final iconSize = iconContainerSize < 40 ? 20.0 : 28.0;
                return Row(
              children: [
                Container(
                  width: iconContainerSize,
                  height: iconContainerSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16.r),
                    color: isGold ? AppColors.gold.withOpacity(0.2) : Colors.white.withOpacity(0.1),
                  ),
                  child: Icon(
                    icon,
                    color: isGold ? AppColors.gold : Colors.white.withOpacity(0.9),
                    size: iconSize,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isGold ? AppColors.gold : Colors.white.withOpacity(0.95),
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isGold ? AppColors.gold.withOpacity(0.6) : Colors.white.withOpacity(0.5),
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null && badge > 0)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        color: AppColors.emerald,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isGold ? AppColors.gold.withOpacity(0.5) : Colors.white.withOpacity(0.4),
                    size: 28,
                  ),
              ],
            );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Компактное меню для сотрудников - 3xN без прокрутки + футуристичная кнопка ИИ
  Widget _buildEmployeeMenu() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 0.h),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          final availableWidth = constraints.maxWidth;

          // Фиксированные размеры
          final headerHeight = 20.0;
          final aiButtonHeight = 52.0;
          final aiButtonTopMargin = 10.0;

          final sections = _getEmployeeSections();

          // 3 равные секции + кнопка ИИ
          final totalGridHeight = availableHeight - (headerHeight * 3) - aiButtonHeight - aiButtonTopMargin;
          final sectionSpacing = totalGridHeight * 0.03;
          final gridHeight = totalGridHeight - (sectionSpacing * 2);
          final sectionHeight = gridHeight / 3 + headerHeight;

          final showMainCash = _userRole?.isManager == true && _userRole!.managedShopIds.isNotEmpty;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < sections.length; i++) ...[
                if (i > 0) SizedBox(height: sectionSpacing),
                _buildEmployeeSection(
                  ['Повседневные Задачи', 'Информация', 'Работа с клиентами'][i],
                  sectionHeight,
                  availableWidth,
                  sections[i],
                  headerHeight,
                ),
              ],
              SizedBox(height: aiButtonTopMargin),
              if (showMainCash)
                _buildAITrainingWithCashRow(aiButtonHeight)
              else
                _buildAITrainingButton(aiButtonHeight),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmployeeSection(String title, double height, double width, List<Widget> items, double headerHeight) {
    final cols = 3;
    final rows = 2;
    final spacing = 6.0;

    final tileWidth = (width - spacing * (cols - 1)) / cols;
    final gridHeight = height - headerHeight;
    final tileHeight = (gridHeight - spacing * (rows - 1)) / rows;
    final aspectRatio = tileWidth / tileHeight;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: headerHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: cols,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
              physics: NeverScrollableScrollPhysics(),
              children: items,
            ),
          ),
        ],
      ),
    );
  }

  /// Кнопка для Обучения ИИ - выделяется, но вписывается в дизайн
  Widget _buildAITrainingButton([double height = 52]) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.emeraldLight.withOpacity(0.8),
            AppColors.emerald,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppColors.turquoise.withOpacity(0.6), // Бирюзовый акцент
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => AITrainingPage()));
          },
          borderRadius: BorderRadius.circular(16.r),
          splashColor: Colors.white.withOpacity(0.2),
          highlightColor: Colors.white.withOpacity(0.1),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  color: Colors.white.withOpacity(0.9),
                  size: 24,
                ),
                SizedBox(width: 10),
                Text(
                  'Обучение ИИ',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: AppColors.turquoise.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(6.r),
                    border: Border.all(
                      color: AppColors.turquoise.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'AI',
                    style: TextStyle(
                      color: AppColors.turquoise,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Строка: 50% Обучение ИИ + 50% золотая Главная касса
  Widget _buildAITrainingWithCashRow(double height) {
    return Row(
      children: [
        // Обучение ИИ — 50%
        Expanded(
          child: Container(
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.emeraldLight.withOpacity(0.8),
                  AppColors.emerald,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: AppColors.turquoise.withOpacity(0.6),
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16.r),
              child: InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AITrainingPage()));
                },
                borderRadius: BorderRadius.circular(16.r),
                splashColor: Colors.white.withOpacity(0.2),
                highlightColor: Colors.white.withOpacity(0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.smart_toy_outlined, color: Colors.white.withOpacity(0.9), size: 20),
                    SizedBox(width: 6),
                    Text(
                      'ИИ',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(width: 6),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.h),
                      decoration: BoxDecoration(
                        color: AppColors.turquoise.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6.r),
                        border: Border.all(
                          color: AppColors.turquoise.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'AI',
                        style: TextStyle(
                          color: AppColors.turquoise,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 8),
        // Главная касса — 50%, золотой
        Expanded(
          child: Container(
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.gold.withOpacity(0.9),
                  AppColors.darkGold,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: AppColors.gold.withOpacity(0.7),
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16.r),
              child: InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => MainCashPage()));
                },
                borderRadius: BorderRadius.circular(16.r),
                splashColor: Colors.white.withOpacity(0.2),
                highlightColor: Colors.white.withOpacity(0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.account_balance_outlined, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Касса',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final showRating = _employeeRating != null &&
        _employeeRating!.position > 0 &&
        (_userRole?.role == UserRole.employee || _userRole?.role == UserRole.admin || _userRole?.role == UserRole.developer);

    final showEfficiency = _efficiencyPoints != null &&
        (_userRole?.role == UserRole.employee || _userRole?.role == UserRole.admin || _userRole?.role == UserRole.developer);

    final isEmployee = _userRole?.role == UserRole.employee;
    final btnSize = isEmployee ? 32.0 : 38.0;
    final iconSize = isEmployee ? 16.0 : 18.0;
    final btnGap = isEmployee ? 8.0 : 10.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, isEmployee ? 8 : 16, 24, isEmployee ? 8 : 20),
      child: Column(
        children: [
          // Одна строка: бейджи | логотип | кнопки
          SizedBox(
            height: btnSize,
            child: Row(
              children: [
                // Левая часть - бейджи
                if (showRating || showEfficiency)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showRating) SizedBox(height: btnSize, child: _buildRatingBadge()),
                      if (showRating && showEfficiency) SizedBox(width: 4),
                      if (showEfficiency) SizedBox(height: btnSize, child: _buildEfficiencyBadge()),
                    ],
                  ),

                // Центр - логотип (занимает оставшееся пространство)
                Expanded(
                  child: Center(
                    child: Image.asset(
                      'assets/images/arabica_logo.png',
                      height: btnSize,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // Правая часть - кнопки
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Кнопка обновления
                    if (_userRole?.role == UserRole.employee || _userRole?.role == UserRole.admin || _userRole?.role == UserRole.developer)
                      GestureDetector(
                        onTap: () async {
                          if (_isUpdateAvailable) {
                            await AppUpdateService.performUpdate(context);
                          } else {
                            final hasUpdate = await AppUpdateService.checkUpdateAvailability();
                            if (mounted) {
                              setState(() => _isUpdateAvailable = hasUpdate);
                              if (hasUpdate) {
                                await AppUpdateService.performUpdate(context);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Установлена актуальная версия'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          }
                        },
                        child: SizedBox(
                          width: btnSize,
                          height: btnSize,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: btnSize,
                                height: btnSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isUpdateAvailable
                                      ? AppColors.success
                                      : Colors.white.withOpacity(0.1),
                                  border: Border.all(
                                    color: _isUpdateAvailable
                                        ? AppColors.successLight
                                        : Colors.white.withOpacity(0.3),
                                    width: 2,
                                  ),
                                  boxShadow: _isUpdateAvailable
                                      ? [
                                          BoxShadow(
                                            color: AppColors.success.withOpacity(0.4),
                                            blurRadius: 8,
                                            offset: Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  Icons.system_update_rounded,
                                  color: _isUpdateAvailable ? Colors.white : Colors.white.withOpacity(0.7),
                                  size: iconSize,
                                ),
                              ),
                              if (_isUpdateAvailable)
                                Positioned(
                                  right: 0.w,
                                  top: 0.h,
                                  child: Container(
                                    width: isEmployee ? 12 : 14,
                                    height: isEmployee ? 12 : 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.red,
                                      border: Border.all(color: AppColors.emerald, width: 2),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '1',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isEmployee ? 7 : 8,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (_userRole?.role == UserRole.employee || _userRole?.role == UserRole.admin || _userRole?.role == UserRole.developer)
                      SizedBox(width: btnGap),
                    // Жёлтая кнопка поиска товара
                    if (_userRole?.role != UserRole.client)
                      GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ProductSearchPage()));
                        },
                        child: Container(
                          width: btnSize,
                          height: btnSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.amber,
                            border: Border.all(color: AppColors.amberLight, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.amber.withOpacity(0.4),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.search_rounded,
                            color: Colors.black87,
                            size: iconSize,
                          ),
                        ),
                      ),
                    if (_userRole?.role != UserRole.client)
                      SizedBox(width: btnGap),
                    // Кнопка выхода
                    GestureDetector(
                      onTap: _logout,
                      child: Container(
                        width: btnSize,
                        height: btnSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: Icon(
                          Icons.logout_rounded,
                          color: Colors.white.withOpacity(0.7),
                          size: iconSize,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: isEmployee ? 8 : 20),

          // Приветствие — всегда строго по центру экрана
          if (_userName != null && _userName!.isNotEmpty) ...[
            // Линия
            Center(
              child: Container(
                width: 40,
                height: 1,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
            SizedBox(height: isEmployee ? 6 : 16),

            Center(
              child: Text(
                _getFirstName(_userName),
                style: TextStyle(
                  fontSize: isEmployee ? 20 : 24,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Минималистичный бейдж рейтинга для левого верхнего угла
  Widget _buildRatingBadge() {
    if (_employeeRating == null) return SizedBox.shrink();

    final rating = _employeeRating!;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.leaderboard_outlined,
            color: Colors.white.withOpacity(0.8),
            size: 14,
          ),
          SizedBox(width: 4),
          Text(
            '${rating.position}/${rating.totalEmployees}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 11.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Бейдж эффективности для левого верхнего угла
  Widget _buildEfficiencyBadge() {
    if (_efficiencyPoints == null) return SizedBox.shrink();

    final points = _efficiencyPoints!;
    final isPositive = points >= 0;
    final formattedPoints = isPositive
        ? '+${points.toStringAsFixed(1)}'
        : points.toStringAsFixed(1);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isPositive
              ? AppColors.success.withOpacity(0.5)
              : Colors.orange.withOpacity(0.5),
        ),
        color: isPositive
            ? AppColors.success.withOpacity(0.15)
            : Colors.orange.withOpacity(0.15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.trending_up_outlined : Icons.trending_down_outlined,
            color: isPositive
                ? AppColors.successLight
                : Colors.orange.shade300,
            size: 14,
          ),
          SizedBox(width: 4),
          Text(
            formattedPoints,
            style: TextStyle(
              color: isPositive
                  ? AppColors.successLight
                  : Colors.orange.shade300,
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Пункты меню только для клиентов (9 пунктов)
  List<Widget> _getClientMenuItems() {
    return [
      _buildCompactTile(Icons.coffee_outlined, 'Меню', () async {
        final shop = await _showShopDialog(context);
        if (!mounted || shop == null) return;
        final cats = await _loadCategories(shop.address);
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => MenuGroupsPage(groups: cats, selectedShop: shop.address),
        ));
      }),
      _buildCompactTile(Icons.shopping_bag_outlined, 'Корзина', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => CartPage()));
      }),
      _buildCompactTile(Icons.place_outlined, 'Кофейни', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ShopsOnMapPage()));
      }),
      _buildCompactTile(Icons.card_membership_outlined, 'Лояльность', () async {
        final enabled = await FirebaseService.areNotificationsEnabled();
        if (!enabled && context.mounted) {
          final result = await NotificationRequiredDialog.show(context);
          if (result == true) {
            await Future.delayed(Duration(milliseconds: 500));
            final ok = await FirebaseService.areNotificationsEnabled();
            if (ok && context.mounted) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => LoyaltyPage()));
            }
          }
          return;
        }
        Navigator.push(context, MaterialPageRoute(builder: (_) => LoyaltyPage()));
      }),
      _buildCompactTile(Icons.star_outline_rounded, 'Отзывы', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewTypeSelectionPage()));
      }),
      _buildCompactTile(
        Icons.chat_bubble_outline_rounded, 'Диалоги', () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => MyDialogsPage()));
          _loadMyDialogsCount();
        },
        badge: _myDialogsUnreadCount,
      ),
      _buildCompactTile(Icons.search_outlined, 'Поиск', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProductSearchShopSelectionPage()));
      }),
      _buildCompactTile(Icons.work_outline_rounded, 'Работа', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => JobApplicationWelcomePage()));
      }),
    ];
  }

  /// Секции меню для сотрудников (3 секции по 6 функций)
  List<List<Widget>> _getEmployeeSections() {
    // Секция 1: Повседневные Задачи (6 функций)
    final dailyTasks = _getDailyTasksSection();
    // Секция 2: Информация (6 функций)
    final information = _getInformationSection();
    // Секция 3: Работа с клиентами (6 функций)
    final clientWork = _getClientWorkSection();

    return [dailyTasks, information, clientWork];
  }

  /// Секция: Повседневные Задачи
  List<Widget> _getDailyTasksSection() {
    return [
      // 1. Я на работе
      _buildCompactTile(Icons.access_time_outlined, 'Я на работе', () async {
        await _executeWithChainCheck('attendance', () async {
          final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
          final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
          try {
            final hasAttendance = await AttendanceService.hasAttendanceToday(employeeName);
            if (!context.mounted) return;
            if (hasAttendance) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Вы уже отметились сегодня'), backgroundColor: Colors.orange.shade700),
              );
              return;
            }
          } catch (e) {
            Logger.warning('Ошибка проверки отметки: $e');
          }
          if (!context.mounted) return;
          await _markAttendanceAutomatically(context, employeeName);
        });
      }),
      // 2. Пересменка
      _buildCompactTile(Icons.swap_horiz_rounded, 'Пересменка', () async {
        await _executeWithChainCheck('shift', () async {
          final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
          final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
          if (!context.mounted) return;
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftShopSelectionPage(employeeName: employeeName)));
        });
      }),
      // 3. Сдать смену
      _buildCompactTile(Icons.check_circle_outline_rounded, 'Сдать смену', () async {
        await _executeWithChainCheck('shift_handover', () async {
          final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
          final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
          if (!context.mounted) return;
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftHandoverShopSelectionPage(employeeName: employeeName)));
        });
      }),
      // 4. Пересчёт
      _buildCompactTile(Icons.inventory_2_outlined, 'Пересчёт', () async {
        await _executeWithChainCheck('recount', () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => RecountShopSelectionPage()));
        });
      }),
      // 5. РКО
      _buildCompactTile(Icons.receipt_long_outlined, 'РКО', () async {
        await _executeWithChainCheck('rko', () async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
            if (phone == null || phone.isEmpty) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Не удалось определить телефон сотрудника'), backgroundColor: Colors.red.shade700),
                );
              }
              return;
            }
            final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
            final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);
            if (registration == null || !registration.isVerified) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Только верифицированные сотрудники могут создавать РКО'), backgroundColor: Colors.orange.shade700),
                );
              }
              return;
            }
            if (!context.mounted) return;
            await Navigator.push(context, MaterialPageRoute(builder: (_) => RKOTypeSelectionPage()));
          } catch (e) {
            Logger.error('Ошибка проверки верификации', e);
          }
        });
      }),
      // 6. Задачи
      _buildCompactTile(Icons.task_alt_outlined, 'Задачи', () async {
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeId = await EmployeesPage.getCurrentEmployeeId();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted) return;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => MyTasksPage(employeeId: employeeId ?? employeeName, employeeName: employeeName),
        ));
        _loadActiveTasksCount(_employeeId);
      }, badge: _activeTasksCount),
    ];
  }

  /// Секция: Информация
  List<Widget> _getInformationSection() {
    return [
      // 1. Рецепты
      _buildCompactTile(Icons.restaurant_menu_outlined, 'Рецепты', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => RecipesListPage()));
      }),
      // 2. Обучение
      _buildCompactTile(Icons.menu_book_outlined, 'Обучение', () => _showTrainingDialog(context)),
      // 3. Мой график
      _buildCompactTile(Icons.calendar_month_outlined, 'Мой график', () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => MySchedulePage()));
        _loadShiftTransferUnreadCount(_employeeId);
      }, badge: _shiftTransferUnreadCount),
      // 4. Эффективность
      _buildCompactTile(Icons.trending_up_outlined, 'Эффектив.', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => MyEfficiencyPage()));
      }),
      // 5. Колесо
      _buildCompactTile(Icons.album_outlined, 'Колесо', () async {
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeId = await EmployeesPage.getCurrentEmployeeId();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted || employeeId == null) return;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => FortuneWheelPage(employeeId: employeeId, employeeName: employeeName),
        ));
        _loadAvailableSpins(employeeId);
      }, badge: _availableSpins),
      // 6. Чат
      _buildCompactTile(Icons.chat_outlined, 'Чат', () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MessengerShellPage()));
        _loadMessengerUnreadCount();
      }, badge: _messengerUnreadCount),
    ];
  }

  /// Секция: Работа с клиентами
  List<Widget> _getClientWorkSection() {
    return [
      // 1. Бонусы
      _buildCompactTile(Icons.card_giftcard_outlined, 'Бонусы', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => LoyaltyScannerPage()));
      }),
      // 2. Приз (выдать приз клиенту от колеса удачи)
      _buildCompactTile(Icons.emoji_events_outlined, 'Приз', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PrizeScannerPage()));
      }),
      // 3. Код
      _buildCompactTile(Icons.person_add_outlined, 'Код', () {
        if (_referralCode != null) {
          _showReferralCodeDialog(_referralCode!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Код приглашения не назначен'), backgroundColor: Colors.orange.shade700),
          );
        }
      }),
      // 3. Ответы
      _buildCompactTile(Icons.search_outlined, 'Ответы', () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductQuestionsManagementPage()));
        _loadUnreadProductQuestionsCount();
      }, badge: _unreadProductQuestionsCount),
      // 4. Заказы
      _buildCompactTile(Icons.shopping_cart_outlined, 'Заказы', () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeeOrdersPage()));
        _loadPendingOrdersCount();
      }, badge: _pendingOrdersCount),
      // 5. Клиент
      _buildCompactTile(Icons.person_outline, 'Клиент', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ClientFunctionsPage()));
      }),
      // 6. Пустое место (Обучение ИИ перенесено вниз)
      SizedBox(),
    ];
  }


  /// Диалог выбора обучения (тесты или статьи)
  Future<void> _showTrainingDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Text('Обучение', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.quiz_outlined, color: Colors.white.withOpacity(0.8)),
              title: Text('Тестирование', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                _executeWithChainCheck('testing', () async {
                  if (!context.mounted) return;
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => TestPage()));
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.article_outlined, color: Colors.white.withOpacity(0.8)),
              title: Text('Статьи', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => TrainingPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ЦЕПОЧКА ВЫПОЛНЕНИЙ - блокировка действий
  // ═══════════════════════════════════════════════════════════════

  /// Загрузить статус цепочки (кэш 30 секунд)
  Future<ExecutionChainStatus?> _loadChainStatus() async {
    // Используем кэш если он свежий (< 30 сек)
    if (_chainStatus != null && _chainStatusLoadedAt != null) {
      final age = DateTime.now().difference(_chainStatusLoadedAt!);
      if (age.inSeconds < 30) return _chainStatus;
    }

    try {
      final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
      final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';

      final prefs = await SharedPreferences.getInstance();
      final shopAddress = prefs.getString('selectedShopAddress') ?? '';

      _chainStatus = await ExecutionChainService.getStatus(
        employeeName: employeeName,
        shopAddress: shopAddress,
      );
      _chainStatusLoadedAt = DateTime.now();
    } catch (e) {
      Logger.warning('Ошибка загрузки статуса цепочки: $e');
    }
    return _chainStatus;
  }

  /// Сбросить кэш цепочки (после выполнения действия)
  void _invalidateChainCache() {
    _chainStatus = null;
    _chainStatusLoadedAt = null;
  }

  /// Выполнить действие с проверкой цепочки
  Future<void> _executeWithChainCheck(String stepId, Future<void> Function() action) async {
    Logger.debug('🔗 Chain check for step: $stepId');
    final status = await _loadChainStatus();
    Logger.debug('🔗 Chain status: ${status == null ? "null" : "enabled=${status.enabled}, canExecute=${ status.canExecute(stepId)}"}');

    // Если цепочка выключена, не загружена, или шаг не в цепочке — просто выполняем
    if (status == null || !status.enabled || status.canExecute(stepId)) {
      await action();
      // Сбрасываем кэш после выполнения (действие могло завершить шаг)
      _invalidateChainCache();
      return;
    }

    // Шаг заблокирован — показать диалог
    final blockingStep = status.getBlockingStep(stepId);
    if (blockingStep != null && mounted) {
      _showChainBlockDialog(blockingStep);
    }
  }

  /// Диалог блокировки цепочки
  void _showChainBlockDialog(ExecutionChainStep blockingStep) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: AppColors.gold.withOpacity(0.3)),
        ),
        title: Row(
          children: [
            Icon(Icons.link_rounded, color: AppColors.gold, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text('Цепочка действий',
                style: TextStyle(color: Colors.white, fontSize: 18.sp),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Сначала выполните:',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14.sp),
            ),
            SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.r),
                color: AppColors.gold.withOpacity(0.1),
                border: Border.all(color: AppColors.gold.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(_getStepIcon(blockingStep.id), color: AppColors.gold, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      blockingStep.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Закрыть', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToStep(blockingStep.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.night,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
            child: Text('Перейти'),
          ),
        ],
      ),
    );
  }

  /// Иконка для шага цепочки
  IconData _getStepIcon(String stepId) {
    switch (stepId) {
      case 'attendance': return Icons.access_time_outlined;
      case 'testing': return Icons.quiz_outlined;
      case 'shift': return Icons.swap_horiz_rounded;
      case 'recount': return Icons.inventory_2_outlined;
      case 'shift_handover': return Icons.check_circle_outline_rounded;
      case 'coffee_machine': return Icons.coffee_outlined;
      case 'envelope': return Icons.mail_outlined;
      case 'rko': return Icons.receipt_long_outlined;
      default: return Icons.help_outline;
    }
  }

  /// Навигация к шагу цепочки
  Future<void> _navigateToStep(String stepId) async {
    switch (stepId) {
      case 'attendance':
        // Повторяем логику "Я на работе"
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted) return;
        await _markAttendanceAutomatically(context, employeeName);
        _invalidateChainCache();
        break;
      case 'testing':
        Navigator.push(context, MaterialPageRoute(builder: (_) => TestPage()));
        _invalidateChainCache();
        break;
      case 'shift':
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted) return;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ShiftShopSelectionPage(employeeName: employeeName),
        ));
        _invalidateChainCache();
        break;
      case 'recount':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => RecountShopSelectionPage()));
        _invalidateChainCache();
        break;
      case 'shift_handover':
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted) return;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ShiftHandoverShopSelectionPage(employeeName: employeeName),
        ));
        _invalidateChainCache();
        break;
      case 'coffee_machine':
        // Кофемашина доступна через "Сдать смену"
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted) return;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ShiftHandoverShopSelectionPage(employeeName: employeeName),
        ));
        _invalidateChainCache();
        break;
      case 'envelope':
        // Конверт доступен через "Сдать смену"
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted) return;
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => ShiftHandoverShopSelectionPage(employeeName: employeeName),
        ));
        _invalidateChainCache();
        break;
      case 'rko':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => RKOTypeSelectionPage()));
        _invalidateChainCache();
        break;
    }
  }

  /// Диалог показа кода приглашения
  void _showReferralCodeDialog(int code) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Text('Код приглашения', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$code',
              style: TextStyle(
                color: Colors.white,
                fontSize: 36.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Поделитесь этим кодом с клиентом',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14.sp),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Закрыть', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Автоматическая отметка посещаемости с GPS
  Future<void> _markAttendanceAutomatically(BuildContext context, String employeeName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.white.withOpacity(0.8)),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Определяем местоположение...',
                style: TextStyle(color: Colors.white.withOpacity(0.9)),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final position = await AttendanceService.getCurrentLocation();
      final shops = await ShopService.getShopsForCurrentUser();

      if (!context.mounted) return;

      final nearestShop = AttendanceService.findNearestShop(
        position.latitude,
        position.longitude,
        shops,
      );

      Navigator.pop(context);

      if (nearestShop == null || nearestShop.latitude == null || nearestShop.longitude == null) {
        _showAttendanceErrorDialog(context, 'Магазины не найдены');
        return;
      }

      final isWithinRadius = AttendanceService.isWithinRadius(
        position.latitude,
        position.longitude,
        nearestShop.latitude!,
        nearestShop.longitude!,
      );

      if (!isWithinRadius) {
        final distance = AttendanceService.calculateDistance(
          position.latitude,
          position.longitude,
          nearestShop.latitude!,
          nearestShop.longitude!,
        );
        _showAttendanceErrorDialog(
          context,
          'Вы не находитесь рядом с магазином\n\n'
          'Ближайший магазин: ${nearestShop.name}\n'
          'Расстояние: ${distance.toStringAsFixed(0)} м\n'
          'Допустимый радиус: 750 м',
        );
        return;
      }

      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (!context.mounted) return;

      bool hasScheduledShift = false;
      String? scheduledShopAddress;
      String? scheduledShiftType;

      if (employeeId != null) {
        try {
          final today = DateTime.now();
          final schedule = await WorkScheduleService.getEmployeeSchedule(employeeId, today);
          if (!context.mounted) return;

          for (var entry in schedule.entries) {
            if (entry.date.year == today.year &&
                entry.date.month == today.month &&
                entry.date.day == today.day) {
              hasScheduledShift = true;
              scheduledShopAddress = entry.shopAddress;
              scheduledShiftType = entry.shiftType.label;
              break;
            }
          }
        } catch (e) {
          Logger.warning('Ошибка проверки графика: $e');
        }
      }

      if (!hasScheduledShift) {
        if (!context.mounted) return;
        final shouldContinue = await _showNoScheduleWarning(context, nearestShop.name);
        if (!context.mounted) return;
        if (!shouldContinue) return;
      }

      if (hasScheduledShift &&
          scheduledShopAddress != null &&
          scheduledShopAddress != nearestShop.address) {
        if (!context.mounted) return;
        final shouldContinue = await _showWrongShopWarning(
          context,
          nearestShop.name,
          scheduledShopAddress,
          scheduledShiftType ?? '',
        );
        if (!context.mounted) return;
        if (!shouldContinue) return;
      }

      if (!context.mounted) return;
      final distance = AttendanceService.calculateDistance(
        position.latitude,
        position.longitude,
        nearestShop.latitude!,
        nearestShop.longitude!,
      );

      final result = await AttendanceService.markAttendance(
        employeeName: employeeName,
        shopAddress: nearestShop.address,
        latitude: position.latitude,
        longitude: position.longitude,
        distance: distance,
      );

      if (!context.mounted) return;
      _showAttendanceResultDialog(context, result, nearestShop.name);
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _showAttendanceErrorDialog(context, 'Ошибка: $e');
      }
    }
  }

  void _showAttendanceErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red.shade300),
            SizedBox(width: 8),
            Text(
              'Ошибка',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showNoScheduleWarning(BuildContext context, String shopName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade300),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Смена не найдена',
                style: TextStyle(color: Colors.white.withOpacity(0.9)),
              ),
            ),
          ],
        ),
        content: Text(
          'У вас сегодня нет запланированной смены в графике.\n\n'
          'Магазин: $shopName\n\n'
          'Всё равно отметиться?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
            child: Text('Отметиться'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<bool> _showWrongShopWarning(
    BuildContext context,
    String actualShop,
    String scheduledShop,
    String shiftType,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Row(
          children: [
            Icon(Icons.swap_horiz_rounded, color: Colors.orange.shade300),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Другой магазин',
                style: TextStyle(color: Colors.white.withOpacity(0.9)),
              ),
            ),
          ],
        ),
        content: Text(
          'По графику вы должны работать в другом магазине.\n\n'
          'По графику: $scheduledShop ($shiftType)\n'
          'Вы находитесь: $actualShop\n\n'
          'Всё равно отметиться здесь?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Отмена',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
            child: Text('Отметиться'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showAttendanceResultDialog(BuildContext context, AttendanceResult result, String shopName) {
    String title;
    String message;
    Color iconColor;
    IconData icon;

    if (result.success) {
      if (result.isOnTime == true) {
        title = 'Вы пришли вовремя';
        message = 'Магазин: $shopName\n${result.message ?? ''}';
        iconColor = Colors.green.shade300;
        icon = Icons.check_circle_outline_rounded;
      } else if (result.isOnTime == false && result.lateMinutes != null) {
        title = 'Вы опоздали';
        message = 'Магазин: $shopName\nОпоздание: ${result.lateMinutes} минут';
        iconColor = Colors.orange.shade300;
        icon = Icons.warning_amber_rounded;
      } else {
        title = 'Отметка сохранена';
        message = 'Магазин: $shopName\n${result.message ?? 'Отметка вне смены'}';
        iconColor = Colors.amber.shade300;
        icon = Icons.info_outline_rounded;
      }
    } else {
      title = 'Ошибка';
      message = result.error ?? 'Неизвестная ошибка';
      iconColor = Colors.red.shade300;
      icon = Icons.error_outline_rounded;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: Colors.white.withOpacity(0.9)),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }


  /// ═══════════════════════════════════════════════════════════════
  /// КОМПАКТНАЯ ПЛИТКА ДЛЯ КЛИЕНТОВ - помещается на экран
  /// ═══════════════════════════════════════════════════════════════
  Widget _buildCompactTile(IconData icon, String label, VoidCallback onTap, {int? badge}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16.r),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16.r),
              splashColor: Colors.white.withOpacity(0.1),
              highlightColor: Colors.white.withOpacity(0.05),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final h = constraints.maxHeight;
                  final iconSize = (h * 0.42).clamp(20.0, 44.0);
                  final fontSize = (h * 0.14).clamp(9.0, 14.0);
                  final gap = (h * 0.05).clamp(2.0, 6.0);
                  final vPad = (h * 0.08).clamp(4.0, 10.0);

                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: vPad),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Icon(
                                icon,
                                size: iconSize,
                                color: Colors.white.withOpacity(0.85),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: gap),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: fontSize,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Бейдж
        if (badge != null && badge > 0)
          Positioned(
            top: 4.h,
            right: 4.w,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                badge > 99 ? '99+' : badge.toString(),
                style: TextStyle(
                  color: AppColors.emerald,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<Shop?> _showShopDialog(BuildContext context) async {
    return Navigator.push<Shop>(
      context,
      MaterialPageRoute(
        builder: (_) => _ShopSelectionPage(),
      ),
    );
  }

  Future<List<String>> _loadCategories(String address) async {
    try {
      final recipes = await Recipe.loadRecipesFromServer();
      return recipes.map((r) => r.category).where((c) => c.isNotEmpty).toSet().toList()..sort();
    } catch (e) {
      Logger.error('Ошибка загрузки категорий', e);
      return [];
    }
  }
}

/// Полноэкранная страница выбора магазина
class _ShopSelectionPage extends StatefulWidget {
  _ShopSelectionPage();

  @override
  State<_ShopSelectionPage> createState() => _ShopSelectionPageState();
}

class _ShopSelectionPageState extends State<_ShopSelectionPage> {
  List<Shop>? _shops;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    try {
      final shops = await ShopService.getShopsForCurrentUser();
      if (mounted) {
        setState(() {
          _shops = shops;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
      if (mounted) {
        setState(() {
          _error = 'Не удалось загрузить список магазинов';
          _isLoading = false;
        });
      }
    }
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
              _buildAppBar(),
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 24.w, 16.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.8),
              size: 22,
            ),
          ),
          Expanded(
            child: Text(
              'Выберите кофейню',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.white.withOpacity(0.6),
                size: 48,
              ),
              SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16.sp,
                ),
              ),
              SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  if (mounted) setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _loadShops();
                },
                icon: Icon(Icons.refresh, color: Colors.white),
                label: Text('Повторить', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_shops == null || _shops!.isEmpty) {
      return Center(
        child: Text(
          'Магазины не найдены',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 16.sp,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
      itemCount: _shops!.length,
      separatorBuilder: (_, __) => SizedBox(height: 12),
      itemBuilder: (_, i) {
        final shop = _shops![i];
        return _buildShopRow(shop);
      },
    );
  }

  Widget _buildShopRow(Shop shop) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: () => Navigator.pop(context, shop),
        borderRadius: BorderRadius.circular(16.r),
        splashColor: Colors.white.withOpacity(0.1),
        highlightColor: Colors.white.withOpacity(0.05),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.r),
                  color: Colors.white.withOpacity(0.1),
                ),
                child: Icon(
                  Icons.storefront_outlined,
                  color: Colors.white.withOpacity(0.85),
                  size: 22,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  shop.address,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.4),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
