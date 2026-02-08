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
  static const _emerald = Color(0xFF1A4D4D);
  static const _emeraldDark = Color(0xFF0D2E2E);
  static const _night = Color(0xFF051515);
  static const _gold = Color(0xFFD4AF37);

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
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Выберите сотрудника',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: _gold),
                      )
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline,
                                    size: 64,
                                    color: Colors.white.withOpacity(0.5)),
                                const SizedBox(height: 16),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 32),
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 16,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.white.withOpacity(0.08),
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withOpacity(0.1),
                                    ),
                                  ),
                                  child: const Text('Назад'),
                                ),
                              ],
                            ),
                          )
                        : _managerEmployees.isEmpty
                            ? Center(
                                child: Text(
                                  'Нет управляющих или администраторов',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 18,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _managerEmployees.length,
                                itemBuilder: (context, index) {
                                  final employee = _managerEmployees[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                WithdrawalFormPage(
                                              shopAddress: widget.shopAddress,
                                              employeeName: employee.name,
                                              employeeId: employee.id,
                                              currentUserName:
                                                  widget.currentUserName,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.06),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color:
                                                Colors.white.withOpacity(0.1),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 28,
                                              backgroundColor: _emerald,
                                              child: Text(
                                                employee.name.isNotEmpty
                                                    ? employee.name[0]
                                                        .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
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
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors.white
                                                          .withOpacity(0.9),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          _getRoleBadgeColor(
                                                              employee),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      _getRoleBadge(employee),
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right,
                                              color: Colors.white
                                                  .withOpacity(0.3),
                                              size: 28,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
