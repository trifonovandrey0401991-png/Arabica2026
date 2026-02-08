import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart' show Employee;
import '../services/store_manager_service.dart';

/// Страница списка заведующих с привязкой магазинов
class StoreManagersPage extends StatefulWidget {
  const StoreManagersPage({super.key});

  @override
  State<StoreManagersPage> createState() => _StoreManagersPageState();
}

class _StoreManagersPageState extends State<StoreManagersPage> {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  List<Employee> _managers = [];
  Map<String, StoreManagerInfo> _shopAssignments = {};
  List<Shop> _allShops = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Загружаем сотрудников и фильтруем по флагу isManager
      final allEmployees = await EmployeeService.getEmployees();
      final managerEmployees = allEmployees
          .where((e) => e.isManager == true)
          .toList();

      // Загружаем привязки магазинов из shop-managers
      final storeManagerInfos = await StoreManagerService.getStoreManagers();
      final assignmentsMap = <String, StoreManagerInfo>{};
      for (final sm in storeManagerInfos) {
        assignmentsMap[sm.phone] = sm;
      }

      final shops = await ShopService.getShops();

      if (mounted) {
        setState(() {
          _managers = managerEmployees;
          _shopAssignments = assignmentsMap;
          _allShops = shops;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки данных', e);
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка загрузки: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _getShopNames(List<String> shopIds) {
    if (shopIds.isEmpty) return 'Нет привязанных магазинов';

    final names = <String>[];
    for (final id in shopIds) {
      final shop = _allShops.where((s) => s.id == id || s.address == id).firstOrNull;
      names.add(shop?.address ?? id);
    }
    return names.join(', ');
  }

  Future<void> _openShopAssignment(Employee employee) async {
    final phone = employee.phone ?? '';
    // Получаем текущие привязки из карты
    final existing = _shopAssignments[phone];
    final selectedIds = Set<String>.from(existing?.managedShopIds ?? []);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => _ShopAssignmentDialog(
        managerName: employee.name,
        allShops: _allShops,
        selectedShopIds: selectedIds,
      ),
    );

    if (result != null) {
      setState(() => _isLoading = true);

      final success = await StoreManagerService.updateShopAssignments(
        phone,
        result.toList(),
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Магазины обновлены'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка обновления магазинов'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isLoading = false);
        }
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
              // Custom AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Заведующие',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadData,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Icon(Icons.refresh, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: _gold))
                    : _errorMessage != null
                        ? _buildErrorState()
                        : _managers.isEmpty
                            ? _buildEmptyState()
                            : _buildManagersList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _loadData,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: _emerald,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Повторить', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.people_outline, size: 40, color: Colors.white.withOpacity(0.3)),
          ),
          const SizedBox(height: 16),
          Text(
            'Нет заведующих',
            style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Отметьте сотрудников как заведующих в разделе Сотрудники',
              style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.3)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManagersList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _managers.length,
      itemBuilder: (context, index) {
        final employee = _managers[index];
        final phone = employee.phone ?? '';
        final assignment = _shopAssignments[phone];
        final managedShopIds = assignment?.managedShopIds ?? [];
        final shopNames = _getShopNames(managedShopIds);
        final hasShops = managedShopIds.isNotEmpty;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => _openShopAssignment(employee),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  // Аватар
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _emerald,
                    child: Text(
                      employee.name.isNotEmpty
                          ? employee.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Информация
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _formatPhone(phone),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        // Привязанные магазины
                        Row(
                          children: [
                            Icon(
                              Icons.store,
                              size: 14,
                              color: hasShops ? _gold : Colors.white.withOpacity(0.3),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                shopNames,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hasShops
                                      ? _gold.withOpacity(0.8)
                                      : Colors.white.withOpacity(0.3),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Стрелка
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withOpacity(0.3),
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatPhone(String phone) {
    if (phone.length == 11) {
      return '+${phone[0]} (${phone.substring(1, 4)}) ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}';
    }
    return phone;
  }
}

/// Диалог выбора магазинов для привязки к заведующей
class _ShopAssignmentDialog extends StatefulWidget {
  final String managerName;
  final List<Shop> allShops;
  final Set<String> selectedShopIds;

  const _ShopAssignmentDialog({
    required this.managerName,
    required this.allShops,
    required this.selectedShopIds,
  });

  @override
  State<_ShopAssignmentDialog> createState() => _ShopAssignmentDialogState();
}

class _ShopAssignmentDialogState extends State<_ShopAssignmentDialog> {
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedShopIds);
  }

  void _toggleShop(Shop shop) {
    setState(() {
      // Используем address как ID привязки (как и в остальной части main_cash)
      final key = shop.address;
      if (_selected.contains(key) || _selected.contains(shop.id)) {
        _selected.remove(key);
        _selected.remove(shop.id);
      } else {
        _selected.add(key);
      }
    });
  }

  bool _isSelected(Shop shop) {
    return _selected.contains(shop.address) || _selected.contains(shop.id);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _night,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          maxWidth: 400,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_emerald, _emeraldDark, _night],
            stops: const [0.0, 0.3, 1.0],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Магазины для',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.managerName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Выбрано: ${_selected.length} из ${widget.allShops.length}',
                    style: TextStyle(fontSize: 13, color: _gold),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            // Shops list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: widget.allShops.length,
                itemBuilder: (context, index) {
                  final shop = widget.allShops[index];
                  final selected = _isSelected(shop);
                  return InkWell(
                    onTap: () => _toggleShop(shop),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: selected ? _emerald.withOpacity(0.5) : Colors.transparent,
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: selected ? _gold : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: selected ? _gold : Colors.white.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: selected
                                ? const Icon(Icons.check, size: 16, color: Colors.black)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              shop.address,
                              style: TextStyle(
                                fontSize: 14,
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.7),
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: Colors.white.withOpacity(0.1)),
            // Buttons
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: const Center(
                          child: Text(
                            'Отмена',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, _selected),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _gold,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            'Сохранить',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
