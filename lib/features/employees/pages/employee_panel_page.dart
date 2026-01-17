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
import '../../product_questions/pages/product_questions_management_page.dart';
import '../../product_questions/services/product_question_service.dart';
import '../../efficiency/pages/my_efficiency_page.dart';
import '../../tasks/pages/my_tasks_page.dart';
import '../../fortune_wheel/pages/fortune_wheel_page.dart';
import '../../fortune_wheel/services/fortune_wheel_service.dart';
import '../../tasks/services/task_service.dart';
import '../../tasks/models/task_model.dart';
import '../../../core/utils/logger.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadAvailableSpins();
    _loadPendingOrdersCount();
    _loadUnreadProductQuestionsCount();
    _loadActiveTasksCount();
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
            _availableSpins = spins?.availableSpins ?? 0;
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
      // 1. Загружаем персональные диалоги с непрочитанными сообщениями от клиента
      final dialogs = await ProductQuestionService.getAllPersonalDialogs();
      final unreadDialogsCount = dialogs.where((d) => d.hasUnreadFromClient).length;

      // 2. Загружаем количество неотвеченных общих вопросов (ProductQuestion)
      final unansweredQuestionsCount = await ProductQuestionService.getUnansweredQuestionsCount();

      // Суммируем оба счётчика
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
        // Считаем активные задачи: pending и submitted
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Панель работника'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            context,
            title: 'Обучение',
            icon: Icons.menu_book,
            onTap: () {
              _showTrainingDialog(context);
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Я на работе',
            icon: Icons.access_time,
            onTap: () async {
              final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
              final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';

              try {
                final hasAttendance = await AttendanceService.hasAttendanceToday(employeeName);

                if (!context.mounted) return;
                if (hasAttendance) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Вы уже отметились сегодня'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }
              } catch (e) {
                Logger.warning('Ошибка проверки отметки: $e');
              }

              // Автоматическое определение магазина по геолокации
              if (!context.mounted) return;
              await _markAttendanceAutomatically(context, employeeName);
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Пересменка',
            icon: Icons.work_history,
            onTap: () async {
              // ВАЖНО: Используем единый источник истины - меню "Сотрудники"
              // Это гарантирует, что имя будет совпадать с отображением в системе
              final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
              final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
              
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShiftShopSelectionPage(
                    employeeName: employeeName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Сдать Смену',
            icon: Icons.assignment_turned_in,
            onTap: () async {
              // ВАЖНО: Используем единый источник истины - меню "Сотрудники"
              final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
              final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';

              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ShiftHandoverShopSelectionPage(
                    employeeName: employeeName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Пересчет товаров',
            icon: Icons.inventory,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RecountShopSelectionPage()),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Рецепты',
            icon: Icons.restaurant_menu,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const RecipesListPage()),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'РКО',
            icon: Icons.receipt_long,
            onTap: () async {
              // Проверяем верификацию сотрудника
              try {
                final prefs = await SharedPreferences.getInstance();
                final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
                
                if (phone == null || phone.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Не удалось определить телефон сотрудника'),
                        backgroundColor: Colors.red,
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
                      const SnackBar(
                        content: Text('Только верифицированные сотрудники могут создавать РКО'),
                        backgroundColor: Colors.orange,
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
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 8),
          _buildOrdersButton(context),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Чат',
            icon: Icons.chat,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EmployeeChatsListPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Секция "Списать бонусы" и "Ваш код приглашения" на одной строке
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Списать бонусы
                Expanded(
                  child: Card(
                    elevation: 2,
                    child: ListTile(
                      leading: const Icon(Icons.qr_code_scanner, color: Color(0xFF004D40)),
                      title: const Text('Бонусы', style: TextStyle(fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoyaltyScannerPage(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Ваш код приглашения
                if (_referralCode != null)
                  Expanded(
                    child: Card(
                      elevation: 2,
                      child: ListTile(
                        leading: const Icon(Icons.person_add, color: Color(0xFF004D40)),
                        title: const Text('Код'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF004D40),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '#$_referralCode',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Мой график',
            icon: Icons.calendar_month,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MySchedulePage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildProductQuestionsButton(context),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Моя эффективность',
            icon: Icons.trending_up,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MyEfficiencyPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _buildMyTasksButton(context),
          const SizedBox(height: 8),
          _buildFortuneWheelButton(context),
          const SizedBox(height: 8),
          _buildSection(
            context,
            title: 'Обучение ИИ',
            icon: Icons.psychology,
            onTap: () {
              // TODO: Логика будет добавлена позже
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Функционал в разработке')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF004D40)),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _buildOrdersButton(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.shopping_cart, color: Color(0xFF004D40)),
            if (_pendingOrdersCount > 0)
              Positioned(
                right: -8,
                top: -8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    '$_pendingOrdersCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        title: const Text('Заказы (Клиенты)'),
        trailing: _pendingOrdersCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_pendingOrdersCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              )
            : const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const EmployeeOrdersPage(),
            ),
          );
          // Обновляем счётчик после возврата
          _loadPendingOrdersCount();
        },
      ),
    );
  }

  Widget _buildProductQuestionsButton(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.search, color: Color(0xFF004D40)),
            if (_unreadProductQuestionsCount > 0)
              Positioned(
                right: -8,
                top: -8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    '$_unreadProductQuestionsCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        title: const Text('Ответы (поиск товара)'),
        trailing: _unreadProductQuestionsCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_unreadProductQuestionsCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ProductQuestionsManagementPage(),
            ),
          );
          // Обновляем счётчик после возврата
          _loadUnreadProductQuestionsCount();
        },
      ),
    );
  }

  Widget _buildMyTasksButton(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.assignment, color: Color(0xFF004D40)),
            if (_activeTasksCount > 0)
              Positioned(
                right: -8,
                top: -8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    '$_activeTasksCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        title: const Text('Мои Задачи'),
        trailing: _activeTasksCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_activeTasksCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              )
            : const Icon(Icons.chevron_right),
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
          // Обновляем счётчик после возврата
          _loadActiveTasksCount();
        },
      ),
    );
  }

  Widget _buildFortuneWheelButton(BuildContext context) {
    return Card(
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: const LinearGradient(
            colors: [Color(0xFF004D40), Color(0xFF00796B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListTile(
          leading: const Text('🎡', style: TextStyle(fontSize: 28)),
          title: const Text(
            'Колесо Удачи',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: _availableSpins > 0
              ? Text(
                  'Доступно прокруток: $_availableSpins',
                  style: const TextStyle(color: Colors.white70),
                )
              : null,
          trailing: _availableSpins > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_availableSpins',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                )
              : const Icon(Icons.chevron_right, color: Colors.white),
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
            // Обновляем количество прокруток после возврата
            _loadAvailableSpins();
          },
        ),
      ),
    );
  }

  /// Показать диалог выбора: Обучение или Тест
  void _showTrainingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Обучение',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF004D40),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TrainingPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.menu_book),
                label: const Text('Обучение'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TestPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.quiz),
                label: const Text('Сдать тест'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Автоматическая отметка прихода на работу
  Future<void> _markAttendanceAutomatically(BuildContext context, String employeeName) async {
    // Показать диалог загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Определяем местоположение...'),
          ],
        ),
      ),
    );

    try {
      // 1. Получить геолокацию
      final position = await AttendanceService.getCurrentLocation();

      // 2. Загрузить список магазинов
      final shops = await Shop.loadShopsFromServer();

      if (!context.mounted) return;

      // 3. Найти ближайший магазин
      final nearestShop = AttendanceService.findNearestShop(
        position.latitude,
        position.longitude,
        shops,
      );

      Navigator.pop(context); // Закрыть диалог загрузки

      if (nearestShop == null || nearestShop.latitude == null || nearestShop.longitude == null) {
        _showErrorDialog(context, 'Магазины не найдены');
        return;
      }

      // 4. Проверить, в радиусе ли пользователь
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

      // 5. Проверить наличие смены в графике
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

          // Ищем смену на сегодня
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

      // Если смены нет - показать предупреждение
      if (!hasScheduledShift) {
        if (!context.mounted) return;
        final shouldContinue = await _showNoScheduleWarning(context, nearestShop.name);
        if (!context.mounted) return;
        if (!shouldContinue) {
          return;
        }
      }

      // Если смена есть, но магазин другой - показать предупреждение
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
        if (!shouldContinue) {
          return;
        }
      }

      // 6. Отметить приход
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

      // 7. Показать результат
      _showAttendanceResultDialog(context, result, nearestShop.name);
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Закрыть диалог загрузки если открыт
        _showErrorDialog(context, 'Ошибка: $e');
      }
    }
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Ошибка'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Показать предупреждение об отсутствии смены в графике
  Future<bool> _showNoScheduleWarning(BuildContext context, String shopName) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('Смена не найдена')),
          ],
        ),
        content: Text(
          'У вас сегодня нет запланированной смены в графике.\n\n'
          'Магазин: $shopName\n\n'
          'Всё равно отметиться?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Отметиться'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Показать предупреждение о несовпадении магазина
  Future<bool> _showWrongShopWarning(
    BuildContext context,
    String actualShop,
    String scheduledShop,
    String shiftType,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.swap_horiz, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('Другой магазин')),
          ],
        ),
        content: Text(
          'По графику вы должны работать в другом магазине.\n\n'
          'По графику: $scheduledShop ($shiftType)\n'
          'Вы находитесь: $actualShop\n\n'
          'Всё равно отметиться здесь?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
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
    Color backgroundColor;
    IconData icon;

    if (result.success) {
      if (result.isOnTime == true) {
        title = 'Вы пришли вовремя';
        message = 'Магазин: $shopName\n${result.message ?? ''}';
        backgroundColor = Colors.green;
        icon = Icons.check_circle;
      } else if (result.isOnTime == false && result.lateMinutes != null) {
        title = 'Вы опоздали';
        message = 'Магазин: $shopName\nОпоздание: ${result.lateMinutes} минут';
        backgroundColor = Colors.orange;
        icon = Icons.warning;
      } else {
        title = 'Отметка сохранена';
        message = 'Магазин: $shopName\n${result.message ?? 'Отметка вне смены'}';
        backgroundColor = Colors.amber;
        icon = Icons.info;
      }
    } else {
      title = 'Ошибка';
      message = result.error ?? 'Неизвестная ошибка';
      backgroundColor = Colors.red;
      icon = Icons.error;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Icon(icon, color: backgroundColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.black87),
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


