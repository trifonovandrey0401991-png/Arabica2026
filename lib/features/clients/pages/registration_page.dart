import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/registration_service.dart';
import '../../loyalty/services/loyalty_storage.dart';
import '../../loyalty/services/loyalty_service.dart';
import '../../employees/services/user_role_service.dart';
import '../../referrals/services/referral_service.dart';
import '../../auth/services/auth_service.dart';
import '../../../core/utils/logger.dart';
import '../../../core/services/firebase_service.dart';

/// Страница регистрации
class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  final _referralCodeController = TextEditingController();
  bool _isLoading = false;
  String? _referralValidationMessage;
  bool _isReferralValid = false;
  bool _obscurePin = true;
  bool _obscurePinConfirm = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  Future<void> _validateReferralCode(String value) async {
    if (value.isEmpty) {
      setState(() {
        _referralValidationMessage = null;
        _isReferralValid = false;
      });
      return;
    }

    final code = int.tryParse(value);
    if (code == null) {
      setState(() {
        _referralValidationMessage = 'Введите число';
        _isReferralValid = false;
      });
      return;
    }

    final result = await ReferralService.validateReferralCode(code);
    if (result != null && result['valid'] == true) {
      setState(() {
        _referralValidationMessage = 'Сотрудник: ${result['employee']?['name'] ?? 'Найден'}';
        _isReferralValid = true;
      });
    } else {
      setState(() {
        _referralValidationMessage = result?['message'] ?? 'Код не найден';
        _isReferralValid = false;
      });
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final phone = '+7${_phoneController.text.trim()}';
      final name = _nameController.text.trim();

      // Сначала проверяем, существует ли пользователь с таким номером
      Logger.debug('Проверка существующего пользователя с номером: $phone');
      try {
        final existingUser = await LoyaltyService.fetchByPhone(phone);
        
        // Пользователь уже существует в базе
        Logger.success('Пользователь найден: ${existingUser.name} (${existingUser.phone})');
        
        if (mounted) {
          // Сохраняем данные существующего пользователя
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('is_registered', true);
          await prefs.setString('user_name', existingUser.name);
          await prefs.setString('user_phone', existingUser.phone);
          await LoyaltyStorage.save(existingUser);

          // Сохраняем FCM токен (теперь когда phone известен)
          await FirebaseService.resaveToken();

          // Проверяем роль пользователя
          try {
            final roleData = await UserRoleService.getUserRole(existingUser.phone);
            await UserRoleService.saveUserRole(roleData);
            // Обновляем имя, если нужно (из столбца G для сотрудников/админов)
            await prefs.setString('user_name', roleData.displayName);
            
            // Сохраняем данные о клиенте на сервере (если это клиент, а не админ/сотрудник)
            if (roleData.role.name == 'client') {
              try {
                final referralCode = _isReferralValid ? int.tryParse(_referralCodeController.text) : null;
                await RegistrationService.saveClientToServer(
                  phone: existingUser.phone,
                  name: existingUser.name,
                  clientName: existingUser.name,
                  referredBy: referralCode,
                );
                Logger.success('Данные существующего клиента сохранены на сервере');
              } catch (e) {
                Logger.warning('Не удалось сохранить данные существующего клиента на сервере: $e');
              }
            } else {
              Logger.info('Пользователь является ${roleData.role.name}, не регистрируем как клиента');
            }
          } catch (e) {
            Logger.warning('Ошибка проверки роли: $e');
            // При ошибке проверки роли, пытаемся проверить через API сотрудников
            try {
              final apiRole = await UserRoleService.checkEmployeeViaAPI(existingUser.phone);
              if (apiRole != null) {
                Logger.success('Сотрудник найден через API после ошибки проверки роли');
                await UserRoleService.saveUserRole(apiRole);
                await prefs.setString('user_name', apiRole.displayName);
                Logger.info('Пользователь является ${apiRole.role.name}, не регистрируем как клиента');
              } else {
                // Если не найден как сотрудник, регистрируем как клиента
                Logger.info('Пользователь не найден как сотрудник, регистрируем как клиента');
                try {
                  final referralCode = _isReferralValid ? int.tryParse(_referralCodeController.text) : null;
                  await RegistrationService.saveClientToServer(
                    phone: existingUser.phone,
                    name: existingUser.name,
                    clientName: existingUser.name,
                    referredBy: referralCode,
                  );
                  Logger.success('Данные существующего клиента сохранены на сервере (без роли)');
                } catch (e2) {
                  Logger.warning('Не удалось сохранить данные существующего клиента на сервере: $e2');
                }
              }
            } catch (apiError) {
              Logger.warning('Ошибка проверки через API сотрудников: $apiError');
              // В случае ошибки API тоже регистрируем как клиента
              try {
                final referralCode = _isReferralValid ? int.tryParse(_referralCodeController.text) : null;
                await RegistrationService.saveClientToServer(
                  phone: existingUser.phone,
                  name: existingUser.name,
                  clientName: existingUser.name,
                  referredBy: referralCode,
                );
                Logger.success('Данные существующего клиента сохранены на сервере (ошибка API)');
              } catch (e2) {
                Logger.warning('Не удалось сохранить данные существующего клиента на сервере: $e2');
              }
            }
          }

          // Регистрируем PIN-код в системе авторизации
          final pin = _pinController.text.trim();
          Logger.debug('🔐 Попытка регистрации PIN: phone=${existingUser.phone}, pin.length=${pin.length}');
          if (pin.isNotEmpty) {
            try {
              Logger.debug('🔐 Вызываем AuthService.registerSimple...');
              final authResult = await AuthService().registerSimple(
                phone: existingUser.phone,
                name: existingUser.name,
                pin: pin,
              );
              if (authResult.success) {
                Logger.success('✅ PIN-код успешно сохранён для существующего пользователя');
              } else {
                // Проверка на "уже зарегистрирован" - вызываем loginOnServer
                final errorText = authResult.error ?? '';
                Logger.debug('🔐 Ошибка регистрации: "$errorText"');
                final isAlreadyRegistered = errorText.contains('уже зарегистрирован') ||
                                            errorText.contains('already registered') ||
                                            errorText.contains('Используйте функцию входа');
                Logger.debug('🔐 isAlreadyRegistered: $isAlreadyRegistered');

                if (isAlreadyRegistered) {
                  // Пользователь уже зарегистрирован - пробуем войти через сервер
                  Logger.debug('🔐 Пользователь уже зарегистрирован, пробуем loginOnServer...');
                  final loginResult = await AuthService().loginOnServer(
                    phone: existingUser.phone,
                    pin: pin,
                  );
                  if (loginResult.success) {
                    Logger.success('✅ Успешный вход с существующим PIN через сервер');
                  } else {
                    Logger.warning('❌ Ошибка входа через сервер: ${loginResult.error}');
                    // Показываем ошибку пользователю и выходим
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(loginResult.error ?? 'Неверный PIN-код'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return; // Не переходим на главную при ошибке
                  }
                } else {
                  Logger.warning('❌ Ошибка сохранения PIN: ${authResult.error}');
                  // Показываем ошибку пользователю
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(authResult.error ?? 'Ошибка регистрации'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return; // Не переходим на главную при ошибке
                }
              }
            } catch (e) {
              Logger.warning('❌ Ошибка регистрации PIN: $e');
            }
          } else {
            Logger.warning('⚠️ PIN пустой, пропускаем регистрацию PIN');
          }

          // Показываем сообщение и переходим в приложение
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Добро пожаловать обратно, ${existingUser.name}!'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );

            // Переходим в главное меню
            Navigator.of(context).pushReplacementNamed('/home');
          }
        }
        return;
      } catch (e) {
        // Пользователь не найден - продолжаем регистрацию
        Logger.info('Пользователь не найден в базе, продолжаем регистрацию: $e');
      }

      // Регистрируем нового пользователя
      final qrCode = Uuid().v4();
      final loyaltyInfo = await RegistrationService.registerUser(
        name: name,
        phone: phone,
        qr: qrCode,
      );

      if (loyaltyInfo != null) {
        // Сохраняем статус регистрации и данные программы лояльности
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_registered', true);
        await prefs.setString('user_name', loyaltyInfo.name);
        await prefs.setString('user_phone', loyaltyInfo.phone);
        await LoyaltyStorage.save(loyaltyInfo);

        // Сохраняем FCM токен (теперь когда phone известен)
        await FirebaseService.resaveToken();

        // Проверяем роль пользователя после регистрации
        bool isEmployee = false;
        try {
          final roleData = await UserRoleService.getUserRole(loyaltyInfo.phone);
          await UserRoleService.saveUserRole(roleData);
          // Обновляем имя, если нужно (из столбца G для сотрудников/админов)
          await prefs.setString('user_name', roleData.displayName);

          // Если это сотрудник или админ, не сохраняем как клиента
          if (roleData.role.name != 'client') {
            Logger.info('Пользователь является ${roleData.role.name}, не регистрируем как клиента');
            isEmployee = true;
          }
        } catch (e) {
          Logger.warning('Ошибка проверки роли при регистрации: $e');
          // При ошибке проверки роли, пытаемся проверить через API сотрудников
          try {
            final apiRole = await UserRoleService.checkEmployeeViaAPI(loyaltyInfo.phone);
            if (apiRole != null) {
              Logger.success('Сотрудник найден через API при регистрации');
              await UserRoleService.saveUserRole(apiRole);
              await prefs.setString('user_name', apiRole.displayName);
              Logger.info('Пользователь является ${apiRole.role.name}, не регистрируем как клиента');
              isEmployee = true;
            }
          } catch (apiError) {
            Logger.warning('Ошибка проверки через API сотрудников при регистрации: $apiError');
            // Продолжаем без роли (по умолчанию клиент)
          }
        }

        // Сохраняем данные клиента на сервере (если это клиент, а не сотрудник)
        if (!isEmployee) {
          try {
            final referralCode = _isReferralValid ? int.tryParse(_referralCodeController.text) : null;
            await RegistrationService.saveClientToServer(
              phone: loyaltyInfo.phone,
              name: loyaltyInfo.name,
              clientName: loyaltyInfo.name,
              referredBy: referralCode,
            );
            Logger.success('Данные нового клиента сохранены на сервере${referralCode != null ? ' (referredBy: $referralCode)' : ''}');
          } catch (e) {
            Logger.warning('Не удалось сохранить данные нового клиента на сервере: $e');
          }
        }

        // Регистрируем PIN-код в системе авторизации
        final pin = _pinController.text.trim();
        Logger.debug('🔐 Попытка регистрации PIN (новый пользователь): phone=${loyaltyInfo.phone}, pin.length=${pin.length}');
        if (pin.isNotEmpty) {
          try {
            Logger.debug('🔐 Вызываем AuthService.registerSimple для нового пользователя...');
            final authResult = await AuthService().registerSimple(
              phone: loyaltyInfo.phone,
              name: loyaltyInfo.name,
              pin: pin,
            );
            if (authResult.success) {
              Logger.success('✅ PIN-код успешно сохранён для нового пользователя');
            } else {
              // Проверка на "уже зарегистрирован" - вызываем loginOnServer
              final errorText = authResult.error ?? '';
              Logger.debug('🔐 Ошибка регистрации (новый): "$errorText"');
              final isAlreadyRegistered = errorText.contains('уже зарегистрирован') ||
                                          errorText.contains('already registered') ||
                                          errorText.contains('Используйте функцию входа');
              Logger.debug('🔐 isAlreadyRegistered: $isAlreadyRegistered');

              if (isAlreadyRegistered) {
                // Пользователь уже зарегистрирован - пробуем войти через сервер
                Logger.debug('🔐 Пользователь уже зарегистрирован, пробуем loginOnServer...');
                final loginResult = await AuthService().loginOnServer(
                  phone: loyaltyInfo.phone,
                  pin: pin,
                );
                if (loginResult.success) {
                  Logger.success('✅ Успешный вход с существующим PIN через сервер');
                } else {
                  Logger.warning('❌ Ошибка входа через сервер: ${loginResult.error}');
                  // Показываем ошибку пользователю и выходим
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(loginResult.error ?? 'Неверный PIN-код'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return; // Не переходим на главную при ошибке
                }
              } else {
                Logger.warning('❌ Ошибка сохранения PIN: ${authResult.error}');
                // Показываем ошибку пользователю
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(authResult.error ?? 'Ошибка регистрации'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return; // Не переходим на главную при ошибке
              }
            }
          } catch (e) {
            Logger.warning('❌ Ошибка регистрации PIN: $e');
          }
        } else {
          Logger.warning('⚠️ PIN пустой, пропускаем регистрацию PIN для нового пользователя');
        }

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка регистрации. Попробуйте еще раз.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Ошибка регистрации. Попробуйте еще раз.';
        
        // Более понятные сообщения об ошибках
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('failed to fetch') || 
            errorString.contains('connection') ||
            errorString.contains('network')) {
          errorMessage = 'Ошибка подключения к серверу. Проверьте интернет-соединение.';
        } else if (errorString.contains('timeout')) {
          errorMessage = 'Превышено время ожидания. Попробуйте еще раз.';
        } else if (errorString.contains('не найден') || 
                   errorString.contains('not found')) {
          errorMessage = 'Сервер недоступен. Попробуйте позже.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Брендовые цвета Arabica
  static const Color _primaryColor = Color(0xFF1A4D4D); // Основной темно-бирюзовый
  static const Color _primaryLight = Color(0xFF2D6B6B); // Светлее
  static const Color _primaryDark = Color(0xFF0D3333); // Темнее
  static const Color _accentGold = Color(0xFFD4AF37); // Золотистый акцент

  InputDecoration _buildInputDecoration({
    required String labelText,
    required String hintText,
    required IconData icon,
    String? prefixText,
    Widget? suffixIcon,
    String? helperText,
    bool isValid = false,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixText: prefixText,
      prefixStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: _primaryColor,
      ),
      labelStyle: TextStyle(
        color: _primaryColor.withOpacity(0.8),
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        color: Colors.grey[400],
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _primaryColor.withOpacity(0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _primaryColor.withOpacity(0.3), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.95),
      prefixIcon: Container(
        margin: const EdgeInsets.only(left: 12, right: 8),
        child: Icon(icon, color: _primaryColor, size: 22),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 48),
      suffixIcon: suffixIcon,
      helperText: helperText,
      helperStyle: TextStyle(
        color: isValid ? const Color(0xFF2E7D32) : Colors.orange[700],
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              _primaryColor,
              _primaryDark,
              Color(0xFF0A2626),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Верхняя часть с логотипом (заполняет всё доступное пространство)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Логотип Arabica (большой)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.white.withOpacity(0.1),
                          border: Border.all(
                            color: _accentGold.withOpacity(0.4),
                            width: 2,
                          ),
                        ),
                        child: Image.asset(
                          'assets/images/arabica_logo.png',
                          width: 100,
                          height: 100,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Приветственный текст
                      const Text(
                        'Добро пожаловать!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Кофейни Arabica',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Карточка формы (внизу)
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.white.withOpacity(0.95),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Поле номера телефона
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _primaryDark,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              decoration: _buildInputDecoration(
                                labelText: 'Номер телефона',
                                hintText: '9001234567',
                                icon: Icons.phone_android_rounded,
                                prefixText: '+7 ',
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Введите номер телефона';
                                }
                                if (value.length != 10) {
                                  return 'Номер должен содержать 10 цифр';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),

                            // Поле имени
                            TextFormField(
                              controller: _nameController,
                              keyboardType: TextInputType.name,
                              textCapitalization: TextCapitalization.words,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _primaryDark,
                              ),
                              decoration: _buildInputDecoration(
                                labelText: 'Как к Вам обращаться?',
                                hintText: 'Введите ваше имя',
                                icon: Icons.person_outline_rounded,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Введите ваше имя';
                                }
                                if (value.length < 2) {
                                  return 'Имя должно содержать минимум 2 символа';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),

                            // Поле PIN-кода
                            TextFormField(
                              controller: _pinController,
                              keyboardType: TextInputType.number,
                              obscureText: _obscurePin,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: _primaryDark,
                                letterSpacing: 4,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              decoration: _buildInputDecoration(
                                labelText: 'Придумайте PIN-код',
                                hintText: '••••',
                                icon: Icons.lock_outline_rounded,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePin ? Icons.visibility_off : Icons.visibility,
                                    color: _primaryColor,
                                  ),
                                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Введите PIN-код';
                                }
                                if (value.length != 4) {
                                  return 'PIN должен содержать 4 цифры';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),

                            // Подтверждение PIN-кода
                            TextFormField(
                              controller: _pinConfirmController,
                              keyboardType: TextInputType.number,
                              obscureText: _obscurePinConfirm,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: _primaryDark,
                                letterSpacing: 4,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              decoration: _buildInputDecoration(
                                labelText: 'Повторите PIN-код',
                                hintText: '••••',
                                icon: Icons.lock_outline_rounded,
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePinConfirm ? Icons.visibility_off : Icons.visibility,
                                    color: _primaryColor,
                                  ),
                                  onPressed: () => setState(() => _obscurePinConfirm = !_obscurePinConfirm),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Подтвердите PIN-код';
                                }
                                if (value != _pinController.text) {
                                  return 'PIN-коды не совпадают';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),

                            // Поле кода приглашения (необязательное)
                            TextFormField(
                              controller: _referralCodeController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _primaryDark,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              decoration: _buildInputDecoration(
                                labelText: 'Код сотрудника (необязательно)',
                                hintText: 'Если вас пригласили',
                                icon: Icons.card_giftcard_rounded,
                                suffixIcon: _referralCodeController.text.isNotEmpty
                                    ? Container(
                                        margin: const EdgeInsets.only(right: 12),
                                        child: Icon(
                                          _isReferralValid
                                              ? Icons.check_circle_rounded
                                              : Icons.info_outline_rounded,
                                          color: _isReferralValid
                                              ? const Color(0xFF2E7D32)
                                              : Colors.orange[700],
                                          size: 24,
                                        ),
                                      )
                                    : null,
                                helperText: _referralValidationMessage,
                                isValid: _isReferralValid,
                              ),
                              onChanged: (value) {
                                _validateReferralCode(value);
                              },
                            ),
                            const SizedBox(height: 14),

                            // Кнопка регистрации с градиентом
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: const LinearGradient(
                                  colors: [_primaryLight, _primaryColor, _primaryDark],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _primaryColor.withOpacity(0.4),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _register,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  disabledBackgroundColor: Colors.transparent,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.login_rounded, size: 22),
                                          SizedBox(width: 10),
                                          Text(
                                            'Зарегистрироваться',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

