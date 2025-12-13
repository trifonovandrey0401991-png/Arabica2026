import 'package:flutter/material.dart';
import 'kpi_service.dart';
import 'kpi_employee_detail_page.dart';
import 'utils/logger.dart';

/// Страница списка всех сотрудников для KPI
class KPIEmployeesListPage extends StatefulWidget {
  const KPIEmployeesListPage({super.key});

  @override
  State<KPIEmployeesListPage> createState() => _KPIEmployeesListPageState();
}

class _KPIEmployeesListPageState extends State<KPIEmployeesListPage> {
  List<String> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    setState(() => _isLoading = true);

    try {
      final employees = await KPIService.getAllEmployees();
      if (mounted) {
        setState(() {
          _employees = employees;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Ошибка загрузки списка сотрудников', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<String> get _filteredEmployees {
    if (_searchQuery.isEmpty) {
      return _employees;
    }
    return _employees
        .where((employee) =>
            employee.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KPI - Сотрудники'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Поиск сотрудника...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          _isLoading
              ? const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              : _filteredEmployees.isEmpty
                  ? Expanded(
                      child: Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'Нет сотрудников'
                              : 'Сотрудники не найдены',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    )
                  : Expanded(
                      child: ListView.builder(
                        itemCount: _filteredEmployees.length,
                        itemBuilder: (context, index) {
                          final employee = _filteredEmployees[index];
                          return ListTile(
                            leading: const Icon(Icons.person),
                            title: Text(employee),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => KPIEmployeeDetailPage(
                                    employeeName: employee,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
        ],
      ),
    );
  }
}






