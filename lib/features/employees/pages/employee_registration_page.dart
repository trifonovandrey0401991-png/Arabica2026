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
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_colors.dart';

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

        if (!mounted) return;
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
    return prefs.getString('user_phone') ?? prefs.getString('userPhone');
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
        SnackBar(
          content: Text('Пожалуйста, добавьте фото лицевой страницы паспорта'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_passportRegistrationPhotoBytes == null && _passportRegistrationPhotoUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Пожалуйста, добавьте фото прописки'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (mounted) setState(() {
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
          Logger.success('Сотрудник автоматически верифицирован: ${Logger.maskPhone(phone)}');
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
          SnackBar(
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
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        enabled: enabled,
        style: TextStyle(fontSize: 16.sp, color: Colors.white.withOpacity(0.9)),
        cursorColor: AppColors.gold,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: AppColors.gold.withOpacity(0.7)),
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
          prefixIcon: Container(
            margin: EdgeInsets.all(12.w),
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, color: AppColors.gold, size: 20),
          ),
          filled: true,
          fillColor: Colors.transparent,
          counterText: '',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide(color: AppColors.gold, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide(color: AppColors.error),
          ),
          errorStyle: TextStyle(color: AppColors.errorLight),
          contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
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
      margin: EdgeInsets.only(bottom: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок секции
          Padding(
            padding: EdgeInsets.only(left: 4.w, bottom: 12.h),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.gold, AppColors.darkGold],
                    ),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // Контент секции
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
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
              // AppBar
              _buildAppBar(),
              // Форма
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: EdgeInsets.all(16.w),
                    children: [
                      // Визуальный заголовок формы
                      _buildFormHeader(),

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
                              SizedBox(width: 12),
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

                      SizedBox(height: 8),

                      // Кнопка сохранения
                      _buildSaveButton(),

                      SizedBox(height: 24),
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

  Widget _buildFormHeader() {
    return Container(
      margin: EdgeInsets.only(bottom: 24.h),
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.15),
            Colors.white.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.25), Colors.white.withOpacity(0.1)],
              ),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Icon(
              _isEditing ? Icons.edit_note : Icons.person_add_alt_1,
              color: Colors.white,
              size: 32,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Редактирование данных' : 'Регистрация сотрудника',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _isEditing
                      ? 'Измените необходимые поля и сохраните'
                      : 'Заполните все обязательные поля для регистрации нового сотрудника',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ),
          ),
        ],
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
              onPressed: () => Navigator.pop(context),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEditing ? 'Редактирование' : 'Новый сотрудник',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _isEditing ? 'Обновите данные сотрудника' : 'Заполните все поля',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13.sp,
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
                description: 'Базовые права',
                icon: Icons.person,
                isSelected: _selectedRole == 'employee',
                onTap: _isLoading ? null : () {
                  if (mounted) setState(() {
                    _selectedRole = 'employee';
                    _isAdmin = false;
                  });
                },
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildRoleCard(
                title: 'Админ',
                description: 'Полный доступ',
                icon: Icons.admin_panel_settings,
                isSelected: _selectedRole == 'admin',
                onTap: _isLoading ? null : () {
                  if (mounted) setState(() {
                    _selectedRole = 'admin';
                    _isAdmin = true;
                  });
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        // Чекбокс заведующего
        Container(
          decoration: BoxDecoration(
            color: _isManager ? AppColors.gold.withOpacity(0.1) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: _isManager ? AppColors.gold : Colors.white.withOpacity(0.1),
            ),
          ),
          child: CheckboxListTile(
            title: Text(
              'Заведующий(ая)',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.9)),
            ),
            subtitle: Text(
              'Расширенные права управления',
              style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.5)),
            ),
            value: _isManager,
            onChanged: _isLoading ? null : (value) {
              if (mounted) setState(() => _isManager = value ?? false);
            },
            activeColor: AppColors.gold,
            checkColor: AppColors.night,
            secondary: Icon(
              Icons.supervisor_account,
              color: _isManager ? AppColors.gold : Colors.white.withOpacity(0.4),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isSelected,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 16.h),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: [AppColors.emerald, AppColors.emeraldLight])
              : null,
          color: isSelected ? null : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: isSelected ? AppColors.gold : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.gold.withOpacity(0.2),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.2) : AppColors.gold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                icon,
                size: 28,
                color: isSelected ? Colors.white : AppColors.gold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14.sp,
                color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
              ),
            ),
            SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 11.sp,
                color: isSelected ? Colors.white.withOpacity(0.7) : Colors.white.withOpacity(0.4),
              ),
              textAlign: TextAlign.center,
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
      margin: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.gold),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (required) ...[
                SizedBox(width: 4),
                Text('*', style: TextStyle(color: AppColors.error)),
              ],
              SizedBox(width: 8),
              if (hasPhoto)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: AppColors.success),
                      SizedBox(width: 4),
                      Text(
                        'Загружено',
                        style: TextStyle(fontSize: 11.sp, color: AppColors.success, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: 10),
          // Превью или кнопки
          if (hasPhoto)
            Stack(
              children: [
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: photoBytes != null
                        ? Image.memory(photoBytes, fit: BoxFit.cover)
                        : AppCachedImage(
                            imageUrl: photoUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Center(
                              child: Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: 8.h,
                  right: 8.w,
                  child: GestureDetector(
                    onTap: () => _pickImage(ImageSource.gallery, photoType),
                    child: Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8.r),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(Icons.edit, size: 18, color: AppColors.gold),
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add_a_photo,
                      size: 28,
                      color: AppColors.gold.withOpacity(0.5),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Добавьте фото',
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.white.withOpacity(0.4),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPhotoButton(
                          icon: Icons.camera_alt,
                          label: 'Камера',
                          onTap: () => _pickImage(ImageSource.camera, photoType),
                        ),
                      ),
                      SizedBox(width: 12),
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
      color: AppColors.gold.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12.r),
      child: InkWell(
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 14.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.gold),
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.gold,
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
        gradient: LinearGradient(
          colors: [AppColors.gold, AppColors.darkGold],
        ),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.3),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _saveRegistration,
          borderRadius: BorderRadius.circular(16.r),
          child: Center(
            child: _isLoading
                ? SizedBox(
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
                      Icon(Icons.save, color: Colors.white),
                      SizedBox(width: 12),
                      Text(
                        _isEditing ? 'Сохранить изменения' : 'Создать сотрудника',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17.sp,
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

