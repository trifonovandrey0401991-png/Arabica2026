import 'package:flutter/material.dart';
import '../models/recurring_task_model.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Группа получателей
enum RecipientGroup {
  managers,   // Заведующие (админы)
  employees,  // Сотрудники
  all,        // Все
}

extension RecipientGroupExtension on RecipientGroup {
  String get displayName {
    switch (this) {
      case RecipientGroup.managers:
        return 'Заведующие';
      case RecipientGroup.employees:
        return 'Сотрудники';
      case RecipientGroup.all:
        return 'Все';
    }
  }
}

/// Страница выбора получателей для циклических задач
class RecurringRecipientSelectionPage extends StatefulWidget {
  final List<TaskRecipient> initialSelected;

  const RecurringRecipientSelectionPage({
    super.key,
    this.initialSelected = const [],
  });

  @override
  State<RecurringRecipientSelectionPage> createState() => _RecurringRecipientSelectionPageState();
}

class _RecurringRecipientSelectionPageState extends State<RecurringRecipientSelectionPage> {
  RecipientGroup _selectedGroup = RecipientGroup.all;
  List<Employee> _allEmployees = [];
  Set<String> _selectedIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.initialSelected.map((r) => r.id).toSet();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);

    try {
      final employees = await EmployeeService.getEmployees();
      setState(() {
        _allEmployees = employees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Employee> get _filteredEmployees {
    switch (_selectedGroup) {
      case RecipientGroup.managers:
        return _allEmployees.where((e) => e.isAdmin == true).toList();
      case RecipientGroup.employees:
        return _allEmployees.where((e) => e.isAdmin != true).toList();
      case RecipientGroup.all:
        return _allEmployees;
    }
  }

  void _toggleEmployee(Employee employee) {
    setState(() {
      if (_selectedIds.contains(employee.id)) {
        _selectedIds.remove(employee.id);
      } else {
        _selectedIds.add(employee.id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      for (final e in _filteredEmployees) {
        _selectedIds.add(e.id);
      }
    });
  }

  void _deselectAll() {
    setState(() {
      for (final e in _filteredEmployees) {
        _selectedIds.remove(e.id);
      }
    });
  }

  void _confirm() {
    final recipients = _allEmployees
        .where((e) => _selectedIds.contains(e.id))
        .map((e) => TaskRecipient(
              id: e.id,
              name: e.name,
              phone: e.phone ?? '', // Важно: передаем телефон для push-уведомлений
            ))
        .toList();

    Navigator.pop(context, recipients);
  }

  @override
  Widget build(BuildContext context) {
    final filteredCount = _filteredEmployees.where((e) => _selectedIds.contains(e.id)).length;
    final totalSelected = _selectedIds.length;

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
        child: Column(
          children: [
            // Custom AppBar
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Получатели',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!_isLoading)
                      TextButton(
                        onPressed: _filteredEmployees.length == filteredCount ? _deselectAll : _selectAll,
                        child: Text(
                          _filteredEmployees.length == filteredCount ? 'Снять все' : 'Выбрать все',
                          style: TextStyle(color: AppColors.gold),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Группы
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: Row(
                children: RecipientGroup.values.map((group) {
                  final isSelected = _selectedGroup == group;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: group != RecipientGroup.values.last ? 8 : 0,
                      ),
                      child: ChoiceChip(
                        label: Text(
                          group.displayName,
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.white,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedGroup = group);
                          }
                        },
                        selectedColor: AppColors.gold,
                        backgroundColor: Colors.white.withOpacity(0.06),
                        side: isSelected
                            ? BorderSide.none
                            : BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            Divider(height: 1, color: Colors.white.withOpacity(0.1)),

            // Список сотрудников
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: AppColors.gold))
                  : _filteredEmployees.isEmpty
                      ? Center(
                          child: Text(
                            'Нет сотрудников в этой группе',
                            style: TextStyle(color: Colors.white.withOpacity(0.5)),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredEmployees.length,
                          itemBuilder: (context, index) {
                            final employee = _filteredEmployees[index];
                            final isSelected = _selectedIds.contains(employee.id);
                            final isManager = employee.isAdmin == true;

                            return CheckboxListTile(
                              value: isSelected,
                              onChanged: (_) => _toggleEmployee(employee),
                              activeColor: AppColors.gold,
                              checkColor: AppColors.night,
                              title: Text(
                                employee.name,
                                style: TextStyle(color: Colors.white),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isManager ? 'Заведующий' : 'Сотрудник',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: Colors.white.withOpacity(0.5),
                                    ),
                                  ),
                                  if (employee.phone != null && employee.phone!.isNotEmpty)
                                    Text(
                                      employee.phone!,
                                      style: TextStyle(
                                        fontSize: 11.sp,
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                    ),
                                ],
                              ),
                              isThreeLine: employee.phone != null && employee.phone!.isNotEmpty,
                              secondary: CircleAvatar(
                                backgroundColor: isManager
                                    ? AppColors.gold.withOpacity(0.15)
                                    : AppColors.emerald.withOpacity(0.3),
                                child: Icon(
                                  isManager
                                      ? Icons.star
                                      : Icons.person,
                                  color: isManager
                                      ? AppColors.gold
                                      : Colors.white.withOpacity(0.7),
                                ),
                              ),
                            );
                          },
                        ),
            ),

            // Кнопка подтверждения
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.emeraldDark,
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: totalSelected > 0 ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: AppColors.night,
                      disabledBackgroundColor: AppColors.gold.withOpacity(0.3),
                      disabledForegroundColor: Colors.white.withOpacity(0.3),
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text(
                      totalSelected > 0
                          ? 'ВЫБРАТЬ ($totalSelected человек)'
                          : 'ВЫБЕРИТЕ ПОЛУЧАТЕЛЕЙ',
                      style: TextStyle(
                        fontSize: 16.sp,
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
    );
  }
}
