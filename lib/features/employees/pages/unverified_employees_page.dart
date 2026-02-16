import 'package:flutter/material.dart';
import 'employees_page.dart';
import '../services/employee_service.dart';
import '../services/employee_registration_service.dart';
import 'employee_registration_view_page.dart';
import '../models/employee_registration_model.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница не верифицированных сотрудников (у которых была снята верификация)
class UnverifiedEmployeesPage extends StatefulWidget {
  const UnverifiedEmployeesPage({super.key});

  @override
  State<UnverifiedEmployeesPage> createState() => _UnverifiedEmployeesPageState();
}

class _UnverifiedEmployeesPageState extends State<UnverifiedEmployeesPage> {
  late Future<List<Employee>> _employeesFuture;
  String _searchQuery = '';
  final Map<String, EmployeeRegistration?> _registrations = {};

  @override
  void initState() {
    super.initState();
    _employeesFuture = _loadUnverifiedEmployees();
  }

  Future<List<Employee>> _loadUnverifiedEmployees() async {
    try {
      // M-06/M-10 fix: загружаем сотрудников и ВСЕ регистрации параллельно (2 запроса вместо N+1)
      final results = await Future.wait([
        EmployeeService.getEmployees(),
        EmployeeRegistrationService.getAllRegistrations(),
      ]).timeout(Duration(seconds: 30));

      final allEmployees = results[0] as List<Employee>;
      final allRegistrations = results[1] as List<EmployeeRegistration>;

      // Индекс регистраций по телефону для быстрого поиска O(1)
      final registrationsByPhone = <String, EmployeeRegistration>{};
      for (final reg in allRegistrations) {
        final phone = reg.phone.replaceAll(RegExp(r'[\s\+]'), '');
        if (phone.isNotEmpty) {
          registrationsByPhone[phone] = reg;
        }
      }

      final List<Employee> employees = [];

      for (final employee in allEmployees) {
        if (employee.phone == null || employee.phone!.isEmpty) continue;
        final normalizedPhone = employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
        final registration = registrationsByPhone[normalizedPhone];

        if (registration != null) {
          if (registration.verifiedAt != null && !registration.isVerified) {
            employees.add(employee);
            _registrations[normalizedPhone] = registration;
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
        title: Text('Не верифицированные сотрудники'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
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
            padding: EdgeInsets.all(12.w),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск сотрудника...',
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
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
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red),
                        SizedBox(height: 16),
                        Text('Ошибка загрузки данных: ${snapshot.error}'),
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _employeesFuture = _loadUnverifiedEmployees();
                            });
                          },
                          child: Text('Повторить'),
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
                  return Center(
                    child: Text('Не верифицированные сотрудники не найдены'),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  itemCount: filteredEmployees.length,
                  itemBuilder: (context, index) {
                    final employee = filteredEmployees[index];
                    final registration = employee.phone != null 
                        ? _registrations[employee.phone!] 
                        : null;

                    return Card(
                      margin: EdgeInsets.symmetric(vertical: 4.h),
                      color: Colors.orange.shade50,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Text(
                            employee.name.isNotEmpty
                                ? employee.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          employee.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16.sp,
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
                                  fontSize: 12.sp,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                        trailing: Icon(Icons.pending, color: Colors.orange),
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

