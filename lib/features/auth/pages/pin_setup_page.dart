import 'package:flutter/material.dart';

import '../services/auth_service.dart' show AuthService, AuthResult;
import '../widgets/pin_input_widget.dart';

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

  const PinSetupPage({
    super.key,
    required this.phone,
    required this.name,
    this.registrationToken,
    this.onSuccess,
    this.isChangingPin = false,
  });

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  final AuthService _authService = AuthService();

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
      Future.delayed(const Duration(milliseconds: 100), () {
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

        Future.delayed(const Duration(milliseconds: 100), () {
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

    // Простая регистрация (без OTP) или сброс PIN через Telegram
    final AuthResult result;
    if (widget.registrationToken != null) {
      // Сброс PIN через Telegram - используем полную регистрацию
      result = await _authService.register(
        phone: widget.phone,
        name: widget.name,
        pin: pin,
        registrationToken: widget.registrationToken,
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
      // Успешная регистрация
      if (widget.onSuccess != null) {
        widget.onSuccess!();
      } else {
        // Показываем успех и закрываем
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Регистрация завершена!'),
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

      Future.delayed(const Duration(milliseconds: 100), () {
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

      Future.delayed(const Duration(milliseconds: 100), () {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isChangingPin ? 'Смена PIN-кода' : 'Создание PIN-кода'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
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
              ),
            ),

            // Индикатор загрузки
            if (_isLoading)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Завершаем регистрацию...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
