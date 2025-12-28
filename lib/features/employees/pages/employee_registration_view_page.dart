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

class _EmployeeRegistrationViewPageState extends State<EmployeeRegistrationViewPage> {
  EmployeeRegistration? _registration;
  Employee? _employee;
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
    _loadRegistration();
  }

  Future<void> _checkAdminRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Пробуем оба варианта ключа
      final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone') ?? '';
      print('🔍 Проверка роли админа для телефона: ${phone.isNotEmpty ? phone : "не найден"}');
      
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
      print('👤 Роль пользователя: ${roleData.role}, isAdmin: $isAdmin');
      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
        });
      }
    } catch (e) {
      print('❌ Ошибка проверки роли: $e');
      if (mounted) {
        setState(() {
          _isAdmin = false;
        });
      }
    }
  }

  Future<void> _loadRegistration() async {
    try {
      print('📥 Загрузка регистрации для телефона: ${widget.employeePhone}');
      final registration = await EmployeeRegistrationService.getRegistration(widget.employeePhone);
      
      if (registration != null) {
        print('✅ Регистрация найдена:');
        print('   ФИО: ${registration.fullName}');
        print('   Верифицирован: ${registration.isVerified}');
        print('   Фото лицевой: ${registration.passportFrontPhotoUrl ?? "нет"}');
        print('   Фото прописки: ${registration.passportRegistrationPhotoUrl ?? "нет"}');
        print('   Доп фото: ${registration.additionalPhotoUrl ?? "нет"}');
      } else {
        print('⚠️ Регистрация не найдена для телефона: ${widget.employeePhone}');
      }
      
      // Загружаем данные сотрудника для получения предпочтений
      await _loadEmployee();
      
      if (mounted) {
        setState(() {
          _registration = registration;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Ошибка загрузки регистрации: $e');
      if (mounted) {
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
  }

  Future<void> _loadEmployee() async {
    try {
      print('🔍 Поиск сотрудника для телефона: ${widget.employeePhone}, имени: ${widget.employeeName}');
      // Загружаем всех сотрудников и ищем по телефону
      final employees = await EmployeeService.getEmployees();
      print('📋 Загружено сотрудников: ${employees.length}');
      final normalizedPhone = widget.employeePhone.replaceAll(RegExp(r'[\s\+]'), '');
      
      try {
        _employee = employees.firstWhere(
          (emp) => emp.phone != null && emp.phone!.replaceAll(RegExp(r'[\s\+]'), '') == normalizedPhone,
        );
        print('✅ Сотрудник найден по телефону: ${_employee!.name}');
        print('   Предпочтения: дни=${_employee!.preferredWorkDays.length}, магазины=${_employee!.preferredShops.length}, смены=${_employee!.shiftPreferences.length}');
      } catch (e) {
        print('⚠️ Не найден по телефону, пробуем по имени...');
        // Если не нашли по телефону, пробуем по имени
        try {
          _employee = employees.firstWhere(
            (emp) => emp.name == widget.employeeName,
          );
          print('✅ Сотрудник найден по имени: ${_employee!.name}');
          print('   Предпочтения: дни=${_employee!.preferredWorkDays.length}, магазины=${_employee!.preferredShops.length}, смены=${_employee!.shiftPreferences.length}');
        } catch (e2) {
          print('⚠️ Сотрудник не найден ни по телефону, ни по имени: $e2');
          _employee = null;
        }
      }
    } catch (e) {
      print('❌ Ошибка загрузки сотрудника: $e');
      _employee = null;
    }
  }

  Future<void> _editPreferences() async {
    print('🔧 Редактирование предпочтений для сотрудника: ${_employee?.name ?? "не найден"}');
    if (_employee == null) {
      print('❌ Сотрудник не найден, пытаемся загрузить...');
      await _loadEmployee();
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

    print('✅ Открываем диалог редактирования предпочтений');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EmployeePreferencesDialog(employee: _employee!),
    );

    if (result == true) {
      print('✅ Предпочтения сохранены, обновляем данные');
      // Обновляем данные сотрудника
      await _loadEmployee();
      setState(() {});
    } else {
      print('⚠️ Редактирование отменено');
    }
  }

  Future<void> _toggleVerification() async {
    if (!_isAdmin || _registration == null) {
      print('⚠️ Верификация невозможна: _isAdmin=$_isAdmin, _registration=${_registration != null}');
      return;
    }

    final newVerifiedStatus = !_registration!.isVerified;
    print('🔄 Переключение статуса верификации: $newVerifiedStatus (текущий: ${_registration!.isVerified})');
    
    final prefs = await SharedPreferences.getInstance();
    // Пробуем оба варианта ключа
    final phone = prefs.getString('userPhone') ?? prefs.getString('user_phone') ?? '';
    print('📞 Телефон администратора из SharedPreferences: ${phone.isNotEmpty ? phone : "не найден"}');
    
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
    print('👤 Имя администратора: $adminName');

    final success = await EmployeeRegistrationService.verifyEmployee(
      widget.employeePhone,
      newVerifiedStatus,
      adminName,
    );

    if (success) {
      print('✅ Верификация успешна, загружаем обновленную регистрацию...');
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
        
        // НЕ закрываем страницу автоматически, чтобы пользователь мог видеть результат
        // Статус обновится при возврате на страницу сотрудников
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

  Widget _buildPhotoSection(String? photoUrl, String label) {
    if (photoUrl == null || photoUrl.isEmpty) {
      print('⚠️ Фото не найдено для: $label');
      return const SizedBox.shrink();
    }

    print('🖼️ Загрузка фото для $label: $photoUrl');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              photoUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  print('✅ Фото загружено: $photoUrl');
                  return child;
                }
                return const Center(
                  child: CircularProgressIndicator(),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                print('❌ Ошибка загрузки фото $photoUrl: $error');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(height: 8),
                      Text(
                        'Ошибка загрузки',
                        style: TextStyle(fontSize: 12, color: Colors.red[700]),
                      ),
                      Text(
                        photoUrl,
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Регистрация: ${widget.employeeName}'),
        backgroundColor: const Color(0xFF004D40),
        actions: [
          if (_isAdmin && _registration != null)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editRegistration,
              tooltip: 'Редактировать',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _registration == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.person_off,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Регистрация не найдена',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      if (_isAdmin) ...[
                        const SizedBox(height: 16),
                        ElevatedButton(
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004D40),
                          ),
                          child: const Text('Создать регистрацию'),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Статус верификации
                    Card(
                      color: _registration!.isVerified
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      child: ListTile(
                        leading: Icon(
                          _registration!.isVerified
                              ? Icons.verified
                              : Icons.pending,
                          color: _registration!.isVerified
                              ? Colors.green
                              : Colors.orange,
                        ),
                        title: Text(
                          _registration!.isVerified
                              ? 'Верифицирован'
                              : 'Не верифицирован',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: _registration!.verifiedAt != null
                            ? Text(
                                'Верифицирован: ${_registration!.verifiedAt!.day}.${_registration!.verifiedAt!.month}.${_registration!.verifiedAt!.year}${_registration!.verifiedBy != null ? ' (${_registration!.verifiedBy})' : ''}',
                              )
                            : null,
                        trailing: _isAdmin
                            ? Switch(
                                value: _registration!.isVerified,
                                onChanged: (value) {
                                  print('🔄 Switch изменен на: $value');
                                  _toggleVerification();
                                },
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ФИО
                    _buildInfoRow('ФИО', _registration!.fullName),
                    const SizedBox(height: 8),

                    // Серия и номер паспорта
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoRow(
                            'Серия паспорта',
                            _registration!.passportSeries,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildInfoRow(
                            'Номер паспорта',
                            _registration!.passportNumber,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Кем выдан
                    _buildInfoRow('Кем выдан', _registration!.issuedBy),
                    const SizedBox(height: 8),

                    // Дата выдачи
                    _buildInfoRow('Дата выдачи', _registration!.issueDate),
                    const SizedBox(height: 16),

                    // Предпочтения сотрудника
                    if (_registration != null) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Предпочтения работы',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_employee != null)
                                    IconButton(
                                      icon: const Icon(Icons.edit),
                                      onPressed: _editPreferences,
                                      tooltip: 'Редактировать предпочтения',
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
                                      icon: const Icon(Icons.info_outline),
                                      label: const Text('Создать сотрудника'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (_employee != null) ...[
                                // Желаемые дни работы
                                if (_employee!.preferredWorkDays.isNotEmpty) ...[
                                  const Text(
                                    'Желаемые дни работы:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _employee!.preferredWorkDays.map((day) {
                                      final dayNames = {
                                        'monday': 'Понедельник',
                                        'tuesday': 'Вторник',
                                        'wednesday': 'Среда',
                                        'thursday': 'Четверг',
                                        'friday': 'Пятница',
                                        'saturday': 'Суббота',
                                        'sunday': 'Воскресенье',
                                      };
                                      return Chip(
                                        label: Text(dayNames[day] ?? day),
                                        backgroundColor: const Color(0xFF004D40).withOpacity(0.1),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 16),
                                ] else
                                  const Text(
                                    'Желаемые дни работы не указаны',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                // Желаемые магазины
                                if (_employee!.preferredShops.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Желаемые магазины:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  FutureBuilder<List<Shop>>(
                                    future: ShopService.getShops(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        return const CircularProgressIndicator();
                                      }
                                      if (snapshot.hasData) {
                                        final shops = snapshot.data!;
                                        final selectedShops = shops.where((shop) =>
                                          _employee!.preferredShops.contains(shop.id) ||
                                          _employee!.preferredShops.contains(shop.address)
                                        ).toList();
                                        
                                        if (selectedShops.isEmpty) {
                                          return const Text(
                                            'Магазины не найдены',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          );
                                        }
                                        
                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: selectedShops.map((shop) {
                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 8),
                                              child: Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF004D40).withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      shop.name,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    if (shop.address.isNotEmpty) ...[
                                                      const SizedBox(height: 4),
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
                                            );
                                          }).toList(),
                                        );
                                      }
                                      return const Text(
                                        'Ошибка загрузки магазинов',
                                        style: TextStyle(color: Colors.red),
                                      );
                                    },
                                  ),
                                ] else
                                  const Text(
                                    'Желаемые магазины не указаны',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                // Предпочтения смен
                                const SizedBox(height: 16),
                                const Text(
                                  'Предпочтения смен:',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_employee!.shiftPreferences.isNotEmpty) ...[
                                  ...['morning', 'day', 'night'].map((shiftKey) {
                                    final shiftName = {
                                      'morning': 'Утро',
                                      'day': 'День',
                                      'night': 'Ночь',
                                    }[shiftKey] ?? shiftKey;
                                    final grade = _employee!.shiftPreferences[shiftKey] ?? 2;
                                    final gradeDescription = {
                                      1: 'Всегда хочет работать',
                                      2: 'Не хочет, но может',
                                      3: 'Не будет работать',
                                    }[grade] ?? 'Не указано';
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              shiftName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: grade == 1
                                                  ? Colors.green.withOpacity(0.2)
                                                  : grade == 2
                                                      ? Colors.orange.withOpacity(0.2)
                                                      : Colors.red.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: grade == 1
                                                    ? Colors.green
                                                    : grade == 2
                                                        ? Colors.orange
                                                        : Colors.red,
                                                width: 1,
                                              ),
                                            ),
                                            child: Text(
                                              gradeDescription,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: grade == 1
                                                    ? Colors.green[800]
                                                    : grade == 2
                                                        ? Colors.orange[800]
                                                        : Colors.red[800],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ] else
                                  const Text(
                                    'Предпочтения смен не указаны',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ] else ...[
                                const Text(
                                  'Сотрудник не найден. Создайте сотрудника из этой регистрации, чтобы настроить предпочтения.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Фото лицевой страницы
                    _buildPhotoSection(
                      _registration!.passportFrontPhotoUrl,
                      'Фото паспорта (Лицевая страница)',
                    ),

                    // Фото прописки
                    _buildPhotoSection(
                      _registration!.passportRegistrationPhotoUrl,
                      'Фото паспорта (Прописка)',
                    ),

                    // Дополнительное фото
                    if (_registration!.additionalPhotoUrl != null)
                      _buildPhotoSection(
                        _registration!.additionalPhotoUrl,
                        'Дополнительное фото',
                      ),

                    const SizedBox(height: 16),

                    // Даты создания и обновления
                    Text(
                      'Создано: ${_registration!.createdAt.day}.${_registration!.createdAt.month}.${_registration!.createdAt.year} ${_registration!.createdAt.hour}:${_registration!.createdAt.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (_registration!.updatedAt != _registration!.createdAt)
                      Text(
                        'Обновлено: ${_registration!.updatedAt.day}.${_registration!.updatedAt.month}.${_registration!.updatedAt.year} ${_registration!.updatedAt.hour}:${_registration!.updatedAt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

