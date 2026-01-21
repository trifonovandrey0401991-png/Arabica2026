import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import '../../features/menu/pages/menu_groups_page.dart';
import '../../features/orders/pages/cart_page.dart';
import '../../features/orders/pages/orders_page.dart';
import '../../features/employees/pages/employees_page.dart';
import '../../features/loyalty/pages/loyalty_page.dart';
import '../../features/shops/models/shop_model.dart';
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
import '../../features/rating/widgets/rating_badge_widget.dart';
import '../../core/utils/logger.dart';
import '../../core/widgets/shop_icon.dart';
import '../../core/services/report_notification_service.dart';
import '../../core/services/firebase_service.dart';
import '../../features/main_cash/services/withdrawal_service.dart';
import '../../shared/dialogs/notification_required_dialog.dart';
import 'my_dialogs_page.dart';
import 'data_management_page.dart';
import 'reports_page.dart';

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  String? _userName;
  UserRoleData? _userRole;
  String? _employeeId; // ID сотрудника для рейтинга
  bool _isLoadingRole = false; // Флаг для предотвращения параллельных запросов
  int _totalUnviewedReports = 0; // Счётчик непросмотренных отчётов
  int _unconfirmedWithdrawalsCount = 0; // Счётчик неподтвержденных выемок

  @override
  void initState() {
    super.initState();
    // Сначала загружаем кэшированную роль для немедленного отображения
    _loadCachedRole();
    // Затем обновляем роль через API
    _loadUserData();
    // Синхронизация отчетов при открытии главного меню
    _syncReports();
    // Загружаем ID сотрудника для рейтинга
    _loadEmployeeId();
    // Загружаем счётчик непросмотренных отчётов
    _loadReportCounts();
    // Загружаем счётчик неподтвержденных выемок
    _loadUnconfirmedWithdrawalsCount();
  }

  Future<void> _loadReportCounts() async {
    final counts = await ReportNotificationService.getUnviewedCounts();
    if (mounted) {
      setState(() {
        _totalUnviewedReports = counts.total;
      });
    }
  }

  Future<void> _loadUnconfirmedWithdrawalsCount() async {
    try {
      final withdrawals = await WithdrawalService.getWithdrawals();
      final unconfirmedCount = withdrawals.where((w) => !w.confirmed).length;
      if (mounted) {
        setState(() {
          _unconfirmedWithdrawalsCount = unconfirmedCount;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки счетчика неподтвержденных выемок', e);
    }
  }

  Future<void> _loadEmployeeId() async {
    try {
      final employeeId = await EmployeesPage.getCurrentEmployeeId();
      if (mounted && employeeId != null) {
        setState(() {
          _employeeId = employeeId;
        });
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
    // Если есть минимум 2 слова, берём второе (имя)
    if (parts.length >= 2) {
      return parts[1];
    }
    // Иначе возвращаем первое слово
    return parts[0];
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
        Logger.debug('Кэшированная роль загружена: ${cachedRole?.role.name ?? "нет"}');
      }
    } catch (e) {
      Logger.warning('Ошибка загрузки кэшированной роли: $e');
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
    // Предотвращаем параллельные запросы
    if (_isLoadingRole) {
      Logger.debug('Загрузка роли уже выполняется, пропускаем...');
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
          Logger.debug('Обновление роли через API...');
          roleData = await UserRoleService.getUserRole(phone);
          await UserRoleService.saveUserRole(roleData);
          Logger.success('Роль обновлена: ${roleData.role.name}');
          // Обновляем имя, если нужно
          if (roleData.displayName.isNotEmpty) {
            await prefs.setString('user_name', roleData.displayName);
          }
        } catch (e) {
          Logger.warning('Ошибка загрузки роли через API: $e');
          // При таймауте или другой ошибке используем кэшированную роль
          // НЕ перезаписываем роль на client, если она уже была admin
          if (cachedRole != null) {
            Logger.debug('Используем кэшированную роль (при ошибке API): ${cachedRole.role.name}');
            roleData = cachedRole;
            // НЕ сохраняем роль заново, чтобы не перезаписать admin на client
          } else {
            // Если кэша нет, только тогда используем client по умолчанию
            Logger.warning('Кэшированной роли нет, используем client по умолчанию');
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
        Logger.debug('Состояние обновлено: роль=${roleData?.role.name}, имя=$displayName');
      }
    } finally {
      _isLoadingRole = false;
    }
  }

  /// Выход из аккаунта
  Future<void> _logout() async {
    // Показываем диалог подтверждения
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти? Вы сможете войти под другим номером телефона.'),
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
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) {
      return; // Пользователь отменил выход
    }

    try {
      // Очищаем все данные пользователя
      final prefs = await SharedPreferences.getInstance();
      
      // Очищаем данные регистрации
      await prefs.remove('is_registered');
      await prefs.remove('user_name');
      await prefs.remove('user_phone');
      
      // Очищаем данные роли
      await UserRoleService.clearUserRole();
      
      // Очищаем данные лояльности
      await LoyaltyStorage.clear();
      
      // Перенаправляем на страницу регистрации
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const RegistrationPage(),
          ),
          (route) => false, // Удаляем все предыдущие маршруты
        );
      }
    } catch (e) {
      Logger.error('Ошибка при выходе', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при выходе: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Арабика'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выход',
            onPressed: _logout,
          ),
        ],
      ),
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
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.waving_hand,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          'Привет, ${_getFirstName(_userName)}!',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  // Бейдж рейтинга для сотрудников и админов
                  if ((_userRole?.role == UserRole.employee || _userRole?.role == UserRole.admin) && _employeeId != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Ваш Рейтинг: ',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        RatingBadgeWidget(employeeId: _employeeId!),
                      ],
                    ),
                  ],
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
                  Logger.debug('GridView.build: получено ${menuItems.length} кнопок');
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
    Logger.debug('_getMenuItems() вызван, роль: ${role.name}');

    // Меню - видно всем
    items.add(_tileMenu(context, 'Меню', () async {
      final shop = await _showShopSelectionDialog(context);
      if (!mounted || shop == null) return;
      final categories = await _loadCategoriesForShop(context, shop.address);
      if (!mounted) return;
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MenuGroupsPage(
              groups: categories,
              selectedShop: shop.address,
            ),
          ),
        );
      }
    }));

    // Корзина - видно всем
    items.add(_tileCart(context, 'Корзина', () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CartPage()),
      );
    }));

    // Мои заказы - видно всем
    items.add(_tileMyOrders(context, 'Мои заказы', () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const OrdersPage()),
      );
    }));

    // Магазины на карте - видно всем
    items.add(_tileShopsOnMap(context, 'Магазины на карте', () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ShopsOnMapPage()),
      );
    }));

    // Управление данными - только админ (включает управление сотрудниками)
    if (role == UserRole.admin) {
      items.add(_tileDataManagement(context, 'Управление данными', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DataManagementPage()),
        );
      }));
    }

    // Отчеты - только для админов
    if (role == UserRole.admin) {
      items.add(_tileReports(context, 'Отчеты', _totalUnviewedReports + _unconfirmedWithdrawalsCount, () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ReportsPage()),
        );
        // Обновляем счётчики после возврата
        _loadReportCounts();
        _loadUnconfirmedWithdrawalsCount();
      }));
    }



    // Карта лояльности - видно всем (с проверкой уведомлений)
    items.add(_tileLoyalty(context, 'Карта лояльности', () async {
      // Проверяем, включены ли уведомления
      final enabled = await FirebaseService.areNotificationsEnabled();
      if (!enabled) {
        if (context.mounted) {
          final result = await NotificationRequiredDialog.show(context);
          // Если пользователь нажал "Включить", проверяем снова после возврата из настроек
          if (result == true) {
            // Даём время на переключение в настройках и обратно
            await Future.delayed(const Duration(milliseconds: 500));
            final enabledNow = await FirebaseService.areNotificationsEnabled();
            if (enabledNow && context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoyaltyPage()),
              );
            }
          }
        }
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LoyaltyPage()),
      );
    }));

    // Отзывы - видно всем
    items.add(_tileReviews(context, 'Отзывы', () {
      Logger.debug('Нажата кнопка "Отзывы"');
      if (!context.mounted) {
        Logger.warning('Context не mounted');
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ReviewTypeSelectionPage(),
        ),
      );
    }));

    // Мои диалоги - видно всем (клиентам, сотрудникам и админам)
    items.add(_tileMyDialogs(context, 'Мои диалоги', () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MyDialogsPage()),
      );
    }));


    // Поиск товара - видно всем
    items.add(_tileProductSearch(context, 'Поиск товара', () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ProductSearchShopSelectionPage(),
        ),
      );
    }));

    // Устроиться на работу - только для клиентов
    if (role == UserRole.client) {
      items.add(_tileJobApplication(context, 'Устроиться на работу', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const JobApplicationWelcomePage()),
        );
      }));
    }

    // Панель работника - только сотрудник и админ
    if (role == UserRole.employee || role == UserRole.admin) {
      items.add(_tileEmployeePanel(context, 'Панель работника', () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EmployeePanelPage()),
        );
      }));
    }

    Logger.debug('Всего кнопок в меню: ${items.length}');

    return items;
  }

  Widget _tile(
      BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: Icon(icon, size: 64, color: Colors.white),
            ),
          ),
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

  /// Кнопка с кастомной иконкой чата
  Widget _tileChat(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/chat_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  /// Кнопка с кастомной иконкой корзины
  Widget _tileCart(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/cart_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  /// Кастомная иконка меню в стиле логотипа (как на картинке)
  Widget _buildMenuIcon() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/main_menu_icon.png',
        width: 80,
        height: 80,
        fit: BoxFit.contain,
      ),
    );
  }

  /// Кастомная иконка карты лояльности
  Widget _buildLoyaltyIcon() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/loyalty_card_icon.png',
        width: 80,
        height: 80,
        fit: BoxFit.contain,
      ),
    );
  }

  /// Плитка карты лояльности с кастомной иконкой
  Widget _tileLoyalty(BuildContext ctx, String label, Function() onTap) {
    return ElevatedButton(
      onPressed: () => onTap(),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/loyalty_card_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  /// Плитка меню с кастомной иконкой
  Widget _tileMenu(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/main_menu_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  Widget _tileWithBadge(
      BuildContext ctx, IconData icon, String label, int badgeCount, VoidCallback onTap) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(12),
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
            children: [
              Expanded(
                child: Center(
                  child: Icon(icon, size: 64, color: Colors.white),
                ),
              ),
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
        ),
        if (badgeCount > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badgeCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
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
            height: MediaQuery.of(context).size.height * 0.7,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: shops.length,
              itemBuilder: (context, index) {
                final shop = shops[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, shop),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            const ShopIcon(size: 56),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                shop.address,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: Colors.white70,
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    } catch (e) {
      Logger.error('Ошибка загрузки магазинов', e);
      return null;
    }
  }

  /// Загрузить категории для конкретного магазина (только те, что есть в рецептах)
  Future<List<String>> _loadCategoriesForShop(BuildContext context, String shopAddress) async {
    try {
      // Загружаем рецепты с сервера - в меню показываем только категории с рецептами
      final recipes = await Recipe.loadRecipesFromServer();

      // Получаем уникальные категории из рецептов
      final categories = recipes
          .map((r) => r.category)
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      return categories;
    } catch (e) {
      Logger.error('Ошибка загрузки категорий', e);
      return [];
    }
  }

  /// Плитка поиска товара с кастомной иконкой
  Widget _tileProductSearch(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/search_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  /// Плитка "Отчеты" с кастомной иконкой и бейджем
  Widget _tileReports(BuildContext ctx, String label, int badgeCount, Future<void> Function() onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/reports_icon.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
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
          if (badgeCount > 0)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 24,
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Плитка "Управление данными" с кастомной иконкой
  Widget _tileDataManagement(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/data_management_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  /// Плитка "Панель работника" с кастомной иконкой
  Widget _tileEmployeePanel(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/employee_panel_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  /// Плитка "Мои заказы" с кастомной иконкой
  Widget _tileMyOrders(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/my_orders_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  /// Плитка "Магазины на карте" с кастомной иконкой
  Widget _tileShopsOnMap(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/map_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  /// Плитка "Мои диалоги" с кастомной иконкой чата
  Widget _tileMyDialogs(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/chat_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  /// Плитка "Отзывы" с кастомной иконкой
  Widget _tileReviews(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/reviews_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

  /// Плитка "Устроиться на работу" с кастомной иконкой
  Widget _tileJobApplication(BuildContext ctx, String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(12),
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
        children: [
          Expanded(
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/job_application_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
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

}

/// Painter для рисования стакана с напитком (как на оригинальной картинке)
class _DrinkIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Стакан - трапеция
    final glassPath = Path();
    glassPath.moveTo(centerX - 10, centerY - 10); // Верх левый
    glassPath.lineTo(centerX + 10, centerY - 10); // Верх правый
    glassPath.lineTo(centerX + 8, centerY + 12); // Низ правый
    glassPath.lineTo(centerX - 8, centerY + 12); // Низ левый
    glassPath.close();
    canvas.drawPath(glassPath, paint);

    // Трубочка
    canvas.drawLine(
      Offset(centerX + 4, centerY - 10),
      Offset(centerX + 10, centerY - 18),
      paint,
    );

    // Кубики льда (маленькие квадраты)
    paint.style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(centerX - 6, centerY - 4, 5, 5),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(centerX + 1, centerY + 2, 5, 5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Painter для иконки карты лояльности (QR-код со стрелкой на телефон)
class _LoyaltyQRIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Белый фон круга
    final bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Тёмно-синяя рамка круга (как на картинке)
    final borderPaint = Paint()
      ..color = const Color(0xFF1A365D) // Тёмно-синий
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius - 1.5, borderPaint);

    // QR-код - чёрные квадраты
    final qrPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    // Размер QR-кода - крупнее, занимает большую часть
    final qrSize = size.width * 0.65;
    final qrLeft = center.dx - qrSize / 2 - 8; // Сдвиг влево
    final qrTop = center.dy - qrSize / 2 + 3;
    final cellSize = qrSize / 21; // 21x21 для более детального QR

    // Функция для рисования угловых маркеров QR (7x7)
    void drawCornerMarker(double left, double top) {
      // Внешний квадрат
      for (int i = 0; i < 7; i++) {
        canvas.drawRect(Rect.fromLTWH(left + i * cellSize, top, cellSize, cellSize), qrPaint);
        canvas.drawRect(Rect.fromLTWH(left + i * cellSize, top + 6 * cellSize, cellSize, cellSize), qrPaint);
        canvas.drawRect(Rect.fromLTWH(left, top + i * cellSize, cellSize, cellSize), qrPaint);
        canvas.drawRect(Rect.fromLTWH(left + 6 * cellSize, top + i * cellSize, cellSize, cellSize), qrPaint);
      }
      // Внутренний квадрат 3x3
      for (int row = 2; row < 5; row++) {
        for (int col = 2; col < 5; col++) {
          canvas.drawRect(Rect.fromLTWH(left + col * cellSize, top + row * cellSize, cellSize, cellSize), qrPaint);
        }
      }
    }

    // Три угловых маркера
    drawCornerMarker(qrLeft, qrTop); // Верхний левый
    drawCornerMarker(qrLeft, qrTop + 14 * cellSize); // Нижний левый
    drawCornerMarker(qrLeft + 14 * cellSize, qrTop); // Верхний правый

    // Дополнительные данные QR (случайный паттерн)
    final dataPoints = [
      // Горизонтальная линия тайминга
      [8, 6], [10, 6], [12, 6],
      // Вертикальная линия тайминга
      [6, 8], [6, 10], [6, 12],
      // Данные
      [8, 8], [9, 8], [11, 8], [12, 9],
      [8, 10], [10, 10], [12, 10],
      [9, 11], [11, 11],
      [8, 12], [10, 12], [12, 12],
      [8, 14], [9, 14], [11, 14], [12, 14],
      [14, 8], [15, 9], [14, 10], [16, 10],
      [14, 12], [15, 12], [16, 12],
      [8, 16], [10, 16], [12, 16],
      [14, 14], [15, 15], [16, 14], [17, 15],
      [14, 16], [16, 16], [17, 17], [18, 16],
      [17, 8], [18, 9], [19, 8],
      [17, 11], [18, 10], [19, 11],
    ];

    for (final point in dataPoints) {
      canvas.drawRect(
        Rect.fromLTWH(qrLeft + point[0] * cellSize, qrTop + point[1] * cellSize, cellSize, cellSize),
        qrPaint,
      );
    }

    // Зелёная изогнутая стрелка (как на картинке - сверху вниз)
    final arrowPaint = Paint()
      ..color = const Color(0xFF4CAF50) // Яркий зелёный
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final arrowPath = Path();
    // Начало сверху
    arrowPath.moveTo(center.dx + 10, center.dy - 38);
    // Изгиб вправо и вниз к телефону
    arrowPath.quadraticBezierTo(
      center.dx + 42, center.dy - 25, // Контрольная точка (вправо)
      center.dx + 35, center.dy + 5, // Конечная точка (вниз к телефону)
    );
    canvas.drawPath(arrowPath, arrowPaint);

    // Наконечник стрелки (треугольник)
    final arrowHeadPaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..style = PaintingStyle.fill;

    final arrowHeadPath = Path();
    arrowHeadPath.moveTo(center.dx + 35, center.dy + 12); // Кончик
    arrowHeadPath.lineTo(center.dx + 28, center.dy + 2);
    arrowHeadPath.lineTo(center.dx + 40, center.dy + 2);
    arrowHeadPath.close();
    canvas.drawPath(arrowHeadPath, arrowHeadPaint);

    // Телефон справа внизу
    final phonePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final phoneBorderPaint = Paint()
      ..color = const Color(0xFF1A365D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Корпус телефона
    final phoneLeft = center.dx + 22;
    final phoneTop = center.dy + 8;
    final phoneWidth = 20.0;
    final phoneHeight = 32.0;

    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(phoneLeft, phoneTop, phoneWidth, phoneHeight),
      const Radius.circular(3),
    );
    canvas.drawRRect(phoneRect, phonePaint);
    canvas.drawRRect(phoneRect, phoneBorderPaint);

    // Мини QR на экране телефона
    final screenPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final miniCell = 2.5;
    final screenLeft = phoneLeft + 3;
    final screenTop = phoneTop + 5;

    // Маленький QR на экране (5x5)
    final miniQrPattern = [
      [1,1,1,0,1],
      [1,0,1,0,1],
      [1,1,1,0,0],
      [0,0,0,1,0],
      [1,1,0,0,1],
    ];

    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 5; col++) {
        if (miniQrPattern[row][col] == 1) {
          canvas.drawRect(
            Rect.fromLTWH(screenLeft + col * miniCell, screenTop + row * miniCell, miniCell, miniCell),
            screenPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

