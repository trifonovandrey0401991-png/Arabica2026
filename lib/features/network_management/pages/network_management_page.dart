import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/network_management_service.dart';
import '../../shops/services/shop_service.dart';
import '../../shops/models/shop_model.dart';
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

  // Данные для вкладок
  List<String> _developers = [];
  List<Map<String, dynamic>> _managers = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _storeManagers = [];
  List<Shop> _allShops = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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

    } catch (e) {
      Logger.debug('❌ Ошибка загрузки данных: $e');
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление сетью'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.code), text: 'Разработчики'),
            Tab(icon: Icon(Icons.business_center), text: 'Управляющие'),
            Tab(icon: Icon(Icons.store), text: 'Магазины'),
            Tab(icon: Icon(Icons.people), text: 'Сотрудники'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDevelopersTab(),
                _buildManagersTab(),
                _buildShopsTab(),
                _buildEmployeesTab(),
              ],
            ),
    );
  }

  // ==================== ВКЛАДКА РАЗРАБОТЧИКИ ====================

  Widget _buildDevelopersTab() {
    return Column(
      children: [
        // Кнопка добавления
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _showAddDeveloperDialog,
            icon: const Icon(Icons.add),
            label: const Text('Добавить разработчика'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),

        // Список разработчиков
        Expanded(
          child: _developers.isEmpty
              ? const Center(
                  child: Text(
                    'Нет разработчиков',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _developers.length,
                  itemBuilder: (context, index) {
                    final phone = _developers[index];
                    final isCurrentUser = phone == _currentUserPhone?.replaceAll(RegExp(r'[\s\+]'), '');

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCurrentUser ? Colors.green : Colors.blue,
                          child: const Icon(Icons.code, color: Colors.white),
                        ),
                        title: Text(_formatPhone(phone)),
                        subtitle: isCurrentUser ? const Text('Это вы') : null,
                        trailing: isCurrentUser
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _confirmRemoveDeveloper(phone),
                              ),
                      ),
                    );
                  },
                ),
        ),

        // Информация
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.withOpacity(0.1),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Разработчики видят ВСЕ магазины, сотрудников и данные системы',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddDeveloperDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить разработчика'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Номер телефона',
            hintText: '79001234567',
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              final phone = controller.text.trim();
              if (phone.isEmpty) return;

              Navigator.pop(context);

              final success = await NetworkManagementService.addDeveloper(
                _currentUserPhone!,
                phone,
              );

              if (success) {
                _loadAllData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Разработчик добавлен')),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ошибка добавления разработчика'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveDeveloper(String phone) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить разработчика?'),
        content: Text('Удалить ${_formatPhone(phone)} из списка разработчиков?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              final success = await NetworkManagementService.removeDeveloper(
                _currentUserPhone!,
                phone,
              );

              if (success) {
                _loadAllData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Разработчик удалён')),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ошибка удаления разработчика'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  // ==================== ВКЛАДКА УПРАВЛЯЮЩИЕ ====================

  Widget _buildManagersTab() {
    return Column(
      children: [
        // Кнопка добавления
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _showAddManagerDialog,
            icon: const Icon(Icons.add),
            label: const Text('Добавить управляющего'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),

        // Список управляющих
        Expanded(
          child: _managers.isEmpty
              ? const Center(
                  child: Text(
                    'Нет управляющих',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _managers.length,
                  itemBuilder: (context, index) {
                    final manager = _managers[index];
                    final shopCount = (manager['managedShops'] as List?)?.length ?? 0;
                    final employeeCount = (manager['employees'] as List?)?.length ?? 0;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ExpansionTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Icon(Icons.business_center, color: Colors.white),
                        ),
                        title: Text(manager['name']?.toString() ?? 'Без имени'),
                        subtitle: Text(_formatPhone(manager['phone']?.toString() ?? '')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(label: Text('$shopCount маг.')),
                            const SizedBox(width: 4),
                            Chip(label: Text('$employeeCount сотр.')),
                          ],
                        ),
                        children: [
                          ListTile(
                            leading: const Icon(Icons.store),
                            title: const Text('Магазины'),
                            subtitle: Text(
                              shopCount > 0
                                  ? (manager['managedShops'] as List).join(', ')
                                  : 'Не назначены',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showEditManagerShopsDialog(manager),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.people),
                            title: const Text('Сотрудники'),
                            subtitle: Text(
                              employeeCount > 0
                                  ? '$employeeCount сотрудников'
                                  : 'Не назначены',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showEditManagerEmployeesDialog(manager),
                            ),
                          ),
                          OverflowBar(
                            alignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _confirmRemoveManager(manager['phone']?.toString() ?? ''),
                                icon: const Icon(Icons.delete, color: Colors.red),
                                label: const Text('Удалить', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),

        // Информация
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.orange.withOpacity(0.1),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Управляющие видят ТОЛЬКО свои магазины и назначенных сотрудников',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddManagerDialog() {
    final phoneController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить управляющего'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Имя',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Номер телефона',
                hintText: '79001234567',
                prefixIcon: Icon(Icons.phone),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              final phone = phoneController.text.trim();
              final name = nameController.text.trim();
              if (phone.isEmpty) return;

              Navigator.pop(context);

              final success = await NetworkManagementService.saveManager(
                _currentUserPhone!,
                {
                  'phone': phone,
                  'name': name,
                  'managedShops': <String>[],
                  'employees': <String>[],
                },
              );

              if (success) {
                _loadAllData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Управляющий добавлен')),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ошибка добавления'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
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
          title: Text('Магазины: ${manager['name']}'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: _allShops.isEmpty
                ? const Center(child: Text('Нет магазинов'))
                : ListView.builder(
                    itemCount: _allShops.length,
                    itemBuilder: (context, index) {
                      final shop = _allShops[index];
                      final shopId = shop.id;
                      final shopName = shop.name;

                      return CheckboxListTile(
                        title: Text(shopName),
                        subtitle: Text(shop.address),
                        value: selectedShops.contains(shopId),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedShops.add(shopId);
                            } else {
                              selectedShops.remove(shopId);
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
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);

                final success = await NetworkManagementService.updateManagerShops(
                  _currentUserPhone!,
                  manager['phone']?.toString() ?? '',
                  selectedShops.toList(),
                );

                if (success) {
                  _loadAllData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Магазины обновлены')),
                    );
                  }
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditManagerEmployeesDialog(Map<String, dynamic> manager) {
    final phoneController = TextEditingController();
    final employees = List<String>.from(
      (manager['employees'] as List?)?.map((e) => e.toString()) ?? [],
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Сотрудники: ${manager['name']}'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                // Поле добавления
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '79001234567',
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final phone = phoneController.text.trim();
                        if (phone.isNotEmpty && !employees.contains(phone)) {
                          setDialogState(() {
                            employees.add(phone.replaceAll(RegExp(r'[\s\+]'), ''));
                            phoneController.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
                const Divider(),

                // Список сотрудников
                Expanded(
                  child: employees.isEmpty
                      ? const Center(child: Text('Нет сотрудников'))
                      : ListView.builder(
                          itemCount: employees.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              title: Text(_formatPhone(employees[index])),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: () {
                                  setDialogState(() {
                                    employees.removeAt(index);
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
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);

                final success = await NetworkManagementService.updateManagerEmployees(
                  _currentUserPhone!,
                  manager['phone']?.toString() ?? '',
                  employees,
                );

                if (success) {
                  _loadAllData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Сотрудники обновлены')),
                    );
                  }
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveManager(String phone) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить управляющего?'),
        content: Text('Удалить ${_formatPhone(phone)} из списка управляющих?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              final success = await NetworkManagementService.removeManager(
                _currentUserPhone!,
                phone,
              );

              if (success) {
                _loadAllData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Управляющий удалён')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  // ==================== ВКЛАДКА МАГАЗИНЫ ====================

  Widget _buildShopsTab() {
    return Column(
      children: [
        // Заголовок
        Container(
          padding: const EdgeInsets.all(16),
          child: const Text(
            'Назначение магазинов управляющим',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),

        // Список магазинов
        Expanded(
          child: _allShops.isEmpty
              ? const Center(child: Text('Нет магазинов'))
              : ListView.builder(
                  itemCount: _allShops.length,
                  itemBuilder: (context, index) {
                    final shop = _allShops[index];
                    final shopId = shop.id;
                    final shopName = shop.name;

                    // Найти управляющего для этого магазина
                    String? assignedManager;
                    for (final manager in _managers) {
                      final shops = manager['managedShops'] as List?;
                      if (shops?.contains(shopId) == true) {
                        assignedManager = manager['name']?.toString() ?? manager['phone']?.toString();
                        break;
                      }
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.purple,
                          child: Icon(Icons.store, color: Colors.white),
                        ),
                        title: Text(shopName),
                        subtitle: Text(
                          assignedManager != null
                              ? 'Управляющий: $assignedManager'
                              : 'Не назначен',
                          style: TextStyle(
                            color: assignedManager != null ? Colors.green : Colors.grey,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showAssignShopDialog(shopId, shopName, assignedManager),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showAssignShopDialog(String shopId, String shopName, String? currentManager) {
    String? selectedManagerPhone;

    // Найти текущего управляющего
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
          title: Text('Назначить: $shopName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Без управляющего
              RadioListTile<String?>(
                title: const Text('Без управляющего'),
                value: null,
                groupValue: selectedManagerPhone,
                onChanged: (value) {
                  setDialogState(() => selectedManagerPhone = value);
                },
              ),
              const Divider(),
              // Список управляющих
              ..._managers.map((manager) {
                final phone = manager['phone']?.toString() ?? '';
                final name = manager['name']?.toString() ?? phone;
                return RadioListTile<String?>(
                  title: Text(name),
                  subtitle: Text(_formatPhone(phone)),
                  value: phone,
                  groupValue: selectedManagerPhone,
                  onChanged: (value) {
                    setDialogState(() => selectedManagerPhone = value);
                  },
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
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
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Магазин назначен')),
                  );
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ВКЛАДКА СОТРУДНИКИ ====================

  Widget _buildEmployeesTab() {
    // Собрать всех сотрудников со всех управляющих
    final allEmployeesList = <Map<String, dynamic>>[];
    for (final manager in _managers) {
      final employees = (manager['employees'] as List?) ?? [];
      for (final empPhone in employees) {
        allEmployeesList.add({
          'phone': empPhone.toString(),
          'managerName': manager['name']?.toString() ?? 'Без имени',
          'managerPhone': manager['phone']?.toString() ?? '',
        });
      }
    }

    return Column(
      children: [
        // Заголовок
        Container(
          padding: const EdgeInsets.all(16),
          child: const Text(
            'Привязка сотрудников к управляющим',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),

        // Список сотрудников
        Expanded(
          child: allEmployeesList.isEmpty
              ? const Center(
                  child: Text(
                    'Нет привязанных сотрудников\n\nДобавьте сотрудников через вкладку "Управляющие"',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: allEmployeesList.length,
                  itemBuilder: (context, index) {
                    final emp = allEmployeesList[index];

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.teal,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(_formatPhone(emp['phone'] ?? '')),
                        subtitle: Text('Управляющий: ${emp['managerName']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.swap_horiz),
                          onPressed: () => _showTransferEmployeeDialog(
                            emp['phone'] ?? '',
                            emp['managerPhone'] ?? '',
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Информация
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.teal.withOpacity(0.1),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.teal),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Сотрудник привязывается к управляющему и может работать в любом его магазине',
                  style: TextStyle(color: Colors.teal),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showTransferEmployeeDialog(String employeePhone, String currentManagerPhone) {
    String? selectedManagerPhone = currentManagerPhone;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Перевести: ${_formatPhone(employeePhone)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _managers.map((manager) {
              final phone = manager['phone']?.toString() ?? '';
              final name = manager['name']?.toString() ?? phone;
              return RadioListTile<String?>(
                title: Text(name),
                subtitle: Text(_formatPhone(phone)),
                value: phone,
                groupValue: selectedManagerPhone,
                onChanged: (value) {
                  setDialogState(() => selectedManagerPhone = value);
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);

                if (selectedManagerPhone == currentManagerPhone) return;

                // Удалить у старого управляющего
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

                // Добавить новому управляющему
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
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Сотрудник переведён')),
                  );
                }
              },
              child: const Text('Перевести'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== УТИЛИТЫ ====================

  String _formatPhone(String phone) {
    if (phone.length == 11) {
      return '+${phone[0]} (${phone.substring(1, 4)}) ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}';
    }
    return phone;
  }
}
