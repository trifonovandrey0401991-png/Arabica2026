import 'package:flutter/material.dart';
import '../models/task_model.dart';
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

/// Страница выбора получателей задачи
class TaskRecipientSelectionPage extends StatefulWidget {
  final List<TaskRecipient> initialSelected;

  const TaskRecipientSelectionPage({
    super.key,
    this.initialSelected = const [],
  });

  @override
  State<TaskRecipientSelectionPage> createState() => _TaskRecipientSelectionPageState();
}

class _TaskRecipientSelectionPageState extends State<TaskRecipientSelectionPage> {
  RecipientGroup _selectedGroup = RecipientGroup.all;
  List<Employee> _allEmployees = [];
  Set<String> _selectedIds = {};
  bool _isLoading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.initialSelected.map((r) => r.id).toSet();
    _loadEmployees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final employees = await EmployeeService.getEmployees();
      if (!mounted) return;
      setState(() {
        // Показываем всех сотрудников
        _allEmployees = employees;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Employee> get _filteredEmployees {
    List<Employee> result;
    switch (_selectedGroup) {
      case RecipientGroup.managers:
        result = _allEmployees.where((e) => e.isAdmin == true).toList();
        break;
      case RecipientGroup.employees:
        result = _allEmployees.where((e) => e.isAdmin != true).toList();
        break;
      case RecipientGroup.all:
        result = _allEmployees;
        break;
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((e) => e.name.toLowerCase().contains(query)).toList();
    }

    return result;
  }

  String _getRole(Employee employee) {
    return employee.isAdmin == true ? 'manager' : 'employee';
  }

  void _toggleEmployee(Employee employee) {
    if (mounted) setState(() {
      if (_selectedIds.contains(employee.id)) {
        _selectedIds.remove(employee.id);
      } else {
        _selectedIds.add(employee.id);
      }
    });
  }

  void _selectAll() {
    if (mounted) setState(() {
      for (final e in _filteredEmployees) {
        _selectedIds.add(e.id);
      }
    });
  }

  void _deselectAll() {
    if (mounted) setState(() {
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
              role: _getRole(e),
            ))
        .toList();

    Navigator.pop(context, recipients);
  }

  @override
  Widget build(BuildContext context) {
    final filteredCount = _filteredEmployees.where((e) => _selectedIds.contains(e.id)).length;
    final totalSelected = _selectedIds.length;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
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
                          style: TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w600,
                          ),
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
                      child: GestureDetector(
                        onTap: () {
                          if (mounted) setState(() => _selectedGroup = group);
                        },
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 200),
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.gold
                                : Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10.r),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.gold
                                  : Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: Text(
                            group.displayName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: isSelected ? AppColors.night : Colors.white,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Поиск по сотрудникам
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: Colors.white, fontSize: 14.sp),
                decoration: InputDecoration(
                  hintText: 'Поиск по имени...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close, color: Colors.white.withOpacity(0.5), size: 20),
                          onPressed: () {
                            _searchController.clear();
                            if (mounted) setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(color: AppColors.gold, width: 1.5),
                  ),
                  contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                ),
                onChanged: (value) {
                  if (mounted) setState(() => _searchQuery = value);
                },
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
                      : ListView.separated(
                          itemCount: _filteredEmployees.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            indent: 72,
                            color: Colors.white.withOpacity(0.1),
                          ),
                          itemBuilder: (context, index) {
                            final employee = _filteredEmployees[index];
                            final isSelected = _selectedIds.contains(employee.id);
                            final role = _getRole(employee);

                            return CheckboxListTile(
                              value: isSelected,
                              onChanged: (_) => _toggleEmployee(employee),
                              title: Text(
                                employee.name,
                                style: TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                role == 'manager' ? 'Заведующий' : 'Сотрудник',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                              secondary: CircleAvatar(
                                backgroundColor: role == 'manager'
                                    ? AppColors.gold.withOpacity(0.15)
                                    : AppColors.emerald.withOpacity(0.3),
                                child: Icon(
                                  role == 'manager'
                                      ? Icons.star
                                      : Icons.person,
                                  color: role == 'manager'
                                      ? AppColors.gold
                                      : Colors.white.withOpacity(0.7),
                                ),
                              ),
                              activeColor: AppColors.gold,
                              checkColor: AppColors.night,
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
                      disabledBackgroundColor: Colors.white.withOpacity(0.06),
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
    ),
    );
  }
}
