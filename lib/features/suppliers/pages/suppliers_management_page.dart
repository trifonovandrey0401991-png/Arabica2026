import 'package:flutter/material.dart';
import '../models/supplier_model.dart';
import '../services/supplier_service.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/employee_service.dart';
import '../../tasks/services/recurring_task_service.dart';
import '../../../core/utils/logger.dart';

/// Страница управления поставщиками
class SuppliersManagementPage extends StatefulWidget {
  const SuppliersManagementPage({super.key});

  @override
  State<SuppliersManagementPage> createState() => _SuppliersManagementPageState();
}

class _SuppliersManagementPageState extends State<SuppliersManagementPage> {
  List<Supplier> _suppliers = [];
  List<Shop> _shops = [];
  List<Employee> _managers = [];  // Список заведующих (менеджеров)
  bool _isLoading = true;
  String _searchQuery = '';

  static const List<String> _weekDays = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        SupplierService.getSuppliers(),
        ShopService.getShops(),
        EmployeeService.getEmployees(),
      ]);
      setState(() {
        _suppliers = results[0] as List<Supplier>;
        _shops = results[1] as List<Shop>;
        // Фильтруем только заведующих (с флагом isManager)
        final allEmployees = results[2] as List<Employee>;
        final managersOnly = allEmployees.where((e) => e.isManager == true).toList();
        // Если нет сотрудников с флагом isManager, показываем всех сотрудников
        // (для обратной совместимости пока не у всех установлен флаг)
        _managers = managersOnly.isNotEmpty ? managersOnly : allEmployees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка загрузки данных'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Supplier> get _filteredSuppliers {
    if (_searchQuery.isEmpty) return _suppliers;
    final query = _searchQuery.toLowerCase();
    return _suppliers.where((s) =>
      s.name.toLowerCase().contains(query) ||
      (s.phone?.contains(query) ?? false) ||
      (s.inn?.contains(query) ?? false)
    ).toList();
  }

  Future<void> _showAddEditDialog([Supplier? supplier]) async {
    final isEditing = supplier != null;
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final innController = TextEditingController(text: supplier?.inn ?? '');
    final phoneController = TextEditingController(text: supplier?.phone ?? '');
    final emailController = TextEditingController(text: supplier?.email ?? '');
    final contactPersonController = TextEditingController(text: supplier?.contactPerson ?? '');

    String selectedLegalType = supplier?.legalType ?? 'ООО';
    String selectedPaymentType = supplier?.paymentType ?? 'БезНал';

    // Map: shopId -> List<String> (выбранные дни)
    Map<String, List<String>> shopDeliveryDays = {};
    // Map: shopId -> List<String> (ID выбранных заведующих)
    Map<String, List<String>> shopManagerIds = {};

    // Инициализация из существующего поставщика
    if (supplier?.shopDeliveries != null) {
      for (var sd in supplier!.shopDeliveries!) {
        shopDeliveryDays[sd.shopId] = List.from(sd.days);
        if (sd.managerIds != null) {
          shopManagerIds[sd.shopId] = List.from(sd.managerIds!);
        }
      }
    }

    // Убедимся что все магазины есть в map
    for (var shop in _shops) {
      shopDeliveryDays.putIfAbsent(shop.id, () => []);
      shopManagerIds.putIfAbsent(shop.id, () => []);
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Редактировать поставщика' : 'Добавить поставщика'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // === Основные данные ===
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Название *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Юридический тип
                  const Text('Тип организации:', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('ООО'),
                          value: 'ООО',
                          groupValue: selectedLegalType,
                          onChanged: (v) => setDialogState(() => selectedLegalType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('ИП'),
                          value: 'ИП',
                          groupValue: selectedLegalType,
                          onChanged: (v) => setDialogState(() => selectedLegalType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: innController,
                    decoration: const InputDecoration(
                      labelText: 'ИНН',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: contactPersonController,
                    decoration: const InputDecoration(
                      labelText: 'Контактное лицо',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Тип оплаты
                  const Text('Тип оплаты:', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('БезНал'),
                          value: 'БезНал',
                          groupValue: selectedPaymentType,
                          onChanged: (v) => setDialogState(() => selectedPaymentType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Нал'),
                          value: 'Нал',
                          groupValue: selectedPaymentType,
                          onChanged: (v) => setDialogState(() => selectedPaymentType = v!),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  // === Дни доставки по магазинам ===
                  const Text(
                    'Дни доставки по магазинам',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Выберите дни доставки для каждого магазина',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  // Список магазинов с днями и заведующими
                  ..._shops.map((shop) => _buildShopDeliveryCard(
                    shop: shop,
                    selectedDays: shopDeliveryDays[shop.id] ?? [],
                    selectedManagerIds: shopManagerIds[shop.id] ?? [],
                    allManagers: _managers,
                    onDaysChanged: (days) {
                      setDialogState(() {
                        shopDeliveryDays[shop.id] = days;
                      });
                    },
                    onManagersChanged: (managerIds) {
                      setDialogState(() {
                        shopManagerIds[shop.id] = managerIds;
                      });
                    },
                  )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Введите название поставщика'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Собираем данные о доставках
                final List<SupplierShopDelivery> deliveries = [];
                for (var shop in _shops) {
                  final days = shopDeliveryDays[shop.id] ?? [];
                  final managerIds = shopManagerIds[shop.id] ?? [];
                  // Сохраняем если есть дни ИЛИ заведующие
                  if (days.isNotEmpty || managerIds.isNotEmpty) {
                    // Сортируем дни по порядку
                    if (days.isNotEmpty) {
                      days.sort((a, b) => _weekDays.indexOf(a).compareTo(_weekDays.indexOf(b)));
                    }
                    // Получаем имена заведующих
                    final managerNames = managerIds
                        .map((id) => _managers.firstWhere(
                              (m) => m.id == id,
                              orElse: () => Employee(id: id, name: 'Неизвестный'),
                            ).name)
                        .toList();
                    deliveries.add(SupplierShopDelivery(
                      shopId: shop.id,
                      shopName: shop.name,
                      days: days,
                      managerIds: managerIds.isNotEmpty ? managerIds : null,
                      managerNames: managerNames.isNotEmpty ? managerNames : null,
                    ));
                  }
                }

                final newSupplier = Supplier(
                  id: supplier?.id ?? 'supplier_${DateTime.now().millisecondsSinceEpoch}',
                  name: nameController.text.trim(),
                  inn: innController.text.trim().isNotEmpty ? innController.text.trim() : null,
                  legalType: selectedLegalType,
                  phone: phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                  email: emailController.text.trim().isNotEmpty ? emailController.text.trim() : null,
                  contactPerson: contactPersonController.text.trim().isNotEmpty ? contactPersonController.text.trim() : null,
                  paymentType: selectedPaymentType,
                  shopDeliveries: deliveries.isNotEmpty ? deliveries : null,
                  createdAt: supplier?.createdAt ?? DateTime.now(),
                  updatedAt: DateTime.now(),
                );

                Supplier? savedSupplier;
                if (isEditing) {
                  savedSupplier = await SupplierService.updateSupplier(newSupplier);
                } else {
                  savedSupplier = await SupplierService.createSupplier(newSupplier);
                }

                if (!context.mounted) return;

                if (savedSupplier != null) {
                  // Создаём/обновляем циклические задачи для поставщика
                  if (savedSupplier.shopDeliveries != null && savedSupplier.shopDeliveries!.isNotEmpty) {
                    try {
                      // Собираем данные о заведующих для передачи в сервис
                      final managersData = _managers
                          .map((m) => {
                                'id': m.id,
                                'name': m.name,
                                'phone': m.phone ?? '',
                              })
                          .toList();

                      // Обновляем задачи (удаляем старые и создаём новые)
                      final createdTasks = await RecurringTaskService.updateTasksForSupplier(
                        supplierId: savedSupplier.id,
                        supplierName: savedSupplier.name,
                        shopDeliveries: savedSupplier.shopDeliveries!,
                        managersData: managersData,
                        createdBy: 'system',
                      );

                      Logger.info('Создано ${createdTasks.length} циклических задач для поставщика ${savedSupplier.name}');
                    } catch (e) {
                      Logger.error('Ошибка создания циклических задач для поставщика', e);
                      // Не блокируем сохранение, только логируем ошибку
                    }
                  } else {
                    // Если нет доставок, удаляем существующие задачи
                    try {
                      await RecurringTaskService.deleteTasksForSupplier(savedSupplier.id);
                    } catch (e) {
                      Logger.error('Ошибка удаления задач поставщика', e);
                    }
                  }

                  Navigator.pop(context, true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ошибка сохранения поставщика'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004D40),
              ),
              child: Text(isEditing ? 'Сохранить' : 'Добавить'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  Widget _buildShopDeliveryCard({
    required Shop shop,
    required List<String> selectedDays,
    required List<String> selectedManagerIds,
    required List<Employee> allManagers,
    required Function(List<String>) onDaysChanged,
    required Function(List<String>) onManagersChanged,
  }) {
    final hasDelivery = selectedDays.isNotEmpty;
    final hasManagers = selectedManagerIds.isNotEmpty;
    final isActive = hasDelivery || hasManagers;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isActive ? Colors.green.shade50 : Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  shop.icon,
                  size: 20,
                  color: isActive ? Colors.green.shade700 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shop.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.green.shade800 : Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasDelivery)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${selectedDays.length} ${_getDayWord(selectedDays.length)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Дни недели
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: _weekDays.map((day) {
                final shortDay = day.substring(0, 2);
                final isSelected = selectedDays.contains(day);
                return FilterChip(
                  label: Text(
                    shortDay,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    final newDays = List<String>.from(selectedDays);
                    if (selected) {
                      newDays.add(day);
                    } else {
                      newDays.remove(day);
                    }
                    onDaysChanged(newDays);
                  },
                  selectedColor: const Color(0xFF004D40).withOpacity(0.3),
                  checkmarkColor: const Color(0xFF004D40),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
            // Заведующие
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showManagersDialog(
                shopName: shop.name,
                allManagers: allManagers,
                selectedIds: selectedManagerIds,
                onChanged: onManagersChanged,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: hasManagers ? Colors.orange.shade300 : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: hasManagers ? Colors.orange.shade50 : Colors.white,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 18,
                      color: hasManagers ? Colors.orange.shade700 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasManagers
                            ? _getManagerNames(selectedManagerIds, allManagers)
                            : 'Выбрать заведующих...',
                        style: TextStyle(
                          fontSize: 13,
                          color: hasManagers ? Colors.orange.shade800 : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasManagers)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${selectedManagerIds.length}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getManagerNames(List<String> ids, List<Employee> allManagers) {
    if (ids.isEmpty) return '';
    return ids
        .map((id) => allManagers
            .firstWhere((m) => m.id == id, orElse: () => Employee(id: id, name: '?'))
            .name)
        .join(', ');
  }

  void _showManagersDialog({
    required String shopName,
    required List<Employee> allManagers,
    required List<String> selectedIds,
    required Function(List<String>) onChanged,
  }) {
    List<String> tempSelected = List.from(selectedIds);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Заведующие: $shopName'),
          content: SizedBox(
            width: double.maxFinite,
            child: allManagers.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Нет сотрудников с должностью "Менеджер" или "Заведующий"',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: allManagers.length,
                    itemBuilder: (context, index) {
                      final manager = allManagers[index];
                      final isSelected = tempSelected.contains(manager.id);
                      return CheckboxListTile(
                        title: Text(manager.name),
                        subtitle: manager.position != null
                            ? Text(
                                manager.position!,
                                style: const TextStyle(fontSize: 12),
                              )
                            : null,
                        value: isSelected,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              tempSelected.add(manager.id);
                            } else {
                              tempSelected.remove(manager.id);
                            }
                          });
                        },
                        activeColor: const Color(0xFF004D40),
                        dense: true,
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
              onPressed: () {
                onChanged(tempSelected);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004D40),
              ),
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }

  String _getDayWord(int count) {
    if (count == 1) return 'день';
    if (count >= 2 && count <= 4) return 'дня';
    return 'дней';
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить поставщика?'),
        content: Text('Вы уверены, что хотите удалить поставщика "${supplier.name}"?'),
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
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await SupplierService.deleteSupplier(supplier.id);
      if (success) {
        // Удаляем связанные циклические задачи
        try {
          await RecurringTaskService.deleteTasksForSupplier(supplier.id);
          Logger.info('Удалены циклические задачи поставщика ${supplier.name}');
        } catch (e) {
          Logger.error('Ошибка удаления задач поставщика', e);
        }

        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Поставщик удален'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка удаления поставщика'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Поставщики'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: const Color(0xFF004D40),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск по названию, ИНН, телефону...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSuppliers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.local_shipping_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Нет поставщиков'
                                  : 'Поставщики не найдены',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (_searchQuery.isEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Нажмите + чтобы добавить',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredSuppliers.length,
                          itemBuilder: (context, index) {
                            final supplier = _filteredSuppliers[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF004D40),
                                  child: Text(
                                    supplier.name.isNotEmpty
                                        ? supplier.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        supplier.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (supplier.legalType != null) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          supplier.legalType!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (supplier.paymentType != null)
                                      Row(
                                        children: [
                                          Icon(
                                            supplier.paymentType == 'Нал'
                                                ? Icons.money
                                                : Icons.credit_card,
                                            size: 14,
                                            color: Colors.grey[600],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            supplier.paymentType!,
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (supplier.deliveryInfoText.isNotEmpty)
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.local_shipping,
                                            size: 14,
                                            color: supplier.shopsWithDeliveryCount > 0
                                                ? Colors.green
                                                : Colors.grey[600],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            supplier.deliveryInfoText,
                                            style: TextStyle(
                                              color: supplier.shopsWithDeliveryCount > 0
                                                  ? Colors.green
                                                  : Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _showAddEditDialog(supplier);
                                    } else if (value == 'delete') {
                                      _deleteSupplier(supplier);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit, size: 20),
                                          SizedBox(width: 8),
                                          Text('Редактировать'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, size: 20, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Удалить', style: TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => _showSupplierDetails(supplier),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showSupplierDetails(Supplier supplier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(supplier.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (supplier.legalType != null) ...[
                _detailRow(Icons.business, 'Тип', supplier.legalType!),
                const Divider(),
              ],
              if (supplier.inn != null) ...[
                _detailRow(Icons.numbers, 'ИНН', supplier.inn!),
                const Divider(),
              ],
              if (supplier.phone != null) ...[
                _detailRow(Icons.phone, 'Телефон', supplier.phone!),
                const Divider(),
              ],
              if (supplier.email != null) ...[
                _detailRow(Icons.email, 'Email', supplier.email!),
                const Divider(),
              ],
              if (supplier.contactPerson != null) ...[
                _detailRow(Icons.person, 'Контактное лицо', supplier.contactPerson!),
                const Divider(),
              ],
              if (supplier.paymentType != null) ...[
                _detailRow(
                  supplier.paymentType == 'Нал' ? Icons.money : Icons.credit_card,
                  'Оплата',
                  supplier.paymentType!,
                ),
                const Divider(),
              ],
              // Показываем доставки по магазинам
              if (supplier.shopDeliveries != null && supplier.shopDeliveries!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Доставки и заведующие:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                ...supplier.shopDeliveries!.map((sd) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.store, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sd.shopName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            if (sd.daysShortText.isNotEmpty)
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 12, color: Colors.green.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    sd.daysShortText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            if (sd.hasManagers)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.person, size: 12, color: Colors.orange.shade600),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        sd.managersText,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showAddEditDialog(supplier);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
            ),
            child: const Text('Редактировать'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
