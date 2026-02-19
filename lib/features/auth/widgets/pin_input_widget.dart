import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Виджет для ввода PIN-кода в стиле Arabica
///
/// Особенности:
/// - 4-6 цифр
/// - Скрытый ввод (точки вместо цифр)
/// - Анимация при ошибке
/// - Цифровая клавиатура
/// - Поддержка светлой и тёмной темы
class PinInputWidget extends StatefulWidget {
  /// Длина PIN-кода (от 4 до 6)
  final int pinLength;

  /// Вызывается когда PIN полностью введён
  final Function(String pin) onCompleted;

  /// Вызывается при изменении PIN
  final Function(String pin)? onChanged;

  /// Показывать ли ошибку
  final bool showError;

  /// Сообщение об ошибке
  final String? errorMessage;

  /// Заголовок над полем ввода
  final String? title;

  /// Описание под заголовком
  final String? subtitle;

  /// Очистить поле
  final bool clear;

  /// Использовать светлую тему (белый текст на тёмном фоне)
  final bool lightTheme;

  /// Цвет акцента (для точек и кнопок)
  final Color? accentColor;

  const PinInputWidget({
    super.key,
    this.pinLength = 4,
    required this.onCompleted,
    this.onChanged,
    this.showError = false,
    this.errorMessage,
    this.title,
    this.subtitle,
    this.clear = false,
    this.lightTheme = false,
    this.accentColor,
  });

  @override
  State<PinInputWidget> createState() => _PinInputWidgetState();
}

class _PinInputWidgetState extends State<PinInputWidget>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  Color get _activeColor => widget.accentColor ?? (widget.lightTheme ? AppColors.gold : AppColors.emerald);
  Color get _textColor => widget.lightTheme ? Colors.white : Colors.black87;
  Color get _subtitleColor => widget.lightTheme ? Colors.white70 : Colors.grey[600]!;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
  }

  @override
  void didUpdateWidget(PinInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clear && !oldWidget.clear) {
      _clearPin();
    }
    if (widget.showError && !oldWidget.showError) {
      _shake();
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _shake() {
    _shakeController.forward().then((_) {
      _shakeController.reverse();
    });
  }

  void _clearPin() {
    if (mounted) setState(() {
      _pin = '';
    });
  }

  void _addDigit(String digit) {
    if (_pin.length >= widget.pinLength) return;

    if (mounted) setState(() {
      _pin += digit;
    });

    widget.onChanged?.call(_pin);

    // Вибрация при нажатии
    HapticFeedback.lightImpact();

    if (_pin.length == widget.pinLength) {
      widget.onCompleted(_pin);
    }
  }

  void _removeDigit() {
    if (_pin.isEmpty) return;

    if (mounted) setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
    });

    widget.onChanged?.call(_pin);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final maxWidth = constraints.maxWidth;

        // Верхняя часть (заголовок + точки + ошибка) ≈ 110px
        final headerEstimate = 110.0;
        final keypadAvailableHeight = maxHeight - headerEstimate;

        // 4 ряда кнопок с отступами между ними
        final byHeight = (keypadAvailableHeight - 24) / 4;
        final byWidth = (maxWidth - 24) / 3;
        final buttonSize = (byHeight < byWidth ? byHeight : byWidth).clamp(48.0, 80.0);

        return Column(
          children: [
            // Заголовок
            if (widget.title != null) ...[
              Text(
                widget.title!,
                style: TextStyle(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 6),
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
              SizedBox(height: 20),
            ],

            // Индикаторы PIN
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.pinLength,
                  (index) => _buildPinDot(index < _pin.length),
                ),
              ),
            ),

            // Ошибка
            if (widget.showError && widget.errorMessage != null) ...[
              SizedBox(height: 10),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
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

            Spacer(),

            // Цифровая клавиатура — размер кнопок от экрана
            _buildKeypad(buttonSize),
          ],
        );
      },
    );
  }

  Widget _buildPinDot(bool filled) {
    final dotColor = widget.showError ? Colors.redAccent : _activeColor;

    return AnimatedContainer(
      duration: Duration(milliseconds: 200),
      width: filled ? 18 : 16,
      height: filled ? 18 : 16,
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? dotColor : Colors.transparent,
        border: Border.all(
          color: dotColor,
          width: 2,
        ),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: dotColor.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildKeypad(double buttonSize) {
    final gap = 4.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKeypadButton('1', buttonSize, gap),
            _buildKeypadButton('2', buttonSize, gap),
            _buildKeypadButton('3', buttonSize, gap),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKeypadButton('4', buttonSize, gap),
            _buildKeypadButton('5', buttonSize, gap),
            _buildKeypadButton('6', buttonSize, gap),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKeypadButton('7', buttonSize, gap),
            _buildKeypadButton('8', buttonSize, gap),
            _buildKeypadButton('9', buttonSize, gap),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildEmptyButton(buttonSize, gap),
            _buildKeypadButton('0', buttonSize, gap),
            _buildBackspaceButton(buttonSize, gap),
          ],
        ),
      ],
    );
  }

  Widget _buildKeypadButton(String digit, double size, double gap) {
    final radius = size / 2;
    final fontSize = size * 0.38;
    return Container(
      width: size,
      height: size,
      margin: EdgeInsets.all(gap),
      child: Material(
        color: widget.lightTheme
            ? Colors.white.withOpacity(0.15)
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          splashColor: _activeColor.withOpacity(0.3),
          highlightColor: _activeColor.withOpacity(0.1),
          onTap: () => _addDigit(digit),
          child: Center(
            child: Text(
              digit,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: _textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton(double size, double gap) {
    final radius = size / 2;
    return Container(
      width: size,
      height: size,
      margin: EdgeInsets.all(gap),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          splashColor: _activeColor.withOpacity(0.3),
          onTap: _removeDigit,
          child: Center(
            child: Icon(
              Icons.backspace_outlined,
              size: size * 0.35,
              color: widget.lightTheme ? Colors.white70 : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyButton(double size, double gap) {
    return Container(
      width: size,
      height: size,
      margin: EdgeInsets.all(gap),
    );
  }
}
