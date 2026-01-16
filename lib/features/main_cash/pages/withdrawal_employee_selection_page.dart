import 'package:flutter/material.dart';
import '../../employees/pages/employees_page.dart';
import '../../employees/services/employee_service.dart';
import 'withdrawal_form_page.dart';

/// Страница выбора сотрудника для выемки (только управляющие и администраторы)
class WithdrawalEmployeeSelectionPage extends StatefulWidget {
  final String shopAddress;
  final String currentUserName;

  const WithdrawalEmployeeSelectionPage({
    super.key,
    required this.shopAddress,
    required this.currentUserName,
  });

  @override
  State<WithdrawalEmployeeSelectionPage> createState() =>
      _WithdrawalEmployeeSelectionPageState();
}

class _WithdrawalEmployeeSelectionPageState
    extends State<WithdrawalEmployeeSelectionPage> {
  List<Employee> _managerEmployees = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadManagers();
  }

  Future<void> _loadManagers() async {
    try {
      final employees = await EmployeeService.getEmployees();

      // Фильтровать только управляющих и администраторов
      final managers = employees.where((e) {
        return e.isManager == true || e.isAdmin == true;
      }).toList();

      if (mounted) {
        setState(() {
          _managerEmployees = managers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка загрузки сотрудников: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _getRoleBadge(Employee employee) {
    if (employee.isAdmin == true) {
      return 'Администратор';
    } else if (employee.isManager == true) {
      return 'Управляющий';
    }
    return '';
  }

  Color _getRoleBadgeColor(Employee employee) {
    if (employee.isAdmin == true) {
      return Colors.red[700]!;
    } else if (employee.isManager == true) {
      return Colors.orange[700]!;
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выберите сотрудника'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40),
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 64, color: Colors.white),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF004D40),
                          ),
                          child: const Text('Назад'),
                        ),
                      ],
                    ),
                  )
                : _managerEmployees.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет управляющих или администраторов',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _managerEmployees.length,
                        itemBuilder: (context, index) {
                          final employee = _managerEmployees[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          WithdrawalFormPage(
                                        shopAddress: widget.shopAddress,
                                        employeeName: employee.name,
                                        employeeId: employee.id,
                                        currentUserName: widget.currentUserName,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.5),
                                      width: 2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor: Colors.white,
                                        child: Text(
                                          employee.name.isNotEmpty
                                              ? employee.name[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF004D40),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              employee.name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _getRoleBadgeColor(
                                                    employee),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                _getRoleBadge(employee),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: Colors.white70,
                                        size: 28,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
