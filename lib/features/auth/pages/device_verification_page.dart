import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/logger.dart';
import '../services/auth_service.dart';
import '../widgets/otp_input_widget.dart';

/// Страница подтверждения нового устройства
///
/// Показывается, когда пользователь вводит правильный PIN,
/// но входит с нового (не доверенного) устройства.
///
/// Два варианта подтверждения:
/// 1. Telegram OTP — пользователь сам получает код в Telegram
/// 2. Запрос разработчику — разработчик одобряет вход в своём приложении
class DeviceVerificationPage extends StatefulWidget {
  final String phone;
  final String pin;
  final VoidCallback? onSuccess;

  const DeviceVerificationPage({
    super.key,
    required this.phone,
    required this.pin,
    this.onSuccess,
  });

  @override
  State<DeviceVerificationPage> createState() => _DeviceVerificationPageState();
}

class _DeviceVerificationPageState extends State<DeviceVerificationPage> {
  final AuthService _authService = AuthService();

  static final Color _primaryDark = Color(0xFF0D3333);

  // States: 'choose', 'otp', 'waitingApproval', 'approved', 'rejected'
  String _state = 'choose';
  bool _isLoading = false;
  String? _errorMessage;
  String? _telegramBotLink;
  String? _requestId;
  Timer? _pollingTimer;

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  // ==================== TELEGRAM OTP FLOW ====================

