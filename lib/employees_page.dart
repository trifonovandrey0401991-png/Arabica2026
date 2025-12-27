import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_role_service.dart';
import 'server_config.dart';
import 'employee_registration_service.dart';
import 'employee_registration_view_page.dart';
import 'employee_registration_page.dart';
import 'employee_service.dart';
import 'user_role_model.dart';
import 'unverified_employees_page.dart';
import 'shops_management_page.dart';

/// Модель сотрудника
class Employee {
  final String id;
  final String name;
  final String? position;
  final String? department;
  final String? phone;
  final String? email;
  final bool? isAdmin;
  final String? employeeName;
  final List<String> preferredWorkDays; // Желаемые дни работы (monday, tuesday, etc.)
  final List<String> preferredShops; // Желаемые магазины (ID или адреса)
  final Map<String, int> shiftPreferences; // Предпочтения смен: {'morning': 1, 'day': 2, 'night': 3} где 1=хочет, 2=может, 3=не будет

  Employee({
    required this.id,
    required this.name,
    this.position,
    this.department,
    this.phone,
    this.email,
    this.isAdmin,
    this.employeeName,
    this.preferredWorkDays = const [],
    this.preferredShops = const [],
    this.shiftPreferences = const {},
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    // Обработка preferredWorkDays
    List<String> workDays = [];
    if (json['preferredWorkDays'] != null) {
      if (json['preferredWorkDays'] is List) {
        workDays = (json['preferredWorkDays'] as List)
            .map((e) => e.toString())
            .toList();
      }
    }

    // Обработка preferredShops
    List<String> shops = [];
    if (json['preferredShops'] != null) {
      if (json['preferredShops'] is List) {
        shops = (json['preferredShops'] as List)
            .map((e) => e.toString())
            .toList();
      }
    }

    // Обработка shiftPreferences
    Map<String, int> shiftPrefs = {};
    if (json['shiftPreferences'] != null) {
      if (json['shiftPreferences'] is Map) {
        final prefsMap = json['shiftPreferences'] as Map;
        prefsMap.forEach((key, value) {
          if (value is int) {
            shiftPrefs[key.toString()] = value;
          } else if (value is String) {
            final intValue = int.tryParse(value);
            if (intValue != null) {
              shiftPrefs[key.toString()] = intValue;
            }
          }
        });
      }
    }

    return Employee(
      id: json['id'] ?? '',
      name: (json['name'] ?? '').toString().trim(),
      position: json['position']?.toString().trim(),
      department: json['department']?.toString().trim(),
      phone: json['phone']?.toString().trim(),
      email: json['email']?.toString().trim(),
      isAdmin: json['isAdmin'] == true || json['isAdmin'] == 1 || json['isAdmin'] == '1',
      employeeName: json['employeeName']?.toString().trim(),
      preferredWorkDays: workDays,
      preferredShops: shops,
      shiftPreferences: shiftPrefs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position,
      'department': department,
      'phone': phone,
      'email': email,
      'isAdmin': isAdmin,
      'employeeName': employeeName,
      'preferredWorkDays': preferredWorkDays,
      'preferredShops': preferredShops,
      'shiftPreferences': shiftPreferences,
    };
  }

  Employee copyWith({
    String? id,
    String? name,
    String? position,
    String? department,
    String? phone,
    String? email,
    bool? isAdmin,
    String? employeeName,
    List<String>? preferredWorkDays,
    List<String>? preferredShops,
    Map<String, int>? shiftPreferences,
  }) {
    return Employee(
      id: id ?? this.id,
      name: name ?? this.name,
      position: position ?? this.position,
      department: department ?? this.department,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      isAdmin: isAdmin ?? this.isAdmin,
      employeeName: employeeName ?? this.employeeName,
      preferredWorkDays: preferredWorkDays ?? this.preferredWorkDays,
      preferredShops: preferredShops ?? this.preferredShops,
      shiftPreferences: shiftPreferences ?? this.shiftPreferences,
    );
  }
}

/// Страница сотрудников
class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key});

  /// Получить ID текущего сотрудника (основной способ)
  /// Сначала проверяет сохраненный employeeId, затем ищет по телефону
  static Future<String?> getCurrentEmployeeId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Пытаемся получить сохраненный employeeId (основной способ)
      final savedEmployeeId = prefs.getString('currentEmployeeId');
      if (savedEmployeeId != null && savedEmployeeId.isNotEmpty) {
        print('✅ Найден сохраненный employeeId: $savedEmployeeId');
        // Проверяем, что сотрудник все еще существует
        try {
          final employees = await EmployeeService.getEmployees();
          final employee = employees.firstWhere((e) => e.id == savedEmployeeId);
          print('✅ Сотрудник найден по сохраненному ID: ${employee.name}');
          return savedEmployeeId;
        } catch (e) {
          print('⚠️ Сотрудник с сохраненным ID не найден, ищем по телефону');
          // Удаляем невалидный ID
          await prefs.remove('currentEmployeeId');
        }
      }
      
      // 2. Резервный способ: ищем по телефону
      print('📞 Поиск сотрудника по телефону...');
      final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');
      
      if (phone == null || phone.isEmpty) {
        print('❌ Телефон не найден в SharedPreferences');
        return null;
      }
      
      // Нормализуем телефон (убираем пробелы и +)
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      print('📞 Нормализованный телефон: $normalizedPhone');
      
      // Загружаем список сотрудников
      final employees = await loadEmployeesForNotifications();
      print('📋 Загружено сотрудников для поиска: ${employees.length}');
      
      // Ищем сотрудника по телефону
      for (var employee in employees) {
        if (employee.phone != null) {
          final employeePhone = employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
          if (employeePhone == normalizedPhone) {
            print('✅ Сотрудник найден по телефону: ${employee.name} (ID: ${employee.id})');
            // Сохраняем employeeId для будущего использования
            await prefs.setString('currentEmployeeId', employee.id);
            await prefs.setString('currentEmployeeName', employee.name);
            print('💾 Сохранен employeeId: ${employee.id}');
            return employee.id;
          }
        }
      }
      
      print('❌ Сотрудник не найден по телефону');
      return null;
    } catch (e) {
      print('❌ Ошибка получения ID текущего сотрудника: $e');
      return null;
    }
  }

  /// Получить имя текущего сотрудника из меню "Сотрудники"
  /// Это единый источник истины для имени сотрудника во всем приложении
  static Future<String?> getCurrentEmployeeName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Пытаемся получить сохраненное имя
      final savedName = prefs.getString('currentEmployeeName');
      if (savedName != null && savedName.isNotEmpty) {
        print('✅ Найдено сохраненное имя сотрудника: $savedName');
        return savedName;
      }
      
      // 2. Получаем ID и затем имя
      final employeeId = await getCurrentEmployeeId();
      if (employeeId == null) {
        return null;
      }
      
      final employees = await EmployeeService.getEmployees();
      final employee = employees.firstWhere(
        (e) => e.id == employeeId,
        orElse: () => throw StateError('Employee not found'),
      );
      
      // Сохраняем имя
      await prefs.setString('currentEmployeeName', employee.name);
      return employee.name;
    } catch (e) {
      print('❌ Ошибка получения имени текущего сотрудника: $e');
      return null;
    }
  }

  /// Загрузить сотрудников для уведомлений (статический метод)
  /// Загружает только сотрудников и админов с сервера
  static Future<List<Employee>> loadEmployeesForNotifications() async {
    try {
      // Загружаем всех сотрудников с сервера
      final allEmployees = await EmployeeService.getEmployees();
      
      // Фильтруем только сотрудников и админов (у которых есть phone или isAdmin = true)
      final employees = allEmployees.where((emp) => 
        emp.phone != null && emp.phone!.isNotEmpty
      ).toList();
      
      return employees;
    } catch (e) {
      print('❌ Ошибка загрузки сотрудников: $e');
      return [];
    }
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
      // Загружаем сотрудников с сервера
      final employees = await EmployeeService.getEmployees();
      
      // Сортируем по имени
      employees.sort((a, b) => a.name.compareTo(b.name));

      // ignore: avoid_print
      print("👥 Загружено сотрудников и админов: ${employees.length}");

      return employees;
    } catch (e) {
      // ignore: avoid_print
      print("❌ Ошибка загрузки сотрудников: $e");
      rethrow;
    }
  }


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Сотрудники'),
          backgroundColor: const Color(0xFF004D40),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Сотрудники', icon: Icon(Icons.people)),
              Tab(text: 'Регистрация', icon: Icon(Icons.person_add)),
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
                });
                _loadVerificationStatuses();
              },
              tooltip: 'Обновить',
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // Вкладка "Сотрудники"
            _buildEmployeesTab(),
            // Вкладка "Регистрация"
            _buildRegistrationTab(),
            // Вкладка "Магазины"
            const ShopsManagementPage(),
          ],
        ),
      ),
    );
  }

  // Метод для обновления данных после регистрации (вызывается из вкладки Регистрация)
  void refreshEmployeesData() {
    setState(() {
      _employeesFuture = _loadEmployees();
    });
    _loadVerificationStatuses();
  }

  Widget _buildEmployeesTab() {
    return Column(
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
                
                // Фильтрация: показываем всех сотрудников (не только верифицированных)
                final filteredEmployees = allEmployees.where((employee) {
                  // Если нет телефона, исключаем из списка
                  if (employee.phone == null || employee.phone!.isEmpty) {
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
                      key: ValueKey(employee.id),
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
      );
  }

  Widget _buildRegistrationTab() {
    return _EmployeeRegistrationTab(
      onEmployeeRegistered: () {
        // Обновляем данные в главном виджете после регистрации
        refreshEmployeesData();
      },
    );
  }
}

/// Вкладка регистрации сотрудников
class _EmployeeRegistrationTab extends StatefulWidget {
  final VoidCallback? onEmployeeRegistered;
  
  const _EmployeeRegistrationTab({
    this.onEmployeeRegistered,
  });

  @override
  State<_EmployeeRegistrationTab> createState() => _EmployeeRegistrationTabState();
}

class _EmployeeRegistrationTabState extends State<_EmployeeRegistrationTab> {
  late Future<List<Employee>> _employeesFuture;
  String _searchQuery = '';
  Map<String, bool> _verificationStatus = {};
  Map<String, bool> _hasRegistration = {}; // Кэш наличия регистрации (независимо от статуса верификации)

  @override
  void initState() {
    super.initState();
    _employeesFuture = _loadEmployees();
    _loadVerificationStatuses();
  }

  Future<List<Employee>> _loadEmployees() async {
    try {
      // Загружаем сотрудников с сервера
      final employees = await EmployeeService.getEmployees();
      
      // Сортируем по имени
      employees.sort((a, b) => a.name.compareTo(b.name));
      
      return employees;
    } catch (e) {
      print('Ошибка загрузки сотрудников: $e');
      rethrow;
    }
  }

  Future<void> _loadVerificationStatuses() async {
    try {
      final employees = await _loadEmployees();
      for (var employee in employees) {
        if (employee.phone != null && employee.phone!.isNotEmpty) {
          // Нормализуем телефон для ключа
          final normalizedPhone = employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
          final registration = await EmployeeRegistrationService.getRegistration(normalizedPhone);
          _verificationStatus[normalizedPhone] = registration?.isVerified ?? false;
          _hasRegistration[normalizedPhone] = registration != null; // Отслеживаем наличие регистрации
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
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
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  // Открываем форму регистрации нового сотрудника
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const EmployeeRegistrationPage(),
                    ),
                  );
                  
                  if (result == true) {
                    // Обновляем список сотрудников и статусы
                    setState(() {
                      _employeesFuture = _loadEmployees();
                    });
                    await _loadVerificationStatuses();
                    // Уведомляем родительский виджет об обновлении
                    if (widget.onEmployeeRegistered != null) {
                      widget.onEmployeeRegistered!();
                    }
                  }
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Новый'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
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
                      const Text('Ошибка загрузки данных'),
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
                return const Center(
                  child: Text('Все сотрудники зарегистрированы или не найдены'),
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
                    key: ValueKey(employee.id),
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
    );
  }
}

