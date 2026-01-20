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
      duration: const Duration(milliseconds: 800),
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
      Logger.debug('Проверка роли админа для телефона: ${phone.isNotEmpty ? phone : "не найден"}');

      if (phone.isEmpty) {
        if (mounted) {
          setState(() {
            _isAdmin = false;
          });
        }
        return;
      }
      final roleData = await UserRoleService.getUserRole(phone);
      final isAdmin = roleData.role == UserRole.admin;
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
      Logger.debug('Загрузка регистрации для телефона: ${widget.employeePhone}');
      final registration = await EmployeeRegistrationService.getRegistration(widget.employeePhone);

      if (registration != null) {
        Logger.success('Регистрация найдена: ФИО: ${registration.fullName}, Верифицирован: ${registration.isVerified}');
        Logger.debug('Фото лицевой: ${registration.passportFrontPhotoUrl ?? "нет"}');
        Logger.debug('Фото прописки: ${registration.passportRegistrationPhotoUrl ?? "нет"}');
        Logger.debug('Доп фото: ${registration.additionalPhotoUrl ?? "нет"}');
      } else {
        Logger.warning('Регистрация не найдена для телефона: ${widget.employeePhone}');
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
      Logger.debug('Поиск сотрудника для телефона: ${widget.employeePhone}, имени: ${widget.employeeName}');
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
          const SnackBar(
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
    Logger.debug('Телефон администратора из SharedPreferences: ${phone.isNotEmpty ? phone : "не найден"}');

    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
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
          const SnackBar(
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
      return const SizedBox.shrink();
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
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок секции фото
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF004D40).withOpacity(0.9),
                    const Color(0xFF00695C).withOpacity(0.9),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.photo_camera,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Контейнер с фото
            Container(
              width: double.infinity,
              height: 220,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                child: Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      Logger.success('Фото загружено: $photoUrl');
                      return child;
                    }
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                const Color(0xFF004D40).withOpacity(0.7),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Загрузка фото...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    Logger.error('Ошибка загрузки фото $photoUrl', error);
                    return Container(
                      color: Colors.grey[100],
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.red,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Не удалось загрузить',
                              style: TextStyle(
                                fontSize: 14,
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
          ],
        ),
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
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isVerified
                ? [const Color(0xFF2E7D32), const Color(0xFF43A047)]
                : [const Color(0xFFE65100), const Color(0xFFFF9800)],
          ),
          boxShadow: [
            BoxShadow(
              color: (isVerified ? Colors.green : Colors.orange).withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
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
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Иконка статуса
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isVerified ? Icons.verified_user : Icons.hourglass_empty,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Текст статуса
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isVerified ? 'Верифицирован' : 'Ожидает верификации',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (_registration!.verifiedAt != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_registration!.verifiedAt!.day}.${_registration!.verifiedAt!.month}.${_registration!.verifiedAt!.year}${_registration!.verifiedBy != null ? ' • ${_registration!.verifiedBy}' : ''}',
                              style: const TextStyle(
                                fontSize: 12,
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
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF004D40).withOpacity(0.1),
                    const Color(0xFF00695C).withOpacity(0.05),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF004D40), Color(0xFF00695C)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.badge_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Паспортные данные',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF004D40),
                    ),
                  ),
                ],
              ),
            ),
            // Информация
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildInfoRowStyled('ФИО', _registration!.fullName, Icons.person_outline),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoRowStyled('Серия', _registration!.passportSeries, Icons.credit_card),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _buildInfoRowStyled('Номер', _registration!.passportNumber, Icons.numbers),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildInfoRowStyled('Кем выдан', _registration!.issuedBy, Icons.account_balance),
                  const Divider(height: 24),
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
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF004D40).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: const Color(0xFF004D40),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
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
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            // Заголовок
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF004D40).withOpacity(0.1),
                    const Color(0xFF00695C).withOpacity(0.05),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF004D40), Color(0xFF00695C)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.tune,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        'Предпочтения работы',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF004D40),
                        ),
                      ),
                    ],
                  ),
                  if (_employee != null)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _editPreferences,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF004D40).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.edit,
                            size: 20,
                            color: Color(0xFF004D40),
                          ),
                        ),
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Сначала нужно создать сотрудника из этой регистрации'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      },
                      icon: const Icon(Icons.info_outline, size: 18),
                      label: const Text('Создать', style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orange[700],
                      ),
                    ),
                ],
              ),
            ),
            // Контент предпочтений
            Padding(
              padding: const EdgeInsets.all(20),
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
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            const Color(0xFF004D40).withOpacity(0.15),
                                            const Color(0xFF00695C).withOpacity(0.1),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(0xFF004D40).withOpacity(0.3),
                                        ),
                                      ),
                                      child: Text(
                                        dayNames[day] ?? day,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF004D40),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                )
                              : _buildEmptyPreference('Не указаны'),
                        ),
                        const SizedBox(height: 20),
                        // Желаемые магазины
                        _buildPreferenceSection(
                          'Желаемые магазины',
                          Icons.store,
                          _employee!.preferredShops.isNotEmpty
                              ? FutureBuilder<List<Shop>>(
                                  future: ShopService.getShops(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const SizedBox(
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
                                            margin: const EdgeInsets.only(bottom: 10),
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  const Color(0xFF004D40).withOpacity(0.08),
                                                  const Color(0xFF00695C).withOpacity(0.04),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: const Color(0xFF004D40).withOpacity(0.15),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF004D40).withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: const Icon(
                                                    Icons.storefront,
                                                    size: 18,
                                                    color: Color(0xFF004D40),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        shop.name,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      if (shop.address.isNotEmpty) ...[
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          shop.address,
                                                          style: TextStyle(
                                                            fontSize: 12,
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
                                    return const Text(
                                      'Ошибка загрузки',
                                      style: TextStyle(color: Colors.red),
                                    );
                                  },
                                )
                              : _buildEmptyPreference('Не указаны'),
                        ),
                        const SizedBox(height: 20),
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
                                      1: {'text': 'Хочет работать', 'color': Colors.green, 'bgColor': const Color(0xFFE8F5E9)},
                                      2: {'text': 'Может работать', 'color': Colors.orange, 'bgColor': const Color(0xFFFFF3E0)},
                                      3: {'text': 'Не будет', 'color': Colors.red, 'bgColor': const Color(0xFFFFEBEE)},
                                    }[grade]!;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: gradeData['bgColor'] as Color,
                                        borderRadius: BorderRadius.circular(12),
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
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              shiftData['name'] as String,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: (gradeData['color'] as Color).withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              gradeData['text'] as String,
                                              style: TextStyle(
                                                fontSize: 12,
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
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
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
                          const SizedBox(height: 16),
                          Text(
                            'Сотрудник не найден',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Создайте сотрудника из этой регистрации,\nчтобы настроить предпочтения',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
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
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _buildEmptyPreference(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.remove_circle_outline, size: 16, color: Colors.grey[400]),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Создано: ${_registration!.createdAt.day}.${_registration!.createdAt.month}.${_registration!.createdAt.year} ${_registration!.createdAt.hour}:${_registration!.createdAt.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_registration!.updatedAt != _registration!.createdAt) ...[
              const SizedBox(height: 4),
              Text(
                'Обновлено: ${_registration!.updatedAt.day}.${_registration!.updatedAt.month}.${_registration!.updatedAt.year}',
                style: TextStyle(
                  fontSize: 11,
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF004D40),
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
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.employeeName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Регистрация сотрудника',
                            style: TextStyle(
                              fontSize: 13,
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
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
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
                            const SizedBox(height: 16),
                            Text(
                              'Загрузка данных...',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _registration == null
                        ? Center(
                            child: Container(
                              margin: const EdgeInsets.all(32),
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
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
                                  const SizedBox(height: 20),
                                  const Text(
                                    'Регистрация не найдена',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Данные регистрации отсутствуют\nдля этого сотрудника',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (_isAdmin) ...[
                                    const SizedBox(height: 24),
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
                                      icon: const Icon(Icons.add),
                                      label: const Text('Создать регистрацию'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF004D40),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                              const SizedBox(height: 8),
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
