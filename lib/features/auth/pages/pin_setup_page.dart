import 'package:flutter/material.dart';

import '../services/auth_service.dart' show AuthService, AuthResult;
import '../widgets/pin_input_widget.dart';
import '../../../features/clients/pages/registration_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница создания PIN-кода
///
/// Третий шаг регистрации:
/// 1. Пользователь создаёт PIN-код (4-6 цифр)
/// 2. Подтверждает PIN-код повторным вводом
/// 3. При успехе завершается регистрация
class PinSetupPage extends StatefulWidget {
  final String phone;
  final String name;
  final String? registrationToken;
  final VoidCallback? onSuccess;

  /// Режим смены PIN (не регистрации)
  final bool isChangingPin;

  /// Показывать ли кнопку выхода (для смены аккаунта)
  final bool showLogout;

  const PinSetupPage({
    super.key,
    required this.phone,
    required this.name,
    this.registrationToken,
    this.onSuccess,
    this.isChangingPin = false,
    this.showLogout = false,
  });

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  final AuthService _authService = AuthService();

  // Брендовые цвета Arabica
  static final Color _primaryColor = Color(0xFF1A4D4D);
  static final Color _primaryDark = Color(0xFF0D3333);
  static final Color _accentGold = Color(0xFFD4AF37);

  bool _isConfirmStep = false;
  String _firstPin = '';
  bool _isLoading = false;
  bool _showError = false;
  String? _errorMessage;
  bool _clearPin = false;

  void _onPinEntered(String pin) {
    if (!_isConfirmStep) {
      // Первый ввод - переходим к подтверждению
      setState(() {
        _firstPin = pin;
        _isConfirmStep = true;
        _clearPin = true;
        _showError = false;
        _errorMessage = null;
      });

      // Сбрасываем флаг очистки
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _clearPin = false;
          });
        }
      });
    } else {
      // Подтверждение PIN
      if (pin == _firstPin) {
        _completeSetup(pin);
      } else {
        setState(() {
          _showError = true;
          _errorMessage = 'PIN-коды не совпадают';
          _clearPin = true;
        });

        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              _clearPin = false;
            });
          }
        });
      }
    }
  }

  Future<void> _completeSetup(String pin) async {
    setState(() {
      _isLoading = true;
      _showError = false;
    });

    // Сброс PIN через Telegram или обычная регистрация
    final AuthResult result;
    if (widget.registrationToken != null) {
      // Сброс PIN через Telegram - используем специальный endpoint reset-pin
      result = await _authService.resetPin(
        widget.phone,
        pin,
        widget.registrationToken!,
      );
    } else {
      // Обычная регистрация - простой метод без OTP
      result = await _authService.registerSimple(
        phone: widget.phone,
        name: widget.name,
        pin: pin,
      );
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result.success) {
      // Успешная регистрация или сброс PIN
      final message = widget.registrationToken != null
          ? 'PIN-код успешно изменён!'
          : 'Регистрация завершена!';

      if (widget.onSuccess != null) {
        widget.onSuccess!();
      } else {
        // Показываем успех и закрываем
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );

        // Закрываем все страницы авторизации
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } else {
      setState(() {
        _showError = true;
        _errorMessage = result.error;
        _isConfirmStep = false;
        _firstPin = '';
        _clearPin = true;
      });

      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _clearPin = false;
          });
        }
      });
    }
  }

  void _goBack() {
    if (_isConfirmStep) {
      setState(() {
        _isConfirmStep = false;
        _firstPin = '';
        _clearPin = true;
        _showError = false;
        _errorMessage = null;
      });

      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _clearPin = false;
          });
        }
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Сменить аккаунт'),
        content: Text(
          'Вы хотите войти с другим номером телефона?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Да, сменить'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _authService.logoutAndClearAll();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => RegistrationPage(),
        ),
      );
    }
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
              _primaryColor,
              _primaryDark,
              Color(0xFF0A2626),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Верхняя панель с кнопкой назад и выхода
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                    child: Row(
                      children: [
                        if (!widget.showLogout)
                          IconButton(
                            icon: Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: _goBack,
                          )
                        else
                          SizedBox(width: 48),
                        Expanded(
                          child: Text(
                            widget.isChangingPin ? 'Смена PIN-кода' : 'Создание PIN-кода',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (widget.showLogout)
                          TextButton(
                            onPressed: _logout,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                            ),
                            child: Text('Сменить'),
                          )
                        else
                          SizedBox(width: 48), // Для баланса
                      ],
                    ),
                  ),

                  // Логотип Arabica
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16.r),
                      color: Colors.white.withOpacity(0.1),
                      border: Border.all(
                        color: _accentGold.withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: Image.asset(
                      'assets/images/arabica_logo.png',
                      width: 60,
                      height: 60,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(height: 8),

                  // PIN ввод
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.w),
                      child: PinInputWidget(
                        pinLength: 4,
                        title: _isConfirmStep ? 'Подтвердите PIN' : 'Создайте PIN-код',
                        subtitle: _isConfirmStep
                            ? 'Введите PIN-код повторно'
                            : 'PIN-код будет использоваться для входа в приложение',
                        onCompleted: _onPinEntered,
                        showError: _showError,
                        errorMessage: _errorMessage,
                        clear: _clearPin,
                        lightTheme: true,
                        accentColor: _accentGold,
                      ),
                    ),
                  ),
                ],
              ),

              // Индикатор загрузки
              if (_isLoading)
                Container(
                  color: Colors.black45,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.all(32.w),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(_accentGold),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Завершаем регистрацию...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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
