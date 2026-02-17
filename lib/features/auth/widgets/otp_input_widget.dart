import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import 'dart:async';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Виджет для ввода OTP-кода (одноразового кода подтверждения)
///
/// Особенности:
/// - 6 отдельных полей ввода
/// - Автоматический переход между полями
/// - Таймер повторной отправки
/// - Автоматическая вставка из буфера обмена
/// - Поддержка светлой и тёмной темы
class OtpInputWidget extends StatefulWidget {
  /// Длина кода (обычно 6)
  final int codeLength;

  /// Вызывается когда код полностью введён
  final Function(String code) onCompleted;

  /// Вызывается при изменении кода
  final Function(String code)? onChanged;

  /// Вызывается при нажатии "Отправить повторно"
  final VoidCallback? onResend;

  /// Показывать ли ошибку
  final bool showError;

  /// Сообщение об ошибке
  final String? errorMessage;

  /// Заголовок
  final String? title;

  /// Описание (куда отправлен код)
  final String? subtitle;

  /// Время до повторной отправки (секунды)
  final int resendTimeout;

  /// Использовать светлую тему (белый текст на тёмном фоне)
  final bool lightTheme;

  /// Цвет акцента
  final Color? accentColor;

  const OtpInputWidget({
    super.key,
    this.codeLength = 6,
    required this.onCompleted,
    this.onChanged,
    this.onResend,
    this.showError = false,
    this.errorMessage,
    this.title,
    this.subtitle,
    this.resendTimeout = 60,
    this.lightTheme = false,
    this.accentColor,
  });

  @override
  State<OtpInputWidget> createState() => _OtpInputWidgetState();
}

class _OtpInputWidgetState extends State<OtpInputWidget> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  Timer? _resendTimer;
  int _remainingSeconds = 0;

  Color get _activeColor => widget.accentColor ?? (widget.lightTheme ? AppColors.gold : AppColors.emerald);
  Color get _textColor => widget.lightTheme ? Colors.white : Colors.black87;
  Color get _subtitleColor => widget.lightTheme ? Colors.white70 : Colors.grey[600]!;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      widget.codeLength,
      (_) => TextEditingController(),
    );
    _focusNodes = List.generate(
      widget.codeLength,
      (_) => FocusNode(),
    );

    // Запускаем таймер
    _startResendTimer();

    // Фокус на первое поле
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _remainingSeconds = widget.resendTimeout;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  String get _code {
    return _controllers.map((c) => c.text).join();
  }

  void _onChanged(String value, int index) {
    // Обрабатываем вставку из буфера (несколько символов сразу)
    if (value.length > 1) {
      _handlePaste(value);
      return;
    }

    // Убираем нецифровые символы
    if (value.isNotEmpty && !RegExp(r'^\d$').hasMatch(value)) {
      _controllers[index].text = '';
      return;
    }

    widget.onChanged?.call(_code);

    // Переход на следующее поле
    if (value.isNotEmpty && index < widget.codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    // Код полностью введён
    if (_code.length == widget.codeLength) {
      widget.onCompleted(_code);
    }
  }

  void _handlePaste(String value) {
    // Извлекаем только цифры
    final digits = value.replaceAll(RegExp(r'\D'), '');

    for (int i = 0; i < digits.length && i < widget.codeLength; i++) {
      _controllers[i].text = digits[i];
    }

    // Фокус на последнее заполненное поле или следующее пустое
    final lastIndex = (digits.length - 1).clamp(0, widget.codeLength - 1);
    if (digits.length < widget.codeLength) {
      _focusNodes[digits.length].requestFocus();
    } else {
      _focusNodes[lastIndex].unfocus();
      widget.onCompleted(_code);
    }

    widget.onChanged?.call(_code);
  }

  void _onKeyDown(KeyEvent event, int index) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        if (_controllers[index].text.isEmpty && index > 0) {
          _controllers[index - 1].clear();
          _focusNodes[index - 1].requestFocus();
        }
      }
    }
  }

  void _clearAll() {
    for (final controller in _controllers) {
      controller.clear();
    }
    _focusNodes[0].requestFocus();
    widget.onChanged?.call('');
  }

  void _handleResend() {
    if (_remainingSeconds > 0) return;
    _clearAll();
    _startResendTimer();
    widget.onResend?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Заголовок
        if (widget.title != null) ...[
          Text(
            widget.title!,
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
        ],

        // Описание
        if (widget.subtitle != null) ...[
          Text(
            widget.subtitle!,
            style: TextStyle(
              fontSize: 14.sp,
              color: _subtitleColor,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 32),
        ],

        // Поля ввода — адаптивная ширина от экрана
        LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final totalMargin = 8.0 * widget.codeLength; // 4.w * 2 per field
            final fieldWidth = ((maxWidth - totalMargin) / widget.codeLength).clamp(36.0, 50.0);
            final fieldHeight = fieldWidth * 1.22;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.codeLength,
                (index) => _buildCodeField(index, fieldWidth, fieldHeight),
              ),
            );
          },
        ),

        // Ошибка
        if (widget.showError && widget.errorMessage != null) ...[
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              widget.errorMessage!,
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],

        SizedBox(height: 32),

        // Кнопка повторной отправки
        if (widget.onResend != null) ...[
          _remainingSeconds > 0
              ? Text(
                  'Отправить повторно через $_remainingSeconds сек',
                  style: TextStyle(
                    color: _subtitleColor,
                    fontSize: 14.sp,
                  ),
                )
              : TextButton(
                  onPressed: _handleResend,
                  style: TextButton.styleFrom(
                    foregroundColor: _activeColor,
                  ),
                  child: Text(
                    'Отправить код повторно',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
        ],
      ],
    );
  }

  Widget _buildCodeField(int index, double fieldWidth, double fieldHeight) {
    final borderColor = widget.showError
        ? Colors.red
        : (widget.lightTheme
            ? Colors.white.withOpacity(0.3)
            : Colors.grey[300]!);

    final focusBorderColor = widget.showError ? Colors.red : _activeColor;

    return Container(
      width: fieldWidth,
      height: fieldHeight,
      margin: EdgeInsets.symmetric(horizontal: 4),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) => _onKeyDown(event, index),
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          style: TextStyle(
            fontSize: 24.sp,
            fontWeight: FontWeight.bold,
            color: widget.lightTheme ? Colors.black87 : Colors.black87,
          ),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.symmetric(vertical: 12.h),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(
                color: focusBorderColor,
                width: 2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide(color: borderColor),
            ),
            filled: true,
            fillColor: widget.lightTheme
                ? Colors.white.withOpacity(0.95)
                : Colors.grey[50],
          ),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          onChanged: (value) => _onChanged(value, index),
        ),
      ),
    );
  }
}
