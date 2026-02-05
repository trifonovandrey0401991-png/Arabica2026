import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../widgets/otp_input_widget.dart';
import 'pin_setup_page.dart';

/// Страница сброса PIN-кода через Telegram
///
/// Flow:
/// 1. Пользователь вводит телефон (или он уже известен)
/// 2. Получает код в Telegram
/// 3. Вводит код в приложении
/// 4. Создаёт новый PIN
class ForgotPinPage extends StatefulWidget {
  /// Телефон пользователя (если известен)
  final String? phone;

  /// Имя пользователя (если известно)
  final String? name;

  /// Callback при успешном сбросе
  final VoidCallback? onSuccess;

  const ForgotPinPage({
    super.key,
    this.phone,
    this.name,
    this.onSuccess,
  });

  @override
  State<ForgotPinPage> createState() => _ForgotPinPageState();
}

class _ForgotPinPageState extends State<ForgotPinPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _phoneController = TextEditingController();

  // Шаги: 0 = ввод телефона, 1 = ожидание кода, 2 = ввод кода
  int _step = 0;
  bool _isLoading = false;
  bool _showError = false;
  String? _errorMessage;
  String? _telegramBotLink;
  String? _registrationToken;

  @override
  void initState() {
    super.initState();
    if (widget.phone != null) {
      _phoneController.text = widget.phone!.substring(1); // Убираем 7 в начале
      // Сразу запрашиваем код если телефон известен
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestCode();
      });
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _fullPhone {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('7') && digits.length == 11) {
      return digits;
    } else if (digits.length == 10) {
      return '7$digits';
    }
    return digits;
  }

  bool get _isPhoneValid {
    final phone = _fullPhone;
    return phone.length == 11 && phone.startsWith('7');
  }

  Future<void> _requestCode() async {
    if (!_isPhoneValid) return;

    setState(() {
      _isLoading = true;
      _showError = false;
      _errorMessage = null;
    });

    final result = await _authService.requestOtp(_fullPhone);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result.success) {
      _telegramBotLink = result.message;
      setState(() {
        _step = 1;
      });
    } else {
      setState(() {
        _showError = true;
        _errorMessage = result.error;
      });
    }
  }

  void _openTelegram() async {
    // Переходим к вводу кода
    setState(() {
      _step = 2;
    });

    // Открываем Telegram
    final link = _telegramBotLink ?? 'https://t.me/ArabicaAuthBot26_bot';
    await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  }

  Future<void> _verifyCode(String code) async {
    setState(() {
      _isLoading = true;
      _showError = false;
      _errorMessage = null;
    });

    final result = await _authService.verifyOtp(_fullPhone, code);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (result.success) {
      _registrationToken = result.message;

      // Переходим к созданию нового PIN
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => PinSetupPage(
            phone: _fullPhone,
            name: widget.name ?? 'Пользователь',
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
    await _requestCode();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сброс PIN-кода'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            _buildContent(),
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

  Widget _buildContent() {
    switch (_step) {
      case 0:
        return _buildPhoneStep();
      case 1:
        return _buildTelegramStep();
      case 2:
        return _buildOtpStep();
      default:
        return _buildPhoneStep();
    }
  }

  /// Шаг 0: Ввод телефона
  Widget _buildPhoneStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),

          Icon(
            Icons.lock_reset,
            size: 80,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 24),

          Text(
            'Сброс PIN-кода',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          Text(
            'Введите номер телефона, на который зарегистрирован аккаунт',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: 'Номер телефона',
              hintText: '9001234567',
              prefixIcon: const Icon(Icons.phone_outlined),
              prefixText: '+7 ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              errorText: _showError ? _errorMessage : null,
            ),
            keyboardType: TextInputType.phone,
            maxLength: 10,
            onChanged: (_) => setState(() {
              _showError = false;
            }),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _isPhoneValid ? _requestCode : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Получить код',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// Шаг 1: Инструкция открыть Telegram
  Widget _buildTelegramStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),

          Icon(
            Icons.telegram,
            size: 80,
            color: Colors.blue[700],
          ),
          const SizedBox(height: 24),

          Text(
            'Откройте Telegram',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          Text(
            'Нажмите кнопку ниже, чтобы открыть бота и получить код подтверждения',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          ElevatedButton.icon(
            onPressed: _openTelegram,
            icon: const Icon(Icons.telegram),
            label: const Text('Открыть Telegram'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Text(
                      'Инструкция',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[900],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Откройте бота @ArabicaAuthBot26_bot\n'
                  '2. Нажмите "Получить код"\n'
                  '3. Поделитесь номером телефона\n'
                  '4. Скопируйте полученный код',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Шаг 2: Ввод OTP кода
  Widget _buildOtpStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),

          OtpInputWidget(
            title: 'Введите код',
            subtitle: 'Код из Telegram-бота',
            onCompleted: _verifyCode,
            onResend: _resendCode,
            showError: _showError,
            errorMessage: _errorMessage,
            resendTimeout: 60,
          ),

          const SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: () async {
              final link = _telegramBotLink ?? 'https://t.me/ArabicaAuthBot26_bot';
              await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.telegram),
            label: const Text('Открыть Telegram'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
