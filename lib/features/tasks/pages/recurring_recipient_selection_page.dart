import 'package:flutter/material.dart';
import '../models/recurring_task_model.dart';
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
      appBar: AppBar(
        title: const Text('Получатели'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _filteredEmployees.length == filteredCount ? _deselectAll : _selectAll,
              child: Text(
                _filteredEmployees.length == filteredCount ? 'Снять все' : 'Выбрать все',
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Группы
          Container(
            padding: const EdgeInsets.all(16),
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
                          fontSize: 13,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedGroup = group);
                        }
                      },
                      selectedColor: const Color(0xFF004D40),
                      backgroundColor: Colors.grey[200],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1),

          // Список сотрудников
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredEmployees.isEmpty
                    ? Center(
                        child: Text(
                          'Нет сотрудников в этой группе',
                          style: TextStyle(color: Colors.grey[600]),
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
                            title: Text(employee.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isManager ? 'Заведующий' : 'Сотрудник',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (employee.phone != null && employee.phone!.isNotEmpty)
                                  Text(
                                    employee.phone!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                              ],
                            ),
                            isThreeLine: employee.phone != null && employee.phone!.isNotEmpty,
                            secondary: CircleAvatar(
                              backgroundColor: isManager
                                  ? Colors.purple[100]
                                  : Colors.blue[100],
                              child: Icon(
                                isManager
                                    ? Icons.star
                                    : Icons.person,
                                color: isManager
                                    ? Colors.purple
                                    : Colors.blue,
                              ),
                            ),
                            activeColor: const Color(0xFF004D40),
                          );
                        },
                      ),
          ),

          // Кнопка подтверждения
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: totalSelected > 0 ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    foregroundColor: Colors.white,
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
    );
  }
}
