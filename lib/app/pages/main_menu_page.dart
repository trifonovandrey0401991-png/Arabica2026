import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../../features/menu/pages/menu_groups_page.dart';
import '../../features/orders/pages/cart_page.dart';
import '../../features/orders/pages/orders_page.dart';
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
import '../../features/employee_chat/pages/employee_chats_list_page.dart';
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
import '../../features/work_schedule/services/work_schedule_service.dart';
import '../../features/work_schedule/models/work_schedule_model.dart';
import '../../core/services/app_update_service.dart';
import '../../features/efficiency/services/efficiency_data_service.dart';
import '../../features/network_management/pages/network_management_page.dart';
import '../../features/main_cash/pages/main_cash_page.dart';

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
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
  int? _referralCode;

  // Флаг доступности обновления
  bool _isUpdateAvailable = false;

  // Баллы эффективности за текущий месяц
  double? _efficiencyPoints;

  // ═══════════════════════════════════════════════════════════════
  // МИНИМАЛИСТИЧНАЯ ПАЛИТРА - только изумруд и белый
  // ═══════════════════════════════════════════════════════════════
  static const Color _emerald = Color(0xFF1A4D4D);       // Из логотипа
  static const Color _emeraldLight = Color(0xFF2A6363); // Светлее
  static const Color _emeraldDark = Color(0xFF0D2E2E);  // Темнее
  static const Color _night = Color(0xFF051515);        // Почти чёрный
  static const Color _gold = Color(0xFFD4AF37);         // Золотой акцент

  @override
  void initState() {
    super.initState();
    _loadCachedRole();
    _loadUserData();
    _syncReports();
    _loadEmployeeId();
    _loadTotalReportsCount();
    _loadMyDialogsCount();
    _loadEmployeeRating();
    // Загрузка счётчиков для сотрудников
    _loadEmployeeCounters();
    // Проверка обновлений
    _checkForUpdates();
    // Загрузка эффективности
    _loadEfficiencyPoints();
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

  /// Загрузка общего счётчика для бейджа "Отчёты" (сумма всех дочерних)
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

  /// Загрузка всех счётчиков для сотрудника
  Future<void> _loadEmployeeCounters() async {
    _loadPendingOrdersCount();
    _loadUnreadProductQuestionsCount();
    _loadActiveTasksCount();
    _loadAvailableSpins();
    _loadShiftTransferUnreadCount();
    _loadReferralCode();
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

  Future<void> _loadActiveTasksCount() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (employeeId != null) {
        final assignments = await TaskService.getMyAssignments(employeeId);
        final activeCount = assignments.where((a) =>
          a.status == TaskStatus.pending || a.status == TaskStatus.submitted
        ).length;
        if (mounted) setState(() => _activeTasksCount = activeCount);
      }
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика задач', e);
    }
  }

  Future<void> _loadAvailableSpins() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (employeeId != null) {
        final spins = await FortuneWheelService.getAvailableSpins(employeeId);
        if (mounted) setState(() => _availableSpins = spins.availableSpins);
      }
    } catch (e) {
      Logger.error('Ошибка загрузки прокруток', e);
    }
  }

  Future<void> _loadShiftTransferUnreadCount() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (employeeId != null) {
        final count = await ShiftTransferService.getUnreadCount(employeeId);
        if (mounted) setState(() => _shiftTransferUnreadCount = count);
      }
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика пересменок', e);
    }
  }

  Future<void> _loadReferralCode() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (employeeId != null) {
        final employees = await EmployeeService.getEmployees();
        final employee = employees.firstWhere(
          (e) => e.id == employeeId,
          orElse: () => throw StateError('Employee not found'),
        );
        if (mounted && employee.referralCode != null) {
          setState(() => _referralCode = employee.referralCode);
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки referralCode', e);
    }
  }

  Future<void> _loadEmployeeRating() async {
    if (_employeeId == null) {
      // Подождём загрузки employeeId
      await Future.delayed(const Duration(milliseconds: 500));
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
        setState(() => _employeeId = employeeId);
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
          roleData = await UserRoleService.getUserRole(phone);
          await UserRoleService.saveUserRole(roleData);
          if (roleData.displayName.isNotEmpty) {
            await prefs.setString('user_name', roleData.displayName);
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
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        title: const Text('Выход', style: TextStyle(color: Colors.white)),
        content: const Text('Выйти из аккаунта?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти', style: TextStyle(color: Colors.white)),
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
          MaterialPageRoute(builder: (_) => const RegistrationPage()),
          (_) => false,
        );
      }
    } catch (e) {
      Logger.error('Ошибка выхода', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _userRole?.role ?? UserRole.client;

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
        return _buildEmployeeMenu(); // Manager видит меню сотрудника
      case UserRole.admin:
        return _buildAdminMenu();
      case UserRole.developer:
        return _buildDeveloperMenu(); // Developer - расширенное меню
    }
  }

  /// Компактное меню для клиентов - помещается на экран без прокрутки
  Widget _buildClientMenu() {
    final items = _getClientMenuItems();
    // 9 пунктов + 1 пустая ячейка = 10, сетка 2x5
    const rows = 5;
    const cols = 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ...items,
              // Пустая ячейка в конце
              const SizedBox(),
            ],
          );
        },
      ),
    );
  }

  /// Стандартное меню для админов (прокручивается)
  Widget _buildDefaultMenu() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.0,
        children: _getMenuItems(),
      ),
    );
  }

  /// Меню для админов - 4 широкие строки на весь экран
  Widget _buildAdminMenu() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;

          // 3 кнопки + 2 отступа между ними
          const buttonCount = 3;
          const spacing = 16.0;
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
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage()));
                  _loadTotalReportsCount();
                },
                badge: _totalReportsCount,
              ),
              const SizedBox(height: spacing),
              _buildAdminRow(
                Icons.grid_view_rounded,
                'Панель сотрудника',
                'Функции сотрудника',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeePanelPage())),
              ),
              const SizedBox(height: spacing),
              _buildAdminRow(
                Icons.person_outline,
                'Клиент',
                'Клиентские функции',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientFunctionsPage())),
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;

          // 5 кнопок + 4 отступа между ними
          const buttonCount = 5;
          const spacing = 12.0;
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
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NetworkManagementPage())),
              ),
              const SizedBox(height: spacing),
              _buildAdminRow(
                Icons.tune_rounded,
                'Управление',
                'Настройки системы и данные',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataManagementPage())),
              ),
              const SizedBox(height: spacing),
              _buildAdminRow(
                Icons.analytics_outlined,
                'Отчёты',
                'Аналитика и статистика',
                buttonHeight,
                () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage()));
                  _loadTotalReportsCount();
                },
                badge: _totalReportsCount,
              ),
              const SizedBox(height: spacing),
              _buildAdminRow(
                Icons.grid_view_rounded,
                'Панель сотрудника',
                'Функции сотрудника',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeePanelPage())),
              ),
              const SizedBox(height: spacing),
              _buildAdminRow(
                Icons.person_outline,
                'Клиент',
                'Клиентские функции',
                buttonHeight,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientFunctionsPage())),
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
  }) {
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: Colors.white.withOpacity(0.1),
          highlightColor: Colors.white.withOpacity(0.05),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white.withOpacity(0.9),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null && badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        color: _emerald,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.4),
                    size: 28,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Компактное меню для сотрудников - 3xN без прокрутки + футуристичная кнопка ИИ
  Widget _buildEmployeeMenu() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          final availableWidth = constraints.maxWidth;

          // Фиксированные размеры
          const headerHeight = 20.0;
          const aiButtonHeight = 52.0;
          const aiButtonTopMargin = 10.0;
          const cols = 3;

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
    const cols = 3;
    const rows = 2;
    const spacing = 6.0;

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
                  fontSize: 13,
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
              physics: const NeverScrollableScrollPhysics(),
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
            _emeraldLight.withOpacity(0.8),
            _emerald,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF4ECDC4).withOpacity(0.6), // Бирюзовый акцент
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AITrainingPage()));
          },
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withOpacity(0.2),
          highlightColor: Colors.white.withOpacity(0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  color: Colors.white.withOpacity(0.9),
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  'Обучение ИИ',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ECDC4).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF4ECDC4).withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'AI',
                    style: TextStyle(
                      color: Color(0xFF4ECDC4),
                      fontSize: 11,
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
                  _emeraldLight.withOpacity(0.8),
                  _emerald,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF4ECDC4).withOpacity(0.6),
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AITrainingPage()));
                },
                borderRadius: BorderRadius.circular(16),
                splashColor: Colors.white.withOpacity(0.2),
                highlightColor: Colors.white.withOpacity(0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.smart_toy_outlined, color: Colors.white.withOpacity(0.9), size: 20),
                    const SizedBox(width: 6),
                    Text(
                      'ИИ',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.95),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4ECDC4).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF4ECDC4).withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'AI',
                        style: TextStyle(
                          color: Color(0xFF4ECDC4),
                          fontSize: 10,
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
        const SizedBox(width: 8),
        // Главная касса — 50%, золотой
        Expanded(
          child: Container(
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _gold.withOpacity(0.9),
                  const Color(0xFFB8960C),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _gold.withOpacity(0.7),
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const MainCashPage()));
                },
                borderRadius: BorderRadius.circular(16),
                splashColor: Colors.white.withOpacity(0.2),
                highlightColor: Colors.white.withOpacity(0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.account_balance_outlined, color: Colors.white, size: 20),
                    const SizedBox(width: 6),
                    const Text(
                      'Касса',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
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

    return Padding(
      padding: EdgeInsets.fromLTRB(24, isEmployee ? 8 : 16, 24, isEmployee ? 8 : 20),
      child: Column(
        children: [
          // Рейтинг, Логотип и выход - Row layout для правильного центрирования
          SizedBox(
            height: isEmployee ? 36 : 44,
            child: Row(
              children: [
                // Левая часть - бейджи (фиксированная ширина)
                SizedBox(
                  width: 140,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      if (showRating) _buildRatingBadge(),
                      if (showRating && showEfficiency) const SizedBox(width: 4),
                      if (showEfficiency) _buildEfficiencyBadge(),
                    ],
                  ),
                ),

                // Центр - логотип
                Expanded(
                  child: Center(
                    child: Image.asset(
                      'assets/images/arabica_logo.png',
                      height: isEmployee ? 36 : 44,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // Правая часть - кнопки (фиксированная ширина)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                      // Кнопка обновления (для сотрудников, админов и разработчиков)
                      if (_userRole?.role == UserRole.employee || _userRole?.role == UserRole.admin || _userRole?.role == UserRole.developer)
                        GestureDetector(
                          onTap: () async {
                            if (_isUpdateAvailable) {
                              await AppUpdateService.performUpdate(context);
                            } else {
                              // Повторная проверка
                              final hasUpdate = await AppUpdateService.checkUpdateAvailability();
                              if (mounted) {
                                setState(() => _isUpdateAvailable = hasUpdate);
                                if (hasUpdate) {
                                  await AppUpdateService.performUpdate(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Установлена актуальная версия'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          child: SizedBox(
                            width: isEmployee ? 32 : 40,
                            height: isEmployee ? 32 : 40,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: isEmployee ? 32 : 40,
                                  height: isEmployee ? 32 : 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isUpdateAvailable
                                      ? const Color(0xFF4CAF50) // Зелёный если есть обновление
                                      : Colors.white.withOpacity(0.1),
                                  border: Border.all(
                                    color: _isUpdateAvailable
                                        ? const Color(0xFF81C784)
                                        : Colors.white.withOpacity(0.3),
                                    width: 2,
                                  ),
                                  boxShadow: _isUpdateAvailable
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFF4CAF50).withOpacity(0.4),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  Icons.system_update_rounded,
                                  color: _isUpdateAvailable ? Colors.white : Colors.white.withOpacity(0.7),
                                  size: isEmployee ? 16 : 20,
                                ),
                              ),
                              // Badge с индикатором
                              if (_isUpdateAvailable)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    width: isEmployee ? 12 : 14,
                                    height: isEmployee ? 12 : 14,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.red,
                                      border: Border.all(color: _emerald, width: 2),
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
                        const SizedBox(width: 12),
                      // Жёлтая кнопка поиска товара (скрыта для клиентов)
                      if (_userRole?.role != UserRole.client)
                        GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductSearchPage()));
                          },
                          child: Container(
                            width: isEmployee ? 32 : 40,
                            height: isEmployee ? 32 : 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFC107), // Жёлтый цвет
                              border: Border.all(color: const Color(0xFFFFD54F), width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFC107).withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.search_rounded,
                              color: Colors.black87,
                              size: isEmployee ? 16 : 20,
                            ),
                          ),
                        ),
                      const SizedBox(width: 12),
                      // Кнопка выхода
                      GestureDetector(
                        onTap: _logout,
                        child: Container(
                          width: isEmployee ? 32 : 40,
                          height: isEmployee ? 32 : 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Icon(
                            Icons.logout_rounded,
                            color: Colors.white.withOpacity(0.7),
                            size: isEmployee ? 16 : 20,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          SizedBox(height: isEmployee ? 8 : 20),

          // Приветствие
          if (_userName != null && _userName!.isNotEmpty) ...[
            // Линия
            Container(
              width: 40,
              height: 1,
              color: Colors.white.withOpacity(0.3),
            ),
            SizedBox(height: isEmployee ? 6 : 16),

            Text(
              _getFirstName(_userName),
              style: TextStyle(
                fontSize: isEmployee ? 20 : 24,
                fontWeight: FontWeight.w300,
                color: Colors.white,
                letterSpacing: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Минималистичный бейдж рейтинга для левого верхнего угла
  Widget _buildRatingBadge() {
    if (_employeeRating == null) return const SizedBox.shrink();

    final rating = _employeeRating!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
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
          const SizedBox(width: 4),
          Text(
            '${rating.position}/${rating.totalEmployees}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Бейдж эффективности для левого верхнего угла
  Widget _buildEfficiencyBadge() {
    if (_efficiencyPoints == null) return const SizedBox.shrink();

    final points = _efficiencyPoints!;
    final isPositive = points >= 0;
    final formattedPoints = isPositive
        ? '+${points.toStringAsFixed(1)}'
        : points.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPositive
              ? const Color(0xFF4CAF50).withOpacity(0.5)
              : Colors.orange.withOpacity(0.5),
        ),
        color: isPositive
            ? const Color(0xFF4CAF50).withOpacity(0.15)
            : Colors.orange.withOpacity(0.15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPositive ? Icons.trending_up_outlined : Icons.trending_down_outlined,
            color: isPositive
                ? const Color(0xFF81C784)
                : Colors.orange.shade300,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            formattedPoints,
            style: TextStyle(
              color: isPositive
                  ? const Color(0xFF81C784)
                  : Colors.orange.shade300,
              fontSize: 11,
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
        Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage()));
      }),
      _buildCompactTile(Icons.receipt_long_outlined, 'Заказы', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersPage()));
      }),
      _buildCompactTile(Icons.place_outlined, 'Кофейни', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopsOnMapPage()));
      }),
      _buildCompactTile(Icons.card_membership_outlined, 'Лояльность', () async {
        final enabled = await FirebaseService.areNotificationsEnabled();
        if (!enabled && context.mounted) {
          final result = await NotificationRequiredDialog.show(context);
          if (result == true) {
            await Future.delayed(const Duration(milliseconds: 500));
            final ok = await FirebaseService.areNotificationsEnabled();
            if (ok && context.mounted) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoyaltyPage()));
            }
          }
          return;
        }
        Navigator.push(context, MaterialPageRoute(builder: (_) => const LoyaltyPage()));
      }),
      _buildCompactTile(Icons.star_outline_rounded, 'Отзывы', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewTypeSelectionPage()));
      }),
      _buildCompactTile(
        Icons.chat_bubble_outline_rounded, 'Диалоги', () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDialogsPage()));
          _loadMyDialogsCount();
        },
        badge: _myDialogsUnreadCount,
      ),
      _buildCompactTile(Icons.search_outlined, 'Поиск', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductSearchShopSelectionPage()));
      }),
      _buildCompactTile(Icons.work_outline_rounded, 'Работа', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const JobApplicationWelcomePage()));
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
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        try {
          final hasAttendance = await AttendanceService.hasAttendanceToday(employeeName);
          if (!context.mounted) return;
          if (hasAttendance) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: const Text('Вы уже отметились сегодня'), backgroundColor: Colors.orange.shade700),
            );
            return;
          }
        } catch (e) {
          Logger.warning('Ошибка проверки отметки: $e');
        }
        if (!context.mounted) return;
        await _markAttendanceAutomatically(context, employeeName);
      }),
      // 2. Пересменка
      _buildCompactTile(Icons.swap_horiz_rounded, 'Пересменка', () async {
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftShopSelectionPage(employeeName: employeeName)));
      }),
      // 3. Сдать смену
      _buildCompactTile(Icons.check_circle_outline_rounded, 'Сдать смену', () async {
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftHandoverShopSelectionPage(employeeName: employeeName)));
      }),
      // 4. Пересчёт
      _buildCompactTile(Icons.inventory_2_outlined, 'Пересчёт', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const RecountShopSelectionPage()));
      }),
      // 5. РКО
      _buildCompactTile(Icons.receipt_long_outlined, 'РКО', () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
          if (phone == null || phone.isEmpty) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: const Text('Не удалось определить телефон сотрудника'), backgroundColor: Colors.red.shade700),
              );
            }
            return;
          }
          final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
          final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);
          if (registration == null || !registration.isVerified) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: const Text('Только верифицированные сотрудники могут создавать РКО'), backgroundColor: Colors.orange.shade700),
              );
            }
            return;
          }
          if (!context.mounted) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => const RKOTypeSelectionPage()));
        } catch (e) {
          Logger.error('Ошибка проверки верификации', e);
        }
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
        _loadActiveTasksCount();
      }, badge: _activeTasksCount),
    ];
  }

  /// Секция: Информация
  List<Widget> _getInformationSection() {
    return [
      // 1. Рецепты
      _buildCompactTile(Icons.restaurant_menu_outlined, 'Рецепты', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const RecipesListPage()));
      }),
      // 2. Обучение
      _buildCompactTile(Icons.menu_book_outlined, 'Обучение', () => _showTrainingDialog(context)),
      // 3. Мой график
      _buildCompactTile(Icons.calendar_month_outlined, 'Мой график', () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MySchedulePage()));
        _loadShiftTransferUnreadCount();
      }, badge: _shiftTransferUnreadCount),
      // 4. Эффективность
      _buildCompactTile(Icons.trending_up_outlined, 'Эффектив.', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const MyEfficiencyPage()));
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
        _loadAvailableSpins();
      }, badge: _availableSpins),
      // 6. Чат
      _buildCompactTile(Icons.chat_outlined, 'Чат', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeChatsListPage()));
      }),
    ];
  }

  /// Секция: Работа с клиентами
  List<Widget> _getClientWorkSection() {
    return [
      // 1. Бонусы
      _buildCompactTile(Icons.card_giftcard_outlined, 'Бонусы', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const LoyaltyScannerPage()));
      }),
      // 2. Приз (выдать приз клиенту от колеса удачи)
      _buildCompactTile(Icons.emoji_events_outlined, 'Приз', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PrizeScannerPage()));
      }),
      // 3. Код
      _buildCompactTile(Icons.person_add_outlined, 'Код', () {
        if (_referralCode != null) {
          _showReferralCodeDialog(_referralCode!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Код приглашения не назначен'), backgroundColor: Colors.orange.shade700),
          );
        }
      }),
      // 3. Ответы
      _buildCompactTile(Icons.search_outlined, 'Ответы', () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductQuestionsManagementPage()));
        _loadUnreadProductQuestionsCount();
      }, badge: _unreadProductQuestionsCount),
      // 4. Заказы
      _buildCompactTile(Icons.shopping_cart_outlined, 'Заказы', () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeeOrdersPage()));
        _loadPendingOrdersCount();
      }, badge: _pendingOrdersCount),
      // 5. Клиент
      _buildCompactTile(Icons.person_outline, 'Клиент', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientFunctionsPage()));
      }),
      // 6. Пустое место (Обучение ИИ перенесено вниз)
      const SizedBox(),
    ];
  }


  /// Диалог выбора обучения (тесты или статьи)
  Future<void> _showTrainingDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: const Text('Обучение', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.quiz_outlined, color: Colors.white.withOpacity(0.8)),
              title: Text('Тестирование', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TestPage()));
              },
            ),
            ListTile(
              leading: Icon(Icons.article_outlined, color: Colors.white.withOpacity(0.8)),
              title: Text('Статьи', style: TextStyle(color: Colors.white.withOpacity(0.9))),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const TrainingPage()));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Диалог показа кода приглашения
  void _showReferralCodeDialog(int code) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: const Text('Код приглашения', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$code',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Поделитесь этим кодом с клиентом',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть', style: TextStyle(color: Colors.white)),
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
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.white.withOpacity(0.8)),
            const SizedBox(width: 16),
            Text(
              'Определяем местоположение...',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
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
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red.shade300),
            const SizedBox(width: 8),
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
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showNoScheduleWarning(BuildContext context, String shopName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade300),
            const SizedBox(width: 8),
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
            child: const Text('Отметиться'),
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
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Row(
          children: [
            Icon(Icons.swap_horiz_rounded, color: Colors.orange.shade300),
            const SizedBox(width: 8),
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
            child: const Text('Отметиться'),
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
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 8),
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
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  List<Widget> _getMenuItems() {
    final role = _userRole?.role ?? UserRole.client;
    final items = <Widget>[];

    // Для админа и разработчика - административные функции + Клиент
    if (role == UserRole.admin || role == UserRole.developer) {
      // "Управление" видит только разработчик
      if (role == UserRole.developer) {
        items.add(_buildTile(Icons.tune_rounded, 'Управление', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const DataManagementPage()));
        }));
      }

      items.add(_buildTile(
        Icons.analytics_outlined, 'Отчёты', () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage()));
          _loadTotalReportsCount();
        },
        badge: _totalReportsCount,
      ));

      items.add(_buildTile(Icons.grid_view_rounded, 'Панель', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeePanelPage()));
      }));

      items.add(_buildTile(Icons.person_outline, 'Клиент', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientFunctionsPage()));
      }));

      return items;
    }

    // Для остальных ролей - полное меню (на случай если используется)
    items.add(_buildTile(Icons.coffee_rounded, 'Меню', () async {
      final shop = await _showShopDialog(context);
      if (!mounted || shop == null) return;
      final cats = await _loadCategories(shop.address);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => MenuGroupsPage(groups: cats, selectedShop: shop.address),
      ));
    }));

    items.add(_buildTile(Icons.shopping_bag_outlined, 'Корзина', () {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CartPage()));
    }));

    items.add(_buildTile(Icons.receipt_long_outlined, 'Заказы', () {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersPage()));
    }));

    items.add(_buildTile(Icons.place_outlined, 'Кофейни', () {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopsOnMapPage()));
    }));

    items.add(_buildTile(Icons.card_membership_outlined, 'Лояльность', () async {
      final enabled = await FirebaseService.areNotificationsEnabled();
      if (!enabled && context.mounted) {
        final result = await NotificationRequiredDialog.show(context);
        if (result == true) {
          await Future.delayed(const Duration(milliseconds: 500));
          final ok = await FirebaseService.areNotificationsEnabled();
          if (ok && context.mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LoyaltyPage()));
          }
        }
        return;
      }
      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoyaltyPage()));
    }));

    items.add(_buildTile(Icons.star_outline_rounded, 'Отзывы', () {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewTypeSelectionPage()));
    }));

    items.add(_buildTile(
      Icons.chat_bubble_outline_rounded, 'Диалоги', () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDialogsPage()));
        _loadMyDialogsCount();
      },
      badge: _myDialogsUnreadCount,
    ));

    items.add(_buildTile(Icons.search_rounded, 'Поиск', () {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductSearchShopSelectionPage()));
    }));

    if (role == UserRole.employee) {
      items.add(_buildTile(Icons.grid_view_rounded, 'Панель', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeePanelPage()));
      }));
    }

    return items;
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
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              splashColor: Colors.white.withOpacity(0.1),
              highlightColor: Colors.white.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: Icon(
                          icon,
                          size: 32,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Бейдж
        if (badge != null && badge > 0)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge > 99 ? '99+' : badge.toString(),
                style: TextStyle(
                  color: _emerald,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// ═══════════════════════════════════════════════════════════════
  /// МИНИМАЛИСТИЧНАЯ ПЛИТКА - для админов и сотрудников
  /// ═══════════════════════════════════════════════════════════════
  Widget _buildTile(IconData icon, String label, VoidCallback onTap, {int? badge}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Основная кнопка
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              splashColor: Colors.white.withOpacity(0.1),
              highlightColor: Colors.white.withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: Icon(
                          icon,
                          size: 44,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Бейдж
        if (badge != null && badge > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge > 99 ? '99+' : badge.toString(),
                style: TextStyle(
                  color: _emerald,
                  fontSize: 11,
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
        builder: (_) => const _ShopSelectionPage(),
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
  const _ShopSelectionPage();

  @override
  State<_ShopSelectionPage> createState() => _ShopSelectionPageState();
}

class _ShopSelectionPageState extends State<_ShopSelectionPage> {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);

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
      padding: const EdgeInsets.fromLTRB(8, 8, 24, 16),
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
          const Expanded(
            child: Text(
              'Выберите кофейню',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w400,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.white.withOpacity(0.6),
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _loadShops();
                },
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Повторить', style: TextStyle(color: Colors.white)),
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
            fontSize: 16,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      itemCount: _shops!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final shop = _shops![i];
        return _buildShopRow(shop);
      },
    );
  }

  Widget _buildShopRow(Shop shop) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => Navigator.pop(context, shop),
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white.withOpacity(0.1),
        highlightColor: Colors.white.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white.withOpacity(0.1),
                ),
                child: Icon(
                  Icons.storefront_outlined,
                  color: Colors.white.withOpacity(0.85),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  shop.address,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 15,
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
