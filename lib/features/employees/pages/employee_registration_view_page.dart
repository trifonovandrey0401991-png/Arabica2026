import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee_registration_model.dart';
import '../services/employee_registration_service.dart';
import 'employee_registration_page.dart';
import '../services/user_role_service.dart';
import '../models/user_role_model.dart';
import 'employees_page.dart';
import '../services/employee_service.dart';
import 'employee_preferences_dialog.dart';
import '../../shops/models/shop_model.dart';
import '../../shops/services/shop_service.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/widgets/app_cached_image.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

class EmployeeRegistrationViewPage extends StatefulWidget {
  final String employeePhone;
  final String employeeName;

  const EmployeeRegistrationViewPage({
    super.key,
    required this.employeePhone,
    required this.employeeName,
  });

  @override
  State<EmployeeRegistrationViewPage> createState() => _EmployeeRegistrationViewPageState();
}

class _EmployeeRegistrationViewPageState extends State<EmployeeRegistrationViewPage>
    with SingleTickerProviderStateMixin {
  EmployeeRegistration? _registration;
  Employee? _employee;
  bool _isLoading = true;
  bool _isAdmin = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _checkAdminRole();
    _loadRegistration();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAdminRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone') ?? '';
      Logger.debug('Проверка роли админа для телефона: ${phone.isNotEmpty ? Logger.maskPhone(phone) : "не найден"}');

      if (phone.isEmpty) {
        if (mounted) {
          setState(() {
            _isAdmin = false;
          });
        }
        return;
      }
      final roleData = await UserRoleService.getUserRole(phone);
      final isAdmin = roleData.role == UserRole.admin || roleData.role == UserRole.developer;
      Logger.debug('Роль пользователя: ${roleData.role}, isAdmin: $isAdmin');
      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
        });
      }
    } catch (e) {
      Logger.error('Ошибка проверки роли', e);
      if (mounted) {
        setState(() {
          _isAdmin = false;
        });
      }
    }
  }

  Future<void> _loadRegistration() async {
    try {
      Logger.debug('Загрузка регистрации для телефона: ${Logger.maskPhone(widget.employeePhone)}');
      final registration = await EmployeeRegistrationService.getRegistration(widget.employeePhone);

      if (registration != null) {
        Logger.success('Регистрация найдена: ФИО: ${registration.fullName}, Верифицирован: ${registration.isVerified}');
        Logger.debug('Фото лицевой: ${registration.passportFrontPhotoUrl ?? "нет"}');
        Logger.debug('Фото прописки: ${registration.passportRegistrationPhotoUrl ?? "нет"}');
        Logger.debug('Доп фото: ${registration.additionalPhotoUrl ?? "нет"}');
      } else {
        Logger.warning('Регистрация не найдена для телефона: ${Logger.maskPhone(widget.employeePhone)}');
      }

      await _loadEmployee();

      if (!mounted) return;
      setState(() {
        _registration = registration;
        _isLoading = false;
      });
      _animationController.forward();
    } catch (e) {
      Logger.error('Ошибка загрузки регистрации', e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки данных: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadEmployee() async {
    try {
      Logger.debug('Поиск сотрудника для телефона: ${Logger.maskPhone(widget.employeePhone)}, имени: ${widget.employeeName}');
      final employees = await EmployeeService.getEmployees();
      Logger.debug('Загружено сотрудников: ${employees.length}');
      final normalizedPhone = widget.employeePhone.replaceAll(RegExp(r'[\s\+]'), '');

      try {
        _employee = employees.firstWhere(
          (emp) => emp.phone != null && emp.phone!.replaceAll(RegExp(r'[\s\+]'), '') == normalizedPhone,
        );
        Logger.success('Сотрудник найден по телефону: ${_employee!.name}');
        Logger.debug('Предпочтения: дни=${_employee!.preferredWorkDays.length}, магазины=${_employee!.preferredShops.length}, смены=${_employee!.shiftPreferences.length}');
      } catch (e) {
        Logger.warning('Не найден по телефону, пробуем по имени...');
        try {
          _employee = employees.firstWhere(
            (emp) => emp.name == widget.employeeName,
          );
          Logger.success('Сотрудник найден по имени: ${_employee!.name}');
          Logger.debug('Предпочтения: дни=${_employee!.preferredWorkDays.length}, магазины=${_employee!.preferredShops.length}, смены=${_employee!.shiftPreferences.length}');
        } catch (e2) {
          Logger.warning('Сотрудник не найден ни по телефону, ни по имени: $e2');
          _employee = null;
        }
      }
    } catch (e) {
      Logger.error('Ошибка загрузки сотрудника', e);
      _employee = null;
    }
  }

  Future<void> _editPreferences() async {
    Logger.debug('Редактирование предпочтений для сотрудника: ${_employee?.name ?? "не найден"}');
    if (_employee == null) {
      Logger.error('Сотрудник не найден, пытаемся загрузить...');
      await _loadEmployee();
      if (!mounted) return;
      if (_employee == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось загрузить данные сотрудника. Убедитесь, что сотрудник создан из этой регистрации.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    Logger.success('Открываем диалог редактирования предпочтений');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EmployeePreferencesDialog(employee: _employee!),
    );

    if (!mounted) return;
    if (result == true) {
      Logger.success('Предпочтения сохранены, обновляем данные');
      await _loadEmployee();
      if (!mounted) return;
      setState(() {});
    } else {
      Logger.warning('Редактирование отменено');
    }
  }

  Future<void> _toggleVerification() async {
    if (!_isAdmin || _registration == null) {
      Logger.warning('Верификация невозможна: _isAdmin=$_isAdmin, _registration=${_registration != null}');
      return;
    }

    final newVerifiedStatus = !_registration!.isVerified;
    Logger.debug('Переключение статуса верификации: $newVerifiedStatus (текущий: ${_registration!.isVerified})');

    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone') ?? '';
    Logger.debug('Телефон администратора из SharedPreferences: ${phone.isNotEmpty ? Logger.maskPhone(phone) : "не найден"}');

    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось определить телефон администратора'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    final roleData = await UserRoleService.getUserRole(phone);
    final adminName = roleData.displayName.isNotEmpty ? roleData.displayName : 'Администратор';
    Logger.debug('Имя администратора: $adminName');

    final success = await EmployeeRegistrationService.verifyEmployee(
      widget.employeePhone,
      newVerifiedStatus,
      adminName,
    );

    if (success) {
      Logger.success('Верификация успешна, загружаем обновленную регистрацию...');
      await _loadRegistration();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newVerifiedStatus
                  ? 'Сотрудник верифицирован'
                  : 'Верификация снята',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка изменения статуса верификации'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editRegistration() async {
    if (!_isAdmin) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeRegistrationPage(
          employeePhone: widget.employeePhone,
          existingRegistration: _registration,
        ),
      ),
    );

    if (result == true) {
      await _loadRegistration();
    }
  }

  Widget _buildPhotoSection(String? photoUrl, String label, int index) {
    if (photoUrl == null || photoUrl.isEmpty) {
      Logger.debug('Фото не найдено для: $label');
      return SizedBox.shrink();
    }

    Logger.debug('Загрузка фото для $label: $photoUrl');

    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        final delay = (index * 0.1).clamp(0.0, 0.5);
        final denominator = (1.0 - delay).clamp(0.1, 1.0);
        final animValue = ((_fadeAnimation.value - delay) / denominator).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 20 * (1 - animValue)),
          child: Opacity(
            opacity: animValue,
            child: child,
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 16.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок секции фото
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryGreen.withOpacity(0.9),
                    Color(0xFF00695C).withOpacity(0.9),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16.r),
                  topRight: Radius.circular(16.r),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(
                      Icons.photo_camera,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Контейнер с фото
            GestureDetector(
              onTap: () => _openFullScreenPhoto(photoUrl, label),
              child: Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16.r),
                  bottomRight: Radius.circular(16.r),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16.r),
                  bottomRight: Radius.circular(16.r),
                ),
                child: AppCachedImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, error, stackTrace) {
                    Logger.error('Ошибка загрузки фото $photoUrl', error);
                    return Container(
                      color: Colors.grey[100],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: EdgeInsets.all(16.w),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.red,
                                size: 32,
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Не удалось загрузить',
                              style: TextStyle(
                                fontSize: 14.sp,
                                color: Colors.red[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullScreenPhoto(String url, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenPhotoPage(imageUrl: url, title: title),
      ),
    );
  }

  Widget _buildVerificationCard() {
    final isVerified = _registration!.isVerified;

    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - _fadeAnimation.value)),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 20.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20.r),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isVerified
                ? [Color(0xFF2E7D32), Color(0xFF43A047)]
                : [Color(0xFFE65100), Color(0xFFFF9800)],
          ),
          boxShadow: [
            BoxShadow(
              color: (isVerified ? Colors.green : Colors.orange).withOpacity(0.3),
              blurRadius: 15,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Декоративные элементы
            Positioned(
              top: -20,
              right: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            Positioned(
              bottom: -30,
              left: -30,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            // Контент
            Padding(
              padding: EdgeInsets.all(20.w),
              child: Row(
                children: [
                  // Иконка статуса
                  Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Icon(
                      isVerified ? Icons.verified_user : Icons.hourglass_empty,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  SizedBox(width: 16),
                  // Текст статуса
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isVerified ? 'Верифицирован' : 'Ожидает верификации',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (_registration!.verifiedAt != null) ...[
                          SizedBox(height: 6),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                            child: Text(
                              '${_registration!.verifiedAt!.day}.${_registration!.verifiedAt!.month}.${_registration!.verifiedAt!.year}${_registration!.verifiedBy != null ? ' • ${_registration!.verifiedBy}' : ''}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Переключатель для админа
                  if (_isAdmin)
                    Transform.scale(
                      scale: 1.1,
                      child: Switch(
                        value: isVerified,
                        onChanged: (value) {
                          Logger.debug('Switch изменен на: $value');
                          _toggleVerification();
                        },
                        activeColor: Colors.white,
                        activeTrackColor: Colors.white.withOpacity(0.4),
                        inactiveThumbColor: Colors.white,
                        inactiveTrackColor: Colors.white.withOpacity(0.3),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPassportInfoCard() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        final animValue = ((_fadeAnimation.value - 0.1) / 0.9).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 20 * (1 - animValue)),
          child: Opacity(
            opacity: animValue,
            child: child,
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 20.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            // Заголовок
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryGreen.withOpacity(0.1),
                    Color(0xFF00695C).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20.r),
                  topRight: Radius.circular(20.r),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primaryGreen, Color(0xFF00695C)],
                      ),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(
                      Icons.badge_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: 14),
                  Text(
                    'Паспортные данные',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ],
              ),
            ),
            // Информация
            Padding(
              padding: EdgeInsets.all(20.w),
              child: Column(
                children: [
                  _buildInfoRowStyled('ФИО', _registration!.fullName, Icons.person_outline),
                  Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoRowStyled('Серия', _registration!.passportSeries, Icons.credit_card),
                      ),
                      SizedBox(width: 20),
                      Expanded(
                        child: _buildInfoRowStyled('Номер', _registration!.passportNumber, Icons.numbers),
                      ),
                    ],
                  ),
                  Divider(height: 24),
                  _buildInfoRowStyled('Кем выдан', _registration!.issuedBy, Icons.account_balance),
                  Divider(height: 24),
                  _buildInfoRowStyled('Дата выдачи', _registration!.issueDate, Icons.calendar_today),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRowStyled(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppColors.primaryGreen,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreferencesCard() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        final animValue = ((_fadeAnimation.value - 0.2) / 0.8).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 20 * (1 - animValue)),
          child: Opacity(
            opacity: animValue,
            child: child,
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 20.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            // Заголовок
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryGreen.withOpacity(0.1),
                    Color(0xFF00695C).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20.r),
                  topRight: Radius.circular(20.r),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10.w),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primaryGreen, Color(0xFF00695C)],
                          ),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Icon(
                          Icons.tune,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      SizedBox(width: 14),
                      Text(
                        'Предпочтения работы',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  if (_employee != null)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _editPreferences,
                        borderRadius: BorderRadius.circular(10.r),
                        child: Container(
                          padding: EdgeInsets.all(8.w),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: Icon(
                            Icons.edit,
                            size: 20,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Сначала нужно создать сотрудника из этой регистрации'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      },
                      icon: Icon(Icons.info_outline, size: 18),
                      label: Text('Создать', style: TextStyle(fontSize: 13.sp)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orange[700],
                      ),
                    ),
                ],
              ),
            ),
            // Контент предпочтений
            Padding(
              padding: EdgeInsets.all(20.w),
              child: _employee != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Желаемые дни работы
                        _buildPreferenceSection(
                          'Желаемые дни работы',
                          Icons.calendar_month,
                          _employee!.preferredWorkDays.isNotEmpty
                              ? Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _employee!.preferredWorkDays.map((day) {
                                    final dayNames = {
                                      'monday': 'Пн',
                                      'tuesday': 'Вт',
                                      'wednesday': 'Ср',
                                      'thursday': 'Чт',
                                      'friday': 'Пт',
                                      'saturday': 'Сб',
                                      'sunday': 'Вс',
                                    };
                                    return Container(
                                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.primaryGreen.withOpacity(0.15),
                                            Color(0xFF00695C).withOpacity(0.1),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(20.r),
                                        border: Border.all(
                                          color: AppColors.primaryGreen.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        dayNames[day] ?? day,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primaryGreen,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                )
                              : _buildEmptyPreference('Не указаны'),
                        ),
                        SizedBox(height: 20),
                        // Желаемые магазины
                        _buildPreferenceSection(
                          'Желаемые магазины',
                          Icons.store,
                          _employee!.preferredShops.isNotEmpty
                              ? FutureBuilder<List<Shop>>(
                                  future: ShopService.getShops(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return SizedBox(
                                        height: 40,
                                        child: Center(
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                        ),
                                      );
                                    }
                                    if (snapshot.hasData) {
                                      final shops = snapshot.data!;
                                      final selectedShops = shops.where((shop) =>
                                        _employee!.preferredShops.contains(shop.id) ||
                                        _employee!.preferredShops.contains(shop.address)
                                      ).toList();

                                      if (selectedShops.isEmpty) {
                                        return _buildEmptyPreference('Не найдены');
                                      }

                                      return Column(
                                        children: selectedShops.map((shop) {
                                          return Container(
                                            margin: EdgeInsets.only(bottom: 10.h),
                                            padding: EdgeInsets.all(14.w),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  AppColors.primaryGreen.withOpacity(0.08),
                                                  Color(0xFF00695C).withOpacity(0.04),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(14.r),
                                              border: Border.all(
                                                color: AppColors.primaryGreen.withOpacity(0.15),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: EdgeInsets.all(8.w),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primaryGreen.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(8.r),
                                                  ),
                                                  child: Icon(
                                                    Icons.storefront,
                                                    size: 18,
                                                    color: AppColors.primaryGreen,
                                                  ),
                                                ),
                                                SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        shop.name,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 14.sp,
                                                        ),
                                                      ),
                                                      if (shop.address.isNotEmpty) ...[
                                                        SizedBox(height: 2),
                                                        Text(
                                                          shop.address,
                                                          style: TextStyle(
                                                            fontSize: 12.sp,
                                                            color: Colors.grey[600],
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      );
                                    }
                                    return Text(
                                      'Ошибка загрузки',
                                      style: TextStyle(color: Colors.red),
                                    );
                                  },
                                )
                              : _buildEmptyPreference('Не указаны'),
                        ),
                        SizedBox(height: 20),
                        // Предпочтения смен
                        _buildPreferenceSection(
                          'Предпочтения смен',
                          Icons.access_time,
                          _employee!.shiftPreferences.isNotEmpty
                              ? Column(
                                  children: ['morning', 'day', 'night'].map((shiftKey) {
                                    final shiftData = {
                                      'morning': {'name': 'Утро', 'icon': Icons.wb_sunny_outlined},
                                      'day': {'name': 'День', 'icon': Icons.light_mode_outlined},
                                      'night': {'name': 'Ночь', 'icon': Icons.nightlight_outlined},
                                    }[shiftKey]!;
                                    final grade = _employee!.shiftPreferences[shiftKey] ?? 2;
                                    final gradeData = {
                                      1: {'text': 'Хочет работать', 'color': Colors.green, 'bgColor': Color(0xFFE8F5E9)},
                                      2: {'text': 'Может работать', 'color': Colors.orange, 'bgColor': Color(0xFFFFF3E0)},
                                      3: {'text': 'Не будет', 'color': Colors.red, 'bgColor': Color(0xFFFFEBEE)},
                                    }[grade]!;

                                    return Container(
                                      margin: EdgeInsets.only(bottom: 10.h),
                                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                                      decoration: BoxDecoration(
                                        color: gradeData['bgColor'] as Color,
                                        borderRadius: BorderRadius.circular(12.r),
                                        border: Border.all(
                                          color: (gradeData['color'] as Color).withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            shiftData['icon'] as IconData,
                                            size: 22,
                                            color: gradeData['color'] as Color,
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              shiftData['name'] as String,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15.sp,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                                            decoration: BoxDecoration(
                                              color: (gradeData['color'] as Color).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(20.r),
                                            ),
                                            child: Text(
                                              gradeData['text'] as String,
                                              style: TextStyle(
                                                fontSize: 12.sp,
                                                fontWeight: FontWeight.w600,
                                                color: gradeData['color'] as Color,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                )
                              : _buildEmptyPreference('Не указаны'),
                        ),
                      ],
                    )
                  : Container(
                      padding: EdgeInsets.all(24.w),
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(16.w),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person_add_outlined,
                              size: 40,
                              color: Colors.grey[400],
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Сотрудник не найден',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Создайте сотрудника из этой регистрации,\nчтобы настроить предпочтения',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferenceSection(String title, IconData icon, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: Colors.grey[600],
            ),
            SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _buildEmptyPreference(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.remove_circle_outline, size: 16, color: Colors.grey[400]),
          SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimestamps() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        final animValue = ((_fadeAnimation.value - 0.5) / 0.5).clamp(0.0, 1.0);
        return Opacity(
          opacity: animValue,
          child: child,
        );
      },
      child: Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Создано: ${_registration!.createdAt.day}.${_registration!.createdAt.month}.${_registration!.createdAt.year} ${_registration!.createdAt.hour}:${_registration!.createdAt.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_registration!.updatedAt != _registration!.createdAt) ...[
              SizedBox(height: 4),
              Text(
                'Обновлено: ${_registration!.updatedAt.day}.${_registration!.updatedAt.month}.${_registration!.updatedAt.year}',
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primaryGreen,
              Color(0xFF00695C),
              Color(0xFF00796B),
              Color(0xFFE0F2F1),
            ],
            stops: [0.0, 0.15, 0.3, 0.5],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 16.h),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(12.r),
                        child: Container(
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.employeeName,
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Регистрация сотрудника',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isAdmin && _registration != null)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _editRegistration,
                          borderRadius: BorderRadius.circular(12.r),
                          child: Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(
                              Icons.edit,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Контент
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 50,
                              height: 50,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Загрузка данных...',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 15.sp,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _registration == null
                        ? Center(
                            child: Container(
                              margin: EdgeInsets.all(32.w),
                              padding: EdgeInsets.all(32.w),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 20,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(20.w),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.person_off_outlined,
                                      size: 50,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    'Регистрация не найдена',
                                    style: TextStyle(
                                      fontSize: 18.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Данные регистрации отсутствуют\nдля этого сотрудника',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (_isAdmin) ...[
                                    SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        final result = await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => EmployeeRegistrationPage(
                                              employeePhone: widget.employeePhone,
                                            ),
                                          ),
                                        );
                                        if (result == true) {
                                          await _loadRegistration();
                                        }
                                      },
                                      icon: Icon(Icons.add),
                                      label: Text('Создать регистрацию'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primaryGreen,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14.r),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            padding: EdgeInsets.fromLTRB(16.w, 0.h, 16.w, 24.h),
                            children: [
                              _buildVerificationCard(),
                              _buildPassportInfoCard(),
                              _buildPreferencesCard(),
                              // Фото документов
                              _buildPhotoSection(
                                _registration!.passportFrontPhotoUrl,
                                'Паспорт (Лицевая страница)',
                                3,
                              ),
                              _buildPhotoSection(
                                _registration!.passportRegistrationPhotoUrl,
                                'Паспорт (Прописка)',
                                4,
                              ),
                              if (_registration!.additionalPhotoUrl != null)
                                _buildPhotoSection(
                                  _registration!.additionalPhotoUrl,
                                  'Дополнительное фото',
                                  5,
                                ),
                              SizedBox(height: 8),
                              _buildTimestamps(),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullScreenPhotoPage extends StatefulWidget {
  final String imageUrl;
  final String title;

  const _FullScreenPhotoPage({required this.imageUrl, required this.title});

  @override
  State<_FullScreenPhotoPage> createState() => _FullScreenPhotoPageState();
}

class _FullScreenPhotoPageState extends State<_FullScreenPhotoPage> {
  final TransformationController _transformController = TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      ),
      body: Center(
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.5,
          maxScale: 4.0,
          child: AppCachedImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.contain,
            errorWidget: (context, error, stackTrace) {
              return const Center(
                child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
              );
            },
          ),
        ),
      ),
    );
  }
}
