import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/employee_registration_service.dart';
import 'employee_registration_view_page.dart';
import 'employee_registration_page.dart';
import '../services/employee_service.dart';
import 'unverified_employees_page.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/cache_manager.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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
      Logger.debug('Нормализованный телефон: ${Logger.maskPhone(normalizedPhone)}');

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

      // 1. Пытаемся получить сохраненное имя (цепочка fallback по всем возможным ключам)
      final savedName = prefs.getString('currentEmployeeName') ??
          prefs.getString('user_employee_name') ??
          prefs.getString('user_name');
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
  List<Employee> _employees = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  final Map<String, bool> _verificationStatus = {}; // Кэш статуса верификации по телефону
  bool _isLoadingVerification = false;
  late AnimationController _animationController;

  static const _cacheKey = 'page_employees';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _loadData();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }


  Future<void> _loadVerificationStatuses() async {
    if (_isLoadingVerification) return;
    if (mounted) setState(() {
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
      for (var employee in _employees) {
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

  Future<void> _loadData() async {
    // Step 1: Show cached data instantly
    final cached = CacheManager.get<List<Employee>>(_cacheKey);
    if (cached != null && mounted) {
      setState(() {
        _employees = cached;
        _isLoading = false;
      });
    }

    // Step 2: Fetch fresh data from server
    try {
      final employees = await EmployeeService.getEmployees();
      employees.sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() {
        _employees = employees;
        _isLoading = false;
        _error = null;
      });

      // Step 3: Save to cache
      CacheManager.set(_cacheKey, employees);

      Logger.info('Загружено сотрудников и админов: ${employees.length}');
    } catch (e) {
      Logger.error('Ошибка загрузки сотрудников', e);
      if (mounted && _employees.isEmpty) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }

    // Load verification statuses
    await _loadVerificationStatuses();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.night,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.emerald, AppColors.emeraldDark, AppColors.night],
            stops: [0.0, 0.3, 1.0],
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
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 12.h),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              'Сотрудники',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Кнопка "Добавить сотрудника"
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.person_add, color: AppColors.gold),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EmployeeRegistrationPage(),
                  ),
                );
                if (result == true && mounted) {
                  refreshEmployeesData();
                }
              },
              tooltip: 'Добавить сотрудника',
            ),
          ),
          SizedBox(width: 8),
          // Кнопка "Не верифицированные"
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.person_off, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UnverifiedEmployeesPage(),
                  ),
                );
              },
              tooltip: 'Не верифицированные сотрудники',
            ),
          ),
          SizedBox(width: 8),
          // Кнопка обновления
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                EmployeeService.clearCache();
                _animationController.reset();
                _loadData();
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
    EmployeeService.clearCache();
    _animationController.reset();
    _loadData();
    _animationController.forward();
  }

  Widget _buildEmployeesTab() {
    return Column(
        children: [
          // Поиск
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: TextField(
                style: TextStyle(color: Colors.white),
                cursorColor: AppColors.gold,
                decoration: InputDecoration(
                  hintText: 'Поиск сотрудника...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: Icon(Icons.search, color: AppColors.gold),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.white.withOpacity(0.3)),
                          onPressed: () {
                            if (mounted) setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                ),
                onChanged: (value) {
                  if (mounted) setState(() {
                    _searchQuery = value.trim().toLowerCase();
                  });
                },
              ),
            ),
          ),
          // Список сотрудников
          Expanded(
            child: _buildEmployeesList(),
          ),
        ],
    );
  }

  Widget _buildEmployeesList() {
    if (_isLoading && _employees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.gold),
            SizedBox(height: 16),
            Text(
              'Загрузка сотрудников...',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    if (_error != null && _employees.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(20.w),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline, size: 48, color: AppColors.error),
              ),
              SizedBox(height: 16),
              Text(
                'Ошибка загрузки данных',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Colors.white.withOpacity(0.5)), textAlign: TextAlign.center),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  _animationController.reset();
                  _loadData();
                  _animationController.forward();
                },
                icon: Icon(Icons.refresh),
                label: Text('Повторить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Пока статусы верификации загружаются и нет кэша — показываем индикатор
    if (_isLoadingVerification && _verificationStatus.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.gold),
            SizedBox(height: 16),
            Text('Проверка верификации...', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ],
        ),
      );
    }

    // Фильтрация: ТОЛЬКО верифицированные сотрудники
    final filteredEmployees = _employees.where((employee) {
      if (employee.phone == null || employee.phone!.isEmpty) return false;
      final normalizedPhone = employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
      final isVerified = _verificationStatus[normalizedPhone] ?? false;
      if (!isVerified) return false;
      if (_searchQuery.isEmpty) return true;
      final name = employee.name.toLowerCase();
      final position = (employee.position ?? '').toLowerCase();
      final department = (employee.department ?? '').toLowerCase();
      return name.contains(_searchQuery) || position.contains(_searchQuery) || department.contains(_searchQuery);
    }).toList();

    if (filteredEmployees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), shape: BoxShape.circle),
              child: Icon(Icons.person_search, size: 48, color: Colors.white.withOpacity(0.3)),
            ),
            SizedBox(height: 16),
            Text('Сотрудники не найдены', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7))),
            SizedBox(height: 8),
            Text('Попробуйте изменить параметры поиска', style: TextStyle(fontSize: 14.sp, color: Colors.white.withOpacity(0.4))),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        EmployeeService.clearCache();
        await _loadData();
        _animationController.reset();
        _animationController.forward();
      },
      color: AppColors.gold,
      backgroundColor: AppColors.emeraldDark,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        itemCount: filteredEmployees.length,
        itemBuilder: (context, index) {
          final employee = filteredEmployees[index];
          final normalizedPhone = employee.phone?.replaceAll(RegExp(r'[\s\+]'), '');
          final isVerified = normalizedPhone != null ? _verificationStatus[normalizedPhone] ?? false : false;
          final delay = index * 0.05;
          final animation = Tween<double>(begin: 0.0, end: 1.0).animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Interval(delay.clamp(0.0, 0.7), (delay + 0.3).clamp(0.0, 1.0), curve: Curves.easeOutBack),
            ),
          );
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final animValue = animation.value.clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(0, 30 * (1 - animValue)),
                child: Opacity(opacity: animValue, child: _buildEmployeeCard(employee, isVerified)),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmployeeCard(Employee employee, bool isVerified) {
    return Container(
      margin: EdgeInsets.only(bottom: 10.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
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
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: isVerified ? AppColors.gold : AppColors.warmAmber,
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
                      colors: [AppColors.emeraldDark, AppColors.emerald],
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                    border: isVerified
                        ? Border.all(color: AppColors.gold.withOpacity(0.6), width: 1.5)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      employee.name.isNotEmpty
                          ? employee.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18.sp,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                // Информация о сотруднике
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Имя
                      Text(
                        employee.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15.sp,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 4),
                      // Телефон и статус в одну строку
                      Row(
                        children: [
                          if (employee.phone != null && employee.phone!.isNotEmpty) ...[
                            Icon(Icons.phone, size: 12, color: Colors.white.withOpacity(0.4)),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                employee.phone!,
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: 8),
                          ],
                          // Компактный статус
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: isVerified
                                  ? AppColors.gold.withOpacity(0.15)
                                  : AppColors.warmAmber.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isVerified ? Icons.check_circle : Icons.schedule,
                                  color: isVerified ? AppColors.gold : AppColors.warmAmber,
                                  size: 10,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  isVerified ? 'Верифицирован' : 'Ожидает',
                                  style: TextStyle(
                                    color: isVerified ? AppColors.gold : AppColors.warmAmber,
                                    fontSize: 10.sp,
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
                  color: Colors.white.withOpacity(0.3),
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
