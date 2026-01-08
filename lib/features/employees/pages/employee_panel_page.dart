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
import '../models/user_role_model.dart';
import '../../rko/pages/rko_type_selection_page.dart';
import '../services/employee_registration_service.dart';
import '../../orders/pages/employee_orders_page.dart';
import '../../employee_chat/pages/employee_chats_list_page.dart';
import '../../work_schedule/services/work_schedule_service.dart';
import '../../work_schedule/models/work_schedule_model.dart';
import '../../loyalty/pages/loyalty_scanner_page.dart';
import '../../work_schedule/pages/my_schedule_page.dart';
import '../../product_questions/pages/product_questions_management_page.dart';
import '../../efficiency/pages/my_efficiency_page.dart';

/// Страница панели работника
class EmployeePanelPage extends StatefulWidget {
  const EmployeePanelPage({super.key});

  @override
  State<EmployeePanelPage> createState() => _EmployeePanelPageState();
}

class _EmployeePanelPageState extends State<EmployeePanelPage> {
  String? _userName;
  UserRoleData? _userRole;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final roleData = await UserRoleService.loadUserRole();
      setState(() {
        _userRole = roleData;
        _userName = roleData?.displayName;
      });
    } catch (e) {
      print('Ошибка загрузки данных пользователя: $e');
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

                if (hasAttendance && mounted) {
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
                print('⚠️ Ошибка проверки отметки: $e');
              }

              if (!mounted) return;
              // Автоматическое определение магазина по геолокации
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
                print('Ошибка проверки верификации: $e');
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
          _buildSection(
            context,
            title: 'Заказы (Клиенты)',
            icon: Icons.shopping_cart,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EmployeeOrdersPage(),
                ),
              );
            },
          ),
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
          _buildSection(
            context,
            title: 'Списать бонусы',
            icon: Icons.qr_code_scanner,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LoyaltyScannerPage(),
                ),
              );
            },
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
          _buildSection(
            context,
            title: 'Ответы (поиск товара)',
            icon: Icons.search,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProductQuestionsManagementPage(),
                ),
              );
            },
          ),
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

      // 3. Найти ближайший магазин
      final nearestShop = AttendanceService.findNearestShop(
        position.latitude,
        position.longitude,
        shops,
      );

      if (!mounted) return;
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
      bool hasScheduledShift = false;
      String? scheduledShopAddress;
      String? scheduledShiftType;

      if (employeeId != null) {
        try {
          final today = DateTime.now();
          final schedule = await WorkScheduleService.getEmployeeSchedule(employeeId, today);

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
          print('⚠️ Ошибка проверки графика: $e');
        }
      }

      // Если смены нет - показать предупреждение
      if (!hasScheduledShift && mounted) {
        final shouldContinue = await _showNoScheduleWarning(context, nearestShop.name);
        if (!shouldContinue) {
          return;
        }
      }

      // Если смена есть, но магазин другой - показать предупреждение
      if (hasScheduledShift &&
          scheduledShopAddress != null &&
          scheduledShopAddress != nearestShop.address &&
          mounted) {
        final shouldContinue = await _showWrongShopWarning(
          context,
          nearestShop.name,
          scheduledShopAddress,
          scheduledShiftType ?? '',
        );
        if (!shouldContinue) {
          return;
        }
      }

      // 6. Отметить приход
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

      if (!mounted) return;

      // 7. Показать результат
      _showAttendanceResultDialog(context, result, nearestShop.name);
    } catch (e) {
      if (mounted) {
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


