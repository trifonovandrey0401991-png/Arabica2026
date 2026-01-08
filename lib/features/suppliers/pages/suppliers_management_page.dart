import 'package:flutter/material.dart';
import '../models/supplier_model.dart';
import '../services/supplier_service.dart';

/// Страница управления поставщиками
class SuppliersManagementPage extends StatefulWidget {
  const SuppliersManagementPage({super.key});

  @override
  State<SuppliersManagementPage> createState() => _SuppliersManagementPageState();
}

class _SuppliersManagementPageState extends State<SuppliersManagementPage> {
  List<Supplier> _suppliers = [];
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
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    try {
      final suppliers = await SupplierService.getSuppliers();
      setState(() {
        _suppliers = suppliers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка загрузки поставщиков'),
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

    String selectedLegalType = supplier?.legalType ?? 'ООО';
    String selectedPaymentType = supplier?.paymentType ?? 'БезНал';
    List<String> selectedDeliveryDays = List.from(supplier?.deliveryDays ?? []);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Редактировать поставщика' : 'Добавить поставщика'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 12),

                // Дни доставки
                const Text('Дни доставки:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _weekDays.map((day) {
                    final isSelected = selectedDeliveryDays.contains(day);
                    return FilterChip(
                      label: Text(day.substring(0, 2)),
                      selected: isSelected,
                      onSelected: (selected) {
                        setDialogState(() {
                          if (selected) {
                            selectedDeliveryDays.add(day);
                          } else {
                            selectedDeliveryDays.remove(day);
                          }
                        });
                      },
                      selectedColor: const Color(0xFF004D40).withOpacity(0.3),
                      checkmarkColor: const Color(0xFF004D40),
                    );
                  }).toList(),
                ),
              ],
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

                // Сортируем дни доставки по порядку
                selectedDeliveryDays.sort((a, b) =>
                  _weekDays.indexOf(a).compareTo(_weekDays.indexOf(b)));

                final newSupplier = Supplier(
                  id: supplier?.id ?? 'supplier_${DateTime.now().millisecondsSinceEpoch}',
                  name: nameController.text.trim(),
                  inn: innController.text.trim().isNotEmpty ? innController.text.trim() : null,
                  legalType: selectedLegalType,
                  deliveryDays: selectedDeliveryDays.isNotEmpty ? selectedDeliveryDays : null,
                  phone: phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                  paymentType: selectedPaymentType,
                  createdAt: supplier?.createdAt ?? DateTime.now(),
                  updatedAt: DateTime.now(),
                );

                Supplier? savedSupplier;
                if (isEditing) {
                  savedSupplier = await SupplierService.updateSupplier(newSupplier);
                } else {
                  savedSupplier = await SupplierService.createSupplier(newSupplier);
                }

                if (savedSupplier != null) {
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
      _loadSuppliers();
    }
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
        _loadSuppliers();
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
            onPressed: _loadSuppliers,
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
                        onRefresh: _loadSuppliers,
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
                                    if (supplier.deliveryDaysText.isNotEmpty)
                                      Text(
                                        supplier.deliveryDaysText,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
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
              if (supplier.paymentType != null) ...[
                _detailRow(
                  supplier.paymentType == 'Нал' ? Icons.money : Icons.credit_card,
                  'Оплата',
                  supplier.paymentType!,
                ),
                const Divider(),
              ],
              if (supplier.deliveryDaysText.isNotEmpty) ...[
                _detailRow(Icons.calendar_today, 'Дни доставки', supplier.deliveryDaysText),
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
