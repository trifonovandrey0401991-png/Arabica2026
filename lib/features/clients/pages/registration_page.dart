import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/registration_service.dart';
import '../../loyalty/services/loyalty_storage.dart';
import '../../loyalty/services/loyalty_service.dart';
import '../../employees/services/user_role_service.dart';
import '../../referrals/services/referral_service.dart';
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
  final _referralCodeController = TextEditingController();
  bool _isLoading = false;
  String? _referralValidationMessage;
  bool _isReferralValid = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF004D40), // Темно-бирюзовый фон (fallback)
          image: DecorationImage(
            image: AssetImage('assets/images/arabica_background.png'),
            fit: BoxFit.cover,
            opacity: 0.6, // Прозрачность фона для хорошей видимости логотипа
          ),
        ),
        child: SafeArea(
          child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Иконка и заголовок
                      const Icon(
                        Icons.person_add,
                        size: 64,
                        color: Color(0xFF004D40),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Регистрация',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF004D40),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Заполните данные для продолжения',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Поле номера телефона
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Номер телефона',
                          hintText: '9001234567',
                          prefixText: '+7 ',
                          prefixStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF004D40),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon: const Icon(Icons.phone),
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
                      const SizedBox(height: 20),

                      // Поле имени
                      TextFormField(
                        controller: _nameController,
                        keyboardType: TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Как к Вам обращаться?',
                          hintText: 'Введите ваше имя',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon: const Icon(Icons.person),
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
                      const SizedBox(height: 20),

                      // Поле кода приглашения (необязательное)
                      TextFormField(
                        controller: _referralCodeController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Код сотрудника (необязательно)',
                          hintText: 'Если вас пригласили',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon: const Icon(Icons.person_pin),
                          suffixIcon: _referralCodeController.text.isNotEmpty
                              ? Icon(
                                  _isReferralValid ? Icons.check_circle : Icons.error,
                                  color: _isReferralValid ? Colors.green : Colors.orange,
                                )
                              : null,
                          helperText: _referralValidationMessage,
                          helperStyle: TextStyle(
                            color: _isReferralValid ? Colors.green : Colors.orange,
                          ),
                        ),
                        onChanged: (value) {
                          _validateReferralCode(value);
                        },
                      ),
                      const SizedBox(height: 32),

                      // Кнопка регистрации
                      ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF004D40),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                                'Зарегистрироваться',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
        ),
    );
  }
}

