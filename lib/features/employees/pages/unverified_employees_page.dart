import 'package:flutter/material.dart';
import 'employees_page.dart';
import '../services/employee_service.dart';
import '../services/employee_registration_service.dart';
import 'employee_registration_view_page.dart';
import '../models/employee_registration_model.dart';
import '../../../core/utils/logger.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница не верифицированных сотрудников (у которых была снята верификация)
class UnverifiedEmployeesPage extends StatefulWidget {
  const UnverifiedEmployeesPage({super.key});

  @override
  State<UnverifiedEmployeesPage> createState() =>
      _UnverifiedEmployeesPageState();
}

class _UnverifiedEmployeesPageState extends State<UnverifiedEmployeesPage>
    with SingleTickerProviderStateMixin {
  late Future<List<Employee>> _employeesFuture;
  String _searchQuery = '';
  final Map<String, EmployeeRegistration?> _registrations = {};
  late AnimationController _animationController;

  // Тёплые янтарные акценты для неверифицированных
  static const Color _primaryWarning = AppColors.warmAmber;
  static const Color _accentWarning = AppColors.warmAmberLight;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _employeesFuture = _loadUnverifiedEmployees();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<List<Employee>> _loadUnverifiedEmployees() async {
    try {
      final results = await Future.wait([
        EmployeeService.getEmployees(),
        EmployeeRegistrationService.getAllRegistrations(),
      ]).timeout(Duration(seconds: 30));

      final allEmployees = results[0] as List<Employee>;
      final allRegistrations = results[1] as List<EmployeeRegistration>;

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
        final normalizedPhone =
            employee.phone!.replaceAll(RegExp(r'[\s\+]'), '');
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

  void _refresh() {
    if (mounted) setState(() {
      _employeesFuture = _loadUnverifiedEmployees();
    });
    _animationController.reset();
    _animationController.forward();
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
              _buildAppBar(),
              Expanded(child: _buildContent()),
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
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Неверифицированные',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Сотрудники со снятой верификацией',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13.sp,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.white),
              onPressed: _refresh,
              tooltip: 'Обновить',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
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
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                ),
                onChanged: (value) {
                  if (mounted) setState(() {
                    _searchQuery = value.trim().toLowerCase();
                  });
                },
              ),
            ),
          ),
          // Список
          Expanded(
            child: FutureBuilder<List<Employee>>(
              future: _employeesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppColors.gold),
                        SizedBox(height: 16),
                        Text(
                          'Загрузка...',
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
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
                            child: Icon(
                              Icons.error_outline,
                              size: 48,
                              color: AppColors.error,
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Ошибка загрузки данных',
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            style: TextStyle(color: Colors.white.withOpacity(0.5)),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _refresh,
                            icon: Icon(Icons.refresh),
                            label: Text('Повторить'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.gold,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24.w, vertical: 12.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final allEmployees = snapshot.data ?? [];
                final filteredEmployees = allEmployees.where((employee) {
                  if (_searchQuery.isEmpty) return true;
                  final name = employee.name.toLowerCase();
                  final phone = (employee.phone ?? '').toLowerCase();
                  return name.contains(_searchQuery) ||
                      phone.contains(_searchQuery);
                }).toList();

                if (filteredEmployees.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(24.w),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.verified_user_outlined,
                            size: 48,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Все сотрудники верифицированы',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Нет сотрудников со снятой верификацией',
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    _refresh();
                  },
                  color: AppColors.gold,
                  backgroundColor: AppColors.emeraldDark,
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    itemCount: filteredEmployees.length + 1,
                    itemBuilder: (context, index) {
                      // Бейдж с количеством
                      if (index == 0) {
                        return _buildCountBadge(filteredEmployees.length,
                            allEmployees.length);
                      }

                      final employee = filteredEmployees[index - 1];
                      final normalizedPhone = employee.phone
                          ?.replaceAll(RegExp(r'[\s\+]'), '');
                      final registration = normalizedPhone != null
                          ? _registrations[normalizedPhone]
                          : null;

                      // Анимация появления
                      final delay = (index - 1) * 0.05;
                      final animation =
                          Tween<double>(begin: 0.0, end: 1.0).animate(
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
                          final animValue = animation.value.clamp(0.0, 1.0);
                          return Transform.translate(
                            offset: Offset(0, 30 * (1 - animValue)),
                            child: Opacity(
                              opacity: animValue,
                              child: _buildEmployeeCard(employee, registration),
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
    );
  }

  Widget _buildCountBadge(int filtered, int total) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _primaryWarning.withOpacity(0.1),
            _accentWarning.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: _accentWarning.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_primaryWarning, _accentWarning]),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 18),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Требуют внимания',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: _primaryWarning,
                  ),
                ),
                Text(
                  _searchQuery.isNotEmpty
                      ? 'Найдено: $filtered из $total'
                      : '$total ${_pluralEmployees(total)}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _pluralEmployees(int count) {
    if (count % 10 == 1 && count % 100 != 11) return 'сотрудник';
    if (count % 10 >= 2 &&
        count % 10 <= 4 &&
        (count % 100 < 10 || count % 100 >= 20)) return 'сотрудника';
    return 'сотрудников';
  }

  Widget _buildEmployeeCard(
      Employee employee, EmployeeRegistration? registration) {
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
                    _refresh();
                  }
                }
              : null,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: _accentWarning,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                // Аватар
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_primaryWarning, _accentWarning],
                    ),
                    borderRadius: BorderRadius.circular(12.r),
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
                // Информация
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                      Row(
                        children: [
                          if (employee.phone != null &&
                              employee.phone!.isNotEmpty) ...[
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
                          // Статус
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6.w, vertical: 2.h),
                            decoration: BoxDecoration(
                              color: _accentWarning.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.remove_circle_outline,
                                  color: _primaryWarning,
                                  size: 10,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'Снята',
                                  style: TextStyle(
                                    color: _primaryWarning,
                                    fontSize: 10.sp,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Дата снятия верификации
                      if (registration != null &&
                          registration.verifiedAt != null) ...[
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.event, size: 11, color: Colors.white.withOpacity(0.3)),
                            SizedBox(width: 4),
                            Text(
                              'Снята: ${registration.verifiedAt!.day.toString().padLeft(2, '0')}.${registration.verifiedAt!.month.toString().padLeft(2, '0')}.${registration.verifiedAt!.year}',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ],
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
