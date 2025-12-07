import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'employees_page.dart';
import 'employee_registration_page.dart';
import 'employee_registration_service.dart';

/// Страница выбора сотрудника для регистрации (только для админа)
class EmployeeRegistrationSelectEmployeePage extends StatefulWidget {
  const EmployeeRegistrationSelectEmployeePage({super.key});

  @override
  State<EmployeeRegistrationSelectEmployeePage> createState() => _EmployeeRegistrationSelectEmployeePageState();
}

class _EmployeeRegistrationSelectEmployeePageState extends State<EmployeeRegistrationSelectEmployeePage> {
  late Future<List<Employee>> _employeesFuture;
  String _searchQuery = '';
  Map<String, bool> _verificationStatus = {};

  @override
  void initState() {
    super.initState();
    _employeesFuture = _loadEmployees();
    _loadVerificationStatuses();
  }

  Future<List<Employee>> _loadEmployees() async {
    try {
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Лист11';
      
      final response = await http.get(Uri.parse(sheetUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки данных: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      final List<Employee> employees = [];

      for (var i = 1; i < lines.length; i++) {
        try {
          final line = lines[i];
          final row = _parseCsvLine(line);
          
          if (row.length > 7) {
            final clientName = row[0].trim().replaceAll('"', '');
            final phone = row[1].trim().replaceAll('"', '');
            final employeeName = row.length > 6 ? row[6].trim().replaceAll('"', '') : '';
            final isAdmin = row.length > 7 ? row[7].trim().replaceAll('"', '') : '';
            
            final isEmployee = employeeName.isNotEmpty;
            final isAdminUser = isAdmin == '1' || isAdmin == '1.0';
            
            if (isEmployee || isAdminUser) {
              final displayName = employeeName.isNotEmpty ? employeeName : clientName;
              
              if (displayName.isNotEmpty && phone.isNotEmpty) {
                employees.add(Employee(
                  name: displayName,
                  phone: phone,
                  position: isAdminUser ? 'Администратор' : (isEmployee ? 'Сотрудник' : null),
                ));
              }
            }
          }
        } catch (e) {
          continue;
        }
      }

      final Map<String, Employee> uniqueEmployees = {};
      for (var employee in employees) {
        if (!uniqueEmployees.containsKey(employee.phone)) {
          uniqueEmployees[employee.phone!] = employee;
        }
      }

      final result = uniqueEmployees.values.toList();
      result.sort((a, b) => a.name.compareTo(b.name));
      
      return result;
    } catch (e) {
      print('Ошибка загрузки сотрудников: $e');
      rethrow;
    }
  }

  List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    String current = '';
    bool inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current);
        current = '';
      } else {
        current += char;
      }
    }
    
    result.add(current);
    return result;
  }

  Future<void> _loadVerificationStatuses() async {
    try {
      final employees = await _loadEmployees();
      for (var employee in employees) {
        if (employee.phone != null && employee.phone!.isNotEmpty) {
          final registration = await EmployeeRegistrationService.getRegistration(employee.phone!);
          _verificationStatus[employee.phone!] = registration?.isVerified ?? false;
        }
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Ошибка загрузки статусов верификации: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выберите сотрудника'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск сотрудника...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Employee>>(
              future: _employeesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Ошибка загрузки данных'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _employeesFuture = _loadEmployees();
                            });
                          },
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  );
                }

                final allEmployees = snapshot.data ?? [];
                final filteredEmployees = allEmployees.where((employee) {
                  if (_searchQuery.isEmpty) return true;
                  final name = employee.name.toLowerCase();
                  return name.contains(_searchQuery);
                }).toList();

                if (filteredEmployees.isEmpty) {
                  return const Center(
                    child: Text('Сотрудники не найдены'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filteredEmployees.length,
                  itemBuilder: (context, index) {
                    final employee = filteredEmployees[index];
                    final isVerified = employee.phone != null
                        ? _verificationStatus[employee.phone!] ?? false
                        : false;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFF004D40),
                              child: Text(
                                employee.name.isNotEmpty
                                    ? employee.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isVerified)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                employee.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (isVerified)
                              const Icon(
                                Icons.verified,
                                color: Colors.green,
                                size: 20,
                              ),
                          ],
                        ),
                        subtitle: employee.phone != null
                            ? Text(employee.phone!)
                            : null,
                        onTap: employee.phone != null && employee.phone!.isNotEmpty
                            ? () async {
                                // Загружаем существующую регистрацию, если есть
                                final existingRegistration = await EmployeeRegistrationService.getRegistration(employee.phone!);
                                
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EmployeeRegistrationPage(
                                      employeePhone: employee.phone!,
                                      existingRegistration: existingRegistration,
                                    ),
                                  ),
                                );
                                
                                if (result == true) {
                                  // Обновляем статусы верификации
                                  await _loadVerificationStatuses();
                                }
                              }
                            : null,
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

