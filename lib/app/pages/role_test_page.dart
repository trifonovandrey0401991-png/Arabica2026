import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../features/employees/models/user_role_model.dart';
import '../../features/employees/services/user_role_service.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Тестовая страница для переключения ролей
class RoleTestPage extends StatefulWidget {
  const RoleTestPage({super.key});

  @override
  State<RoleTestPage> createState() => _RoleTestPageState();
}

class _RoleTestPageState extends State<RoleTestPage> {
  UserRole? _selectedRole;
  String _testDisplayName = '';
  String? _testEmployeeName;
  UserRoleData? _currentRole;

  @override
  void initState() {
    super.initState();
    _loadCurrentRole();
  }

  Future<void> _loadCurrentRole() async {
    final roleData = await UserRoleService.loadUserRole();
    if (!mounted) return;
    setState(() {
      _currentRole = roleData;
      if (roleData != null) {
        _selectedRole = roleData.role;
        _testDisplayName = roleData.displayName;
        _testEmployeeName = roleData.employeeName;
      }
    });
  }

  Future<void> _applyRole() async {
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Выберите роль'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';

    // Создаем тестовые данные роли
    final roleData = UserRoleData(
      role: _selectedRole!,
      displayName: _testDisplayName.isNotEmpty ? _testDisplayName : 'Тестовый пользователь',
      phone: phone,
      employeeName: _testEmployeeName?.isNotEmpty == true ? _testEmployeeName : null,
    );

    // Сохраняем роль
    await UserRoleService.saveUserRole(roleData);

    // Обновляем имя пользователя в SharedPreferences
    await prefs.setString('user_name', roleData.displayName);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Роль "${_getRoleName(_selectedRole!)}" применена'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Возвращаемся в главное меню
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  String _getRoleName(UserRole role) {
    switch (role) {
      case UserRole.developer:
        return 'Разработчик';
      case UserRole.admin:
        return 'Админ';
      case UserRole.manager:
        return 'Заведующая';
      case UserRole.employee:
        return 'Сотрудник';
      case UserRole.client:
        return 'Клиент';
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.developer:
        return Colors.purple;
      case UserRole.admin:
        return Colors.red;
      case UserRole.manager:
        return Colors.orange;
      case UserRole.employee:
        return Colors.blue;
      case UserRole.client:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Тест ролей'),
        backgroundColor: AppColors.primaryGreen,
      ),
      body: Container(
        decoration: BoxDecoration(
          color: AppColors.primaryGreen,
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6,
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Текущая роль
              if (_currentRole != null)
                Card(
                  color: Colors.white.withOpacity(0.95),
                  child: Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Текущая роль:',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                        SizedBox(height: 8),
                        Container(
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                            color: _getRoleColor(_currentRole!.role).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(
                              color: _getRoleColor(_currentRole!.role),
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.person,
                                color: _getRoleColor(_currentRole!.role),
                              ),
                              SizedBox(width: 8),
                              Text(
                                _getRoleName(_currentRole!.role),
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.bold,
                                  color: _getRoleColor(_currentRole!.role),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 8),
                        Text('Имя: ${_currentRole!.displayName}'),
                        if (_currentRole!.employeeName != null)
                          Text('Имя сотрудника (G): ${_currentRole!.employeeName}'),
                        Text('Телефон: ${_currentRole!.phone}'),
                      ],
                    ),
                  ),
                ),
              SizedBox(height: 24),
              // Выбор роли
              Card(
                color: Colors.white.withOpacity(0.95),
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Выберите роль для тестирования:',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      SizedBox(height: 16),
                      // Админ
                      RadioListTile<UserRole>(
                        title: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Админ'),
                          ],
                        ),
                        subtitle: Text('Видит весь функционал'),
                        value: UserRole.admin,
                        groupValue: _selectedRole,
                        onChanged: (value) {
                          if (mounted) setState(() {
                            _selectedRole = value;
                            _testDisplayName = 'Админ Тестовый';
                            _testEmployeeName = 'Админ Тестовый';
                          });
                        },
                      ),
                      // Сотрудник
                      RadioListTile<UserRole>(
                        title: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Сотрудник'),
                          ],
                        ),
                        subtitle: Text('Видит функционал для сотрудников'),
                        value: UserRole.employee,
                        groupValue: _selectedRole,
                        onChanged: (value) {
                          if (mounted) setState(() {
                            _selectedRole = value;
                            _testDisplayName = 'Сотрудник Тестовый';
                            _testEmployeeName = 'Сотрудник Тестовый';
                          });
                        },
                      ),
                      // Клиент
                      RadioListTile<UserRole>(
                        title: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Клиент'),
                          ],
                        ),
                        subtitle: Text('Видит базовый функционал'),
                        value: UserRole.client,
                        groupValue: _selectedRole,
                        onChanged: (value) {
                          if (mounted) setState(() {
                            _selectedRole = value;
                            _testDisplayName = 'Клиент Тестовый';
                            _testEmployeeName = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
              // Поля для тестового имени
              if (_selectedRole != null)
                Card(
                  color: Colors.white.withOpacity(0.95),
                  child: Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Тестовые данные:',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                        SizedBox(height: 12),
                        TextField(
                          decoration: InputDecoration(
                            labelText: 'Имя для отображения',
                            border: OutlineInputBorder(),
                            hintText: 'Введите имя',
                          ),
                          controller: TextEditingController(text: _testDisplayName)
                            ..selection = TextSelection.collapsed(offset: _testDisplayName.length),
                          onChanged: (value) {
                            _testDisplayName = value;
                          },
                        ),
                        if (_selectedRole == UserRole.admin || _selectedRole == UserRole.employee) ...[
                          SizedBox(height: 12),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Имя сотрудника (столбец G)',
                              border: OutlineInputBorder(),
                              hintText: 'Введите имя сотрудника',
                            ),
                            controller: TextEditingController(text: _testEmployeeName ?? '')
                              ..selection = TextSelection.collapsed(offset: _testEmployeeName?.length ?? 0),
                            onChanged: (value) {
                              _testEmployeeName = value.isEmpty ? null : value;
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              SizedBox(height: 24),
              // Кнопка применения
              ElevatedButton(
                onPressed: _applyRole,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  padding: EdgeInsets.symmetric(vertical: 16.h),
                ),
                child: Text(
                  'Применить роль',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(height: 16),
              // Информация о функционале
              Card(
                color: Colors.white.withOpacity(0.95),
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Функционал по ролям:',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      SizedBox(height: 12),
                      _buildRoleInfo('Админ', Colors.red, 'Весь функционал'),
                      _buildRoleInfo('Сотрудник', Colors.blue, 'Меню, Корзина, Заказы, Лояльность, Списать бонусы, Отзывы, Диалоги, Наличие, Обучение, Тестирование, Пересменка, Пересчет, Рецепты'),
                      _buildRoleInfo('Клиент', Colors.green, 'Меню, Корзина, Заказы, Лояльность, Отзывы, Наличие'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleInfo(String role, Color color, String features) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: EdgeInsets.only(top: 6.h, right: 8.w),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  features,
                  style: TextStyle(fontSize: 12.sp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}












