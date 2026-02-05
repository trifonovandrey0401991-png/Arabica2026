import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../widgets/pin_input_widget.dart';
import 'phone_entry_page.dart';
import 'forgot_pin_page.dart';

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
    setState(() {
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
      widget.onSuccess?.call();
    } else {
      setState(() {
        _showError = true;
        _errorMessage = result.error;
        _clearPin = true;
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _clearPin = false;
          });
        }
      });
    }
  }

  Future<void> _authenticateWithBiometric() async {
    setState(() {
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
        setState(() {
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
        title: const Text('Выход'),
        content: const Text(
          'Вы уверены, что хотите выйти? Для повторного входа потребуется подтверждение через Telegram.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _authService.logoutAndClearAll();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => PhoneEntryPage(
            onSuccess: widget.onSuccess,
          ),
        ),
      );
    }
  }

  Future<void> _forgotPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Забыли PIN?'),
        content: const Text(
          'Для сброса PIN-кода мы отправим код подтверждения в Telegram.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Сбросить PIN'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Получаем текущую сессию для номера телефона
      final session = await _authService.getCurrentSession();
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ForgotPinPage(
              phone: session?.phone,
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
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Кнопка выхода
                if (widget.showLogout)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextButton(
                        onPressed: _logout,
                        child: const Text('Выйти'),
                      ),
                    ),
                  ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 32),

                        // PIN ввод
                        Expanded(
                          child: PinInputWidget(
                            pinLength: 4,
                            title: 'Введите PIN-код',
                            subtitle: 'Для входа в приложение',
                            onCompleted: _onPinEntered,
                            showError: _showError,
                            errorMessage: _errorMessage,
                            clear: _clearPin,
                          ),
                        ),

                        // Кнопка биометрии
                        if (_biometricAvailable && _biometricEnabled) ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _authenticateWithBiometric,
                            icon: Icon(
                              _biometricName == 'Face ID'
                                  ? Icons.face
                                  : Icons.fingerprint,
                            ),
                            label: Text('Войти через $_biometricName'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],

                        // Забыли PIN
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _forgotPin,
                          child: const Text('Забыли PIN-код?'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Индикатор загрузки
            if (_isLoading)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
