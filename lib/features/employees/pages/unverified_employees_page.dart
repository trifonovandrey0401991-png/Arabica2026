import 'package:flutter/material.dart';
import 'employees_page.dart';
import '../services/employee_service.dart';
import '../services/employee_registration_service.dart';
import 'employee_registration_view_page.dart';
import '../models/employee_registration_model.dart';
import '../../../core/utils/logger.dart';

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
      // Загружаем всех сотрудников с сервера
      final allEmployees = await EmployeeService.getEmployees();
      final List<Employee> employees = [];

      // Фильтруем только сотрудников с телефоном
      for (var employee in allEmployees) {
        if (employee.phone != null && employee.phone!.isNotEmpty) {
          // Нормализуем телефон
          final normalizedPhone = employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
          
          // Проверяем регистрацию
          final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);
          
          // Показываем только тех, у кого была снята верификация
          // (есть регистрация, verifiedAt != null, но isVerified = false)
          if (registration != null) {
            Logger.debug('Проверка для не верифицированных: ${employee.name}');
            Logger.debug('isVerified: ${registration.isVerified}, verifiedAt: ${registration.verifiedAt}');

            if (registration.verifiedAt != null && !registration.isVerified) {
              Logger.success('Добавлен в список не верифицированных: ${employee.name}');
              employees.add(employee);
              _registrations[normalizedPhone] = registration;
            } else {
              Logger.debug('Не подходит: verifiedAt=${registration.verifiedAt}, isVerified=${registration.isVerified}');
            }
          } else {
            Logger.debug('Регистрация не найдена для: ${employee.name}');
          }
        }
      }

      employees.sort((a, b) => a.name.compareTo(b.name));

      return employees;
    } catch (e) {
      Logger.error('Ошибка загрузки не верифицированных сотрудников', e);
      rethrow;
    }
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
                                // Сохраняем navigator перед async операцией
                                final navigator = Navigator.of(context);

                                if (!mounted) return;

                                final result = await navigator.push(
                                  MaterialPageRoute(
                                    builder: (context) => EmployeeRegistrationViewPage(
                                      employeePhone: employee.phone!,
                                      employeeName: employee.name,
                                    ),
                                  ),
                                );

                                if (!mounted) return;
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

