import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'employees_page.dart';
import 'employee_registration_service.dart';
import 'employee_registration_view_page.dart';
import 'employee_registration_model.dart';

/// Страница не верифицированных сотрудников (у которых была снята верификация)
class UnverifiedEmployeesPage extends StatefulWidget {
  const UnverifiedEmployeesPage({super.key});

  @override
  State<UnverifiedEmployeesPage> createState() => _UnverifiedEmployeesPageState();
}

class _UnverifiedEmployeesPageState extends State<UnverifiedEmployeesPage> {
  late Future<List<Employee>> _employeesFuture;
  String _searchQuery = '';
  Map<String, EmployeeRegistration?> _registrations = {};

  @override
  void initState() {
    super.initState();
    _employeesFuture = _loadUnverifiedEmployees();
  }

  Future<List<Employee>> _loadUnverifiedEmployees() async {
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
            
            if ((isEmployee || isAdminUser) && phone.isNotEmpty) {
              // Нормализуем телефон
              final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
              
              // Проверяем регистрацию
              final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);
              
              // Показываем только тех, у кого была снята верификация
              // (есть регистрация, verifiedAt != null, но isVerified = false)
              if (registration != null && 
                  registration.verifiedAt != null && 
                  !registration.isVerified) {
                final displayName = employeeName.isNotEmpty ? employeeName : clientName;
                
                if (displayName.isNotEmpty) {
                  employees.add(Employee(
                    name: displayName,
                    phone: normalizedPhone,
                    position: isAdminUser ? 'Администратор' : (isEmployee ? 'Сотрудник' : null),
                  ));
                  _registrations[normalizedPhone] = registration;
                }
              }
            }
          }
        } catch (e) {
          continue;
        }
      }

      employees.sort((a, b) => a.name.compareTo(b.name));
      
      return employees;
    } catch (e) {
      print('Ошибка загрузки не верифицированных сотрудников: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Не верифицированные сотрудники'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _employeesFuture = _loadUnverifiedEmployees();
              });
            },
            tooltip: 'Обновить',
          ),
        ],
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
                        Text('Ошибка загрузки данных: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _employeesFuture = _loadUnverifiedEmployees();
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
                    child: Text('Не верифицированные сотрудники не найдены'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filteredEmployees.length,
                  itemBuilder: (context, index) {
                    final employee = filteredEmployees[index];
                    final registration = employee.phone != null 
                        ? _registrations[employee.phone!] 
                        : null;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: Colors.orange.shade50,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange,
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
                        title: Text(
                          employee.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (employee.phone != null) Text(employee.phone!),
                            if (registration != null && registration.verifiedAt != null)
                              Text(
                                'Верификация снята: ${registration.verifiedAt!.day}.${registration.verifiedAt!.month}.${registration.verifiedAt!.year}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.pending, color: Colors.orange),
                        onTap: employee.phone != null && employee.phone!.isNotEmpty
                            ? () async {
                                final existingRegistration = await EmployeeRegistrationService.getRegistration(employee.phone!);
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EmployeeRegistrationViewPage(
                                      employeePhone: employee.phone!,
                                      employeeName: employee.name,
                                    ),
                                  ),
                                );
                                if (result == true) {
                                  // Обновляем список после верификации
                                  setState(() {
                                    _employeesFuture = _loadUnverifiedEmployees();
                                  });
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

