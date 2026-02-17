import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../widgets/otp_input_widget.dart';
import 'pin_setup_page.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

  // Цвет не из палитры AppColors
  static final Color _primaryDark = Color(0xFF0D3333);

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
              Column(
                children: [
                  // Верхняя панель с кнопкой назад
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Text(
                            'Сброс PIN-кода',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18.sp,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(width: 48),
                      ],
                    ),
                  ),

                  // Контент
                  Expanded(child: _buildContent()),
                ],
              ),

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
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 32),

          Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50.r),
              color: Colors.white.withOpacity(0.1),
              border: Border.all(
                color: AppColors.gold.withOpacity(0.4),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.lock_reset,
              size: 60,
              color: AppColors.gold,
            ),
          ),
          SizedBox(height: 24),

          Text(
            'Сброс PIN-кода',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),

          Text(
            'Введите номер телефона, на который зарегистрирован аккаунт',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 32),

          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.r),
              color: Colors.white.withOpacity(0.95),
            ),
            child: TextField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: 'Номер телефона',
                hintText: '9001234567',
                prefixIcon: Icon(Icons.phone_outlined, color: AppColors.emerald),
                prefixText: '+7 ',
                prefixStyle: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.emerald,
                ),
                labelStyle: TextStyle(color: AppColors.emerald.withOpacity(0.8)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.transparent,
                errorText: _showError ? _errorMessage : null,
                counterStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
              keyboardType: TextInputType.phone,
              maxLength: 10,
              onChanged: (_) => setState(() {
                _showError = false;
              }),
            ),
          ),
          SizedBox(height: 24),

          ElevatedButton(
            onPressed: _isPhoneValid ? _requestCode : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black87,
              padding: EdgeInsets.symmetric(vertical: 16.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              disabledBackgroundColor: AppColors.gold.withOpacity(0.3),
            ),
            child: Text(
              'Получить код',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Шаг 1: Инструкция открыть Telegram
  Widget _buildTelegramStep() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 32),

          Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50.r),
              color: Colors.white.withOpacity(0.1),
              border: Border.all(
                color: Colors.blue.withOpacity(0.4),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.telegram,
              size: 60,
              color: Colors.blue,
            ),
          ),
          SizedBox(height: 24),

          Text(
            'Откройте Telegram',
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),

          Text(
            'Нажмите кнопку ниже, чтобы открыть бота и получить код подтверждения',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 32),

          ElevatedButton.icon(
            onPressed: _openTelegram,
            icon: Icon(Icons.telegram),
            label: Text('Открыть Telegram'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 16.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          ),
          SizedBox(height: 24),

          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.gold.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.gold),
                    SizedBox(width: 8),
                    Text(
                      'Инструкция',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '1. Откройте бота @ArabicaAuthBot26_bot\n'
                  '2. Нажмите "Получить код"\n'
                  '3. Поделитесь номером телефона\n'
                  '4. Скопируйте полученный код',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.white.withOpacity(0.8),
                    height: 1.5,
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
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 32),

          OtpInputWidget(
            title: 'Введите код',
            subtitle: 'Код из Telegram-бота',
            onCompleted: _verifyCode,
            onResend: _resendCode,
            showError: _showError,
            errorMessage: _errorMessage,
            resendTimeout: 60,
            lightTheme: true,
            accentColor: AppColors.gold,
          ),

          SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: () async {
              final link = _telegramBotLink ?? 'https://t.me/ArabicaAuthBot26_bot';
              await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
            },
            icon: Icon(Icons.telegram, color: Colors.blue),
            label: Text('Открыть Telegram'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.blue.withOpacity(0.6)),
              padding: EdgeInsets.symmetric(vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          ),

          SizedBox(height: 24),

          // Инструкция по получению кода
          Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.gold.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline, color: AppColors.gold, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Как получить код?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                        fontSize: 14.sp,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  '🔄 Восстанавливаете повторно?\n'
                  '     Введите /start и нажмите\n'
                  '     "Поделиться номером"\n\n'
                  '🆕 Впервые восстанавливаете?\n'
                  '     Просто нажмите кнопку\n'
                  '     "Поделиться номером"',
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: Colors.white.withOpacity(0.85),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
