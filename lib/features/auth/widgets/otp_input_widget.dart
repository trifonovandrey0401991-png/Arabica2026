import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

/// Виджет для ввода OTP-кода (одноразового кода подтверждения)
///
/// Особенности:
/// - 6 отдельных полей ввода
/// - Автоматический переход между полями
/// - Таймер повторной отправки
/// - Автоматическая вставка из буфера обмена
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
  });

  @override
  State<OtpInputWidget> createState() => _OtpInputWidgetState();
}

class _OtpInputWidgetState extends State<OtpInputWidget> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  Timer? _resendTimer;
  int _remainingSeconds = 0;

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
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],

        // Описание
        if (widget.subtitle != null) ...[
          Text(
            widget.subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
        ],

        // Поля ввода
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.codeLength,
            (index) => _buildCodeField(index),
          ),
        ),

        // Ошибка
        if (widget.showError && widget.errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.errorMessage!,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],

        const SizedBox(height: 32),

        // Кнопка повторной отправки
        if (widget.onResend != null) ...[
          _remainingSeconds > 0
              ? Text(
                  'Отправить повторно через $_remainingSeconds сек',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                )
              : TextButton(
                  onPressed: _handleResend,
                  child: const Text('Отправить код повторно'),
                ),
        ],
      ],
    );
  }

  Widget _buildCodeField(int index) {
    return Container(
      width: 45,
      height: 55,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (event) => _onKeyDown(event, index),
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 1,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: widget.showError ? Colors.red : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: widget.showError
                    ? Colors.red
                    : Theme.of(context).primaryColor,
                width: 2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: widget.showError ? Colors.red : Colors.grey[300]!,
              ),
            ),
            filled: true,
            fillColor: Colors.grey[50],
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