  Future<void> _startOtpFlow() async {
    if (mounted) setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.requestOtp(widget.phone);

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _state = 'otp';
          // message contains the Telegram bot link
          _telegramBotLink = result.message;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Ошибка запроса кода';
          _isLoading = false;
        });
      }
    } catch (e, st) {
      Logger.error('Error requesting OTP for device verification', e, st);
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Нет связи с сервером';
        _isLoading = false;
      });
    }
  }

  Future<void> _openTelegram() async {
    final link = _telegramBotLink ?? 'https://t.me/ArabicaAuthBot26_bot';
    final uri = Uri.parse(link);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _verifyOtp(String code) async {
    if (mounted) setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.verifyDeviceOtp(
        phone: widget.phone,
        code: code,
        pin: widget.pin,
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (result.success) {
        widget.onSuccess?.call();
      } else {
        setState(() {
          _errorMessage = result.error ?? 'Неверный код';
        });
      }
    } catch (e, st) {
      Logger.error('Error verifying device OTP', e, st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка проверки кода';
      });
    }
  }

  // ==================== DEVELOPER APPROVAL FLOW ====================

  Future<void> _startApprovalFlow() async {
    if (mounted) setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.requestDeviceApproval(
        phone: widget.phone,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          _state = 'waitingApproval';
          _requestId = result['requestId'] as String?;
          _isLoading = false;
        });
        _startPolling();
      } else {
        setState(() {
          _errorMessage = result['error'] as String? ?? 'Ошибка отправки запроса';
          _isLoading = false;
        });
      }
    } catch (e, st) {
      Logger.error('Error requesting device approval', e, st);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Нет связи с сервером';
      });
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!mounted) {
        _pollingTimer?.cancel();
        return;
      }

      try {
        final status = await _authService.checkDeviceApprovalStatus(widget.phone);

        if (!mounted) return;

        if (status == 'approved') {
          _pollingTimer?.cancel();
          // Device is now trusted, try login again
          setState(() {
            _state = 'approved';
            _isLoading = true;
          });
          final loginResult = await _authService.loginOnServer(
            phone: widget.phone,
            pin: widget.pin,
          );
          if (!mounted) return;
          setState(() => _isLoading = false);
          if (loginResult.success) {
            widget.onSuccess?.call();
          } else {
            setState(() {
              _errorMessage = loginResult.error ?? 'Ошибка входа после подтверждения';
            });
          }
        } else if (status == 'rejected') {
          _pollingTimer?.cancel();
          setState(() {
            _state = 'rejected';
          });
        }
      } catch (e) {
        // Polling errors are non-critical, continue trying
      }
    });
  }

  // ==================== BUILD ====================

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
                    // Back button
                    Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back, color: Colors.white70),
                      ),
                    ),

                    SizedBox(height: 16.h),

                    // Icon
                    Container(
                      padding: EdgeInsets.all(16.w),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.1),
                        border: Border.all(
                          color: AppColors.gold.withOpacity(0.6),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.security,
                        color: AppColors.gold,
                        size: 40,
                      ),
                    ),

                    SizedBox(height: 16.h),

                    // Title
                    Text(
                      'Новое устройство',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'PIN-код верный, но вы входите\nс нового устройства. Подтвердите, что это вы.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14.sp,
                      ),
                    ),

                    SizedBox(height: 24.h),

                    // Content based on state
                    Expanded(
                      child: _buildContent(),
                    ),
                  ],
                ),
              ),

              // Loading overlay
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
    switch (_state) {
      case 'otp':
        return _buildOtpStep();
      case 'waitingApproval':
        return _buildWaitingApproval();
      case 'approved':
        return _buildApproved();
      case 'rejected':
        return _buildRejected();
      default:
        return _buildChooseMethod();
    }
  }

  Widget _buildChooseMethod() {
    return Column(
      children: [
        // Error message
        if (_errorMessage != null)
          Container(
            margin: EdgeInsets.only(bottom: 16.h),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.redAccent, fontSize: 13.sp),
              textAlign: TextAlign.center,
            ),
          ),

        // Option 1: Telegram
        _buildOptionCard(
          icon: Icons.telegram,
          title: 'Получить код в Telegram',
          subtitle: 'Мгновенно — откроет бот',
          onTap: _startOtpFlow,
        ),

        SizedBox(height: 12.h),

        // Option 2: Developer approval
        _buildOptionCard(
          icon: Icons.person_outline,
          title: 'Запросить подтверждение',
          subtitle: 'Разработчик одобрит вход',
          onTap: _startApprovalFlow,
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: AppColors.gold.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 32),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 13.sp,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpStep() {
    return Column(
      children: [
        // Error
        if (_errorMessage != null)
          Container(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.redAccent, fontSize: 13.sp),
              textAlign: TextAlign.center,
            ),
          ),

        // Instruction
        Text(
          'Откройте Telegram-бота и\nнажмите «Получить код»',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 14.sp),
        ),

        SizedBox(height: 16.h),

        // Open Telegram button
        if (_telegramBotLink != null)
          OutlinedButton.icon(
            onPressed: _openTelegram,
            icon: Icon(Icons.telegram, color: AppColors.gold),
            label: Text('Открыть Telegram'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: AppColors.gold.withOpacity(0.6), width: 1.5),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          ),

        SizedBox(height: 24.h),

        // OTP input
        OtpInputWidget(
          onCompleted: _verifyOtp,
          lightTheme: true,
        ),

        Spacer(),

        // Back button
        TextButton(
          onPressed: () {
            if (mounted) setState(() {
              _state = 'choose';
              _errorMessage = null;
            });
          },
          style: TextButton.styleFrom(foregroundColor: Colors.white54),
          child: Text('Назад'),
        ),
        SizedBox(height: 16.h),
      ],
    );
  }

  Widget _buildWaitingApproval() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.hourglass_top,
          color: AppColors.gold,
          size: 48,
        ),
        SizedBox(height: 16.h),
        Text(
          'Запрос отправлен',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Ожидайте подтверждения от разработчика.\nВы получите уведомление.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 14.sp),
        ),
        SizedBox(height: 24.h),
        SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold.withOpacity(0.5)),
          ),
        ),
        Spacer(),
        TextButton(
          onPressed: () {
            _pollingTimer?.cancel();
            Navigator.of(context).pop();
          },
          style: TextButton.styleFrom(foregroundColor: Colors.white54),
          child: Text('Отмена'),
        ),
        SizedBox(height: 16.h),
      ],
    );
  }

  Widget _buildApproved() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.check_circle,
          color: Colors.greenAccent,
          size: 48,
        ),
        SizedBox(height: 16.h),
        Text(
          'Устройство подтверждено!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Выполняется вход...',
          style: TextStyle(color: Colors.white70, fontSize: 14.sp),
        ),
        if (_errorMessage != null) ...[
          SizedBox(height: 16.h),
          Text(
            _errorMessage!,
            style: TextStyle(color: Colors.redAccent, fontSize: 13.sp),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16.h),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
            child: Text('Назад'),
          ),
        ],
      ],
    );
  }

  Widget _buildRejected() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.cancel,
          color: Colors.redAccent,
          size: 48,
        ),
        SizedBox(height: 16.h),
        Text(
          'Запрос отклонён',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'Обратитесь к руководству.',
          style: TextStyle(color: Colors.white70, fontSize: 14.sp),
        ),
        SizedBox(height: 24.h),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white38),
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
          child: Text('Назад'),
        ),
      ],
    );
  }
}
