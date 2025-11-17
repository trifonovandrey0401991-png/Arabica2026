import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Модель сотрудника
class Employee {
  final String name;
  final String? position;
  final String? department;
  final String? phone;
  final String? email;

  Employee({
    required this.name,
    this.position,
    this.department,
    this.phone,
    this.email,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      name: (json['name'] ?? '').toString().trim(),
      position: json['position']?.toString().trim(),
      department: json['department']?.toString().trim(),
      phone: json['phone']?.toString().trim(),
      email: json['email']?.toString().trim(),
    );
  }
}

/// Страница сотрудников
class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  /// Загрузить сотрудников для уведомлений (статический метод)
  static Future<List<Employee>> loadEmployeesForNotifications() async {
    try {
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Работники';
      
      final response = await http.get(Uri.parse(sheetUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки данных: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      final List<Employee> employees = [];

      for (var i = 1; i < lines.length; i++) {
        try {
          final line = lines[i];
          final row = _parseCsvLineStatic(line);
          
          if (row.length > 4) {
            final name = row[4].trim().replaceAll('"', '');
            
            if (name.isNotEmpty) {
              employees.add(Employee(name: name));
            }
          }
        } catch (e) {
          continue;
        }
      }

      final Map<String, Employee> uniqueEmployees = {};
      for (var employee in employees) {
        if (!uniqueEmployees.containsKey(employee.name)) {
          uniqueEmployees[employee.name] = employee;
        }
      }

      return uniqueEmployees.values.toList();
    } catch (e) {
      return [];
    }
  }

  static List<String> _parseCsvLineStatic(String line) {
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
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  late Future<List<Employee>> _employeesFuture;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _employeesFuture = _loadEmployees();
  }

  Future<List<Employee>> _loadEmployees() async {
    try {
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Работники';
      
      final response = await http.get(Uri.parse(sheetUrl));
      
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки данных: ${response.statusCode}');
      }

      final lines = const LineSplitter().convert(response.body);
      final List<Employee> employees = [];

      // Пропускаем заголовок (первая строка)
      for (var i = 1; i < lines.length; i++) {
        try {
          final line = lines[i];
          
          // Парсим CSV строку, учитывая кавычки
          final row = _parseCsvLine(line);
          
          // Столбец E - это индекс 4 (5-й столбец)
          if (row.length > 4) {
            final name = row[4].trim().replaceAll('"', '');
            
            if (name.isNotEmpty) {
              employees.add(Employee(
                name: name,
                position: row.length > 0 ? row[0].trim().replaceAll('"', '') : null,
                department: row.length > 1 ? row[1].trim().replaceAll('"', '') : null,
                phone: row.length > 2 ? row[2].trim().replaceAll('"', '') : null,
                email: row.length > 3 ? row[3].trim().replaceAll('"', '') : null,
              ));
            }
          }
        } catch (e) {
          // ignore: avoid_print
          print("⚠️ Ошибка парсинга строки $i: $e");
          continue;
        }
      }

      // Удаляем дубликаты по имени
      final Map<String, Employee> uniqueEmployees = {};
      for (var employee in employees) {
        if (!uniqueEmployees.containsKey(employee.name)) {
          uniqueEmployees[employee.name] = employee;
        }
      }

      final result = uniqueEmployees.values.toList();
      result.sort((a, b) => a.name.compareTo(b.name));

      // ignore: avoid_print
      print("👥 Загружено сотрудников: ${result.length}");

      return result;
    } catch (e) {
      // ignore: avoid_print
      print("❌ Ошибка загрузки сотрудников: $e");
      rethrow;
    }
  }

  /// Парсинг CSV строки с учетом кавычек
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
    
    result.add(current); // Добавляем последнее поле
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сотрудники'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Column(
        children: [
          // Поиск
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
          // Список сотрудников
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
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ошибка загрузки данных',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _employeesFuture = _loadEmployees();
                            });
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Повторить'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004D40),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final allEmployees = snapshot.data ?? [];
                
                // Фильтрация по поисковому запросу
                final filteredEmployees = allEmployees.where((employee) {
                  if (_searchQuery.isEmpty) return true;
                  
                  final name = employee.name.toLowerCase();
                  final position = (employee.position ?? '').toLowerCase();
                  final department = (employee.department ?? '').toLowerCase();
                  
                  return name.contains(_searchQuery) ||
                      position.contains(_searchQuery) ||
                      department.contains(_searchQuery);
                }).toList();

                if (filteredEmployees.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_search,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Сотрудники не найдены',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filteredEmployees.length,
                  itemBuilder: (context, index) {
                    final employee = filteredEmployees[index];
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
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
                            if (employee.position != null &&
                                employee.position!.isNotEmpty)
                              Text(
                                employee.position!,
                                style: const TextStyle(fontSize: 14),
                              ),
                            if (employee.department != null &&
                                employee.department!.isNotEmpty)
                              Text(
                                employee.department!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            if (employee.phone != null &&
                                employee.phone!.isNotEmpty)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.phone,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    employee.phone!,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            if (employee.email != null &&
                                employee.email!.isNotEmpty)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.email,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      employee.email!,
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        isThreeLine: employee.position != null ||
                            employee.department != null ||
                            employee.phone != null ||
                            employee.email != null,
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

