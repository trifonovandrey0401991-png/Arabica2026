import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'user_role_service.dart';
import 'google_script_config.dart';
import 'employee_registration_service.dart';
import 'employee_registration_view_page.dart';
import 'user_role_model.dart';
import 'unverified_employees_page.dart';
import 'shops_management_page.dart';

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
  /// Загружает только сотрудников и админов из Лист11
  static Future<List<Employee>> loadEmployeesForNotifications() async {
    try {
      const sheetUrl =
          'https://docs.google.com/spreadsheets/d/1n7E3sph8x_FanomlEuEeG5a0OMWSz9UXNlIjXAr19MU/gviz/tq?tqx=out:csv&sheet=Лист11';
      
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
          final row = _parseCsvLineStatic(line);
          
          // Столбец A (0) - имя клиента
          // Столбец B (1) - телефон
          // Столбец G (6) - имя сотрудника (если заполнено - сотрудник)
          // Столбец H (7) - админ (если "1" - админ)
          
          if (row.length > 7) {
            final clientName = row[0].trim().replaceAll('"', '');
            final phone = row[1].trim().replaceAll('"', '');
            final employeeName = row.length > 6 ? row[6].trim().replaceAll('"', '') : '';
            final isAdmin = row.length > 7 ? row[7].trim().replaceAll('"', '') : '';
            
            // Проверяем, является ли пользователь сотрудником или админом
            final isEmployee = employeeName.isNotEmpty;
            final isAdminUser = isAdmin == '1' || isAdmin == '1.0';
            
            if (isEmployee || isAdminUser) {
              // Используем имя из столбца G, если оно заполнено, иначе из столбца A
              final displayName = employeeName.isNotEmpty ? employeeName : clientName;
              
              if (displayName.isNotEmpty) {
                employees.add(Employee(
                  name: displayName,
                  phone: phone.isNotEmpty ? phone : null,
                ));
              }
            }
          }
        } catch (e) {
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
      
      return result;
    } catch (e) {
      print('❌ Ошибка загрузки сотрудников: $e');
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
  Map<String, bool> _verificationStatus = {}; // Кэш статуса верификации по телефону
  bool _isLoadingVerification = false;

  @override
  void initState() {
    super.initState();
    _employeesFuture = _loadEmployees();
    _loadVerificationStatuses();
  }


  Future<void> _loadVerificationStatuses() async {
    if (_isLoadingVerification) return;
    setState(() {
      _isLoadingVerification = true;
    });

    try {
      final employees = await _loadEmployees();
      print('🔍 Загрузка статусов верификации для ${employees.length} сотрудников');
      for (var employee in employees) {
        if (employee.phone != null && employee.phone!.isNotEmpty) {
          print('  📞 Проверка сотрудника: ${employee.name}, телефон: ${employee.phone}');
          final registration = await EmployeeRegistrationService.getRegistration(employee.phone!);
          final isVerified = registration?.isVerified ?? false;
          _verificationStatus[employee.phone!] = isVerified;
          print('  ✅ Статус верификации для ${employee.name}: $isVerified (регистрация: ${registration != null ? "найдена" : "не найдена"})');
        }
      }
      print('✅ Загружено статусов верификации: ${_verificationStatus.length}');
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ Ошибка загрузки статусов верификации: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVerification = false;
        });
      }
    }
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

      // Пропускаем заголовок (первая строка)
      for (var i = 1; i < lines.length; i++) {
        try {
          final line = lines[i];
          
          // Парсим CSV строку, учитывая кавычки
          final row = _parseCsvLine(line);
          
          // Столбец A (0) - имя клиента
          // Столбец B (1) - телефон
          // Столбец G (6) - имя сотрудника (если заполнено - сотрудник)
          // Столбец H (7) - админ (если "1" - админ)
          
          if (row.length > 7) {
            final clientName = row[0].trim().replaceAll('"', '');
            final phone = row[1].trim().replaceAll('"', '');
            final employeeName = row.length > 6 ? row[6].trim().replaceAll('"', '') : '';
            final isAdmin = row.length > 7 ? row[7].trim().replaceAll('"', '') : '';
            
            // Проверяем, является ли пользователь сотрудником или админом
            final isEmployee = employeeName.isNotEmpty;
            final isAdminUser = isAdmin == '1' || isAdmin == '1.0';
            
            if (isEmployee || isAdminUser) {
              // Используем имя из столбца G, если оно заполнено, иначе из столбца A
              final displayName = employeeName.isNotEmpty ? employeeName : clientName;
              
              if (displayName.isNotEmpty) {
                // Нормализуем телефон (убираем пробелы и +)
                final normalizedPhone = phone.isNotEmpty 
                    ? phone.replaceAll(RegExp(r'[\s\+]'), '') 
                    : null;
                
                employees.add(Employee(
                  name: displayName,
                  phone: normalizedPhone,
                  // Для админов можно добавить пометку
                  position: isAdminUser ? 'Администратор' : (isEmployee ? 'Сотрудник' : null),
                ));
              }
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
      print("👥 Загружено сотрудников и админов: ${result.length}");

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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Сотрудники'),
          backgroundColor: const Color(0xFF004D40),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Сотрудники', icon: Icon(Icons.people)),
              Tab(text: 'Магазины', icon: Icon(Icons.store)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_off),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UnverifiedEmployeesPage(),
                  ),
                );
              },
              tooltip: 'Не верифицированные сотрудники',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _employeesFuture = _loadEmployees();
                  _loadVerificationStatuses();
                });
              },
              tooltip: 'Обновить',
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // Вкладка "Сотрудники"
            Column(
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
                
                // Фильтрация: показываем только верифицированных сотрудников
                final filteredEmployees = allEmployees.where((employee) {
                  // Показываем только верифицированных сотрудников
                  if (employee.phone != null && employee.phone!.isNotEmpty) {
                    final isVerified = _verificationStatus[employee.phone!] ?? false;
                    if (!isVerified) {
                      return false; // Исключаем не верифицированных
                    }
                  } else {
                    // Если нет телефона, исключаем из списка
                    return false;
                  }
                  
                  // Фильтрация по поисковому запросу
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
                        onTap: employee.phone != null && employee.phone!.isNotEmpty
                            ? () async {
                                // Открываем страницу просмотра регистрации
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EmployeeRegistrationViewPage(
                                      employeePhone: employee.phone!,
                                      employeeName: employee.name,
                                    ),
                                  ),
                                );
                                // Обновляем статусы верификации после возврата
                                if (result == true || result != null) {
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
            // Вкладка "Магазины"
            const ShopsManagementPage(),
          ],
        ),
      ),
    );
  }
}

