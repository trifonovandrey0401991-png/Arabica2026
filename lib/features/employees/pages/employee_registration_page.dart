import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../models/employee_registration_model.dart';
import '../services/employee_registration_service.dart';
import '../services/employee_service.dart';
import 'employees_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/widgets/app_cached_image.dart';

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
  final _phoneController = TextEditingController(); // Добавляем контроллер для телефона
  final _passportSeriesController = TextEditingController();
  final _passportNumberController = TextEditingController();
  final _issuedByController = TextEditingController();
  final _issueDateController = TextEditingController();

  // Храним байты фото для надежной загрузки (работает с content:// URI на Android)
  Uint8List? _passportFrontPhotoBytes;
  Uint8List? _passportRegistrationPhotoBytes;
  Uint8List? _additionalPhotoBytes;

  String? _passportFrontPhotoUrl;
  String? _passportRegistrationPhotoUrl;
  String? _additionalPhotoUrl;

  bool _isLoading = false;
  bool _isEditing = false;
  
  // Переменные для выбора роли
  String? _selectedRole; // 'admin' или 'employee'
  bool _isAdmin = false;
  bool _isManager = false; // Флаг заведующего(ей)

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existingRegistration != null;
    if (widget.existingRegistration != null) {
      final reg = widget.existingRegistration!;
      _fullNameController.text = reg.fullName;
      _phoneController.text = reg.phone; // Заполняем телефон из регистрации
      _passportSeriesController.text = reg.passportSeries;
      _passportNumberController.text = reg.passportNumber;
      _issuedByController.text = reg.issuedBy;
      _issueDateController.text = reg.issueDate;
      _passportFrontPhotoUrl = reg.passportFrontPhotoUrl;
      _passportRegistrationPhotoUrl = reg.passportRegistrationPhotoUrl;
      _additionalPhotoUrl = reg.additionalPhotoUrl;
    } else if (widget.employeePhone != null) {
      // Если передан телефон, заполняем его
      _phoneController.text = widget.employeePhone!;
    }
    // По умолчанию роль - сотрудник
    _selectedRole = 'employee';
    _isAdmin = false;
    _isManager = false;
    
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
            final isManager = emp.isManager == true;
            if (mounted) {
              setState(() {
                _isAdmin = isAdmin;
                _isManager = isManager;
                _selectedRole = isAdmin ? 'admin' : 'employee';
              });
            }
            Logger.success('Загружена роль сотрудника: ${isAdmin ? "Админ" : "Сотрудник"}, Заведующий: $isManager');
            return;
          }
        }
      }
    } catch (e) {
      Logger.warning('Ошибка загрузки роли сотрудника: $e');
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
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
        // Сразу читаем байты через XFile (работает с content:// URI на Android)
        final bytes = await image.readAsBytes();
        Logger.debug('📷 Фото выбрано: ${image.path}, размер: ${bytes.length} байт');

        setState(() {
          if (photoType == 'front') {
            _passportFrontPhotoBytes = bytes;
            _passportFrontPhotoUrl = null;
          } else if (photoType == 'registration') {
            _passportRegistrationPhotoBytes = bytes;
            _passportRegistrationPhotoUrl = null;
          } else if (photoType == 'additional') {
            _additionalPhotoBytes = bytes;
            _additionalPhotoUrl = null;
          }
        });
      }
    } catch (e) {
      Logger.error('Ошибка выбора фото: $e');
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
    // Если телефон указан в виджете, используем его
    if (widget.employeePhone != null && widget.employeePhone!.isNotEmpty) {
      return widget.employeePhone;
    }
    // Если телефон введен в поле, используем его
    if (_phoneController.text.trim().isNotEmpty) {
      return _phoneController.text.trim();
    }
    // Получаем телефон из SharedPreferences (для случая, когда сотрудник регистрирует себя)
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userPhone');
  }

  /// Создать или обновить запись сотрудника с указанной ролью
  Future<void> _createOrUpdateEmployee(String phone, String name, bool isAdmin, bool isManager) async {
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
          isManager: isManager,
        );
        Logger.success('Сотрудник обновлен: $name, роль: ${isAdmin ? "Админ" : "Сотрудник"}, Заведующий: $isManager');
      } else {
        // Создаем нового сотрудника
        await EmployeeService.createEmployee(
          name: name,
          phone: normalizedPhone,
          isAdmin: isAdmin,
          isManager: isManager,
        );
        Logger.success('Сотрудник создан: $name, роль: ${isAdmin ? "Админ" : "Сотрудник"}, Заведующий: $isManager');
      }
    } catch (e) {
      Logger.warning('Ошибка создания/обновления сотрудника: $e');
      // Не прерываем процесс, так как регистрация уже сохранена
    }
  }

  Future<void> _saveRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Проверяем обязательные фото (bytes для новых, url для существующих)
    if (_passportFrontPhotoBytes == null && _passportFrontPhotoUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Пожалуйста, добавьте фото лицевой страницы паспорта'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_passportRegistrationPhotoBytes == null && _passportRegistrationPhotoUrl == null) {
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

      // Загружаем фото из сохраненных байтов (более надежно для Android)
      if (_passportFrontPhotoBytes != null) {
        Logger.debug('Загрузка фото front из байтов: ${_passportFrontPhotoBytes!.length} байт');

        frontPhotoUrl = await EmployeeRegistrationService.uploadPhotoFromBytes(
          _passportFrontPhotoBytes!,
          phone,
          'front',
        );
        if (frontPhotoUrl == null) {
          final error = EmployeeRegistrationService.lastUploadError ?? 'Неизвестная ошибка';
          throw Exception('Ошибка загрузки фото лицевой страницы: $error');
        }
      }

      if (_passportRegistrationPhotoBytes != null) {
        Logger.debug('Загрузка фото registration из байтов: ${_passportRegistrationPhotoBytes!.length} байт');

        registrationPhotoUrl = await EmployeeRegistrationService.uploadPhotoFromBytes(
          _passportRegistrationPhotoBytes!,
          phone,
          'registration',
        );
        if (registrationPhotoUrl == null) {
          final error = EmployeeRegistrationService.lastUploadError ?? 'Неизвестная ошибка';
          throw Exception('Ошибка загрузки фото прописки: $error');
        }
      }

      if (_additionalPhotoBytes != null) {
        Logger.debug('Загрузка дополнительного фото из байтов: ${_additionalPhotoBytes!.length} байт');

        additionalPhotoUrl = await EmployeeRegistrationService.uploadPhotoFromBytes(
          _additionalPhotoBytes!,
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

      if (!mounted) return;
      if (success) {
        // Создаем или обновляем запись сотрудника с указанной ролью
        await _createOrUpdateEmployee(phone, _fullNameController.text.trim(), _isAdmin, _isManager);

        // Автоматически верифицируем нового сотрудника (если создаётся админом)
        if (!_isEditing) {
          await EmployeeRegistrationService.verifyEmployee(
            phone,
            true,
            'Система (авто-верификация)',
          );
          Logger.success('Сотрудник автоматически верифицирован: $phone');
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Регистрация обновлена' : 'Сотрудник создан и верифицирован'),
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

  static const _primaryColor = Color(0xFF004D40);
  static const _accentColor = Color(0xFF00897B);

  /// Красивое поле ввода
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        enabled: enabled,
        style: const TextStyle(fontSize: 16, color: Color(0xFF1A1A1A)),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: _primaryColor.withOpacity(0.7)),
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _primaryColor, size: 20),
          ),
          filled: true,
          fillColor: Colors.white,
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.red),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
        validator: validator,
      ),
    );
  }

  /// Секция с заголовком
  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок секции
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_primaryColor, _accentColor],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Контент секции
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(children: children),
          ),
        ],
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
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // AppBar
              _buildAppBar(),
              // Форма
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Секция: Личные данные
                      _buildSection(
                        title: 'Личные данные',
                        icon: Icons.person,
                        children: [
                          _buildTextField(
                            controller: _fullNameController,
                            label: 'ФИО',
                            hint: 'Иванов Иван Иванович',
                            icon: Icons.badge,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите ФИО';
                              }
                              return null;
                            },
                          ),
                          if (widget.employeePhone == null)
                            _buildTextField(
                              controller: _phoneController,
                              label: 'Телефон',
                              hint: '79001234567',
                              icon: Icons.phone,
                              keyboardType: TextInputType.phone,
                              enabled: !_isEditing,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Введите телефон';
                                }
                                final phoneDigits = value.replaceAll(RegExp(r'[^\d]'), '');
                                if (phoneDigits.length < 10) {
                                  return 'Минимум 10 цифр';
                                }
                                return null;
                              },
                            ),
                        ],
                      ),

                      // Секция: Паспортные данные
                      _buildSection(
                        title: 'Паспортные данные',
                        icon: Icons.credit_card,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: _buildTextField(
                                  controller: _passportSeriesController,
                                  label: 'Серия',
                                  hint: '0000',
                                  icon: Icons.numbers,
                                  keyboardType: TextInputType.number,
                                  maxLength: 4,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Введите';
                                    }
                                    if (!EmployeeRegistrationService.isValidPassportSeries(value.trim())) {
                                      return '4 цифры';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 3,
                                child: _buildTextField(
                                  controller: _passportNumberController,
                                  label: 'Номер',
                                  hint: '000000',
                                  icon: Icons.tag,
                                  keyboardType: TextInputType.number,
                                  maxLength: 6,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Введите';
                                    }
                                    if (!EmployeeRegistrationService.isValidPassportNumber(value.trim())) {
                                      return '6 цифр';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          _buildTextField(
                            controller: _issuedByController,
                            label: 'Кем выдан',
                            hint: 'УФМС России по...',
                            icon: Icons.account_balance,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите кем выдан';
                              }
                              return null;
                            },
                          ),
                          _buildTextField(
                            controller: _issueDateController,
                            label: 'Дата выдачи',
                            hint: 'ДД.ММ.ГГГГ',
                            icon: Icons.calendar_today,
                            keyboardType: TextInputType.datetime,
                            maxLength: 10,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите дату';
                              }
                              if (!EmployeeRegistrationService.isValidDate(value.trim())) {
                                return 'Формат: ДД.ММ.ГГГГ';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),

                      // Секция: Роль
                      _buildSection(
                        title: 'Роль в системе',
                        icon: Icons.work,
                        children: [
                          _buildRoleSelector(),
                        ],
                      ),

                      // Секция: Документы
                      _buildSection(
                        title: 'Документы',
                        icon: Icons.photo_camera,
                        children: [
                          _buildModernPhotoField(
                            label: 'Паспорт (лицевая сторона)',
                            icon: Icons.badge,
                            photoType: 'front',
                            photoBytes: _passportFrontPhotoBytes,
                            photoUrl: _passportFrontPhotoUrl,
                            required: true,
                          ),
                          _buildModernPhotoField(
                            label: 'Паспорт (прописка)',
                            icon: Icons.home,
                            photoType: 'registration',
                            photoBytes: _passportRegistrationPhotoBytes,
                            photoUrl: _passportRegistrationPhotoUrl,
                            required: true,
                          ),
                          _buildModernPhotoField(
                            label: 'Дополнительное фото',
                            icon: Icons.add_photo_alternate,
                            photoType: 'additional',
                            photoBytes: _additionalPhotoBytes,
                            photoUrl: _additionalPhotoUrl,
                            required: false,
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Кнопка сохранения
                      _buildSaveButton(),

                      const SizedBox(height: 24),
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

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Редактирование' : 'Новый сотрудник',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _isEditing ? 'Обновите данные сотрудника' : 'Заполните все поля',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Column(
      children: [
        // Роли
        Row(
          children: [
            Expanded(
              child: _buildRoleCard(
                title: 'Сотрудник',
                icon: Icons.person,
                isSelected: _selectedRole == 'employee',
                onTap: _isLoading ? null : () {
                  setState(() {
                    _selectedRole = 'employee';
                    _isAdmin = false;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildRoleCard(
                title: 'Админ',
                icon: Icons.admin_panel_settings,
                isSelected: _selectedRole == 'admin',
                onTap: _isLoading ? null : () {
                  setState(() {
                    _selectedRole = 'admin';
                    _isAdmin = true;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Чекбокс заведующего
        Container(
          decoration: BoxDecoration(
            color: _isManager ? Colors.purple.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isManager ? Colors.purple : Colors.grey.withOpacity(0.2),
            ),
          ),
          child: CheckboxListTile(
            title: const Text(
              'Заведующий(ая)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Расширенные права управления',
              style: TextStyle(fontSize: 12),
            ),
            value: _isManager,
            onChanged: _isLoading ? null : (value) {
              setState(() => _isManager = value ?? false);
            },
            activeColor: Colors.purple,
            secondary: Icon(
              Icons.supervisor_account,
              color: _isManager ? Colors.purple : Colors.grey,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard({
    required String title,
    required IconData icon,
    required bool isSelected,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(colors: [_primaryColor, _accentColor])
              : null,
          color: isSelected ? null : Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _primaryColor : Colors.grey.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? Colors.white : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernPhotoField({
    required String label,
    required IconData icon,
    required String photoType,
    Uint8List? photoBytes,
    String? photoUrl,
    bool required = false,
  }) {
    final hasPhoto = photoBytes != null || photoUrl != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Row(
            children: [
              Icon(icon, size: 18, color: _primaryColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (required) ...[
                const SizedBox(width: 4),
                const Text('*', style: TextStyle(color: Colors.red)),
              ],
              const Spacer(),
              if (hasPhoto)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        'Загружено',
                        style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Превью или кнопки
          if (hasPhoto)
            Stack(
              children: [
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: photoBytes != null
                        ? Image.memory(photoBytes, fit: BoxFit.cover)
                        : AppCachedImage(
                            imageUrl: photoUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => _pickImage(ImageSource.gallery, photoType),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.edit, size: 18, color: _primaryColor),
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildPhotoButton(
                    icon: Icons.camera_alt,
                    label: 'Камера',
                    onTap: () => _pickImage(ImageSource.camera, photoType),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildPhotoButton(
                    icon: Icons.photo_library,
                    label: 'Галерея',
                    onTap: () => _pickImage(ImageSource.gallery, photoType),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _primaryColor.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: _primaryColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: _primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primaryColor, _accentColor],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _saveRegistration,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.save, color: Colors.white),
                      const SizedBox(width: 12),
                      Text(
                        _isEditing ? 'Сохранить изменения' : 'Создать сотрудника',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

