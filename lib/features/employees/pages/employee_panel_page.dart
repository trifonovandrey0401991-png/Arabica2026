import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../training/pages/training_page.dart';
import '../../tests/pages/test_page.dart';
import '../../shifts/pages/shift_shop_selection_page.dart';
import '../../shift_handover/pages/shift_handover_shop_selection_page.dart';
import '../../recount/pages/recount_shop_selection_page.dart';
import '../../recipes/pages/recipes_list_page.dart';
import '../../attendance/services/attendance_service.dart';
import '../../shops/models/shop_model.dart';
import 'employees_page.dart';
import '../services/user_role_service.dart';
import '../services/employee_service.dart';
import '../models/user_role_model.dart';
import '../../rko/pages/rko_type_selection_page.dart';
import '../services/employee_registration_service.dart';
import '../../orders/pages/employee_orders_page.dart';
import '../../orders/services/order_service.dart';
import '../../employee_chat/pages/employee_chats_list_page.dart';
import '../../work_schedule/services/work_schedule_service.dart';
import '../../work_schedule/models/work_schedule_model.dart';
import '../../loyalty/pages/loyalty_scanner_page.dart';
import '../../work_schedule/pages/my_schedule_page.dart';
import '../../work_schedule/services/shift_transfer_service.dart';
import '../../product_questions/pages/product_questions_management_page.dart';
import '../../product_questions/services/product_question_service.dart';
import '../../efficiency/pages/my_efficiency_page.dart';
import '../../tasks/pages/my_tasks_page.dart';
import '../../fortune_wheel/pages/fortune_wheel_page.dart';
import '../../fortune_wheel/services/fortune_wheel_service.dart';
import '../../tasks/services/task_service.dart';
import '../../tasks/models/task_model.dart';
import '../../../core/utils/logger.dart';
import '../../ai_training/pages/ai_training_page.dart';

/// Страница панели работника
class EmployeePanelPage extends StatefulWidget {
  const EmployeePanelPage({super.key});

  @override
  State<EmployeePanelPage> createState() => _EmployeePanelPageState();
}

class _EmployeePanelPageState extends State<EmployeePanelPage> {
  String? _userName;
  UserRoleData? _userRole;
  int? _referralCode;
  int _availableSpins = 0;
  int _pendingOrdersCount = 0;
  int _unreadProductQuestionsCount = 0;
  int _activeTasksCount = 0;
  int _shiftTransferUnreadCount = 0;

