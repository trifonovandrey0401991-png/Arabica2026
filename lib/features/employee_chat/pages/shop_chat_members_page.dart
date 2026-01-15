import 'package:flutter/material.dart';
import '../services/employee_chat_service.dart';
import '../../employees/services/employee_service.dart';
import '../../employees/pages/employees_page.dart';

/// Страница управления участниками чата магазина
class ShopChatMembersPage extends StatefulWidget {
  final String shopAddress;

  const ShopChatMembersPage({
    super.key,
    required this.shopAddress,
  });

  @override
  State<ShopChatMembersPage> createState() => _ShopChatMembersPageState();
}

class _ShopChatMembersPageState extends State<ShopChatMembersPage> {
  List<ShopChatMember> _members = [];
  List<Employee> _allEmployees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        EmployeeChatService.getShopChatMembers(widget.shopAddress),
        EmployeeService.getEmployees(),
      ]);

      if (mounted) {
        setState(() {
          _members = results[0] as List<ShopChatMember>;
          _allEmployees = results[1] as List<Employee>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Получить сотрудников, которые ещё не добавлены в чат
  List<Employee> get _availableEmployees {
    final memberPhones = _members.map((m) => m.phone).toSet();
    return _allEmployees
        .where((e) => e.phone != null && !memberPhones.contains(e.phone))
        .toList();
  }

  Future<void> _showAddMembersDialog() async {
    final available = _availableEmployees;

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Все сотрудники уже добавлены в чат'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedPhones = <String>{};

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Добавить сотрудников'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: available.length,
              itemBuilder: (context, index) {
                final employee = available[index];
                final isSelected = selectedPhones.contains(employee.phone);

                return CheckboxListTile(
                  value: isSelected,
                  title: Text(employee.name),
                  subtitle: Text(employee.phone ?? ''),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true && employee.phone != null) {
                        selectedPhones.add(employee.phone!);
                      } else {
                        selectedPhones.remove(employee.phone);
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
              onPressed: selectedPhones.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _addMembers(selectedPhones.toList());
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004D40),
              ),
              child: Text('Добавить (${selectedPhones.length})'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMembers(List<String> phones) async {
    final success = await EmployeeChatService.addShopChatMembers(
      widget.shopAddress,
      phones,
    );

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Добавлено ${phones.length} сотрудников'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка добавления сотрудников'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeMember(ShopChatMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: Text('Удалить ${member.name} из чата магазина?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await EmployeeChatService.removeShopChatMember(
        widget.shopAddress,
        member.phone,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.name} удалён из чата'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка удаления'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Участники чата'),
            Text(
              widget.shopAddress,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _members.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.group_off,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Нет участников',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Добавьте сотрудников в чат магазина',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    itemCount: _members.length,
                    itemBuilder: (context, index) {
                      final member = _members[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange[100],
                          child: Text(
                            member.name.isNotEmpty
                                ? member.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: Colors.orange[800],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(member.name),
                        subtitle: Text(member.phone),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                          onPressed: () => _removeMember(member),
                          tooltip: 'Удалить',
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMembersDialog,
        backgroundColor: const Color(0xFF004D40),
        icon: const Icon(Icons.person_add),
        label: const Text('Добавить'),
      ),
    );
  }
}
