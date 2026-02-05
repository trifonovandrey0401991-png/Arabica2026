import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../widgets/otp_input_widget.dart';
import 'pin_setup_page.dart';

/// Страница ввода OTP-кода
///
/// Второй шаг регистрации:
/// 1. Пользователь получает код в Telegram
/// 2. Вводит код в приложении
/// 3. При успехе переходит к созданию PIN-кода
class OtpVerificationPage extends StatefulWidget {
  final String phone;
  final String name;
  final String? telegramBotLink;
  final VoidCallback? onSuccess;

  const OtpVerificationPage({
    super.key,
    required this.phone,
    required this.name,
    this.telegramBotLink,
    this.onSuccess,
  });

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _showError = false;
  String? _errorMessage;
  String? _registrationToken;

  Future<void> _verifyCode(String code) async {
    setState(() {
      _isLoading = true;
      _showError = false;
      _errorMessage = null;
    });

    final result = await _authService.verifyOtp(widget.phone, code);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result.success) {
      _registrationToken = result.message;

      // Переходим к созданию PIN-кода
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => PinSetupPage(
            phone: widget.phone,
            name: widget.name,
            registrationToken: _registrationToken,
            onSuccess: widget.onSuccess,
          ),
        ),
      );
    } else {
      setState(() {
        _showError = true;
        _errorMessage = result.error;
      });
    }
  }

  Future<void> _resendCode() async {
    setState(() {
      _isLoading = true;
      _showError = false;
      _errorMessage = null;
    });

    final result = await _authService.requestOtp(widget.phone);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result.success) {
      // Открываем Telegram
      final botLink = result.message ?? widget.telegramBotLink;
      if (botLink != null && botLink.startsWith('http')) {
        await launchUrl(Uri.parse(botLink), mode: LaunchMode.externalApplication);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Новый код отправлен в Telegram'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      setState(() {
        _showError = true;
        _errorMessage = result.error;
      });
    }
  }

  void _openTelegram() async {
    final link = widget.telegramBotLink ?? 'https://t.me/ArabicaAuthBot26_bot';
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }

  String get _maskedPhone {
    if (widget.phone.length < 11) return widget.phone;
    return '+7 ${widget.phone.substring(1, 4)} *** ** ${widget.phone.substring(9)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подтверждение'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),

                  // Виджет ввода кода
                  OtpInputWidget(
                    title: 'Введите код',
                    subtitle: 'Код отправлен на $_maskedPhone\nчерез Telegram',
                    onCompleted: _verifyCode,
                    onResend: _resendCode,
                    showError: _showError,
                    errorMessage: _errorMessage,
                    resendTimeout: 60,
                  ),

                  const SizedBox(height: 32),

                  // Кнопка открытия Telegram
                  OutlinedButton.icon(
                    onPressed: _openTelegram,
                    icon: const Icon(Icons.telegram),
                    label: const Text('Открыть Telegram'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Подсказка
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Если код не пришёл, проверьте что вы открыли бота @ArabicaAuthBot26_bot и поделились своим номером телефона',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
