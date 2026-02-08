import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart';

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
  static const Color _emerald = Color(0xFF1A4D4D);
  static const Color _emeraldDark = Color(0xFF0D2E2E);
  static const Color _night = Color(0xFF051515);
  static const Color _gold = Color(0xFFD4AF37);

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
        // Показываем всех сотрудников
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
        // Заведующие - это те, у кого isAdmin == true
        return _allEmployees.where((e) => e.isAdmin == true).toList();
      case RecipientGroup.employees:
        // Сотрудники - те, у кого isAdmin != true
        return _allEmployees.where((e) => e.isAdmin != true).toList();
      case RecipientGroup.all:
        return _allEmployees;
    }
  }

  String _getRole(Employee employee) {
    return employee.isAdmin == true ? 'manager' : 'employee';
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
              role: _getRole(e),
            ))
        .toList();

    Navigator.pop(context, recipients);
  }

  @override
  Widget build(BuildContext context) {
    final filteredCount = _filteredEmployees.where((e) => _selectedIds.contains(e.id)).length;
    final totalSelected = _selectedIds.length;

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
        child: Column(
          children: [
            // Custom AppBar
            SafeArea(
              bottom: false,
              child: Padding(
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
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Получатели',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
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
                            color: _gold,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedGroup = group);
                          }
                        },
                        selectedColor: _gold,
                        backgroundColor: Colors.white.withOpacity(0.06),
                        side: isSelected
                            ? BorderSide.none
                            : BorderSide(color: Colors.white.withOpacity(0.1)),
                        labelStyle: TextStyle(
                          fontSize: 13,
                          color: isSelected ? _night : Colors.white,
                        ),
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
                  ? Center(child: CircularProgressIndicator(color: _gold))
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
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                role == 'manager' ? 'Заведующий' : 'Сотрудник',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                              secondary: CircleAvatar(
                                backgroundColor: role == 'manager'
                                    ? _gold.withOpacity(0.15)
                                    : _emerald.withOpacity(0.3),
                                child: Icon(
                                  role == 'manager'
                                      ? Icons.star
                                      : Icons.person,
                                  color: role == 'manager'
                                      ? _gold
                                      : Colors.white.withOpacity(0.7),
                                ),
                              ),
                              activeColor: _gold,
                              checkColor: _night,
                            );
                          },
                        ),
            ),

            // Кнопка подтверждения
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _emeraldDark,
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
                      backgroundColor: _gold,
                      foregroundColor: _night,
                      disabledBackgroundColor: Colors.white.withOpacity(0.06),
                      disabledForegroundColor: Colors.white.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      totalSelected > 0
                          ? 'ВЫБРАТЬ ($totalSelected человек)'
                          : 'ВЫБЕРИТЕ ПОЛУЧАТЕЛЕЙ',
                      style: const TextStyle(
                        fontSize: 16,
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
