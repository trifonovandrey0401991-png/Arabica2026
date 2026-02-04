import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/network_management_service.dart';
import '../../shops/services/shop_service.dart';
import '../../shops/models/shop_model.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../../core/utils/logger.dart';

/// Страница управления сетью магазинов
/// Доступна только для developer
class NetworkManagementPage extends StatefulWidget {
  const NetworkManagementPage({super.key});

  @override
  State<NetworkManagementPage> createState() => _NetworkManagementPageState();
}

class _NetworkManagementPageState extends State<NetworkManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _currentUserPhone;
  bool _isLoading = true;

  // Цветовая схема
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _accent = Color(0xFF2DD4BF);

  // Данные для вкладок
  List<String> _developers = [];
  List<Map<String, dynamic>> _managers = [];
  List<Map<String, dynamic>> _storeManagers = [];
  List<Shop> _allShops = [];
  List<Employee> _allEmployees = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUserPhone = prefs.getString('user_phone');
    if (_currentUserPhone != null) {
      await _loadAllData();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadAllData() async {
    if (_currentUserPhone == null) return;

    setState(() => _isLoading = true);

    try {
      // Загружаем конфигурацию shop-managers
      final config = await NetworkManagementService.getShopManagersConfig(_currentUserPhone!);
      if (config != null) {
        _developers = (config['developers'] as List?)?.map((e) => e.toString()).toList() ?? [];
        _managers = (config['managers'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? [];
        _storeManagers = (config['storeManagers'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ?? [];
      }

      // Загружаем все магазины
      _allShops = await ShopService.getShops();

      // Загружаем всех сотрудников
      _allEmployees = await EmployeeService.getEmployees();

    } catch (e) {
      Logger.debug('❌ Ошибка загрузки данных: $e');
    }

    setState(() => _isLoading = false);
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
              _buildTabBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: _accent))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildDevelopersTab(),
                          _buildManagersTab(),
                          _buildShopsTab(),
                          _buildEmployeesTab(),
                          _buildStoreManagersTab(),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'Управление сетью',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadAllData,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        indicatorColor: _accent,
        indicatorWeight: 3,
        labelColor: _accent,
        unselectedLabelColor: Colors.white60,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        tabs: const [
          Tab(icon: Icon(Icons.code, size: 20), text: 'Разработчики'),
          Tab(icon: Icon(Icons.business_center, size: 20), text: 'Управляющие'),
          Tab(icon: Icon(Icons.store, size: 20), text: 'Магазины'),
          Tab(icon: Icon(Icons.people, size: 20), text: 'Сотрудники'),
          Tab(icon: Icon(Icons.supervisor_account, size: 20), text: 'Заведующие'),
        ],
      ),
    );
  }

  // ==================== ВКЛАДКА РАЗРАБОТЧИКИ ====================

  Widget _buildDevelopersTab() {
    return Column(
      children: [
        const SizedBox(height: 16),
        _buildAddButton('Добавить разработчика', Icons.code, _showAddDeveloperDialog),
        Expanded(
          child: _developers.isEmpty
              ? _buildEmptyState('Нет разработчиков', Icons.code)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _developers.length,
                  itemBuilder: (context, index) {
                    final phone = _developers[index];
                    final isCurrentUser = phone == _currentUserPhone?.replaceAll(RegExp(r'[\s\+]'), '');
                    return _buildPersonCard(
                      phone: phone,
                      title: _formatPhone(phone),
                      subtitle: isCurrentUser ? 'Это вы' : null,
                      color: isCurrentUser ? _accent : Colors.blue,
                      icon: Icons.code,
                      onDelete: isCurrentUser ? null : () => _confirmRemoveDeveloper(phone),
                    );
                  },
                ),
        ),
        _buildInfoPanel(
          'Разработчики видят ВСЕ магазины, сотрудников и данные системы',
          Colors.blue,
        ),
      ],
    );
  }

  // ==================== ВКЛАДКА УПРАВЛЯЮЩИЕ ====================

  Widget _buildManagersTab() {
    return Column(
      children: [
        const SizedBox(height: 16),
        _buildAddButton('Добавить управляющего', Icons.business_center, _showAddManagerDialog),
        Expanded(
          child: _managers.isEmpty
              ? _buildEmptyState('Нет управляющих', Icons.business_center)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _managers.length,
                  itemBuilder: (context, index) {
                    final manager = _managers[index];
                    final shopCount = (manager['managedShops'] as List?)?.length ?? 0;
                    final employeeCount = (manager['employees'] as List?)?.length ?? 0;
                    return _buildManagerCard(manager, shopCount, employeeCount);
                  },
                ),
        ),
        _buildInfoPanel(
          'Управляющие видят ТОЛЬКО свои магазины и назначенных сотрудников',
          Colors.orange,
        ),
      ],
    );
  }

  Widget _buildManagerCard(Map<String, dynamic> manager, int shopCount, int employeeCount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.business_center, color: Colors.orange),
          ),
          title: Text(
            manager['name']?.toString() ?? 'Без имени',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            _formatPhone(manager['phone']?.toString() ?? ''),
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBadge('$shopCount маг.', Colors.purple),
              const SizedBox(width: 8),
              _buildBadge('$employeeCount сотр.', Colors.teal),
            ],
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildManagerOption(
                    icon: Icons.store,
                    title: 'Магазины',
                    value: shopCount > 0
                        ? (manager['managedShops'] as List).map((id) {
                            final shop = _allShops.where((s) => s.id == id).firstOrNull;
                            return shop?.name ?? id;
                          }).join(', ')
                        : 'Не назначены',
                    onEdit: () => _showEditManagerShopsDialog(manager),
                  ),
                  const SizedBox(height: 12),
                  _buildManagerOption(
                    icon: Icons.people,
                    title: 'Сотрудники',
                    value: employeeCount > 0 ? '$employeeCount сотрудников' : 'Не назначены',
                    onEdit: () => _showEditManagerEmployeesDialog(manager),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _confirmRemoveManager(manager['phone']?.toString() ?? ''),
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        label: const Text('Удалить', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManagerOption({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onEdit,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white60, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: _accent, size: 20),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }

  // ==================== ВКЛАДКА МАГАЗИНЫ ====================

  Widget _buildShopsTab() {
    return Column(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Назначение магазинов управляющим',
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _allShops.isEmpty
              ? _buildEmptyState('Нет магазинов', Icons.store)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _allShops.length,
                  itemBuilder: (context, index) {
                    final shop = _allShops[index];
                    String? assignedManager;
                    for (final manager in _managers) {
                      final shops = manager['managedShops'] as List?;
                      if (shops?.contains(shop.id) == true) {
                        assignedManager = manager['name']?.toString() ?? manager['phone']?.toString();
                        break;
                      }
                    }
                    return _buildShopCard(shop, assignedManager);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShopCard(Shop shop, String? assignedManager) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.store, color: Colors.purple),
        ),
        title: Text(shop.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(
          assignedManager != null ? 'Управляющий: $assignedManager' : 'Не назначен',
          style: TextStyle(
            color: assignedManager != null ? _accent : Colors.white.withOpacity(0.5),
            fontSize: 12,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit, color: _accent),
          onPressed: () => _showAssignShopDialog(shop.id, shop.name, assignedManager),
        ),
      ),
    );
  }

  // ==================== ВКЛАДКА СОТРУДНИКИ ====================

  Widget _buildEmployeesTab() {
    // Собрать всех привязанных сотрудников
    final assignedEmployees = <Map<String, dynamic>>[];
    for (final manager in _managers) {
      final employees = (manager['employees'] as List?) ?? [];
      for (final empPhone in employees) {
        assignedEmployees.add({
          'phone': empPhone.toString(),
          'managerName': manager['name']?.toString() ?? 'Без имени',
          'managerPhone': manager['phone']?.toString() ?? '',
        });
      }
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Привязка сотрудников к управляющим',
            style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: assignedEmployees.isEmpty
              ? _buildEmptyState('Нет привязанных сотрудников\n\nДобавьте через вкладку "Управляющие"', Icons.people)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: assignedEmployees.length,
                  itemBuilder: (context, index) {
                    final emp = assignedEmployees[index];
                    final employee = _allEmployees.where(
                      (e) => e.phone?.replaceAll(RegExp(r'[\s\+]'), '') == emp['phone'],
                    ).firstOrNull;
                    return _buildEmployeeCard(emp, employee);
                  },
                ),
        ),
        _buildInfoPanel(
          'Сотрудник привязывается к управляющему и может работать в любом его магазине',
          Colors.teal,
        ),
      ],
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> emp, Employee? employee) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.teal.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.person, color: Colors.teal),
        ),
        title: Text(
          employee?.employeeName ?? employee?.name ?? _formatPhone(emp['phone'] ?? ''),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (employee?.employeeName != null || employee?.name != null)
              Text(
                _formatPhone(emp['phone'] ?? ''),
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
              ),
            Row(
              children: [
                const Icon(Icons.business_center, size: 12, color: Colors.orange),
                const SizedBox(width: 4),
                Text(
                  emp['managerName'] ?? '',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.swap_horiz, color: _accent),
          onPressed: () => _showTransferEmployeeDialog(emp['phone'] ?? '', emp['managerPhone'] ?? ''),
        ),
      ),
    );
  }

  // ==================== ВКЛАДКА ЗАВЕДУЮЩИЕ ====================

  Widget _buildStoreManagersTab() {
    return Column(
      children: [
        const SizedBox(height: 16),
        _buildAddButton('Добавить заведующую', Icons.supervisor_account, _showAddStoreManagerDialog),
        Expanded(
          child: _storeManagers.isEmpty
              ? _buildEmptyState('Нет заведующих\n\nЗаведующая — сотрудник с расширенными правами', Icons.supervisor_account)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _storeManagers.length,
                  itemBuilder: (context, index) {
                    final sm = _storeManagers[index];
                    return _buildStoreManagerCard(sm);
                  },
                ),
        ),
        _buildInfoPanel(
          'Заведующая может видеть только свой магазин или все магазины управляющего',
          Colors.amber,
        ),
      ],
    );
  }

  Widget _buildStoreManagerCard(Map<String, dynamic> sm) {
    final phone = sm['phone']?.toString() ?? '';
    final shopId = sm['shopId']?.toString() ?? '';
    final canSeeAll = sm['canSeeAllManagerShops'] == true;
    final shop = _allShops.where((s) => s.id == shopId).firstOrNull;
    final shopName = shop?.name ?? shopId;

    String? managerName;
    for (final manager in _managers) {
      final shops = manager['managedShops'] as List?;
      if (shops?.contains(shopId) == true) {
        managerName = manager['name']?.toString() ?? 'Без имени';
        break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: canSeeAll ? Colors.green.withOpacity(0.3) : Colors.amber.withOpacity(0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (canSeeAll ? Colors.green : Colors.amber).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.supervisor_account, color: canSeeAll ? Colors.green : Colors.amber),
          ),
          title: Text(
            _formatPhone(phone),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'Магазин: $shopName',
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
          trailing: _buildBadge(
            canSeeAll ? 'Все магазины' : 'Только свой',
            canSeeAll ? Colors.green : Colors.amber,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildStoreManagerInfo(Icons.store, 'Магазин', shopName),
                  if (managerName != null) ...[
                    const SizedBox(height: 8),
                    _buildStoreManagerInfo(Icons.business_center, 'Управляющий', managerName),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          canSeeAll ? Icons.visibility : Icons.visibility_off,
                          color: canSeeAll ? Colors.green : Colors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            canSeeAll
                                ? 'Видит ВСЕ магазины управляющего'
                                : 'Видит ТОЛЬКО свой магазин',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                        Switch(
                          value: canSeeAll,
                          activeColor: Colors.green,
                          onChanged: (value) => _toggleStoreManagerVisibility(phone, value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: () => _showEditStoreManagerDialog(sm),
                        icon: const Icon(Icons.edit, color: _accent, size: 20),
                        label: const Text('Изменить', style: TextStyle(color: _accent)),
                      ),
                      TextButton.icon(
                        onPressed: () => _confirmRemoveStoreManager(phone),
                        icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                        label: const Text('Удалить', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoreManagerInfo(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white60, size: 18),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
        Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 13))),
      ],
    );
  }

  // ==================== ОБЩИЕ ВИДЖЕТЫ ====================

  Widget _buildAddButton(String text, IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: _accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: _accent, size: 20),
                const SizedBox(width: 8),
                Text(text, style: const TextStyle(color: _accent, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(String text, Color color) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonCard({
    required String phone,
    required String title,
    String? subtitle,
    required Color color,
    required IconData icon,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: subtitle != null
            ? Text(subtitle, style: TextStyle(color: _accent, fontSize: 12))
            : null,
        trailing: onDelete != null
            ? IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: onDelete,
              )
            : null,
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  // ==================== ДИАЛОГИ ====================

  void _showAddDeveloperDialog() {
    final controller = TextEditingController();
    _showInputDialog(
      title: 'Добавить разработчика',
      hint: '79001234567',
      label: 'Номер телефона',
      icon: Icons.phone,
      controller: controller,
      onConfirm: () async {
        final phone = controller.text.trim();
        if (phone.isEmpty) return;
        Navigator.pop(context);
        final success = await NetworkManagementService.addDeveloper(_currentUserPhone!, phone);
        if (success) {
          _loadAllData();
          _showSnackBar('Разработчик добавлен');
        } else {
          _showSnackBar('Ошибка добавления', isError: true);
        }
      },
    );
  }

  void _confirmRemoveDeveloper(String phone) {
    _showConfirmDialog(
      title: 'Удалить разработчика?',
      content: 'Удалить ${_formatPhone(phone)} из списка разработчиков?',
      onConfirm: () async {
        Navigator.pop(context);
        final success = await NetworkManagementService.removeDeveloper(_currentUserPhone!, phone);
        if (success) {
          _loadAllData();
          _showSnackBar('Разработчик удалён');
        }
      },
    );
  }

  void _showAddManagerDialog() {
    final phoneController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Добавить управляющего', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTextField(nameController, 'Имя', Icons.person),
            const SizedBox(height: 16),
            _buildTextField(phoneController, 'Телефон', Icons.phone, hint: '79001234567'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () async {
              final phone = phoneController.text.trim();
              final name = nameController.text.trim();
              if (phone.isEmpty) return;
              Navigator.pop(context);
              final success = await NetworkManagementService.saveManager(
                _currentUserPhone!,
                {'phone': phone, 'name': name, 'managedShops': <String>[], 'employees': <String>[]},
              );
              if (success) {
                _loadAllData();
                _showSnackBar('Управляющий добавлен');
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _showEditManagerShopsDialog(Map<String, dynamic> manager) {
    final selectedShops = Set<String>.from(
      (manager['managedShops'] as List?)?.map((e) => e.toString()) ?? [],
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _emeraldDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Магазины: ${manager['name']}', style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: _allShops.isEmpty
                ? const Center(child: Text('Нет магазинов', style: TextStyle(color: Colors.white60)))
                : ListView.builder(
                    itemCount: _allShops.length,
                    itemBuilder: (context, index) {
                      final shop = _allShops[index];
                      return CheckboxListTile(
                        title: Text(shop.name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(shop.address, style: TextStyle(color: Colors.white.withOpacity(0.5))),
                        value: selectedShops.contains(shop.id),
                        activeColor: _accent,
                        checkColor: _night,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedShops.add(shop.id);
                            } else {
                              selectedShops.remove(shop.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accent),
              onPressed: () async {
                Navigator.pop(context);
                await NetworkManagementService.updateManagerShops(
                  _currentUserPhone!,
                  manager['phone']?.toString() ?? '',
                  selectedShops.toList(),
                );
                _loadAllData();
                _showSnackBar('Магазины обновлены');
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditManagerEmployeesDialog(Map<String, dynamic> manager) {
    final selectedEmployees = Set<String>.from(
      (manager['employees'] as List?)?.map((e) => e.toString()) ?? [],
    );

    // Создаём Map для быстрого поиска управляющего по телефону сотрудника
    final employeeToManager = <String, String>{};
    for (final m in _managers) {
      final mName = m['name']?.toString() ?? 'Без имени';
      for (final empPhone in (m['employees'] as List?) ?? []) {
        employeeToManager[empPhone.toString()] = mName;
      }
    }

    // Сортируем сотрудников: сначала свободные, потом привязанные
    final sortedEmployees = List<Employee>.from(_allEmployees);
    sortedEmployees.sort((a, b) {
      final aPhone = a.phone?.replaceAll(RegExp(r'[\s\+]'), '') ?? '';
      final bPhone = b.phone?.replaceAll(RegExp(r'[\s\+]'), '') ?? '';
      final aHasManager = employeeToManager.containsKey(aPhone);
      final bHasManager = employeeToManager.containsKey(bPhone);
      if (aHasManager && !bHasManager) return 1;
      if (!aHasManager && bHasManager) return -1;
      return 0;
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _emeraldDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Сотрудники: ${manager['name']}', style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                // Счётчик
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people, color: _accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Выбрано: ${selectedEmployees.length}',
                        style: const TextStyle(color: _accent, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Список сотрудников
                Expanded(
                  child: sortedEmployees.isEmpty
                      ? const Center(child: Text('Нет сотрудников', style: TextStyle(color: Colors.white60)))
                      : ListView.builder(
                          itemCount: sortedEmployees.length,
                          itemBuilder: (context, index) {
                            final emp = sortedEmployees[index];
                            final empPhone = emp.phone?.replaceAll(RegExp(r'[\s\+]'), '') ?? '';
                            final empName = emp.employeeName ?? emp.name;
                            final assignedTo = employeeToManager[empPhone];
                            final isSelected = selectedEmployees.contains(empPhone);
                            final isAssignedToOther = assignedTo != null && assignedTo != manager['name'];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _accent.withOpacity(0.15)
                                    : isAssignedToOther
                                        ? Colors.orange.withOpacity(0.1)
                                        : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: isSelected
                                    ? Border.all(color: _accent.withOpacity(0.5))
                                    : null,
                              ),
                              child: CheckboxListTile(
                                title: Text(
                                  empName,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatPhone(empPhone),
                                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                                    ),
                                    if (assignedTo != null)
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.business_center,
                                            size: 12,
                                            color: isAssignedToOther ? Colors.orange : _accent,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            assignedTo,
                                            style: TextStyle(
                                              color: isAssignedToOther ? Colors.orange : _accent,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                value: isSelected,
                                activeColor: _accent,
                                checkColor: _night,
                                onChanged: (value) {
                                  setDialogState(() {
                                    if (value == true) {
                                      selectedEmployees.add(empPhone);
                                    } else {
                                      selectedEmployees.remove(empPhone);
                                    }
                                  });
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accent),
              onPressed: () async {
                Navigator.pop(context);

                // Удалить выбранных сотрудников у других управляющих
                for (final m in _managers) {
                  if (m['phone'] == manager['phone']) continue;
                  final mEmployees = List<String>.from(
                    (m['employees'] as List?)?.map((e) => e.toString()) ?? [],
                  );
                  bool changed = false;
                  for (final emp in selectedEmployees) {
                    if (mEmployees.contains(emp)) {
                      mEmployees.remove(emp);
                      changed = true;
                    }
                  }
                  if (changed) {
                    await NetworkManagementService.updateManagerEmployees(
                      _currentUserPhone!,
                      m['phone']?.toString() ?? '',
                      mEmployees,
                    );
                  }
                }

                // Обновить сотрудников текущего управляющего
                await NetworkManagementService.updateManagerEmployees(
                  _currentUserPhone!,
                  manager['phone']?.toString() ?? '',
                  selectedEmployees.toList(),
                );
                _loadAllData();
                _showSnackBar('Сотрудники обновлены');
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveManager(String phone) {
    _showConfirmDialog(
      title: 'Удалить управляющего?',
      content: 'Удалить ${_formatPhone(phone)} из списка управляющих?',
      onConfirm: () async {
        Navigator.pop(context);
        final success = await NetworkManagementService.removeManager(_currentUserPhone!, phone);
        if (success) {
          _loadAllData();
          _showSnackBar('Управляющий удалён');
        }
      },
    );
  }

  void _showAssignShopDialog(String shopId, String shopName, String? currentManager) {
    String? selectedManagerPhone;
    for (final manager in _managers) {
      final shops = manager['managedShops'] as List?;
      if (shops?.contains(shopId) == true) {
        selectedManagerPhone = manager['phone']?.toString();
        break;
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _emeraldDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Назначить: $shopName', style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String?>(
                title: const Text('Без управляющего', style: TextStyle(color: Colors.white)),
                value: null,
                groupValue: selectedManagerPhone,
                activeColor: _accent,
                onChanged: (value) => setDialogState(() => selectedManagerPhone = value),
              ),
              const Divider(color: Colors.white24),
              ..._managers.map((manager) {
                final phone = manager['phone']?.toString() ?? '';
                final name = manager['name']?.toString() ?? phone;
                return RadioListTile<String?>(
                  title: Text(name, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(_formatPhone(phone), style: TextStyle(color: Colors.white.withOpacity(0.5))),
                  value: phone,
                  groupValue: selectedManagerPhone,
                  activeColor: _accent,
                  onChanged: (value) => setDialogState(() => selectedManagerPhone = value),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accent),
              onPressed: () async {
                Navigator.pop(context);
                // Удалить магазин у всех управляющих
                for (final manager in _managers) {
                  final shops = List<String>.from(
                    (manager['managedShops'] as List?)?.map((e) => e.toString()) ?? [],
                  );
                  if (shops.contains(shopId)) {
                    shops.remove(shopId);
                    await NetworkManagementService.updateManagerShops(
                      _currentUserPhone!,
                      manager['phone']?.toString() ?? '',
                      shops,
                    );
                  }
                }
                // Добавить магазин новому управляющему
                if (selectedManagerPhone != null) {
                  final targetManager = _managers.firstWhere(
                    (m) => m['phone']?.toString() == selectedManagerPhone,
                    orElse: () => {},
                  );
                  if (targetManager.isNotEmpty) {
                    final shops = List<String>.from(
                      (targetManager['managedShops'] as List?)?.map((e) => e.toString()) ?? [],
                    );
                    shops.add(shopId);
                    await NetworkManagementService.updateManagerShops(
                      _currentUserPhone!,
                      selectedManagerPhone!,
                      shops,
                    );
                  }
                }
                _loadAllData();
                _showSnackBar('Магазин назначен');
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransferEmployeeDialog(String employeePhone, String currentManagerPhone) {
    String? selectedManagerPhone = currentManagerPhone;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _emeraldDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Перевести: ${_formatPhone(employeePhone)}', style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _managers.map((manager) {
              final phone = manager['phone']?.toString() ?? '';
              final name = manager['name']?.toString() ?? phone;
              return RadioListTile<String?>(
                title: Text(name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(_formatPhone(phone), style: TextStyle(color: Colors.white.withOpacity(0.5))),
                value: phone,
                groupValue: selectedManagerPhone,
                activeColor: _accent,
                onChanged: (value) => setDialogState(() => selectedManagerPhone = value),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accent),
              onPressed: () async {
                Navigator.pop(context);
                if (selectedManagerPhone == currentManagerPhone) return;
                // Удалить у старого
                final oldManager = _managers.firstWhere(
                  (m) => m['phone']?.toString() == currentManagerPhone,
                  orElse: () => {},
                );
                if (oldManager.isNotEmpty) {
                  final employees = List<String>.from(
                    (oldManager['employees'] as List?)?.map((e) => e.toString()) ?? [],
                  );
                  employees.remove(employeePhone);
                  await NetworkManagementService.updateManagerEmployees(
                    _currentUserPhone!,
                    currentManagerPhone,
                    employees,
                  );
                }
                // Добавить новому
                if (selectedManagerPhone != null) {
                  final newManager = _managers.firstWhere(
                    (m) => m['phone']?.toString() == selectedManagerPhone,
                    orElse: () => {},
                  );
                  if (newManager.isNotEmpty) {
                    final employees = List<String>.from(
                      (newManager['employees'] as List?)?.map((e) => e.toString()) ?? [],
                    );
                    employees.add(employeePhone);
                    await NetworkManagementService.updateManagerEmployees(
                      _currentUserPhone!,
                      selectedManagerPhone!,
                      employees,
                    );
                  }
                }
                _loadAllData();
                _showSnackBar('Сотрудник переведён');
              },
              child: const Text('Перевести'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddStoreManagerDialog() {
    final phoneController = TextEditingController();
    String? selectedShopId;
    bool canSeeAll = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _emeraldDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Добавить заведующую', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTextField(phoneController, 'Телефон', Icons.phone, hint: '79001234567'),
                const SizedBox(height: 16),
                Text('Магазин:', style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedShopId,
                  isExpanded: true,
                  dropdownColor: _emeraldDark,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.store, color: Colors.white60),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                  ),
                  hint: Text('Выберите магазин', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                  items: _allShops.map((shop) {
                    return DropdownMenuItem(
                      value: shop.id,
                      child: Text(shop.name, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => selectedShopId = value),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SwitchListTile(
                    title: const Text('Видеть все магазины', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      canSeeAll ? 'Все магазины управляющего' : 'Только свой магазин',
                      style: TextStyle(color: canSeeAll ? Colors.green : Colors.white60),
                    ),
                    value: canSeeAll,
                    activeColor: Colors.green,
                    onChanged: (value) => setDialogState(() => canSeeAll = value),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accent),
              onPressed: () async {
                final phone = phoneController.text.trim().replaceAll(RegExp(r'[\s\+]'), '');
                if (phone.isEmpty || selectedShopId == null) {
                  _showSnackBar('Заполните все поля', isError: true);
                  return;
                }
                Navigator.pop(context);
                final success = await NetworkManagementService.saveStoreManager(
                  _currentUserPhone!,
                  {'phone': phone, 'shopId': selectedShopId, 'canSeeAllManagerShops': canSeeAll},
                );
                if (success) {
                  _loadAllData();
                  _showSnackBar('Заведующая добавлена');
                } else {
                  _showSnackBar('Ошибка добавления', isError: true);
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditStoreManagerDialog(Map<String, dynamic> sm) {
    String? selectedShopId = sm['shopId']?.toString();
    bool canSeeAll = sm['canSeeAllManagerShops'] == true;
    final phone = sm['phone']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _emeraldDark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Редактировать: ${_formatPhone(phone)}', style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Магазин:', style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedShopId,
                  isExpanded: true,
                  dropdownColor: _emeraldDark,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.store, color: Colors.white60),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                  ),
                  items: _allShops.map((shop) {
                    return DropdownMenuItem(
                      value: shop.id,
                      child: Text(shop.name, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => selectedShopId = value),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SwitchListTile(
                    title: const Text('Видеть все магазины', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      canSeeAll ? 'Все магазины управляющего' : 'Только свой магазин',
                      style: TextStyle(color: canSeeAll ? Colors.green : Colors.white60),
                    ),
                    value: canSeeAll,
                    activeColor: Colors.green,
                    onChanged: (value) => setDialogState(() => canSeeAll = value),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accent),
              onPressed: () async {
                if (selectedShopId == null) return;
                Navigator.pop(context);
                final success = await NetworkManagementService.saveStoreManager(
                  _currentUserPhone!,
                  {'phone': phone, 'shopId': selectedShopId, 'canSeeAllManagerShops': canSeeAll},
                );
                if (success) {
                  _loadAllData();
                  _showSnackBar('Заведующая обновлена');
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStoreManagerVisibility(String phone, bool canSeeAll) async {
    final sm = _storeManagers.firstWhere(
      (s) => s['phone']?.toString() == phone,
      orElse: () => {},
    );
    if (sm.isEmpty) return;
    final success = await NetworkManagementService.saveStoreManager(
      _currentUserPhone!,
      {'phone': phone, 'shopId': sm['shopId'], 'canSeeAllManagerShops': canSeeAll},
    );
    if (success) {
      _loadAllData();
      _showSnackBar(canSeeAll ? 'Видит все магазины' : 'Видит только свой магазин');
    }
  }

  void _confirmRemoveStoreManager(String phone) {
    _showConfirmDialog(
      title: 'Удалить заведующую?',
      content: 'Удалить ${_formatPhone(phone)} из списка заведующих?',
      onConfirm: () async {
        Navigator.pop(context);
        final success = await NetworkManagementService.removeStoreManager(_currentUserPhone!, phone);
        if (success) {
          _loadAllData();
          _showSnackBar('Заведующая удалена');
        } else {
          _showSnackBar('Ошибка удаления', isError: true);
        }
      },
    );
  }

  // ==================== ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ====================

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {String? hint}) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        prefixIcon: Icon(icon, color: Colors.white60),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _accent),
        ),
      ),
    );
  }

  void _showInputDialog({
    required String title,
    required String hint,
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: _buildTextField(controller, label, icon, hint: hint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: onConfirm,
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _showConfirmDialog({
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _emeraldDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: TextStyle(color: Colors.white.withOpacity(0.8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: onConfirm,
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : _accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  String _formatPhone(String phone) {
    if (phone.length == 11) {
      return '+${phone[0]} (${phone.substring(1, 4)}) ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}';
    }
    return phone;
  }
}
