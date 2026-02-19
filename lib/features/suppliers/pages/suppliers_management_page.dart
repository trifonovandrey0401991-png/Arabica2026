import 'package:flutter/material.dart';
import '../models/supplier_model.dart';
import '../services/supplier_service.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/employee_service.dart';
import '../../tasks/services/recurring_task_service.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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

  static final List<String> _weekDays = [
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
    if (mounted) setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        SupplierService.getSuppliers(),
        ShopService.getShopsForCurrentUser(),  // Фильтрация по роли
        EmployeeService.getEmployees(),
      ]);
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
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

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28.r),
              topRight: Radius.circular(28.r),
            ),
          ),
          child: Column(
            children: [
              // Заголовок
              Container(
                padding: EdgeInsets.fromLTRB(24.w, 16.h, 16.w, 16.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF00695C),
                      AppColors.primaryGreen,
                    ],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(28.r),
                    topRight: Radius.circular(28.r),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      child: Icon(
                        Icons.local_shipping,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Редактирование' : 'Новый поставщик',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            isEditing ? supplier.name : 'Заполните данные',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13.sp,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              // Контент
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Секция: Основная информация
                      _buildSectionHeader(
                        icon: Icons.info_outline,
                        title: 'Основная информация',
                        color: AppColors.primaryGreen,
                      ),
                      SizedBox(height: 12),
                      _buildStyledTextField(
                        controller: nameController,
                        label: 'Название компании',
                        hint: 'Введите название',
                        icon: Icons.business,
                        isRequired: true,
                      ),
                      SizedBox(height: 14),
                      // Тип организации - красивые кнопки
                      Text(
                        'Тип организации',
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF636E72),
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSelectButton(
                              label: 'ООО',
                              isSelected: selectedLegalType == 'ООО',
                              onTap: () => setDialogState(() => selectedLegalType = 'ООО'),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: _buildSelectButton(
                              label: 'ИП',
                              isSelected: selectedLegalType == 'ИП',
                              onTap: () => setDialogState(() => selectedLegalType = 'ИП'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 14),
                      _buildStyledTextField(
                        controller: innController,
                        label: 'ИНН',
                        hint: 'Введите ИНН',
                        icon: Icons.numbers,
                        keyboardType: TextInputType.number,
                      ),

                      SizedBox(height: 24),
                      // Секция: Контакты
                      _buildSectionHeader(
                        icon: Icons.contact_phone_outlined,
                        title: 'Контактные данные',
                        color: Colors.blue,
                      ),
                      SizedBox(height: 12),
                      _buildStyledTextField(
                        controller: contactPersonController,
                        label: 'Контактное лицо',
                        hint: 'ФИО представителя',
                        icon: Icons.person_outline,
                      ),
                      SizedBox(height: 14),
                      _buildStyledTextField(
                        controller: phoneController,
                        label: 'Телефон',
                        hint: '+7 (___) ___-__-__',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      SizedBox(height: 14),
                      _buildStyledTextField(
                        controller: emailController,
                        label: 'Email',
                        hint: 'email@example.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),

                      SizedBox(height: 24),
                      // Секция: Оплата
                      _buildSectionHeader(
                        icon: Icons.payment_outlined,
                        title: 'Тип оплаты',
                        color: Colors.orange,
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSelectButton(
                              label: 'Безналичный',
                              icon: Icons.credit_card,
                              isSelected: selectedPaymentType == 'БезНал',
                              onTap: () => setDialogState(() => selectedPaymentType = 'БезНал'),
                              color: Colors.blue,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: _buildSelectButton(
                              label: 'Наличный',
                              icon: Icons.money,
                              isSelected: selectedPaymentType == 'Нал',
                              onTap: () => setDialogState(() => selectedPaymentType = 'Нал'),
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 24),
                      // Секция: Доставки
                      _buildSectionHeader(
                        icon: Icons.store_outlined,
                        title: 'Доставки по магазинам',
                        color: Colors.green,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Выберите дни доставки и ответственных',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.grey[500],
                        ),
                      ),
                      SizedBox(height: 12),
                      // Список магазинов
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
                      SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              // Кнопки внизу
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[700],
                          side: BorderSide(color: Colors.grey[300]!),
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                        ),
                        child: Text(
                          'Отмена',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF00695C), AppColors.primaryGreen],
                          ),
                          borderRadius: BorderRadius.circular(14.r),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryGreen.withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            if (nameController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      Icon(Icons.error_outline, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text('Введите название поставщика'),
                                    ],
                                  ),
                                  backgroundColor: Colors.red[400],
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                ),
                              );
                              return;
                            }

                            // Собираем данные о доставках
                            final List<SupplierShopDelivery> deliveries = [];
                            for (var shop in _shops) {
                              final days = shopDeliveryDays[shop.id] ?? [];
                              final managerIds = shopManagerIds[shop.id] ?? [];
                              if (days.isNotEmpty || managerIds.isNotEmpty) {
                                if (days.isNotEmpty) {
                                  days.sort((a, b) => _weekDays.indexOf(a).compareTo(_weekDays.indexOf(b)));
                                }
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
                              if (savedSupplier.shopDeliveries != null && savedSupplier.shopDeliveries!.isNotEmpty) {
                                try {
                                  final managersData = _managers
                                      .map((m) => {
                                            'id': m.id,
                                            'name': m.name,
                                            'phone': m.phone ?? '',
                                          })
                                      .toList();

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
                                }
                              } else {
                                try {
                                  await RecurringTaskService.deleteTasksForSupplier(savedSupplier.id);
                                } catch (e) {
                                  Logger.error('Ошибка удаления задач поставщика', e);
                                }
                              }

                              Navigator.pop(context, true);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      Icon(Icons.error_outline, color: Colors.white),
                                      SizedBox(width: 8),
                                      Text('Ошибка сохранения'),
                                    ],
                                  ),
                                  backgroundColor: Colors.red[400],
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: EdgeInsets.symmetric(vertical: 14.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(isEditing ? Icons.save_outlined : Icons.add, size: 20),
                              SizedBox(width: 8),
                              Text(
                                isEditing ? 'Сохранить' : 'Добавить поставщика',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.sp),
                              ),
                            ],
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
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: Color(0xFF636E72),
              ),
            ),
            if (isRequired)
              Text(
                ' *',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
          ],
        ),
        SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: Icon(icon, color: Colors.grey[400], size: 20),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
    Color color = AppColors.primaryGreen,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 16.w),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isSelected ? color : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: isSelected ? color : Colors.grey[500],
              ),
              SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
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
      margin: EdgeInsets.only(bottom: 8.h),
      color: isActive ? Colors.green.shade50 : Colors.grey.shade50,
      child: Padding(
        padding: EdgeInsets.all(12.w),
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
                SizedBox(width: 8),
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
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      '${selectedDays.length} ${_getDayWord(selectedDays.length)}',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 8),
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
                      fontSize: 12.sp,
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
                  selectedColor: AppColors.primaryGreen.withOpacity(0.3),
                  checkmarkColor: AppColors.primaryGreen,
                  padding: EdgeInsets.symmetric(horizontal: 4.w),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
            // Заведующие
            SizedBox(height: 8),
            InkWell(
              onTap: () => _showManagersDialog(
                shopName: shop.name,
                allManagers: allManagers,
                selectedIds: selectedManagerIds,
                onChanged: onManagersChanged,
              ),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: hasManagers ? Colors.orange.shade300 : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(8.r),
                  color: hasManagers ? Colors.orange.shade50 : Colors.white,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 18,
                      color: hasManagers ? Colors.orange.shade700 : Colors.grey.shade600,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hasManagers
                            ? _getManagerNames(selectedManagerIds, allManagers)
                            : 'Выбрать заведующих...',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: hasManagers ? Colors.orange.shade800 : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasManagers)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Text(
                          '${selectedManagerIds.length}',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    SizedBox(width: 4),
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
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.w),
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
                                style: TextStyle(fontSize: 12.sp),
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
                        activeColor: AppColors.primaryGreen,
                        dense: true,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                onChanged(tempSelected);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
              ),
              child: Text('Применить'),
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
        title: Text('Удалить поставщика?'),
        content: Text('Вы уверены, что хотите удалить поставщика "${supplier.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text('Удалить'),
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
            SnackBar(
              content: Text('Поставщик удален'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
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
      backgroundColor: AppColors.night,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Поставщики'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: AppColors.gold),
              onPressed: _loadData,
            ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.gold, AppColors.darkGold],
          ),
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withOpacity(0.3),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => _showAddEditDialog(),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Icon(Icons.add, size: 28, color: AppColors.night),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
          ),
        ),
        child: Column(
          children: [
            // Заголовок с количеством
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 60.h, 16.w, 16.h),
                child: Column(
                  children: [
                    // Поле поиска
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: TextField(
                        style: TextStyle(color: Colors.white),
                        cursorColor: AppColors.gold,
                        decoration: InputDecoration(
                          hintText: 'Поиск по названию, ИНН, телефону...',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: Icon(Icons.search, color: AppColors.gold),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                        ),
                        onChanged: (value) {
                          if (mounted) setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 14),
                    // Статистика
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStatChip(
                          icon: Icons.local_shipping,
                          label: 'Всего',
                          count: _suppliers.length,
                          color: AppColors.gold,
                        ),
                        SizedBox(width: 12),
                        _buildStatChip(
                          icon: Icons.check_circle,
                          label: 'С доставкой',
                          count: _suppliers.where((s) => s.shopsWithDeliveryCount > 0).length,
                          color: AppColors.emeraldGreenLight,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                  : _filteredSuppliers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                                ),
                                child: Icon(
                                  Icons.local_shipping_outlined,
                                  size: 40,
                                  color: Colors.white.withOpacity(0.3),
                                ),
                              ),
                              SizedBox(height: 20),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'Нет поставщиков'
                                    : 'Поставщики не найдены',
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                              if (_searchQuery.isEmpty) ...[
                                SizedBox(height: 8),
                                Text(
                                  'Нажмите + чтобы добавить первого',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    color: Colors.white.withOpacity(0.4),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          color: AppColors.gold,
                          backgroundColor: AppColors.emeraldDark,
                          child: ListView.builder(
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                            itemCount: _filteredSuppliers.length,
                            itemBuilder: (context, index) {
                              final supplier = _filteredSuppliers[index];
                              return _buildSupplierCard(supplier);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16.sp,
            ),
          ),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12.sp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierCard(Supplier supplier) {
    final hasDelivery = supplier.shopsWithDeliveryCount > 0;

    return Container(
      margin: EdgeInsets.only(bottom: 6.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          onTap: () => _showSupplierDetails(supplier),
          borderRadius: BorderRadius.circular(14.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            child: Row(
              children: [
                // Компактный аватар
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.emeraldDark, AppColors.emerald],
                    ),
                    borderRadius: BorderRadius.circular(10.r),
                    border: hasDelivery
                        ? Border.all(color: AppColors.gold.withOpacity(0.5), width: 1.5)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      supplier.name.isNotEmpty
                          ? supplier.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.sp,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                // Информация — одна строка
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          supplier.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.sp,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (supplier.legalType != null) ...[
                        SizedBox(width: 6),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            supplier.legalType!,
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 6),
                // Теги справа (компактные)
                if (supplier.paymentType != null)
                  _buildInfoChip(
                    icon: supplier.paymentType == 'Нал' ? Icons.money : Icons.credit_card,
                    label: supplier.paymentType!,
                    color: supplier.paymentType == 'Нал' ? AppColors.warmAmber : AppColors.info,
                  ),
                if (supplier.paymentType != null && hasDelivery) SizedBox(width: 4),
                if (hasDelivery)
                  _buildInfoChip(
                    icon: Icons.local_shipping,
                    label: '${supplier.shopsWithDeliveryCount}',
                    color: AppColors.emeraldGreenLight,
                  ),
                // Телефон
                if (supplier.phone != null)
                  Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.phone, size: 14, color: Colors.white.withOpacity(0.3)),
                  ),
                // Меню
                SizedBox(
                  width: 32,
                  height: 32,
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.3), size: 18),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showAddEditDialog(supplier);
                      } else if (value == 'delete') {
                        _deleteSupplier(supplier);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20, color: Colors.grey[700]),
                            SizedBox(width: 12),
                            Text('Редактировать'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Удалить', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
              color: color,
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
                Divider(),
              ],
              if (supplier.inn != null) ...[
                _detailRow(Icons.numbers, 'ИНН', supplier.inn!),
                Divider(),
              ],
              if (supplier.phone != null) ...[
                _detailRow(Icons.phone, 'Телефон', supplier.phone!),
                Divider(),
              ],
              if (supplier.email != null) ...[
                _detailRow(Icons.email, 'Email', supplier.email!),
                Divider(),
              ],
              if (supplier.contactPerson != null) ...[
                _detailRow(Icons.person, 'Контактное лицо', supplier.contactPerson!),
                Divider(),
              ],
              if (supplier.paymentType != null) ...[
                _detailRow(
                  supplier.paymentType == 'Нал' ? Icons.money : Icons.credit_card,
                  'Оплата',
                  supplier.paymentType!,
                ),
                Divider(),
              ],
              // Показываем доставки по магазинам
              if (supplier.shopDeliveries != null && supplier.shopDeliveries!.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  'Доставки и заведующие:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.sp,
                  ),
                ),
                SizedBox(height: 8),
                ...supplier.shopDeliveries!.map((sd) => Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.store, size: 16, color: Colors.grey),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sd.shopName,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13.sp,
                              ),
                            ),
                            if (sd.daysShortText.isNotEmpty)
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 12, color: Colors.green.shade600),
                                  SizedBox(width: 4),
                                  Text(
                                    sd.daysShortText,
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            if (sd.hasManagers)
                              Padding(
                                padding: EdgeInsets.only(top: 2.h),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.person, size: 12, color: Colors.orange.shade600),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        sd.managersText,
                                        style: TextStyle(
                                          fontSize: 12.sp,
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
            child: Text('Закрыть'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showAddEditDialog(supplier);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            child: Text('Редактировать'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(fontSize: 14.sp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
