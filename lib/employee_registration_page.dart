import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'employee_registration_model.dart';
import 'employee_registration_service.dart';
import 'employee_service.dart';
import 'employees_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmployeeRegistrationPage extends StatefulWidget {
  final String? employeePhone; // Если указан - редактирование существующей регистрации
  final EmployeeRegistration? existingRegistration;

  const EmployeeRegistrationPage({
    super.key,
    this.employeePhone,
    this.existingRegistration,
  });

  @override
  State<EmployeeRegistrationPage> createState() => _EmployeeRegistrationPageState();
}

class _EmployeeRegistrationPageState extends State<EmployeeRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _passportSeriesController = TextEditingController();
  final _passportNumberController = TextEditingController();
  final _issuedByController = TextEditingController();
  final _issueDateController = TextEditingController();

  String? _passportFrontPhotoPath;
  String? _passportRegistrationPhotoPath;
  String? _additionalPhotoPath;

  String? _passportFrontPhotoUrl;
  String? _passportRegistrationPhotoUrl;
  String? _additionalPhotoUrl;

  bool _isLoading = false;
  bool _isEditing = false;
  
  // Переменные для выбора роли
  String? _selectedRole; // 'admin' или 'employee'
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existingRegistration != null;
    if (widget.existingRegistration != null) {
      final reg = widget.existingRegistration!;
      _fullNameController.text = reg.fullName;
      _passportSeriesController.text = reg.passportSeries;
      _passportNumberController.text = reg.passportNumber;
      _issuedByController.text = reg.issuedBy;
      _issueDateController.text = reg.issueDate;
      _passportFrontPhotoUrl = reg.passportFrontPhotoUrl;
      _passportRegistrationPhotoUrl = reg.passportRegistrationPhotoUrl;
      _additionalPhotoUrl = reg.additionalPhotoUrl;
    }
    // По умолчанию роль - сотрудник
    _selectedRole = 'employee';
    _isAdmin = false;
    
    // Загружаем текущую роль сотрудника, если редактируем существующую регистрацию
    if (widget.existingRegistration != null || widget.employeePhone != null) {
      _loadEmployeeRole();
    }
  }

  /// Загрузить текущую роль сотрудника по телефону
  Future<void> _loadEmployeeRole() async {
    try {
      final phone = await _getEmployeePhone();
      if (phone == null || phone.isEmpty) {
        return;
      }

      // Получаем всех сотрудников и ищем по телефону
      final allEmployees = await EmployeeService.getEmployees();
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      
      for (var emp in allEmployees) {
        if (emp.phone != null) {
          final empPhone = emp.phone!.replaceAll(RegExp(r'[\s\+]'), '');
          if (empPhone == normalizedPhone) {
            // Найден сотрудник, устанавливаем его роль
            final isAdmin = emp.isAdmin == true;
            if (mounted) {
              setState(() {
                _isAdmin = isAdmin;
                _selectedRole = isAdmin ? 'admin' : 'employee';
              });
            }
            print('✅ Загружена роль сотрудника: ${isAdmin ? "Админ" : "Сотрудник"}');
            return;
          }
        }
      }
    } catch (e) {
      print('⚠️ Ошибка загрузки роли сотрудника: $e');
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _passportSeriesController.dispose();
    _passportNumberController.dispose();
    _issuedByController.dispose();
    _issueDateController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source, String photoType) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (image != null) {
        setState(() {
          if (photoType == 'front') {
            _passportFrontPhotoPath = image.path;
            _passportFrontPhotoUrl = null; // Сбрасываем URL, так как загружаем новое фото
          } else if (photoType == 'registration') {
            _passportRegistrationPhotoPath = image.path;
            _passportRegistrationPhotoUrl = null;
          } else if (photoType == 'additional') {
            _additionalPhotoPath = image.path;
            _additionalPhotoUrl = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка выбора фото: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _getEmployeePhone() async {
    if (widget.employeePhone != null && widget.employeePhone!.isNotEmpty) {
      return widget.employeePhone;
    }
    // Получаем телефон из SharedPreferences (для случая, когда сотрудник регистрирует себя)
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userPhone');
  }

  /// Создать или обновить запись сотрудника с указанной ролью
  Future<void> _createOrUpdateEmployee(String phone, String name, bool isAdmin) async {
    try {
      // Получаем всех сотрудников и ищем по телефону
      final allEmployees = await EmployeeService.getEmployees();
      final normalizedPhone = phone.replaceAll(RegExp(r'[\s\+]'), '');
      
      Employee? existingEmployee;
      for (var emp in allEmployees) {
        if (emp.phone != null) {
          final empPhone = emp.phone!.replaceAll(RegExp(r'[\s\+]'), '');
          if (empPhone == normalizedPhone) {
            existingEmployee = emp;
            break;
          }
        }
      }

      if (existingEmployee != null) {
        // Обновляем существующего сотрудника
        await EmployeeService.updateEmployee(
          id: existingEmployee.id,
          name: name,
          phone: normalizedPhone,
          isAdmin: isAdmin,
        );
        print('✅ Сотрудник обновлен: $name, роль: ${isAdmin ? "Админ" : "Сотрудник"}');
      } else {
        // Создаем нового сотрудника
        await EmployeeService.createEmployee(
          name: name,
          phone: normalizedPhone,
          isAdmin: isAdmin,
        );
        print('✅ Сотрудник создан: $name, роль: ${isAdmin ? "Админ" : "Сотрудник"}');
      }
    } catch (e) {
      print('⚠️ Ошибка создания/обновления сотрудника: $e');
      // Не прерываем процесс, так как регистрация уже сохранена
    }
  }

  Future<void> _saveRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Проверяем обязательные фото
    if (_passportFrontPhotoPath == null && _passportFrontPhotoUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пожалуйста, добавьте фото лицевой страницы паспорта'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_passportRegistrationPhotoPath == null && _passportRegistrationPhotoUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пожалуйста, добавьте фото прописки'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final phone = await _getEmployeePhone();
      if (phone == null || phone.isEmpty) {
        throw Exception('Не удалось определить телефон сотрудника');
      }

      // Загружаем новые фото, если они есть
      String? frontPhotoUrl = _passportFrontPhotoUrl;
      String? registrationPhotoUrl = _passportRegistrationPhotoUrl;
      String? additionalPhotoUrl = _additionalPhotoUrl;

      if (_passportFrontPhotoPath != null) {
        frontPhotoUrl = await EmployeeRegistrationService.uploadPhoto(
          _passportFrontPhotoPath!,
          phone,
          'front',
        );
        if (frontPhotoUrl == null) {
          throw Exception('Ошибка загрузки фото лицевой страницы');
        }
      }

      if (_passportRegistrationPhotoPath != null) {
        registrationPhotoUrl = await EmployeeRegistrationService.uploadPhoto(
          _passportRegistrationPhotoPath!,
          phone,
          'registration',
        );
        if (registrationPhotoUrl == null) {
          throw Exception('Ошибка загрузки фото прописки');
        }
      }

      if (_additionalPhotoPath != null) {
        additionalPhotoUrl = await EmployeeRegistrationService.uploadPhoto(
          _additionalPhotoPath!,
          phone,
          'additional',
        );
      }

      final now = DateTime.now();
      final registration = widget.existingRegistration?.copyWith(
        fullName: _fullNameController.text.trim(),
        passportSeries: _passportSeriesController.text.trim(),
        passportNumber: _passportNumberController.text.trim(),
        issuedBy: _issuedByController.text.trim(),
        issueDate: _issueDateController.text.trim(),
        passportFrontPhotoUrl: frontPhotoUrl,
        passportRegistrationPhotoUrl: registrationPhotoUrl,
        additionalPhotoUrl: additionalPhotoUrl,
        updatedAt: now,
      ) ?? EmployeeRegistration(
        phone: phone,
        fullName: _fullNameController.text.trim(),
        passportSeries: _passportSeriesController.text.trim(),
        passportNumber: _passportNumberController.text.trim(),
        issuedBy: _issuedByController.text.trim(),
        issueDate: _issueDateController.text.trim(),
        passportFrontPhotoUrl: frontPhotoUrl,
        passportRegistrationPhotoUrl: registrationPhotoUrl,
        additionalPhotoUrl: additionalPhotoUrl,
        createdAt: now,
        updatedAt: now,
      );

      final success = await EmployeeRegistrationService.saveRegistration(registration);

      if (mounted) {
        if (success) {
          // Создаем или обновляем запись сотрудника с указанной ролью
          await _createOrUpdateEmployee(phone, _fullNameController.text.trim(), _isAdmin);
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Регистрация успешно сохранена'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // Возвращаем true для обновления списка
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка сохранения регистрации'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildPhotoField({
    required String label,
    required String photoType,
    String? photoPath,
    String? photoUrl,
  }) {
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
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () => _pickImage(ImageSource.camera, photoType),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Сфотографировать'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () => _pickImage(ImageSource.gallery, photoType),
                icon: const Icon(Icons.photo_library),
                label: const Text('Выбрать из галереи'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                ),
              ),
            ),
          ],
        ),
        if (photoPath != null || photoUrl != null) ...[
          const SizedBox(height: 8),
          Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: photoPath != null
                  ? Image.file(
                      File(photoPath),
                      fit: BoxFit.cover,
                    )
                  : photoUrl != null
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(Icons.error, color: Colors.red),
                            );
                          },
                        )
                      : null,
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Редактирование регистрации' : 'Регистрация сотрудника'),
        backgroundColor: const Color(0xFF004D40),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ФИО
            TextFormField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                labelText: 'Введите ФИО',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Пожалуйста, введите ФИО';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Серия паспорта
            TextFormField(
              controller: _passportSeriesController,
              decoration: const InputDecoration(
                labelText: 'Введите Серию Паспорта',
                border: OutlineInputBorder(),
                hintText: '4 цифры',
              ),
              keyboardType: TextInputType.number,
              maxLength: 4,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Пожалуйста, введите серию паспорта';
                }
                if (!EmployeeRegistrationService.isValidPassportSeries(value.trim())) {
                  return 'Серия паспорта должна состоять из 4 цифр';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Номер паспорта
            TextFormField(
              controller: _passportNumberController,
              decoration: const InputDecoration(
                labelText: 'Введите Номер Паспорта',
                border: OutlineInputBorder(),
                hintText: '6 цифр',
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Пожалуйста, введите номер паспорта';
                }
                if (!EmployeeRegistrationService.isValidPassportNumber(value.trim())) {
                  return 'Номер паспорта должен состоять из 6 цифр';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Кем выдан
            TextFormField(
              controller: _issuedByController,
              decoration: const InputDecoration(
                labelText: 'Кем Выдан',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Пожалуйста, введите кем выдан паспорт';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Дата выдачи
            TextFormField(
              controller: _issueDateController,
              decoration: const InputDecoration(
                labelText: 'Дата Выдачи',
                border: OutlineInputBorder(),
                hintText: 'ДД.ММ.ГГГГ',
              ),
              keyboardType: TextInputType.datetime,
              maxLength: 10,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Пожалуйста, введите дату выдачи';
                }
                if (!EmployeeRegistrationService.isValidDate(value.trim())) {
                  return 'Неверный формат даты. Используйте ДД.ММ.ГГГГ';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Роль сотрудника
            const Text(
              'Роль сотрудника',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              title: const Text('Сотрудник'),
              value: 'employee',
              groupValue: _selectedRole,
              onChanged: _isLoading ? null : (value) {
                setState(() {
                  _selectedRole = value;
                  _isAdmin = false;
                });
              },
            ),
            RadioListTile<String>(
              title: const Text('Администратор'),
              value: 'admin',
              groupValue: _selectedRole,
              onChanged: _isLoading ? null : (value) {
                setState(() {
                  _selectedRole = value;
                  _isAdmin = true;
                });
              },
            ),
            const SizedBox(height: 16),

            // Фото лицевой страницы
            _buildPhotoField(
              label: 'Добавьте фото Паспорта (Лицевая Страница)',
              photoType: 'front',
              photoPath: _passportFrontPhotoPath,
              photoUrl: _passportFrontPhotoUrl,
            ),

            // Фото прописки
            _buildPhotoField(
              label: 'Добавьте фото Паспорта (Прописка)',
              photoType: 'registration',
              photoPath: _passportRegistrationPhotoPath,
              photoUrl: _passportRegistrationPhotoUrl,
            ),

            // Дополнительное фото
            _buildPhotoField(
              label: 'Добавьте Доп Фото если нужно',
              photoType: 'additional',
              photoPath: _additionalPhotoPath,
              photoUrl: _additionalPhotoUrl,
            ),

            const SizedBox(height: 24),

            // Кнопка сохранения
            ElevatedButton(
              onPressed: _isLoading ? null : _saveRegistration,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004D40),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Сохранить',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

