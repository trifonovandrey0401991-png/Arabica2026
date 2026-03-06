import 'package:flutter/material.dart';
import 'employees_page.dart';
import '../services/employee_service.dart';
import 'employee_registration_page.dart';
import '../services/employee_registration_service.dart';
import '../models/employee_registration_model.dart';
import '../../../core/utils/logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

/// Страница выбора сотрудника для регистрации (только для админа)
class EmployeeRegistrationSelectEmployeePage extends StatefulWidget {
  const EmployeeRegistrationSelectEmployeePage({super.key});

  @override
  State<EmployeeRegistrationSelectEmployeePage> createState() => _EmployeeRegistrationSelectEmployeePageState();
}

class _EmployeeRegistrationSelectEmployeePageState extends State<EmployeeRegistrationSelectEmployeePage> {
  late Future<List<Employee>> _employeesFuture;
  String _searchQuery = '';
  final Map<String, bool> _verificationStatus = {};
  final Map<String, bool> _hasRegistration = {}; // Кэш наличия регистрации (независимо от статуса верификации)

  @override
  void initState() {
    super.initState();
    _employeesFuture = _loadEmployees();
    _loadVerificationStatuses();
  }

  Future<List<Employee>> _loadEmployees() async {
    try {
      final employees = await EmployeeService.getEmployees();
      employees.sort((a, b) => a.name.compareTo(b.name));
      return employees;
    } catch (e) {
      Logger.error('Ошибка загрузки сотрудников', e);
      rethrow;
    }
  }

  Future<void> _loadVerificationStatuses() async {
    try {
      // Один запрос вместо N отдельных — загружаем все регистрации разом
      final allRegistrations = await EmployeeRegistrationService.getAllRegistrations();
      final regMap = <String, EmployeeRegistration>{};
      for (final reg in allRegistrations) {
        final normalizedPhone = reg.phone.replaceAll(RegExp(r'[\s\+]'), '');
        regMap[normalizedPhone] = reg;
      }

      // Используем уже загруженных сотрудников (без повторного запроса)
      final employees = await _employeesFuture;
      for (var employee in employees) {
        if (employee.phone != null && employee.phone!.isNotEmpty) {
          final normalizedPhone = employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
          final registration = regMap[normalizedPhone];
          _verificationStatus[normalizedPhone] = registration?.isVerified ?? false;
          _hasRegistration[normalizedPhone] = registration != null;
        }
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      Logger.error('Ошибка загрузки статусов верификации', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Выберите сотрудника'),
        backgroundColor: AppColors.primaryGreen,
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
                if (mounted) setState(() {
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
                        Text('Ошибка загрузки данных'),
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            if (mounted) setState(() {
                              _employeesFuture = _loadEmployees();
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
                  // Исключаем сотрудников, у которых уже есть регистрация (даже если isVerified = false)
                  if (employee.phone != null && employee.phone!.isNotEmpty) {
                    final normalizedPhone = employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
                    if (_hasRegistration[normalizedPhone] == true) {
                      return false; // Скрываем сотрудников с регистрацией
                    }
                  }
                  
                  if (_searchQuery.isEmpty) return true;
                  final name = employee.name.toLowerCase();
                  return name.contains(_searchQuery);
                }).toList();

                if (filteredEmployees.isEmpty) {
                  return Center(
                    child: Text('Все сотрудники зарегистрированы или не найдены'),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  itemCount: filteredEmployees.length,
                  itemBuilder: (context, index) {
                    final employee = filteredEmployees[index];
                    final isVerified = employee.phone != null
                        ? _verificationStatus[employee.phone!] ?? false
                        : false;

                    return Card(
                      margin: EdgeInsets.symmetric(vertical: 4.h),
                      child: ListTile(
                        leading: Stack(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.primaryGreen,
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
                            if (isVerified)
                              Positioned(
                                right: 0.w,
                                bottom: 0.h,
                                child: Container(
                                  padding: EdgeInsets.all(2.w),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
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
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16.sp,
                                ),
                              ),
                            ),
                            if (isVerified)
                              Icon(
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

                                if (!mounted) return;

                                if (!context.mounted) return;
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EmployeeRegistrationPage(
                                      employeePhone: employee.phone!,
                                      existingRegistration: existingRegistration,
                                    ),
                                  ),
                                );

                                if (!mounted) return;
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

