import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/employee_registration_service.dart';
import 'employee_registration_view_page.dart';
import 'employee_registration_page.dart';
import '../services/employee_service.dart';
import 'unverified_employees_page.dart';
import '../../../core/utils/logger.dart';

/// Модель сотрудника
class Employee {
  final String id;
  final String name;
  final String? position;
  final String? department;
  final String? phone;
  final String? email;
  final bool? isAdmin;
  final bool? isManager; // Флаг заведующего(ей)
  final String? employeeName;
  final int? referralCode; // Уникальный код приглашения (1-1000)
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
    this.isManager,
    this.employeeName,
    this.referralCode,
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
      isManager: json['isManager'] == true || json['isManager'] == 1 || json['isManager'] == '1',
      employeeName: json['employeeName']?.toString().trim(),
      referralCode: json['referralCode'] is int ? json['referralCode'] : int.tryParse(json['referralCode']?.toString() ?? ''),
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
      'isManager': isManager,
      'employeeName': employeeName,
      'referralCode': referralCode,
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
    bool? isManager,
    String? employeeName,
    int? referralCode,
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
      isManager: isManager ?? this.isManager,
      employeeName: employeeName ?? this.employeeName,
      referralCode: referralCode ?? this.referralCode,
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
        Logger.success('Найден сохраненный employeeId: $savedEmployeeId');
        // Проверяем, что сотрудник все еще существует
        try {
          final employees = await EmployeeService.getEmployees();
          final employee = employees.firstWhere((e) => e.id == savedEmployeeId);
          Logger.success('Сотрудник найден по сохраненному ID: ${employee.name}');
          return savedEmployeeId;
        } catch (e) {
          Logger.warning('Сотрудник с сохраненным ID не найден, ищем по телефону');
          // Удаляем невалидный ID
          await prefs.remove('currentEmployeeId');
        }
      }

      // 2. Резервный способ: ищем по телефону
      Logger.debug('Поиск сотрудника по телефону...');
      final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone');

      if (phone == null || phone.isEmpty) {
        Logger.error('Телефон не найден в SharedPreferences');
        return null;
      }

      // Нормализуем телефон (убираем пробелы и +)
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      Logger.debug('Нормализованный телефон: $normalizedPhone');

      // Загружаем список сотрудников
      final employees = await loadEmployeesForNotifications();
      Logger.debug('Загружено сотрудников для поиска: ${employees.length}');

      // Ищем сотрудника по телефону
      for (var employee in employees) {
        if (employee.phone != null) {
          final employeePhone = employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
          if (employeePhone == normalizedPhone) {
            Logger.success('Сотрудник найден по телефону: ${employee.name} (ID: ${employee.id})');
            // Сохраняем employeeId для будущего использования
            await prefs.setString('currentEmployeeId', employee.id);
            await prefs.setString('currentEmployeeName', employee.name);
            Logger.debug('Сохранен employeeId: ${employee.id}');
            return employee.id;
          }
        }
      }

      Logger.error('Сотрудник не найден по телефону');
      return null;
    } catch (e) {
      Logger.error('Ошибка получения ID текущего сотрудника', e);
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
        Logger.success('Найдено сохраненное имя сотрудника: $savedName');
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
      Logger.error('Ошибка получения имени текущего сотрудника', e);
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
      Logger.error('Ошибка загрузки сотрудников', e);
      return [];
    }
  }


  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> with TickerProviderStateMixin {
  late Future<List<Employee>> _employeesFuture;
  String _searchQuery = '';
  final Map<String, bool> _verificationStatus = {}; // Кэш статуса верификации по телефону
  bool _isLoadingVerification = false;
  late AnimationController _animationController;
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _employeesFuture = _loadEmployees();
    _loadVerificationStatuses();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }


  Future<void> _loadVerificationStatuses() async {
    if (_isLoadingVerification) return;
    setState(() {
      _isLoadingVerification = true;
    });

    try {
      // Загружаем ВСЕ регистрации одним запросом вместо 31 отдельного
      final registrations = await EmployeeRegistrationService.getAllRegistrations();
      Logger.debug('Загружено регистраций: ${registrations.length}');

      // Строим карту верификации по нормализованному телефону
      for (var reg in registrations) {
        final phone = reg.phone.replaceAll(RegExp(r'[\s\+]'), '');
        _verificationStatus[phone] = reg.isVerified;
      }

      // Также добавляем записи для сотрудников без регистрации (isVerified = false)
      final employees = await _employeesFuture;
      for (var employee in employees) {
        if (employee.phone != null && employee.phone!.isNotEmpty) {
          final phone = employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
          _verificationStatus.putIfAbsent(phone, () => false);
        }
      }
      Logger.success('Загружено статусов верификации: ${_verificationStatus.length}');
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      Logger.error('Ошибка загрузки статусов верификации', e);
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

      Logger.info('Загружено сотрудников и админов: ${employees.length}');

      return employees;
    } catch (e) {
      Logger.error('Ошибка загрузки сотрудников', e);
      rethrow;
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF004D40),
              Color(0xFF00695C),
              Color(0xFF00796B),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              _buildAppBar(),
              // Список сотрудников (без вкладок)
              Expanded(
                child: _buildEmployeesTab(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'Сотрудники',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Кнопка "Добавить сотрудника"
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.person_add, color: Colors.white),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EmployeeRegistrationPage(),
                  ),
                );
                if (result == true && mounted) {
                  refreshEmployeesData();
                }
              },
              tooltip: 'Добавить сотрудника',
            ),
          ),
          const SizedBox(width: 8),
          // Кнопка "Не верифицированные"
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.person_off, color: Colors.white),
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
          ),
          const SizedBox(width: 8),
          // Кнопка обновления
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                setState(() {
                  _employeesFuture = _loadEmployees();
                });
                _loadVerificationStatuses();
                _animationController.reset();
                _animationController.forward();
              },
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
    );
  }

  // Метод для обновления данных
  void refreshEmployeesData() {
    setState(() {
      _employeesFuture = _loadEmployees();
    });
    _loadVerificationStatuses();
    _animationController.reset();
    _animationController.forward();
  }

  Widget _buildEmployeesTab() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F5),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Поиск
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Поиск сотрудника...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  prefixIcon: Icon(Icons.search, color: const Color(0xFF004D40).withOpacity(0.7)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.grey[400]),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.trim().toLowerCase();
                  });
                },
              ),
            ),
          ),
          // Список сотрудников
          Expanded(
            child: FutureBuilder<List<Employee>>(
              future: _employeesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF004D40)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Загрузка сотрудников...',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Ошибка загрузки данных',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _employeesFuture = _loadEmployees();
                              });
                              _animationController.reset();
                              _animationController.forward();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Повторить'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF004D40),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final allEmployees = snapshot.data ?? [];

                // Пока статусы верификации загружаются — показываем индикатор
                if (_isLoadingVerification) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF004D40)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Проверка верификации...',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                // Фильтрация: ТОЛЬКО верифицированные сотрудники
                // Не верифицированные отображаются на отдельной странице
                final filteredEmployees = allEmployees.where((employee) {
                  // Если нет телефона, исключаем из списка
                  if (employee.phone == null || employee.phone!.isEmpty) {
                    return false;
                  }

                  // Показываем только верифицированных
                  final normalizedPhone = employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
                  final isVerified = _verificationStatus[normalizedPhone] ?? false;
                  if (!isVerified) {
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
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_search,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Сотрудники не найдены',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Попробуйте изменить параметры поиска',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _employeesFuture = _loadEmployees();
                    });
                    await _loadVerificationStatuses();
                    _animationController.reset();
                    _animationController.forward();
                  },
                  color: const Color(0xFF004D40),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredEmployees.length,
                    itemBuilder: (context, index) {
                      final employee = filteredEmployees[index];
                      final normalizedPhone = employee.phone?.replaceAll(RegExp(r'[\s\+]'), '');
                      final isVerified = normalizedPhone != null
                          ? _verificationStatus[normalizedPhone] ?? false
                          : false;

                      // Анимация появления
                      final delay = index * 0.05;
                      final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _animationController,
                          curve: Interval(
                            delay.clamp(0.0, 0.7),
                            (delay + 0.3).clamp(0.0, 1.0),
                            curve: Curves.easeOutBack,
                          ),
                        ),
                      );

                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) {
                          // Clamp нужен т.к. easeOutBack может генерировать значения > 1.0
                          final animValue = animation.value.clamp(0.0, 1.0);
                          return Transform.translate(
                            offset: Offset(0, 30 * (1 - animValue)),
                            child: Opacity(
                              opacity: animValue,
                              child: _buildEmployeeCard(employee, isVerified),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard(Employee employee, bool isVerified) {
    // Определяем цвета в зависимости от статуса
    final Color primaryColor = isVerified ? const Color(0xFF004D40) : const Color(0xFF78909C);
    final Color accentColor = isVerified ? const Color(0xFF00897B) : const Color(0xFF90A4AE);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: employee.phone != null && employee.phone!.isNotEmpty
              ? () async {
                  final navigator = Navigator.of(context);
                  final result = await navigator.push(
                    MaterialPageRoute(
                      builder: (context) => EmployeeRegistrationViewPage(
                        employeePhone: employee.phone!,
                        employeeName: employee.name,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  if (result == true || result != null) {
                    await _loadVerificationStatuses();
                  }
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isVerified ? const Color(0xFF4CAF50) : Colors.orange,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                // Компактный аватар
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [primaryColor, accentColor],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      employee.name.isNotEmpty
                          ? employee.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Информация о сотруднике
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Имя
                      Text(
                        employee.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Color(0xFF1A1A1A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Телефон и статус в одну строку
                      Row(
                        children: [
                          if (employee.phone != null && employee.phone!.isNotEmpty) ...[
                            Icon(Icons.phone, size: 12, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                employee.phone!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          // Компактный статус
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isVerified
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isVerified ? Icons.check_circle : Icons.schedule,
                                  color: isVerified ? Colors.green[700] : Colors.orange[700],
                                  size: 10,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  isVerified ? 'Верифицирован' : 'Ожидает',
                                  style: TextStyle(
                                    color: isVerified ? Colors.green[700] : Colors.orange[700],
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Стрелка
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
