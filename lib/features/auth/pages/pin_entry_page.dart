import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../widgets/pin_input_widget.dart';
import '../../../features/clients/pages/registration_page.dart';
import 'forgot_pin_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Страница ввода PIN-кода
///
/// Используется для ежедневного входа:
/// 1. Пользователь вводит PIN-код
/// 2. Или использует биометрию (если включена)
/// 3. При успехе переходит в приложение
class PinEntryPage extends StatefulWidget {
  /// Callback при успешном входе
  final VoidCallback? onSuccess;

  /// Показывать ли кнопку выхода (для смены аккаунта)
  final bool showLogout;

  const PinEntryPage({
    super.key,
    this.onSuccess,
    this.showLogout = true,
  });

  @override
  State<PinEntryPage> createState() => _PinEntryPageState();
}

class _PinEntryPageState extends State<PinEntryPage> {
  final AuthService _authService = AuthService();
  final BiometricService _biometricService = BiometricService();

  // Цвет не из палитры AppColors
  static final Color _primaryDark = Color(0xFF0D3333);

  bool _isLoading = false;
  bool _showError = false;
  String? _errorMessage;
  bool _clearPin = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String _biometricName = '';

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final available = await _biometricService.isAvailable();
    final enabled = await _authService.isBiometricEnabled();
    final name = await _biometricService.getBiometricTypeName();

    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
        _biometricName = name;
      });

      // Автоматически запускаем биометрию если включена
      if (available && enabled) {
        _authenticateWithBiometric();
      }
    }
  }

  Future<void> _onPinEntered(String pin) async {
    if (mounted) setState(() {
      _isLoading = true;
      _showError = false;
      _errorMessage = null;
    });

    final result = await _authService.loginWithPin(pin);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result.success) {
      // Если биометрия доступна но НЕ включена - предложить включить
      if (_biometricAvailable && !_biometricEnabled) {
        await _offerEnableBiometric();
      }
      widget.onSuccess?.call();
    } else {
      if (mounted) setState(() {
        _showError = true;
        _errorMessage = result.error;
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

  Future<void> _offerEnableBiometric() async {
    if (!mounted) return;

    final enable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Включить $_biometricName?'),
        content: Text(
          'Хотите использовать $_biometricName для быстрого входа в приложение?\n\n'
          'Это позволит входить без ввода PIN-кода.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Не сейчас'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Включить'),
          ),
        ],
      ),
    );

    if (enable == true && mounted) {
      await _authService.enableBiometric();
      if (mounted) setState(() {
        _biometricEnabled = true;
      });
    }
  }

  Future<void> _onBiometricButtonPressed() async {
    if (_biometricEnabled) {
      // Биометрия уже включена - просто авторизуемся
      await _authenticateWithBiometric();
    } else {
      // Биометрия не включена - предложить включить
      final enable = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Включить $_biometricName?'),
          content: Text(
            'Для использования $_biometricName необходимо сначала включить эту функцию.\n\n'
            'После включения вы сможете входить без ввода PIN-кода.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Включить'),
            ),
          ],
        ),
      );

      if (enable == true && mounted) {
        // Сначала проверяем биометрию
        final authenticated = await _biometricService.authenticate(
          reason: 'Подтвердите личность для включения $_biometricName',
        );

        if (authenticated && mounted) {
          await _authService.enableBiometric();
          if (mounted) setState(() {
            _biometricEnabled = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_biometricName успешно включён!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  Future<void> _authenticateWithBiometric() async {
    if (mounted) setState(() {
      _isLoading = true;
      _showError = false;
    });

    final result = await _authService.loginWithBiometric();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result.success) {
      widget.onSuccess?.call();
    } else {
      // Не показываем ошибку при отмене биометрии
      if (result.error?.contains('отклонена') != true) {
        if (mounted) setState(() {
          _showError = true;
          _errorMessage = result.error;
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Выход'),
        content: Text(
          'Вы уверены, что хотите выйти? Для повторного входа потребуется подтверждение через Telegram.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Выйти'),
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

  Future<void> _forgotPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Забыли PIN?'),
        content: Text(
          'Для сброса PIN-кода мы отправим код подтверждения в Telegram.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Сбросить PIN'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Получаем текущую сессию для номера телефона и имени
      final session = await _authService.getCurrentSession();
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ForgotPinPage(
              phone: session?.phone,
              name: session?.name,
              onSuccess: widget.onSuccess,
            ),
          ),
        );
      }
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
              AppColors.emerald,
              _primaryDark,
              Color(0xFF0A2626),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  children: [
                    // Верхняя панель с кнопкой выхода
                    if (widget.showLogout)
                      Align(
                        alignment: Alignment.topRight,
                        child: TextButton(
                          onPressed: _logout,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                          child: Text('Выйти'),
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
                          color: AppColors.gold.withOpacity(0.4),
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

                    // PIN ввод — занимает всё оставшееся пространство
                    Expanded(
                      child: PinInputWidget(
                        pinLength: 4,
                        title: 'Введите PIN-код',
                        subtitle: 'Для входа в приложение',
                        onCompleted: _onPinEntered,
                        showError: _showError,
                        errorMessage: _errorMessage,
                        clear: _clearPin,
                        lightTheme: true,
                        accentColor: AppColors.gold,
                      ),
                    ),

                    // Кнопка биометрии (показываем если доступна)
                    if (_biometricAvailable)
                      Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: _onBiometricButtonPressed,
                          icon: Icon(
                            _biometricName == 'Face ID'
                                ? Icons.face
                                : Icons.fingerprint,
                            color: AppColors.gold,
                            size: 24,
                          ),
                          label: Text(
                            _biometricEnabled
                                ? 'Войти через $_biometricName'
                                : 'Использовать $_biometricName',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: AppColors.gold.withOpacity(0.6),
                              width: 1.5,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 20.w,
                              vertical: 10.h,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                        ),
                      ),

                    // Забыли PIN
                    TextButton(
                      onPressed: _forgotPin,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.gold,
                      ),
                      child: Text(
                        'Забыли PIN-код?',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                  ],
                ),
              ),

              // Индикатор загрузки
              if (_isLoading)
                Container(
                  color: Colors.black45,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.all(24.w),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold),
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
