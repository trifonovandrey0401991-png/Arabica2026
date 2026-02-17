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
import '../../loyalty/pages/prize_scanner_page.dart';
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
import '../../../app/pages/client_functions_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница панели работника (сетка как у сотрудника)
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
                child: _buildEmployeeMenu(),
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
              'Панель работника',
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

  // ═══════════════════════════════════════════════════════════════
  // СЕТКА МЕНЮ (как у сотрудника)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEmployeeMenu() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 0.h),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          final availableWidth = constraints.maxWidth;

          final headerHeight = 20.0;
          final aiButtonHeight = 52.0;
          final aiButtonTopMargin = 10.0;

          final sections = _getEmployeeSections();

          final totalGridHeight = availableHeight - (headerHeight * 3) - aiButtonHeight - aiButtonTopMargin;
          final sectionSpacing = totalGridHeight * 0.03;
          final gridHeight = totalGridHeight - (sectionSpacing * 2);
          final sectionHeight = gridHeight / 3 + headerHeight;

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

  // ═══════════════════════════════════════════════════════════════
  // СЕКЦИИ СЕТКИ
  // ═══════════════════════════════════════════════════════════════

  List<List<Widget>> _getEmployeeSections() {
    return [
      _getDailyTasksSection(),
      _getInformationSection(),
      _getClientWorkSection(),
    ];
  }

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
              SnackBar(
                content: Text('Вы уже отметились сегодня'),
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
      }),
      // 2. Пересменка
      _buildCompactTile(Icons.swap_horiz_rounded, 'Пересменка', () async {
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShiftShopSelectionPage(employeeName: employeeName),
          ),
        );
      }),
      // 3. Сдать смену
      _buildCompactTile(Icons.check_circle_outline_rounded, 'Сдать смену', () async {
        final systemEmployeeName = await EmployeesPage.getCurrentEmployeeName();
        final employeeName = systemEmployeeName ?? _userRole?.displayName ?? _userName ?? 'Сотрудник';
        if (!context.mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ShiftHandoverShopSelectionPage(employeeName: employeeName),
          ),
        );
      }),
      // 4. Пересчёт
      _buildCompactTile(Icons.inventory_2_outlined, 'Пересчёт', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => RecountShopSelectionPage()),
        );
      }),
      // 5. РКО
      _buildCompactTile(Icons.receipt_long_outlined, 'РКО', () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');

          if (phone == null || phone.isEmpty) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Не удалось определить телефон сотрудника'),
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
                  content: Text('Только верифицированные сотрудники могут создавать РКО'),
                  backgroundColor: Colors.orange.shade700,
                ),
              );
            }
            return;
          }

          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RKOTypeSelectionPage()),
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
      }),
      // 6. Задачи
      _buildCompactTile(Icons.task_alt_outlined, 'Задачи', () async {
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
      }, badge: _activeTasksCount),
    ];
  }

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
        _loadShiftTransferUnreadCount();
      }, badge: _shiftTransferUnreadCount),
      // 4. Эффективность
      _buildCompactTile(Icons.trending_up_outlined, 'Эффектив.', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => MyEfficiencyPage()));
      }),
      // 5. Колесо
      _buildCompactTile(Icons.album_outlined, 'Колесо', () async {
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
      }, badge: _availableSpins),
      // 6. Чат
      _buildCompactTile(Icons.chat_outlined, 'Чат', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeeChatsListPage()));
      }),
    ];
  }

  List<Widget> _getClientWorkSection() {
    return [
      // 1. Бонусы
      _buildCompactTile(Icons.card_giftcard_outlined, 'Бонусы', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => LoyaltyScannerPage()));
      }),
      // 2. Приз
      _buildCompactTile(Icons.emoji_events_outlined, 'Приз', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PrizeScannerPage()));
      }),
      // 3. Код
      _buildCompactTile(Icons.person_add_outlined, 'Код', () {
        if (_referralCode != null) {
          _showReferralCodeDialog(_referralCode!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Код приглашения не назначен'),
              backgroundColor: Colors.orange.shade700,
            ),
          );
        }
      }),
      // 4. Ответы
      _buildCompactTile(Icons.search_outlined, 'Ответы', () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductQuestionsManagementPage()));
        _loadUnreadProductQuestionsCount();
      }, badge: _unreadProductQuestionsCount),
      // 5. Заказы
      _buildCompactTile(Icons.shopping_cart_outlined, 'Заказы', () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => EmployeeOrdersPage()));
        _loadPendingOrdersCount();
      }, badge: _pendingOrdersCount),
      // 6. Клиент
      _buildCompactTile(Icons.person_outline, 'Клиент', () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ClientFunctionsPage()));
      }),
    ];
  }

  // ═══════════════════════════════════════════════════════════════
  // КНОПКА ОБУЧЕНИЕ ИИ
  // ═══════════════════════════════════════════════════════════════

  Widget _buildAITrainingButton([double height = 52]) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.emeraldLight.withOpacity(0.8), AppColors.emerald],
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
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AITrainingPage())),
          borderRadius: BorderRadius.circular(16.r),
          splashColor: Colors.white.withOpacity(0.2),
          highlightColor: Colors.white.withOpacity(0.1),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.smart_toy_outlined, color: Colors.white.withOpacity(0.9), size: 24),
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
                    border: Border.all(color: AppColors.turquoise.withOpacity(0.5), width: 1),
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

  // ═══════════════════════════════════════════════════════════════
  // ДИАЛОГИ
  // ═══════════════════════════════════════════════════════════════

  void _showReferralCodeDialog(int code) {
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
            Icon(Icons.person_add_outlined, color: Colors.white.withOpacity(0.85)),
            SizedBox(width: 8),
            Text(
              'Код приглашения',
              style: TextStyle(color: Colors.white.withOpacity(0.9)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Text(
                '#$code',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Сообщите этот код новому сотруднику',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13.sp,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Закрыть',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
        ],
      ),
    );
  }

  void _showTrainingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.emeraldDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        contentPadding: EdgeInsets.all(20.w),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Обучение и тесты',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            SizedBox(height: 20),
            _buildDialogOption(
              icon: Icons.menu_book_outlined,
              title: 'Обучение',
              subtitle: 'Изучайте материалы',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => TrainingPage()),
                );
              },
            ),
            SizedBox(height: 12),
            _buildDialogOption(
              icon: Icons.quiz_outlined,
              title: 'Сдать тест',
              subtitle: 'Проверьте знания',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => TestPage()),
                );
              },
            ),
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
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
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.r),
                  color: Colors.white.withOpacity(0.1),
                ),
                child: Icon(
                  icon,
                  color: Colors.white.withOpacity(0.85),
                  size: 22,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.sp,
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

  // ═══════════════════════════════════════════════════════════════
  // ЛОГИКА ПОСЕЩАЕМОСТИ (GPS)
  // ═══════════════════════════════════════════════════════════════

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
}