  // ═══════════════════════════════════════════════════════════════
  // МИНИМАЛИСТИЧНАЯ ПАЛИТРА
  // ═══════════════════════════════════════════════════════════════
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadAvailableSpins();
    _loadPendingOrdersCount();
    _loadUnreadProductQuestionsCount();
    _loadActiveTasksCount();
    _loadShiftTransferUnreadCount();
  }

  Future<void> _loadUserData() async {
    try {
      final roleData = await UserRoleService.loadUserRole();
      setState(() {
        _userRole = roleData;
        _userName = roleData?.displayName;
      });

      // Загружаем referralCode текущего сотрудника
      await _loadReferralCode();
    } catch (e) {
      Logger.error('Ошибка загрузки данных пользователя', e);
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
          setState(() {
            _referralCode = employee.referralCode;
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки referralCode', e);
    }
  }

  Future<void> _loadAvailableSpins() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (employeeId != null) {
        final spins = await FortuneWheelService.getAvailableSpins(employeeId);
        if (mounted) {
          setState(() {
            _availableSpins = spins.availableSpins;
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки прокруток', e);
    }
  }

  Future<void> _loadPendingOrdersCount() async {
    try {
      final orders = await OrderService.getAllOrders(status: 'pending');
      if (mounted) {
        setState(() {
          _pendingOrdersCount = orders.length;
        });
      }
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

      if (mounted) {
        setState(() {
          _unreadProductQuestionsCount = totalCount;
        });
      }
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

        if (mounted) {
          setState(() {
            _activeTasksCount = activeCount;
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика задач', e);
    }
  }

  Future<void> _loadShiftTransferUnreadCount() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (employeeId != null) {
        final count = await ShiftTransferService.getUnreadCount(employeeId);
        if (mounted) {
          setState(() {
            _shiftTransferUnreadCount = count;
          });
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки счётчика пересменок', e);
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  children: [
                    _buildRow(
                      icon: Icons.menu_book_outlined,
                      title: 'Обучение',
                      onTap: () => _showTrainingDialog(context),
                    ),
                    _buildRow(
                      icon: Icons.access_time_outlined,
                      title: 'Я на работе',
                      onTap: () async {
                        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
                        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';

                        try {
                          final hasAttendance = await AttendanceService.hasAttendanceToday(employeeName);
                          if (!context.mounted) return;
                          if (hasAttendance) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Вы уже отметились сегодня'),
                                backgroundColor: Colors.orange.shade700,
                              ),
                            );
                            return;
                          }
                        } catch (e) {
                          Logger.warning('Ошибка проверки отметки: $e');
                        }

                        if (!context.mounted) return;
                        await _markAttendanceAutomatically(context, employeeName);
                      },
                    ),
                    _buildRow(
                      icon: Icons.swap_horiz_rounded,
                      title: 'Пересменка',
                      onTap: () async {
                        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
                        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ShiftShopSelectionPage(employeeName: employeeName),
                          ),
                        );
                      },
                    ),
                    _buildRow(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Сдать Смену',
                      onTap: () async {
                        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
                        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ShiftHandoverShopSelectionPage(employeeName: employeeName),
                          ),
                        );
                      },
                    ),
                    _buildRow(
                      icon: Icons.inventory_2_outlined,
                      title: 'Пересчет товаров',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RecountShopSelectionPage()),
                        );
                      },
                    ),
                    _buildRow(
                      icon: Icons.restaurant_menu_outlined,
                      title: 'Рецепты',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RecipesListPage()),
                        );
                      },
                    ),
                    _buildRow(
                      icon: Icons.receipt_long_outlined,
                      title: 'РКО',
                      onTap: () async {
                        try {
                          final prefs = await SharedPreferences.getInstance();
                          final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');

                          if (phone == null || phone.isEmpty) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Не удалось определить телефон сотрудника'),
                                  backgroundColor: Colors.red.shade700,
                                ),
                              );
                            }
                            return;
                          }

                          final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
                          final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);

                          if (registration == null || !registration.isVerified) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Только верифицированные сотрудники могут создавать РКО'),
                                  backgroundColor: Colors.orange.shade700,
                                ),
                              );
                            }
                            return;
                          }

                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RKOTypeSelectionPage()),
                          );
                        } catch (e) {
                          Logger.error('Ошибка проверки верификации', e);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Ошибка: $e'),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    _buildRow(
                      icon: Icons.shopping_cart_outlined,
                      title: 'Заказы (Клиенты)',
                      badge: _pendingOrdersCount,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const EmployeeOrdersPage()),
                        );
                        _loadPendingOrdersCount();
                      },
                    ),
                    _buildRow(
                      icon: Icons.chat_outlined,
                      title: 'Чат',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const EmployeeChatsListPage()),
                        );
                      },
                    ),
                    // Бонусы и Код приглашения
                    Row(
                      children: [
                        Expanded(
                          child: _buildCompactRow(
                            icon: Icons.card_giftcard_outlined,
                            title: 'Бонусы',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const LoyaltyScannerPage()),
                              );
                            },
                          ),
                        ),
                        if (_referralCode != null) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildReferralCodeRow(),
                          ),
                        ],
                      ],
                    ),
                    _buildRow(
                      icon: Icons.calendar_month_outlined,
                      title: 'Мой график',
                      badge: _shiftTransferUnreadCount,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const MySchedulePage()),
                        );
                        _loadShiftTransferUnreadCount();
                      },
                    ),
                    _buildRow(
                      icon: Icons.search_outlined,
                      title: 'Ответы (поиск товара)',
                      badge: _unreadProductQuestionsCount,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ProductQuestionsManagementPage()),
                        );
                        _loadUnreadProductQuestionsCount();
                      },
                    ),
                    _buildRow(
                      icon: Icons.trending_up_outlined,
                      title: 'Моя Эффективность',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const MyEfficiencyPage()),
                        );
                      },
                    ),
                    _buildRow(
                      icon: Icons.task_alt_outlined,
                      title: 'Мои Задачи',
                      badge: _activeTasksCount,
                      onTap: () async {
                        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
                        final employeeId = await EmployeesPage.getCurrentEmployeeId();
                        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';

                        if (!context.mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MyTasksPage(
                              employeeId: employeeId ?? employeeName,
                              employeeName: employeeName,
                            ),
                          ),
                        );
                        _loadActiveTasksCount();
                      },
                    ),
                    _buildFortuneWheelRow(),
                    _buildRow(
                      icon: Icons.psychology_outlined,
                      title: 'Обучение ИИ',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const AITrainingPage()),
                        );
                      },
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
              'Панель работника',
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

  Widget _buildRow({
    required IconData icon,
    required String title,
    int? badge,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
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
                    icon,
                    color: Colors.white.withOpacity(0.85),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                if (badge != null && badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        color: _emerald,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.4),
                    size: 24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withOpacity(0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white.withOpacity(0.85),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.4),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReferralCodeRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withOpacity(0.1),
              ),
              child: Icon(
                Icons.person_add_outlined,
                color: Colors.white.withOpacity(0.85),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Код',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Text(
                '#$_referralCode',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFortuneWheelRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () async {
            final employeeId = await EmployeesPage.getCurrentEmployeeId();
            final employeeName = await EmployeesPage.getCurrentEmployeeName() ??
                _userRole?.displayName ?? _userName ?? 'Сотрудник';

            if (!context.mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FortuneWheelPage(
                  employeeId: employeeId ?? employeeName,
                  employeeName: employeeName,
                ),
              ),
            );
            _loadAvailableSpins();
          },
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withOpacity(0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _availableSpins > 0
                    ? const Color(0xFFFFD700).withOpacity(0.5)
                    : Colors.white.withOpacity(0.15),
              ),
              gradient: _availableSpins > 0
                  ? LinearGradient(
                      colors: [
                        const Color(0xFFFFD700).withOpacity(0.15),
                        Colors.transparent,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: _availableSpins > 0
                        ? const Color(0xFFFFD700).withOpacity(0.2)
                        : Colors.white.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.stars_outlined,
                    color: _availableSpins > 0
                        ? const Color(0xFFFFD700)
                        : Colors.white.withOpacity(0.85),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Колесо Удачи',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (_availableSpins > 0)
                        Text(
                          'Доступно: $_availableSpins',
                          style: TextStyle(
                            color: const Color(0xFFFFD700).withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_availableSpins > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_availableSpins',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withOpacity(0.4),
                    size: 24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTrainingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Обучение и тесты',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 20),
            _buildDialogOption(
              icon: Icons.menu_book_outlined,
              title: 'Обучение',
              subtitle: 'Изучайте материалы',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TrainingPage()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildDialogOption(
              icon: Icons.quiz_outlined,
              title: 'Сдать тест',
              subtitle: 'Проверьте знания',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TestPage()),
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.white.withOpacity(0.2)),
                  ),
                ),
                child: Text(
                  'Отмена',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white.withOpacity(0.1),
                ),
                child: Icon(
                  icon,
                  color: Colors.white.withOpacity(0.85),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.4),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

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
      final shops = await Shop.loadShopsFromServer();

      if (!context.mounted) return;

      final nearestShop = AttendanceService.findNearestShop(
        position.latitude,
        position.longitude,
        shops,
      );

      Navigator.pop(context);

      if (nearestShop == null || nearestShop.latitude == null || nearestShop.longitude == null) {
        _showErrorDialog(context, 'Магазины не найдены');
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
        _showErrorDialog(
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
        _showErrorDialog(context, 'Ошибка: $e');
      }
    }
  }

  void _showErrorDialog(BuildContext context, String message) {
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
}
