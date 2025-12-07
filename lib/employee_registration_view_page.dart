import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'employee_registration_model.dart';
import 'employee_registration_service.dart';
import 'employee_registration_page.dart';
import 'user_role_service.dart';
import 'user_role_model.dart';

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
      final phone = prefs.getString('userPhone') ?? '';
      if (phone.isEmpty) {
        setState(() {
          _isAdmin = false;
        });
        return;
      }
      final roleData = await UserRoleService.getUserRole(phone);
      setState(() {
        _isAdmin = roleData.role == UserRole.admin;
      });
    } catch (e) {
      print('Ошибка проверки роли: $e');
      setState(() {
        _isAdmin = false;
      });
    }
  }

  Future<void> _loadRegistration() async {
    try {
      final registration = await EmployeeRegistrationService.getRegistration(widget.employeePhone);
      setState(() {
        _registration = registration;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки данных: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleVerification() async {
    if (!_isAdmin || _registration == null) return;

    final newVerifiedStatus = !_registration!.isVerified;
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone') ?? '';
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

    final success = await EmployeeRegistrationService.verifyEmployee(
      widget.employeePhone,
      newVerifiedStatus,
      adminName,
    );

    if (success) {
      await _loadRegistration();
      // Обновляем статус в локальном состоянии
      setState(() {
        // Статус уже обновлен в _loadRegistration
      });
      
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
      
      // Возвращаем true, чтобы обновить статус в списке сотрудников
      if (mounted) {
        Navigator.pop(context, true);
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
                                onChanged: (value) => _toggleVerification(),
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

