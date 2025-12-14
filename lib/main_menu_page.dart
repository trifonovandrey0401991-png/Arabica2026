import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'menu_groups_page.dart';
import 'cart_page.dart';
import 'orders_page.dart';
import 'employees_page.dart';
import 'test_notifications_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'loyalty_page.dart';
import 'loyalty_scanner_page.dart';
import 'shop_model.dart';
import 'training_page.dart';
import 'test_page.dart';
import 'shift_shop_selection_page.dart';
import 'shift_reports_list_page.dart';
import 'shift_sync_service.dart';
import 'rko_service.dart';
import 'recipes_list_page.dart';
import 'recipe_edit_page.dart';
import 'review_type_selection_page.dart';
import 'reviews_list_page.dart';
import 'my_dialogs_page.dart';
import 'recount_shop_selection_page.dart';
import 'recount_reports_list_page.dart';
import 'user_role_service.dart';
import 'user_role_model.dart';
import 'role_test_page.dart';
import 'attendance_shop_selection_page.dart';
import 'attendance_reports_page.dart';
import 'attendance_service.dart';
import 'employee_registration_page.dart';
import 'employee_registration_select_employee_page.dart';
import 'rko_type_selection_page.dart';
import 'employee_registration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'rko_reports_page.dart';
import 'kpi_type_selection_page.dart';

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  String? _userName;
  UserRoleData? _userRole;
  bool _isLoadingRole = false; // Флаг для предотвращения параллельных запросов

  @override
  void initState() {
    super.initState();
    // Сначала загружаем кэшированную роль для немедленного отображения
    _loadCachedRole();
    // Затем обновляем роль через API
    _loadUserData();
    // Синхронизация отчетов при открытии главного меню
    _syncReports();
  }

  /// Загрузить кэшированную роль для немедленного отображения
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
        print('📦 Кэшированная роль загружена: ${cachedRole?.role.name ?? "нет"}');
      }
    } catch (e) {
      print('⚠️ Ошибка загрузки кэшированной роли: $e');
    }
  }

  Future<void> _syncReports() async {
    try {
      await ShiftSyncService.syncAllReports();
    } catch (e) {
      print('⚠️ Ошибка синхронизации: $e');
    }
  }

  Future<void> _loadUserData() async {
    // Предотвращаем параллельные запросы
    if (_isLoadingRole) {
      print('⚠️ Загрузка роли уже выполняется, пропускаем...');
      return;
    }
    
    _isLoadingRole = true;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('user_name');
      final phone = prefs.getString('user_phone');
      
      // Загружаем роль пользователя из кэша (как fallback)
      UserRoleData? cachedRole = await UserRoleService.loadUserRole();
      UserRoleData? roleData = cachedRole;
      
      // Сохраняем текущую роль перед запросом, чтобы не перезаписать при таймауте
      final roleBeforeRequest = roleData;
      
      // Всегда проверяем роль через API (если есть телефон)
      if (phone != null && phone.isNotEmpty) {
        try {
          print('🔄 Обновление роли через API...');
          roleData = await UserRoleService.getUserRole(phone);
          await UserRoleService.saveUserRole(roleData);
          print('✅ Роль обновлена: ${roleData.role.name}');
          // Обновляем имя, если нужно
          if (roleData.displayName.isNotEmpty) {
            await prefs.setString('user_name', roleData.displayName);
          }
        } catch (e) {
          print('⚠️ Ошибка загрузки роли через API: $e');
          // При таймауте или другой ошибке используем кэшированную роль
          // НЕ перезаписываем роль на client, если она уже была admin
          if (cachedRole != null) {
            print('📦 Используем кэшированную роль (при ошибке API): ${cachedRole.role.name}');
            roleData = cachedRole;
            // НЕ сохраняем роль заново, чтобы не перезаписать admin на client
          } else {
            // Если кэша нет, только тогда используем client по умолчанию
            print('⚠️ Кэшированной роли нет, используем client по умолчанию');
            roleData = UserRoleData(
              role: UserRole.client,
              displayName: name ?? '',
              phone: phone ?? '',
            );
          }
        }
      }
      
      // Используем имя из роли, если есть
      final displayName = roleData?.displayName ?? name;
      
      if (mounted) {
        setState(() {
          _userName = displayName;
          _userRole = roleData;
        });
        print('✅ Состояние обновлено: роль=${roleData?.role.name}, имя=$displayName');
      }
    } finally {
      _isLoadingRole = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Арабика')),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40), // Темно-бирюзовый фон (fallback)
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6, // Увеличена прозрачность для лучшей видимости логотипа
          ),
        ),
        child: Column(
          children: [
          // Приветствие с именем
          if (_userName != null && _userName!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.waving_hand,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Привет, $_userName!',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          // Сетка меню
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Builder(
                builder: (context) {
                  final menuItems = _getMenuItems();
                  print('🔵 GridView.build: получено ${menuItems.length} кнопок');
                  return GridView.count(
                    crossAxisCount: 2,           // 2 кнопки в строке
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1,         // делает плитки квадратными
                    children: menuItems,
                  );
                },
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// Получить список кнопок меню в зависимости от роли пользователя
  List<Widget> _getMenuItems() {
    final role = _userRole?.role ?? UserRole.client;
    final items = <Widget>[];
    print('🔵 _getMenuItems() вызван, роль: ${role.name}');

    // Меню - видно всем
    items.add(_tile(context, Icons.local_cafe, 'Меню', () async {
      final shop = await _showShopSelectionDialog(context);
      if (!context.mounted || shop == null) return;
      final categories = await _loadCategoriesForShop(context, shop.address);
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MenuGroupsPage(
            groups: categories,
            selectedShop: shop.address,
          ),
        ),
      );
    }));

    // Корзина - видно всем
    items.add(_tile(context, Icons.shopping_cart, 'Корзина', () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CartPage()),
      );
    }));

    // Мои заказы - видно всем
    items.add(_tile(context, Icons.receipt_long, 'Мои заказы', () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const OrdersPage()),
      );
    }));

    // Сотрудники - только админ
    if (role == UserRole.admin) {
      items.add(_tile(context, Icons.people, 'Сотрудники', () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EmployeesPage()),
        );
        // Обновляем страницу после возврата (на случай, если были изменения)
        if (mounted) {
          setState(() {});
        }
      }));
    }

    // Регистрация сотрудника - только админ
    if (role == UserRole.admin) {
      items.add(_tile(context, Icons.person_add, 'Регистрация сотрудника', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EmployeeRegistrationSelectEmployeePage()),
        );
      }));
    }

    // РКО - только для верифицированных сотрудников
    if (role == UserRole.employee || role == UserRole.admin) {
      items.add(_tile(context, Icons.receipt_long, 'РКО', () async {
        // Проверяем верификацию сотрудника
        try {
          final prefs = await SharedPreferences.getInstance();
          final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
          
          if (phone == null || phone.isEmpty) {
            if (mounted) {
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
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Только верифицированные сотрудники могут создавать РКО'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }

          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RKOTypeSelectionPage()),
          );
        } catch (e) {
          print('Ошибка проверки верификации: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Ошибка: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }));
    }

    // Отчеты по РКО - только для админов и верифицированных сотрудников
    if (role == UserRole.admin || role == UserRole.employee) {
      items.add(_tile(context, Icons.assessment, 'Отчеты по РКО', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RKOReportsPage()),
        );
      }));
    }

    // Карта лояльности - видно всем
    items.add(_tile(context, Icons.qr_code, 'Карта лояльности', () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LoyaltyPage()),
      );
    }));

    // Списать бонусы - только сотрудник и админ
    if (role == UserRole.employee || role == UserRole.admin) {
      items.add(_tile(context, Icons.qr_code_scanner, 'Списать бонусы', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LoyaltyScannerPage()),
        );
      }));
    }

    // Отзывы - видно всем
    items.add(_tile(context, Icons.rate_review, 'Отзывы', () {
      print('🔵 ========== НАЖАТА КНОПКА "ОТЗЫВЫ" ==========');
      if (!context.mounted) {
        print('❌ Context не mounted');
        return;
      }
      print('🔵 Context mounted, открываем ReviewTypeSelectionPage');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) {
            print('🔵 Builder вызван, создаем ReviewTypeSelectionPage');
            return const ReviewTypeSelectionPage();
          },
        ),
      );
    }));

    // Мои диалоги - только сотрудник и админ
    if (role == UserRole.employee || role == UserRole.admin) {
      items.add(_tile(context, Icons.chat, 'Мои диалоги', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MyDialogsPage()),
        );
      }));
    }

    // Отзывы покупателей - видно всем
    items.add(_tile(context, Icons.feedback, 'Отзывы покупателей', () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ReviewsListPage()),
      );
    }));

    // Наличие товара - видно всем
    items.add(_tile(context, Icons.search, 'Наличие товара', () {}));

    // Обучение - только сотрудник и админ
    if (role == UserRole.employee || role == UserRole.admin) {
      items.add(_tile(context, Icons.menu_book, 'Обучение', () {
        _showTrainingDialog(context);
      }));
    }

    // Тест - доступно для всех ролей
    items.add(_tile(context, Icons.science, 'Тест', () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TestNotificationsPage()),
      );
    }));

    // Я на работе - только сотрудник и админ
    if (role == UserRole.employee || role == UserRole.admin) {
      items.add(_tile(context, Icons.access_time, 'Я на работе', () async {
        // ВАЖНО: Используем единый источник истины - меню "Сотрудники"
        // Это гарантирует, что имя будет совпадать с отображением в системе
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
          // Продолжаем, даже если проверка не удалась
        }
        
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AttendanceShopSelectionPage(
              employeeName: employeeName,
            ),
          ),
        );
      }));
    }

    // Пересменка - только сотрудник и админ
    if (role == UserRole.employee || role == UserRole.admin) {
      items.add(_tile(context, Icons.work_history, 'Пересменка', () async {
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
      }));
    }

    // Пересчет товаров - только сотрудник и админ
    if (role == UserRole.employee || role == UserRole.admin) {
      items.add(_tile(context, Icons.inventory, 'Пересчет товаров', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RecountShopSelectionPage()),
        );
      }));
    }

    // Отчет по пересменкам - только админ
    if (role == UserRole.admin) {
      items.add(_tile(context, Icons.assessment, 'Отчет по пересменкам', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ShiftReportsListPage()),
        );
      }));
    }

    // Отчет по пересчету - только админ
    if (role == UserRole.admin) {
      items.add(_tile(context, Icons.inventory_2, 'Отчет по пересчету', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RecountReportsListPage()),
        );
      }));
    }

    // Отчеты по приходам - только админ
    if (role == UserRole.admin) {
      items.add(_tile(context, Icons.access_time_filled, 'Отчеты по приходам', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AttendanceReportsPage()),
        );
      }));
    }

    // KPI - только админ
    if (role == UserRole.admin) {
      items.add(_tile(context, Icons.analytics, 'KPI', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const KPITypeSelectionPage()),
        );
      }));
    }

    // Рецепты - только сотрудник и админ
    if (role == UserRole.employee || role == UserRole.admin) {
      items.add(_tile(context, Icons.restaurant_menu, 'Рецепты', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RecipesListPage()),
        );
      }));
    }
    
    // Редактировать рецепты - только админ
    if (role == UserRole.admin) {
      items.add(_tile(context, Icons.edit_note, 'Редактировать рецепты', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RecipeEditPage()),
        );
      }));
    }

    // Тест ролей - всегда видно (для тестирования)
    items.add(_tile(context, Icons.science, 'Тест ролей', () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const RoleTestPage()),
      );
    }));
    
    print('🔵 Всего кнопок в меню: ${items.length}');
    print('🔵 Кнопка "Тест ролей" добавлена');

    return items;
  }

  Widget _tile(
      BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white.withOpacity(0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withOpacity(0.5),
            width: 1,
          ),
        ),
        elevation: 4,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.white),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Показать диалог выбора магазина
  Future<Shop?> _showShopSelectionDialog(BuildContext context) async {
    try {
      final shops = await Shop.loadShopsFromGoogleSheets();
      if (!context.mounted) return null;

      return await showDialog<Shop>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF004D40).withOpacity(0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          title: const Text(
            'Выберите магазин',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: shops.length,
              itemBuilder: (context, index) {
                final shop = shops[index];
                return GestureDetector(
                  onTap: () => Navigator.pop(context, shop),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          shop.icon,
                          size: 40,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            shop.address,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    } catch (e) {
      print('Ошибка загрузки магазинов: $e');
      return null;
    }
  }

  /// Загрузить категории для конкретного магазина
  Future<List<String>> _loadCategoriesForShop(BuildContext context, String shopAddress) async {
    try {
      // Загружаем меню из menu.json
      final jsonString = await rootBundle.loadString('assets/menu.json');
      final List<dynamic> jsonData = json.decode(jsonString);
      
      // Фильтруем по магазину и получаем уникальные категории
      final categories = jsonData
          .map((e) => {
                'category': (e['category'] ?? '').toString(),
                'shop': (e['shop'] ?? '').toString(),
              })
          .where((item) => item['shop'] == shopAddress)
          .map((e) => e['category'] as String)
          .toSet()
          .toList()
        ..sort();
      
      return categories;
    } catch (e) {
      print('Ошибка загрузки категорий: $e');
      return [];
    }
  }

  Future<List<String>> _loadCategories(BuildContext context) async {
    try {
      // Пробуем загрузить из menu.json (более надежно)
      final jsonString = await rootBundle.loadString('assets/menu.json');
      final List<dynamic> jsonData = json.decode(jsonString);
      final Set<String> categories = {};
      
      for (var item in jsonData) {
        final category = (item['category'] ?? '').toString().trim();
        if (category.isNotEmpty) {
          categories.add(category);
        }
      }
      
      final categoriesList = categories.toList()..sort();
      // ignore: avoid_print
      print("📋 Загружено категорий из menu.json: ${categoriesList.length}");
      // ignore: avoid_print
      print("📋 Категории: $categoriesList");
      return categoriesList;
    } catch (e) {
      // Если не получилось загрузить из JSON, пробуем из Google Sheets
      // ignore: avoid_print
      print("⚠️ Ошибка загрузки из menu.json: $e, пробуем Google Sheets...");
      
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Меню';
      final response = await http.get(Uri.parse(sheetUrl));
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки категорий');
      }
      final lines = const LineSplitter().convert(response.body);
      final Set<String> categories = {};
      for (var i = 1; i < lines.length; i++) {
        final row = lines[i].split(',');
        if (row.length >= 3) {
          // Убираем кавычки и лишние пробелы
          String category = row[2].trim().replaceAll('"', '').trim();
          if (category.isNotEmpty) {
            categories.add(category);
          }
        }
      }
      final categoriesList = categories.toList()..sort();
      // ignore: avoid_print
      print("📋 Загружено категорий из Google Sheets: ${categoriesList.length}");
      return categoriesList;
    }
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
}
